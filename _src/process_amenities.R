#' Run One Step and Log How Long It Took
#'
#' Evaluates `expr`, prints `⏱️ <label>: <seconds> s` (also if it errors), and
#' returns the value of `expr`. Used to see where the time goes in step 3.
#'
#' @param label Text shown in the log line.
#' @param expr Code to run.
#' @return The value of `expr`.
timed_step <- function(label, expr) {
  t0 <- Sys.time()
  on.exit(
    message(glue::glue(
      "   ⏱️ {label}: {round(as.numeric(difftime(Sys.time(), t0, units = 'secs')), 1)} s"
    ))
  )
  expr
}

#' Clip Polygons Into Square Tiles
#'
#' Creates the temp table `dest` with one row per (`id_col`, tile) holding the
#' part of each polygon of `src` that falls in a `tile_size` square. A point is
#' then tested only against the few small tiles near it instead of one polygon
#' with tens of thousands of vertices: a 3599 s driving band went from 20 s to
#' 0.1 s per table, and the county layer from 8.5 s to under 1 s, with
#' identical matches. A point on a tile seam matches both tiles, so join
#' results must be grouped by the point's key.
#'
#' TODO(ST_Subdivide): this tiling is a workaround for DuckDB spatial having no
#' ST_Subdivide. Replace it when that exists:
#' https://github.com/duckdb/duckdb-spatial/issues/905
#' The untiled version (same results, ~13.6 min instead of ~0.6 min for the
#' whole of step 3) is commit b338f99: git show b338f99:_src/process_amenities.R
#'
#' @param conn DuckDB connection with `spatial` loaded.
#' @param src Table with columns `id_col` and `geom`.
#' @param dest Name of the temp table to create (columns `id_col`, `geom`).
#' @param id_col Name of the column that identifies each polygon (kept as is).
#' @param tile_size Tile edge length in the units of the geometry's CRS.
#' @return `dest`, invisibly.
tile_polygons <- function(conn, src, dest, id_col, tile_size) {
  DBI::dbExecute(
    conn,
    glue::glue(
      "
      CREATE OR REPLACE TEMP TABLE {dest} AS
      WITH g AS (
        SELECT {id_col}, geom,
               floor(ST_XMin(geom) / {tile_size})::INT AS x0, floor(ST_XMax(geom) / {tile_size})::INT AS x1,
               floor(ST_YMin(geom) / {tile_size})::INT AS y0, floor(ST_YMax(geom) / {tile_size})::INT AS y1
        FROM {src}
      ),
      gx AS (SELECT {id_col}, geom, unnest(range(x0, x1 + 1)) AS cx, y0, y1 FROM g),
      gxy AS (SELECT {id_col}, geom, cx, unnest(range(y0, y1 + 1)) AS cy FROM gx)
      SELECT {id_col},
             ST_Intersection(geom, ST_MakeEnvelope(cx * {tile_size}, cy * {tile_size},
                                                   (cx + 1) * {tile_size}, (cy + 1) * {tile_size})) AS geom
      FROM gxy
    "
    )
  )
  DBI::dbExecute(conn, glue::glue("DELETE FROM {dest} WHERE geom IS NULL OR ST_IsEmpty(geom)"))
  invisible(dest)
}

