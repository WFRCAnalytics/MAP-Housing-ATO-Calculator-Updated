#' Download an ArcGIS Feature Layer to Parquet
#'
#' Downloads a layer from an ArcGIS FeatureServer, cleans names, projects it,
#' and saves it as a Parquet file in the PROCESSED directory.
#'
#' @param url URL to the FeatureServer layer.
#' @param name Desired output filename (without extension).
#' @param save_dir Directory to save the Parquet file. Defaults to `dirs$processed`.
#' @param query SQL-style WHERE clause (default "1=1").
#' @param crs Target EPSG code (default `CRS_PROJ`).
#' @export
download_feature_layer <- function(
  url,
  name,
  save_dir = dirs$processed,
  query = "1=1",
  crs = CRS_PROJ
) {
  # 1. Dependency Check
  required_pkgs <- c("arcgislayers", "janitor", "arrow")
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
  fp <- file.path(save_dir, paste0(name, ".parquet"))

  # 3. Cache Check
  if (file.exists(fp)) {
    message(paste("✅ Exists:", name))
    return(fp)
  }

  message(paste("⬇️ Downloading:", name))

  # 4. Execution
  tryCatch(
    {
      sf_obj <- arcgislayers::arc_read(url, where = query, crs = crs)

      # Clean & Save
      sf_obj <- janitor::clean_names(sf_obj)
      arrow::write_parquet(sf_obj, fp)

      message(paste("💾 Saved to processed:", fp))
      return(fp)
    },
    error = function(e) {
      stop(paste("❌ Error downloading:", name, "\nReason:", e$message))
    }
  )
}
