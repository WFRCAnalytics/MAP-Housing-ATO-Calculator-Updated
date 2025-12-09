#' Generate Isochrones and Save to Parquet
#'
#' Generates isochrones for points in a Parquet file using the OpenRouteService API.
#' Supports both time-based and distance-based isochrones via the `range` argument.
#' The output is automatically saved into a subfolder corresponding to the routing profile.
#' Uses DuckDB to stream coordinates efficiently without loading the entire input file into memory.
#'
#' @param path A string path to the input Parquet file (from PROCESSED).
#' @param name Desired output filename (without extension).
#' @param profile A string for the ORS routing profile (e.g., 'foot-walking', 'driving-car').
#' @param range A numeric vector of ranges.
#'   If `range_type = "time"` (default), values are in **seconds**.
#'   If `range_type = "distance"`, values are in **meters**.
#' @param input_filter A SQL WHERE clause to filter input points (e.g., "type = 'Grocery'").
#' @param boundary_path Path to the regional boundary parquet (optional).
#' @param batch_size An integer number of coordinates to send per API call (default 5).
#' @param save_dir A string path to the root isochrone directory.
#'   Defaults to `dirs$isochrones`.
#' @param crs Projected EPSG code for spatial operations (default `CRS_STP`).
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
#' Requires `openrouteservice`, `sf`, `dplyr`, `purrr`, `arrow`, `geoarrow`, `janitor`, `duckdb`, `DBI`.
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
  input_filter = "1=1",
  boundary_path = NULL,
  batch_size = 5,
  save_dir = dirs$isochrones,
  crs = CRS_STP,
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
    "geoarrow",
    "janitor",
    "duckdb",
    "DBI",
    "glue"
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

  # 3. Connect to DuckDB
  conn <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(conn, shutdown = TRUE), add = TRUE)

  tryCatch(
    {
      DBI::dbExecute(conn, "INSTALL spatial; LOAD spatial;")
      # DBI::dbExecute(conn, "CALL register_geoarrow_extensions()")

      # --- QUERY CONSTRUCTION ---
      if (!is.null(boundary_path)) {
        # 1. Read ANY boundary file -> 2. Dissolve All Features -> 3. Spatial Join
        query_view <- glue::glue(
          "
          CREATE OR REPLACE VIEW input_points AS
          WITH region_source AS (
            -- 1. Read Boundary (4326) and convert WKB to Geometry
            SELECT geometry as geom FROM read_parquet('{boundary_path}')
          ),
          region_projected AS (
            -- 2. Project to Meter Plane (3566) and FIX VALIDITY
            -- ST_MakeValid is crucial to prevent crashes during Union
            SELECT ST_MakeValid(ST_Transform(geom, 'EPSG:4326', '{crs}')) as geom
            FROM region_source
          ),
          region_unified AS (
            -- 3. Safely Dissolve (Union) all boundary features into one
            SELECT ST_Union_Agg(geom) as geom FROM region_projected
          ),
          pts AS (
            -- 4. Read Points (4326) -> Filter Attributes
            SELECT * FROM read_parquet('{path}')
            WHERE {input_filter}
          )
          SELECT
            -- 6. Extract Original 4326 Coordinates for API
            ST_X(pts.geometry) as lon,
            ST_Y(pts.geometry) as lat
          FROM pts, region_unified
          -- 5. Project Point to Meter Plane (3566) -> Intersect with Dissolved Boundary
          WHERE ST_Intersects(ST_Transform(pts.geometry, 'EPSG:4326', '{crs}'), region_unified.geom)
        "
        )
        message(
          "   🛡️  Filtering | SQL: [",
          input_filter,
          "] | Boundary: [",
          basename(boundary_path),
          "]"
        )
      } else {
        # Original query (No boundary)
        query_view <- glue::glue(
          "
          CREATE OR REPLACE VIEW input_points AS
          SELECT
            ST_X(geometry) as lon,
            ST_Y(geometry) as lat
          FROM read_parquet('{path}')
          WHERE {input_filter}
        "
        )
        message("   🔎 Filtering | SQL: [", input_filter, "]")
      }

      DBI::dbExecute(conn, query_view)

      # Count total rows
      total_rows <- DBI::dbGetQuery(
        conn,
        "SELECT COUNT(*) as n FROM input_points"
      )$n
      num_batches <- ceiling(total_rows / batch_size)

      # --- DRY RUN ---
      if (dry_run) {
        message("⚠️  DRY RUN: API Request Preview (Streaming Mode)")
        message("------------------------------------------------")
        message(paste("   Input File:   ", basename(path)))
        message(paste("   Total Points: ", total_rows))
        message(paste("   Batch Size:   ", batch_size))
        message(paste("   Num Batches:  ", num_batches))

        # Sample first batch query
        sample_batch <- DBI::dbGetQuery(
          conn,
          glue::glue(
            "SELECT lon, lat FROM input_points LIMIT {batch_size} OFFSET 0"
          )
        )
        # Convert to list of pairs for API
        sample_list <- purrr::array_branch(as.matrix(sample_batch), 1)

        message("   Sample Batch 1 (Coordinates):")
        print(sample_list)
        return(invisible(NULL))
      }

      message(paste("   Streaming", num_batches, "batches..."))

      # 4. Process Batches (Streaming Loop)
      results_list <- purrr::map(
        1:num_batches,
        function(i) {
          # Calculate OFFSET
          offset <- (i - 1) * batch_size

          # Fetch just this batch from DuckDB
          # This keeps RAM usage tiny regardless of dataset size
          batch_df <- DBI::dbGetQuery(
            conn,
            glue::glue(
              "SELECT lon, lat FROM input_points LIMIT {batch_size} OFFSET {offset}"
            )
          )

          # Convert to API format (List of c(lon, lat))
          batch_coords <- purrr::array_branch(as.matrix(batch_df), 1)

          # Rate Limit Sleep
          Sys.sleep(1.5)

          tryCatch(
            {
              openrouteservice::ors_isochrones(
                locations = batch_coords,
                profile = profile,
                range = range,
                output = "sf",
                ...
              )
            },
            error = function(e) {
              warning(paste("   ⚠️ Batch", i, "failed:", e$message))
              return(NULL)
            }
          )
        },
        .progress = TRUE
      ) # Add progress bar!

      # 5. Save Results
      final_iso <- results_list |>
        purrr::discard(is.null) |>
        dplyr::bind_rows()

      if (nrow(final_iso) > 0) {
        # API returns 4326. We simply save it as 4326.
        final_iso <- final_iso |>
          janitor::clean_names() |>
          sf::st_cast("MULTIPOLYGON")

        sf::st_geometry(final_iso) <- "geometry"

        # Ensure CRS is set (ORS output usually has it, but good to be explicit)
        if (is.na(sf::st_crs(final_iso))) {
          sf::st_crs(final_iso) <- 4326
        }

        arrow_table <- as_geoparquet_table(final_iso)

        arrow::write_parquet(arrow_table, out_fp)
        message(paste("💾 Saved:", out_fp))
        return(out_fp)

        rm(final_iso, arrow_table)
        gc()
      } else {
        warning("❌ No isochrones generated.")
        return(NULL)
      }
    },
    error = function(e) stop(paste("❌ Error:", e$message))
  )
}
