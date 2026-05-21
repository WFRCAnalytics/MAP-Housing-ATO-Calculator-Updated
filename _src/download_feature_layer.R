#' Download an ArcGIS Feature Layer to Parquet
#'
#' Downloads a layer from an ArcGIS FeatureServer, cleans names, projects it,
#' and saves it as a Parquet file in the PROCESSED directory.
#'
#' @param url URL to the FeatureServer layer.
#' @param name Desired output filename (without extension).
#' @param save_dir Directory to save the Parquet file. Defaults to `dirs$processed`.
#' @param where A simple SQL where statement indicating which features should be
#'   selected (e.g., "POPULATION > 1000"). Passed to \code{arcgislayers::arc_read}.
#'   Defaults to "1=1" (all features).
#' @param crs Target EPSG code (default `CRS_WGS`).
#' @param partitioning Character vector of columns to partition by (e.g. "co_name").
#' @param overwrite Logical. If \code{TRUE}, overwrites existing files. Default \code{FALSE}.
#' @return A string containing the full path to the saved file or directory.
#' @export
download_feature_layer <- function(
  url,
  name,
  save_dir = dirs$processed,
  where = "1=1",
  crs = CRS_WGS,
  partitioning = NULL,
  overwrite = FALSE
) {
  # 1. Dependency Check
  required_pkgs <- c("arcgislayers", "janitor", "sf", "dplyr", "duckdb", "DBI", "glue")
  missing_pkgs <- required_pkgs[
    !sapply(required_pkgs, requireNamespace, quietly = TRUE)
  ]
  if (length(missing_pkgs) > 0) {
    stop("Missing packages: ", paste(missing_pkgs, collapse = ", "))
  }

  # 2. Path Setup
  if (!dir.exists(save_dir)) {
    dir.create(save_dir, recursive = TRUE)
  }

  if (!is.null(partitioning)) {
    out_fp <- file.path(save_dir, name)
  } else {
    out_fp <- file.path(save_dir, paste0(name, ".parquet"))
  }

  # 3. Cache Check
  if (file.exists(out_fp) && !overwrite) {
    message(paste("✅ Exists:", name))
    return(out_fp)
  }

  message(paste("⬇️ Downloading:", name))

  # 4. Execution
  tryCatch(
    {
      sf_obj <- arcgislayers::arc_read(url, where = where, crs = crs)

      # Clean Names
      sf_obj <- janitor::clean_names(sf_obj)

      # Clean Names
      sf_obj <- sf::st_make_valid(sf_obj)

      # Force the active geometry column to be named "geometry".
      # ArcGIS often returns 'shape', 'Shape', or 'esrigeometry'.
      sf::st_geometry(sf_obj) <- "geometry"

      # Write via DuckDB — produces null CRS in GeoParquet metadata (DuckDB 1.5 compatible)
      con_write <- DBI::dbConnect(duckdb::duckdb())
      on.exit(DBI::dbDisconnect(con_write, shutdown = TRUE), add = TRUE)
      DBI::dbExecute(con_write, "INSTALL spatial; LOAD spatial;")
      DBI::dbExecute(con_write, "SET geometry_always_xy = true")

      df_out <- sf::st_drop_geometry(sf_obj)
      df_out[["geometry"]] <- sf::st_as_binary(sf::st_geometry(sf_obj))
      duckdb::duckdb_register(con_write, "_write_tmp", df_out)

      if (!is.null(partitioning)) {
        if (dir.exists(out_fp)) unlink(out_fp, recursive = TRUE)
        dir.create(out_fp, recursive = TRUE)
        partition_cols <- paste(partitioning, collapse = ", ")
        DBI::dbExecute(
          con_write,
          glue::glue(
            "COPY (SELECT * EXCLUDE geometry, ST_GeomFromWKB(geometry) AS geometry FROM _write_tmp) TO '{out_fp}' (FORMAT PARQUET, PARTITION_BY ({partition_cols}))"
          )
        )
        message(paste("💾 Saved Partitioned Dataset:", out_fp))
      } else {
        DBI::dbExecute(
          con_write,
          glue::glue(
            "COPY (SELECT * EXCLUDE geometry, ST_GeomFromWKB(geometry) AS geometry FROM _write_tmp) TO '{out_fp}' (FORMAT PARQUET)"
          )
        )
        message(paste("💾 Saved Parquet File:", out_fp))
      }

      duckdb::duckdb_unregister(con_write, "_write_tmp")

      rm(sf_obj, df_out)
      gc()

      return(out_fp)
    },
    error = function(e) {
      stop(paste("❌ Error downloading:", name, "\nReason:", e$message))
    }
  )
}