#' Prepare One Amenity Layer for Matching
#'
#' Loads the layer into the temp table `raw_layer` and, for isochrones,
#' dissolves each band into one geometry in `band_geom`. Call this once per
#' layer, then call `process_layers()` for every point table, then
#' `drop_layer()`. Dissolving once and reusing it for parcels and H3 halves the
#' single-threaded work.
#'
#' The dissolve is two-level: polygons are first unioned per 10 km grid cell
#' (parallel across cells), then the cell results are unioned per band. The
#' result is identical to one big union (checked: zero area difference) and up
#' to 3-4x faster on the large driving isochrones.
#'
#' @param conn DuckDB connection with `spatial` loaded and `geometry_always_xy` set.
#' @param config One row of the amenity config: `col_name`, `type`
#'   (`binary`, `isochrone`, `buffer`), `path`, `filter_sql`, `value_col`.
#' @param crs CRS of the point tables (EPSG string). Layers are transformed to
#'   it, which is a no-op for layers already stored in it.
#' @param simplify_tolerance `ST_Simplify` tolerance in the units of `crs`
#'   (metres for EPSG:26912). Default 1.0. Use `0` to skip simplification.
#' @param tile_size Edge length, in the units of `crs`, of the square tiles the
#'   dissolved isochrone bands are clipped into before joining (`band_tiles`).
#'   Tiling does not change which points match. Default 5000.
#' @return `NULL`, invisibly.
prepare_layer <- function(
  conn,
  config,
  crs = "EPSG:26912",
  simplify_tolerance = 1.0,
  tile_size = 5000
) {
  col <- config$col_name
  type <- config$type
  path <- config$path

  if (!file.exists(path)) stop("Missing amenity layer for ", col, ": ", path)
  message(glue::glue("📥 {col} ({type}): preparing layer..."))

  t_lap <- Sys.time()
  lap <- function(label) {
    now <- Sys.time()
    message(glue::glue("   ⏱️ {label}: {round(as.numeric(difftime(now, t_lap, units = 'secs')), 1)} s"))
    t_lap <<- now
  }

  # Simplification keeps the polygon joins fast; a polygon that collapses
  # becomes NULL and simply never matches.
  geom_sql <- glue::glue("ST_Transform(geometry, '{crs}')")
  if (simplify_tolerance > 0) {
    geom_sql <- glue::glue("ST_Simplify({geom_sql}, {simplify_tolerance})")
  }
  val_sql <- if (type == "isochrone") glue::glue(", {config$value_col} AS val") else ""
  DBI::dbExecute(
    conn,
    glue::glue(
      "
      CREATE OR REPLACE TEMP TABLE raw_layer AS
      SELECT ST_MakeValid({geom_sql}) AS geom
             {val_sql}
      FROM read_parquet('{path}')
      WHERE {config$filter_sql}
    "
    )
  )
  lap("load + simplify")

  if (type == "isochrone") {
    DBI::dbExecute(
      conn,
      "
      CREATE OR REPLACE TEMP TABLE band_geom AS
      WITH cells AS (
        SELECT val,
               ST_Union_Agg(geom) AS geom
        FROM raw_layer
        GROUP BY val,
                 floor(ST_X(ST_Centroid(geom)) / 10000),
                 floor(ST_Y(ST_Centroid(geom)) / 10000)
      )
      SELECT val, ST_MakeValid(ST_Union_Agg(geom)) AS geom
      FROM cells
      GROUP BY val
    "
    )
    lap("dissolve bands")

    # Clip the dissolved bands into tiles so the join can use its index
    # (see tile_polygons()).
    tile_polygons(conn, "band_geom", "band_tiles", "val", tile_size)
    lap("tile bands")
  }
  invisible(NULL)
}

#' Drop the Temp Tables Made by `prepare_layer()`
#' @param conn DuckDB connection.
drop_layer <- function(conn) {
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS raw_layer")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS band_geom")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS band_tiles")
  invisible(NULL)
}

#' Match One Prepared Amenity Layer to a Table of Points
#'
#' Joins every point to the layer set up by `prepare_layer()` and stores the
#' match in a small result table `res_<point_table>_<col>` with columns
#' (`key`, `val`). Only matched points get a row. Nothing is written to the
#' (large) point table, so there are no UPDATEs, no table rewrites and no
#' indexes: DuckDB's spatial join builds its own R-tree for each join.
#'
#' Isochrone bands and buffer distances are nested, so they are matched closest
#' first and each pass only tests the points that no closer pass has matched.
#'
#' @param conn DuckDB connection with `spatial` loaded and `geometry_always_xy` set.
#' @param point_table Table with columns `key` and `geom` (one point per target).
#' @param key Name of the unique id column in `point_table`.
#' @param config The same config row passed to `prepare_layer()`
#'   (plus `buffer_opts` in miles for the buffer type).
#' @return The name of the result table, invisibly.
process_layers <- function(conn, point_table, key, config) {
  col <- config$col_name
  type <- config$type
  res_table <- paste0("res_", point_table, "_", col)

  message(glue::glue("🔄 {col} ({type}) on {point_table}..."))

  t_lap <- Sys.time()
  lap <- function(label) {
    now <- Sys.time()
    message(glue::glue("   ⏱️ {label}: {round(as.numeric(difftime(now, t_lap, units = 'secs')), 1)} s"))
    t_lap <<- now
  }

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
      bands <- DBI::dbGetQuery(conn, "SELECT val FROM band_geom ORDER BY val")$val
      passes <- lapply(bands, function(b) {
        list(
          label = glue::glue("band {b}"),
          val = b,
          layer = glue::glue("(SELECT geom FROM band_tiles WHERE val = {b})"),
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
      lap(glue::glue("join {p$label}"))
    }
    DBI::dbExecute(conn, "DROP TABLE todo")
  }

  if (type == "binary") lap("join")
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
