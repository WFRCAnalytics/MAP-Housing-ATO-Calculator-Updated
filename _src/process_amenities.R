#' Match One Amenity Layer to a Table of Points
#'
#' Joins every point to one amenity layer and stores the match in a small
#' result table `res_<point_table>_<col>` with columns (`key`, `val`). Only
#' matched points get a row. Nothing is written to the (large) point table, so
#' there are no UPDATEs, no table rewrites and no indexes: DuckDB's spatial join
#' builds its own R-tree for each join and drops it afterwards.
#'
#' Isochrone bands and buffer distances are nested, so they are matched closest
#' first and each pass only tests the points that no closer pass has matched.
#' Each isochrone band is dissolved into one geometry before the join. Measured
#' on this data, that is the difference between seconds and hours for the large
#' driving isochrones (hundreds of overlapping ~6,000-vertex polygons).
#'
#' @param conn DuckDB connection with `spatial` loaded and `geometry_always_xy` set.
#' @param point_table Table with columns `key` and `geom` (one point per target).
#' @param key Name of the unique id column in `point_table`.
#' @param config One row of the amenity config: `col_name`, `type`
#'   (`binary`, `isochrone`, `buffer`), `path`, `filter_sql`, `value_col`,
#'   `buffer_opts` (miles, buffer type only).
#' @param crs CRS of the point table (EPSG string). Layers are transformed to it,
#'   which is a no-op for layers already stored in it.
#' @return The name of the result table, invisibly.
process_layers <- function(conn, point_table, key, config, crs = "EPSG:26912") {
  col <- config$col_name
  type <- config$type
  path <- config$path
  res_table <- paste0("res_", point_table, "_", col)

  if (!file.exists(path)) stop("Missing amenity layer for ", col, ": ", path)
  message(glue::glue("🔄 {col} ({type}) on {point_table}..."))

  # 1. Load the layer. Simplification keeps the polygon joins fast; a
  #    polygon that collapses becomes NULL and simply never matches.
  val_sql <- if (type == "isochrone") glue::glue(", {config$value_col} AS val") else ""
  DBI::dbExecute(
    conn,
    glue::glue(
      "
      CREATE OR REPLACE TEMP TABLE raw_layer AS
      SELECT ST_MakeValid(ST_Simplify(ST_Transform(geometry, '{crs}'), 1.0)) AS geom
             {val_sql}
      FROM read_parquet('{path}')
      WHERE {config$filter_sql}
    "
    )
  )

  # 2. Match
  if (type == "binary") {
    DBI::dbExecute(
      conn,
      glue::glue(
        "
        CREATE OR REPLACE TABLE {res_table} AS
        SELECT pt.{key}, 1.0 AS val
        FROM {point_table} pt
        JOIN raw_layer r ON ST_Intersects(pt.geom, r.geom)
        GROUP BY pt.{key}
      "
      )
    )
  } else {
    DBI::dbExecute(
      conn,
      glue::glue(
        "CREATE OR REPLACE TABLE {res_table} AS
         SELECT {key}, 0.0::DOUBLE AS val FROM {point_table} WHERE false"
      )
    )

    if (type == "isochrone") {
      # One pass per band (e.g. 300 s, 600 s, ...), smallest first
      # Each band is dissolved into one geometry first (seconds), because
      # joining hundreds of overlapping ~6,000-vertex driving polygons one by one
      # is orders of magnitude slower than testing one dissolved polygon.
      DBI::dbExecute(
        conn,
        "
        CREATE OR REPLACE TEMP TABLE band_geom AS
        SELECT val, ST_MakeValid(ST_Union_Agg(geom)) AS geom
        FROM raw_layer
        GROUP BY val
      "
      )
      bands <- DBI::dbGetQuery(conn, "SELECT val FROM band_geom ORDER BY val")$val
      passes <- lapply(bands, function(b) {
        list(
          label = glue::glue("band {b}"),
          val = b,
          layer = glue::glue("(SELECT geom FROM band_geom WHERE val = {b})"),
          on = "ST_Intersects(t.geom, r.geom)"
        )
      })
    } else if (type == "buffer") {
      # One pass per distance in miles, nearest first
      passes <- lapply(sort(unlist(config$buffer_opts)), function(miles) {
        list(
          label = glue::glue("{miles} miles"),
          val = miles,
          layer = "raw_layer",
          on = glue::glue("ST_DWithin(t.geom, r.geom, {miles * 1609.34})")
        )
      })
    } else {
      stop("Unknown amenity type: ", type)
    }

    for (p in passes) {
      message(glue::glue("   {p$label}"))
      DBI::dbExecute(
        conn,
        glue::glue(
          "
          CREATE OR REPLACE TEMP TABLE todo AS
          SELECT pt.{key}, pt.geom
          FROM {point_table} pt
          ANTI JOIN {res_table} m ON pt.{key} = m.{key}
        "
        )
      )
      DBI::dbExecute(
        conn,
        glue::glue(
          "
          INSERT INTO {res_table}
          SELECT t.{key}, {p$val}
          FROM todo t
          JOIN {p$layer} r ON {p$on}
          GROUP BY t.{key}
        "
        )
      )
    }
    DBI::dbExecute(conn, "DROP TABLE todo")
  }

  DBI::dbExecute(conn, "DROP TABLE raw_layer")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS band_geom")
  invisible(res_table)
}

#' Add the Amenity Columns to a Target Table in One Join
#'
#' Rebuilds `target_table` as a single CREATE TABLE AS with one LEFT JOIN per
#' amenity result table, then drops the result tables. Unmatched binary layers
#' become 0; unmatched isochrone and buffer layers stay NULL.
#'
#' @param conn DuckDB connection.
#' @param target_table Table to extend.
#' @param point_table Point table the results were computed on.
#' @param key Name of the unique id column shared by both tables.
#' @param config The full amenity config (one row per layer).
join_amenities <- function(conn, target_table, point_table, key, config) {
  cols <- config$col_name
  res_tables <- paste0("res_", point_table, "_", cols)
  alias <- paste0("a", seq_along(cols))

  select_sql <- ifelse(
    config$type == "binary",
    glue::glue('COALESCE({alias}.val, 0) AS "{cols}"'),
    glue::glue('{alias}.val AS "{cols}"')
  )
  join_sql <- glue::glue("LEFT JOIN {res_tables} {alias} ON t.{key} = {alias}.{key}")

  message(glue::glue("📦 Adding {length(cols)} amenity columns to {target_table}..."))
  DBI::dbExecute(
    conn,
    glue::glue(
      "
      CREATE OR REPLACE TABLE {target_table}_new AS
      SELECT t.*,
             {paste(select_sql, collapse = ',\n             ')}
      FROM {target_table} t
      {paste(join_sql, collapse = '\n      ')}
    "
    )
  )
  DBI::dbExecute(conn, glue::glue("DROP TABLE {target_table}"))
  DBI::dbExecute(conn, glue::glue("ALTER TABLE {target_table}_new RENAME TO {target_table}"))
  for (tbl in res_tables) DBI::dbExecute(conn, glue::glue("DROP TABLE {tbl}"))
  invisible(target_table)
}
