#' Process Vector File to Parquet
#'
#' Reads a vector file (local zip, local file, remote URL, or remote zip) via
#' DuckDB's ST_Read() — which uses GDAL under the hood — and writes to
#' GeoParquet using COPY TO. Geometry is forced to 2D, made valid, and
#' reprojected entirely inside DuckDB, so large files (e.g. 600 MB GDB zips)
#' never load into R memory.
#'
#' @param path Path relative to `dirs$raw` OR a full URL.
#' @param name Desired output filename (without extension).
#' @param save_dir Directory to save the Parquet file. Defaults to `dirs$processed`.
#' @param layer (Optional) Layer name if reading from a multi-layer source (e.g. GDB).
#' @param query (Optional) A SQL WHERE clause ("STATE = 'UT'") or a full OGR-style
#'   SQL string ("SELECT * FROM layer WHERE cond"). If a full SQL string is given,
#'   the layer name and WHERE clause are extracted automatically.
#' @param crs Target CRS as an EPSG string (default: `CRS_WGS` = "EPSG:4326").
#' @param read_mode How to read the file. Options:
#'   - "auto": (Default) Detects based on URL/zip pattern.
#'   - "standard": Local file (e.g. .shp, .gdb).
#'   - "zip": Local zip file (/vsizip/).
#'   - "url": Remote file (/vsicurl/).
#'   - "remote_zip": Remote zip file (/vsizip//vsicurl/).
#' @param partitioning Character vector of columns to partition by (e.g. "co_name").
#' @param overwrite Logical. If \code{TRUE}, overwrites existing files. Default \code{FALSE}.
#'
#' @return A string containing the full path to the saved file or directory.
#' @export
process_local_layer <- function(
  path,
  name,
  save_dir = dirs$processed,
  layer = NULL,
  query = NA,
  crs = CRS_WGS,
  read_mode = "auto",
  partitioning = NULL,
  overwrite = FALSE
) {
  # 1. Dependency Check
  required_pkgs <- c("duckdb", "DBI", "glue", "janitor")
  missing_pkgs <- required_pkgs[
    !sapply(required_pkgs, requireNamespace, quietly = TRUE)
  ]
  if (length(missing_pkgs) > 0) {
    stop("Missing packages: ", paste(missing_pkgs, collapse = ", "))
  }

  # 2. GDAL Config — scoped to this call, restored on exit even if it errors.
  # ONLY_CCW bypasses organizePolygons() DEFAULT, which is not thread-safe under
  # DuckDB's parallel scan and crashes on ESRI FileGDB features with 100+ rings.
  # ONLY_CCW is geometrically correct for ESRI data (inner rings are CCW by convention).
  .old_ogp <- Sys.getenv("OGR_ORGANIZE_POLYGONS", unset = NA)
  Sys.setenv(OGR_ORGANIZE_POLYGONS = "ONLY_CCW")
  on.exit(
    if (is.na(.old_ogp)) Sys.unsetenv("OGR_ORGANIZE_POLYGONS")
    else Sys.setenv(OGR_ORGANIZE_POLYGONS = .old_ogp),
    add = TRUE
  )

  # 3. Path Setup
  if (!dir.exists(save_dir)) dir.create(save_dir, recursive = TRUE)
  out_fp <- if (!is.null(partitioning)) {
    file.path(save_dir, name)
  } else {
    file.path(save_dir, paste0(name, ".parquet"))
  }

  # 3. Cache Check
  if (file.exists(out_fp) && !overwrite) {
    message(paste("✅ Exists:", name))
    return(out_fp)
  }

  # 4. Resolve DSN path (GDAL virtual filesystem prefixes)
  is_url_str <- grepl("^(http|ftp)s?://", path)
  is_zip_str <- grepl("\\.zip$", path, ignore.case = TRUE)

  if (read_mode == "auto") {
    if (is_url_str && is_zip_str) read_mode <- "remote_zip"
    else if (is_url_str)          read_mode <- "url"
    else if (is_zip_str)          read_mode <- "zip"
    else                          read_mode <- "standard"
  }

  dsn_path <- switch(
    read_mode,
    remote_zip = {
      message(paste("🌐 Reading Remote Zip:", path))
      paste0("/vsizip//vsicurl/", path)
    },
    url = {
      message(paste("🌐 Reading Remote URL:", path))
      paste0("/vsicurl/", path)
    },
    zip = {
      input_path <- file.path(dirs$raw, path)
      if (!file.exists(input_path)) { warning("Input not found: ", input_path); return(NULL) }
      message(paste("📦 Reading Local Zip:", path))
      paste0("/vsizip/", gsub("\\\\", "/", normalizePath(input_path)))
    },
    {
      input_path <- file.path(dirs$raw, path)
      if (!file.exists(input_path)) { warning("Input not found: ", input_path); return(NULL) }
      message(paste("⚙️ Processing:", name))
      gsub("\\\\", "/", normalizePath(input_path))
    }
  )

  # 5. Parse `query` param: extract layer name + WHERE clause from full SQL if given
  where_sql <- ""
  if (!is.na(query)) {
    where_match <- regmatches(query, regexpr("(?i)WHERE\\s+.+", query, perl = TRUE))
    if (length(where_match) == 1) where_sql <- where_match

    if (is.null(layer)) {
      from_match <- regmatches(query, regexpr("(?i)FROM\\s+(\\S+)", query, perl = TRUE))
      if (length(from_match) == 1) {
        layer <- trimws(sub("(?i)FROM\\s+", "", from_match, perl = TRUE))
      }
    }
  }

  layer_sql <- if (!is.null(layer)) glue::glue(", layer = '{layer}'") else ""

  # 6. DuckDB Pipeline: ST_Read (GDAL) → transform/clean → COPY TO PARQUET
  tryCatch(
    {
      con <- DBI::dbConnect(duckdb::duckdb())
      on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
      DBI::dbExecute(con, "INSTALL spatial; LOAD spatial;")
      DBI::dbExecute(con, "SET geometry_always_xy = true")

      # Inspect schema via a temporary view — more reliable than DESCRIBE on
      # a table function, and duckdb_columns() returns a stable data_type field
      DBI::dbExecute(con, glue::glue(
        "CREATE OR REPLACE VIEW _schema_probe AS
         SELECT * FROM ST_Read('{dsn_path}'{layer_sql})"
      ))
      schema <- DBI::dbGetQuery(
        con,
        "SELECT column_name, data_type
         FROM duckdb_columns()
         WHERE table_name = '_schema_probe'"
      )
      DBI::dbExecute(con, "DROP VIEW IF EXISTS _schema_probe")

      orig_names <- schema$column_name

      # Match geometry column: by data_type (case-insensitive) then by name pattern
      geom_idx <- which(grepl("^GEOMETRY$", schema$data_type, ignore.case = TRUE))
      if (length(geom_idx) == 0) {
        geom_idx <- which(grepl(
          "^(geom|geometry|shape|wkb_geometry|the_geom)$",
          schema$column_name, ignore.case = TRUE
        ))
      }
      if (length(geom_idx) == 0) {
        message("Schema returned by DuckDB (no GEOMETRY found):")
        print(schema)
        stop("No GEOMETRY column found in source")
      }

      geom_col       <- orig_names[geom_idx[1]]
      non_geom_orig  <- orig_names[-geom_idx]
      non_geom_clean <- janitor::make_clean_names(non_geom_orig)

      # Build SELECT list:
      # - Non-geometry cols: original name → cleaned snake_case alias
      # - Geometry col: transform → make valid → force 2D
      col_sql <- paste(
        c(
          glue::glue('"{non_geom_orig}" AS "{non_geom_clean}"'),
          glue::glue(
            'ST_Force2D(ST_MakeValid(ST_Transform("{geom_col}", \'{crs}\'))) AS geometry'
          )
        ),
        collapse = ",\n      "
      )

      if (!is.null(partitioning)) {
        if (dir.exists(out_fp)) unlink(out_fp, recursive = TRUE)
        dir.create(out_fp, recursive = TRUE)
        partition_cols <- paste(partitioning, collapse = ", ")
        DBI::dbExecute(con, glue::glue(
          "COPY (
            SELECT
              {col_sql}
            FROM ST_Read('{dsn_path}'{layer_sql})
            {where_sql}
          ) TO '{out_fp}' (FORMAT PARQUET, PARTITION_BY ({partition_cols}))"
        ))
        message(paste("💾 Saved Partitioned Dataset:", out_fp))
      } else {
        DBI::dbExecute(con, glue::glue(
          "COPY (
            SELECT
              {col_sql}
            FROM ST_Read('{dsn_path}'{layer_sql})
            {where_sql}
          ) TO '{out_fp}' (FORMAT PARQUET)"
        ))
        message(paste("💾 Saved Parquet File:", out_fp))
      }

      return(out_fp)
    },
    error = function(e) {
      # DuckDB ST_Read failed (ESRI CurvePolygon/CompoundCurve/MultiSurface in WKB).
      # Fall back: sf reads and calls st_cast("MULTIPOLYGON") to linearize all
      # curved types via GDAL's forceTo() before st_make_valid(), which would
      # otherwise pass WKB type 12 to S2 and fail. DuckDB reads the data frame
      # from memory via standard WKB binary and writes parquet.
      message("⚠️ ST_Read failed (", conditionMessage(e), "), trying sf fallback...")
      sf_data <- sf::st_read(dsn_path, layer = layer, quiet = TRUE)
      sf_data <- sf::st_cast(sf_data, "MULTIPOLYGON")
      sf_data <- sf::st_transform(sf_data, crs)
      sf_data <- sf::st_zm(sf_data, drop = TRUE, what = "ZM")
      sf_data <- janitor::clean_names(sf_data)
      geom_col <- attr(sf_data, "sf_column")
      wkb <- sf::st_as_binary(sf::st_geometry(sf_data))
      class(wkb) <- "blob"
      df_data <- sf::st_drop_geometry(sf_data)
      df_data[[geom_col]] <- wkb
      con_fb <- DBI::dbConnect(duckdb::duckdb())
      on.exit(DBI::dbDisconnect(con_fb, shutdown = TRUE), add = TRUE)
      DBI::dbExecute(con_fb, "INSTALL spatial; LOAD spatial;")
      duckdb::duckdb_register(con_fb, "_sf_data", df_data)
      DBI::dbExecute(con_fb, glue::glue(
        "COPY (
          SELECT
            * EXCLUDE ({geom_col}),
            ST_MakeValid(ST_GeomFromWKB({geom_col})) AS geometry
          FROM _sf_data
        ) TO '{out_fp}' (FORMAT PARQUET)"
      ))
      message(paste("💾 Saved Parquet File:", out_fp))
      out_fp
    }
  )
}
