#' Generate Isochrones and Save to Parquet
#'
#' Generates isochrones for points in a Parquet file using the OpenRouteService API.
#' Supports both time-based and distance-based isochrones via the `range` argument.
#' The output is automatically saved into a subfolder corresponding to the routing profile.
#'
#' @param path A string path to the input Parquet file (from PROCESSED).
#' @param name Desired output filename (without extension).
#' @param profile A string for the ORS routing profile (e.g., 'foot-walking', 'driving-car').
#' @param range A numeric vector of ranges.
#'   If `range_type = "time"` (default), values are in **seconds**.
#'   If `range_type = "distance"`, values are in **meters**.
#' @param batch_size An integer number of coordinates to send per API call (default 5).
#' @param save_dir A string path to the root isochrone directory.
#'   Defaults to `dirs$isochrones`.
#' @param crs Target EPSG code (default `CRS_PROJ`).
#' @param dry_run Logical. If `TRUE`, prints batch details without calling the API.
#' @param ... Additional arguments passed to \code{openrouteservice::ors_isochrones}.
#'   Common options include:
#'   \itemize{
#'     \item \code{range_type}: "time" (default) or "distance".
#'     \item \code{units}: "m", "km", or "mi" (for distance).
#'     \item \code{interval}: Segmentation interval (e.g., break 600s into 60s chunks).
#'     \item \code{location_type}: "start" (default) or "destination".
#'     \item \code{smoothing}: Float between 0 and 1.
#'     \item \code{attributes}: Vector like \code{c("area", "reachfactor", "total_pop")}.
#'   }
#'
#' @return A string containing the file path to the saved isochrone Parquet file,
#'   or NULL if dry_run is TRUE or generation fails.
#'
#' @section Dependencies:
#' Requires `openrouteservice`, `sf`, `dplyr`, `purrr`, `arrow`, `janitor`.
#'
#' @examples
#' \dontrun{
#'   # Example 1: Time-based (Walking, 5 & 10 mins) with Population Attributes
#'   process_isochrones(
#'     path = "_data/processed/amenities/grocery.parquet",
#'     name = "iso_grocery_walk",
#'     profile = "foot-walking",
#'     range = c(300, 600),
#'     attributes = c("total_pop", "area")
#'   )
#'
#'   # Example 2: Distance-based (Driving, 5km & 10km)
#'   process_isochrones(
#'     path = "_data/processed/landuse/centers.parquet",
#'     name = "iso_centers_drive_dist",
#'     profile = "driving-car",
#'     range = c(5000, 10000),
#'     range_type = "distance",
#'     units = "m"
#'   )
#' }
#'
#' @export
process_isochrones <- function(
  path,
  name,
  profile,
  range,
  batch_size = 5,
  save_dir = dirs$isochrones,
  crs = CRS_PROJ,
  dry_run = TRUE,
  ...
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
  target_dir <- file.path(save_dir, profile)
  if (!dir.exists(target_dir)) {
    dir.create(target_dir, recursive = TRUE)
  }
  out_fp <- file.path(target_dir, paste0(name, ".parquet"))

  # 3. Cache Check
  if (file.exists(out_fp) && !dry_run) {
    message(paste("✅ Isochrones exist:", name))
    return(out_fp)
  }

  message(paste("🚀 Generating isochrones:", name, "| Profile:", profile))

  tryCatch(
    {
      # 3. Read & Prepare Data
      points_sf <- arrow::read_parquet(path) |>
        sf::st_as_sf() |>
        sf::st_transform(4326) # ORS requires WGS84

      # Prepare Batches
      coords_mat <- sf::st_coordinates(points_sf)
      coords_list <- purrr::array_branch(coords_mat[, 1:2], 1)
      batches <- split(
        coords_list,
        ceiling(seq_along(coords_list) / batch_size)
      )

      # --- DRY RUN SIMULATION ---
      if (dry_run) {
        message("⚠️  DRY RUN: API Request Preview")
        message("------------------------------------------------")
        message(paste("   Input File:   ", basename(path)))
        message(paste("   Output Path:  ", out_fp))
        message(paste("   Total Points: ", length(coords_list)))
        message(paste("   Batch Size:   ", batch_size))
        message(paste("   Num Batches:  ", length(batches)))

        # Capture the arguments that WOULD be sent
        api_params <- list(
          locations = "Batch 1 (Coordinates hidden)",
          profile = profile,
          range = range,
          output = "sf",
          ... # This captures units, range_type, etc.
        )

        message("   API Parameters (passed to ors_isochrones):")
        print(api_params)
        message("------------------------------------------------")
        return(invisible(NULL))
      }

      message(paste("   Mapping over", length(batches), "batches..."))

      # 4. Execute Batches
      results_list <- purrr::imap(batches, function(batch, i) {
        Sys.sleep(1.5) # Rate limit

        tryCatch(
          {
            openrouteservice::ors_isochrones(
              locations = batch,
              profile = profile,
              range = range, # Renamed from ranges_sec
              output = "sf",
              ... # Passes range_type, units, interval, etc.
            )
          },
          error = function(e) {
            warning(paste("   ⚠️ Batch", i, "failed:", e$message))
            return(NULL)
          }
        )
      })

      # 5. Collapse & Save
      final_iso <- results_list |>
        purrr::discard(is.null) |>
        dplyr::bind_rows()

      if (nrow(final_iso) > 0) {
        final_iso <- final_iso |>
          janitor::clean_names() |>
          sf::st_cast("MULTIPOLYGON") |>
          sf::st_transform(crs) # Project back to local CRS

        # Standardize geometry column name for downstream consistency
        sf::st_geometry(final_iso) <- "geometry"

        arrow::write_parquet(final_iso, out_fp)
        message(paste("💾 Saved:", out_fp))
        return(out_fp)
      } else {
        warning("❌ No isochrones generated.")
        return(NULL)
      }
    },
    error = function(e) stop(paste("❌ Error:", e$message))
  )
}
