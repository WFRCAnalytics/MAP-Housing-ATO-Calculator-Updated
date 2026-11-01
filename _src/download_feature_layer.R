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

  # Write to a temp path and publish only on success (see publish_output()),
  # so an interrupted write is never mistaken for a cached layer.
  tmp_fp <- paste0(out_fp, ".tmp")
  unlink(tmp_fp, recursive = TRUE)

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

      # Write via DuckDB, which carries the sf object's CRS into the GeoParquet metadata
      write_sf_parquet(sf_obj, tmp_fp, crs, partitioning)
      publish_output(tmp_fp, out_fp)
      message(paste(
        if (is.null(partitioning)) "💾 Saved Parquet File:" else "💾 Saved Partitioned Dataset:",
        out_fp
      ))

      rm(sf_obj)
      gc()

      return(out_fp)
    },
    error = function(e) {
      stop(paste("❌ Error downloading:", name, "\nReason:", e$message))
    }
  )
}
