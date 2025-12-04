#' Generate Isochrones and Save to Parquet
#'
#' Generates isochrones for points in a Parquet file (from PROCESSED)
#' and saves the result to PROCESSED.
#'
#' @param input_parquet Full path to input Parquet file.
#' @param output_name Desired output filename (without extension).
#' @param profile ORS profile (e.g., 'foot-walking').
#' @param ranges_sec Vector of time ranges in seconds.
#' @param batch_size Coordinates per API call (default 5).
#' @export
process_isochrones <- function(
  input_parquet,
  output_name,
  profile,
  ranges_sec,
  batch_size = 5,
  processed_dir = dirs$processed
) {
  # 1. Dependency Check
  required_pkgs <- c(
    "openrouteservice",
    "sf",
    "dplyr",
    "purrr",
    "arrow",
    "janitor"
  )
  missing_pkgs <- required_pkgs[
    !sapply(required_pkgs, requireNamespace, quietly = TRUE)
  ]
  if (length(missing_pkgs) > 0) {
    stop("Missing packages: ", paste(missing_pkgs, collapse = ", "))
  }

  # 2. Path Setup
  if (!dir.exists(processed_dir)) {
    dir.create(processed_dir, recursive = TRUE)
  }
  out_fp <- file.path(processed_dir, paste0(output_name, ".parquet"))

  if (file.exists(out_fp)) {
    message(paste("✅ Isochrones exist:", output_name))
    return(out_fp)
  }

  message(paste("🚀 Generating isochrones:", output_name))

  # 3. Execution
  tryCatch(
    {
      # Read Points (From Processed Parquet)
      points_sf <- arrow::read_parquet(input_parquet) |>
        sf::st_as_sf(wkt = "geometry", crs = 4326)

      coords_list <- purrr::map(
        1:nrow(points_sf),
        ~ sf::st_coordinates(points_sf)[., 1:2]
      )
      batches <- split(
        coords_list,
        ceiling(seq_along(coords_list) / batch_size)
      )

      message(paste("   Processing", length(batches), "batches..."))
      results_list <- list()

      for (i in seq_along(batches)) {
        tryCatch(
          {
            res <- openrouteservice::ors_isochrones(
              locations = batches[[i]],
              profile = profile,
              range = ranges_sec,
              output = "sf"
            )
            results_list[[i]] <- res
            Sys.sleep(1.5)
          },
          error = function(e) warning(paste("Batch", i, "failed"))
        )
      }

      if (length(results_list) > 0) {
        final_iso <- dplyr::bind_rows(results_list) |>
          janitor::clean_names() |>
          sf::st_cast("MULTIPOLYGON")

        arrow::write_parquet(final_iso, out_fp)
        message(paste("💾 Saved Isochrones:", out_fp))
        return(out_fp)
      } else {
        warning("❌ No isochrones generated.")
        return(NULL)
      }
    },
    error = function(e) {
      stop(paste("❌ Error in process_isochrones:", e$message))
    }
  )
}
