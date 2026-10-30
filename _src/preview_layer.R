#' Preview a Parquet Spatial Layer
#'
#' Reads a (Geo)Parquet file or partitioned directory through DuckDB, converts
#' the geometry to sf using the CRS stored in the file, and renders a map with
#' mapgl::maplibre_view.
#'
#' @param file_path A string path to the parquet file or partitioned directory.
#' @param limit An integer for the max number of features to load.
#'   Default is \code{NULL} (loads all data). If provided, loads the first N rows.
#' @param crs The EPSG code to assume if the file has no CRS (default 4326).
#' @param ... Additional arguments passed to \code{mapgl::maplibre_view}
#'   (e.g., \code{tooltip}, \code{style}, \code{palette}, \code{n}).
#'
#' @return A mapgl object (interactive map) or NULL if the file/column is missing.
#'
#' @export
preview_layer <- function(
  file_path,
  limit = NULL,
  crs = 4326,
  ...
) {
  # 1. Dependency Check
  required_pkgs <- c("duckdb", "DBI", "glue", "dplyr", "sf", "mapgl")
  missing_pkgs <- required_pkgs[
    !sapply(required_pkgs, requireNamespace, quietly = TRUE)
  ]

  if (length(missing_pkgs) > 0) {
    stop(paste0(
      "❌ Missing required packages: ",
      paste(missing_pkgs, collapse = ", ")
    ))
  }

  if (!file.exists(file_path)) {
    warning(paste("⚠️ File not found:", file_path))
    return(NULL)
  }

  tryCatch(
    {
      src <- gsub("\\\\", "/", file_path)
      src_sql <- if (dir.exists(file_path)) {
        glue::glue("read_parquet('{src}/**/*.parquet', hive_partitioning = true)")
      } else {
        glue::glue("read_parquet('{src}')")
      }
      limit_sql <- if (is.null(limit)) "" else paste("LIMIT", as.integer(limit))

      with_duckdb(function(conn) {
        # 2. Geometry column: the writers in this project always name it "geometry"
        cols <- DBI::dbGetQuery(conn, glue::glue("DESCRIBE SELECT * FROM {src_sql}"))
        if (!"geometry" %in% cols$column_name) {
          stop("No geometry column found in parquet file.")
        }

        # 3. Read geometry as WKB plus the CRS stored in the file
        df_raw <- DBI::dbGetQuery(
          conn,
          glue::glue(
            "SELECT * EXCLUDE (geometry), ST_AsWKB(geometry) AS geometry
             FROM {src_sql} {limit_sql}"
          )
        )
        file_crs <- DBI::dbGetQuery(
          conn,
          glue::glue("SELECT ST_CRS(geometry) AS crs FROM {src_sql} LIMIT 1")
        )$crs
        if (length(file_crs) == 0 || is.na(file_crs) || !nzchar(file_crs)) {
          file_crs <- crs
        }

        if (nrow(df_raw) == 0) {
          warning("⚠️ Layer is empty: ", basename(file_path))
          return(NULL)
        }

        # 4. Create sf with the file's CRS
        df_raw$geometry <- sf::st_as_sfc(df_raw$geometry, crs = file_crs)
        sf_obj <- sf::st_as_sf(df_raw)

        # Flatten list columns for mapgl
        sf_obj <- sf_obj |>
          dplyr::mutate(dplyr::across(
            dplyr::where(is.list) & !dplyr::where(~ inherits(.x, "sfc")),
            ~ as.character(.)
          ))

        # 5. Render
        mapgl::maplibre_view(data = sf_obj, ...)
      })
    },
    error = function(e) {
      message(paste(
        "❌ Preview failed:",
        basename(file_path),
        "
Reason:",
        e$message
      ))
      return(NULL)
    }
  )
}
