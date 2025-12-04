#' Process Local Vector File (GDB/SHP) to Parquet
#'
#' Reads a raw vector file from the RAW directory, cleans it, projects it,
#' and saves it as a Parquet file in the PROCESSED directory.
#'
#' @param relative_path Path relative to `dirs$raw` (e.g., "Folder/file.shp").
#' @param output_name Desired output filename (without extension).
#' @param layer_name (Optional) Layer name if reading from GDB.
#' @param target_crs Target EPSG code (default `CRS_PROJ`).
#' @export
process_local_layer <- function(
  relative_path,
  output_name,
  layer_name = NULL,
  target_crs = CRS_PROJ
) {
  # 1. Define Paths
  input_path <- file.path(dirs$raw, relative_path)
  out_fp <- file.path(dirs$processed, paste0(output_name, ".parquet"))

  # 2. Cache Check
  if (file.exists(out_fp)) {
    message(paste("✅ Exists:", output_name))
    return(out_fp)
  }

  if (!file.exists(input_path)) {
    warning(paste("⚠️ Input file not found in raw:", relative_path))
    return(NULL)
  }

  message(paste("⚙️ Processing local file:", output_name))

  # 3. Execution
  tryCatch(
    {
      # Read GDB vs Shapefile
      if (!is.null(layer_name)) {
        sf_obj <- sf::st_read(
          dsn = input_path,
          layer = layer_name,
          quiet = TRUE
        )
      } else {
        sf_obj <- sf::st_read(input_path, quiet = TRUE)
      }

      # Clean, Transform, Save
      sf_obj <- sf_obj |>
        janitor::clean_names() |>
        sf::st_transform(target_crs)

      arrow::write_parquet(sf_obj, out_fp)
      message(paste("💾 Saved to processed:", out_fp))
      return(out_fp)
    },
    error = function(e) {
      warning(paste("❌ Error processing", output_name, ":", e$message))
      return(NULL)
    }
  )
}
