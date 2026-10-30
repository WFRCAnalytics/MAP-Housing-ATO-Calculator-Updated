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
#' @param boundary_crs The EPSG code of the boundary file (e.g., "EPSG:26912").
#'   Defaults to "EPSG:4326" (which matches your new boundary generation).
#' @param batch_size An integer number of coordinates to send per API call (default 5).
#' @param save_dir A string path to the isochrone profile directory.
#'   Defaults to `dirs$isochrones`.
#' @param crs Projected EPSG code for spatial operations (default `CRS_STP`).
#' @param dry_run Logical. If `TRUE`, prints batch details without calling the API.
#' @param overwrite Logical. If \code{TRUE}, overwrites existing files. Default \code{FALSE}.
#' @param max_retries Attempts per API batch before the layer fails (default 3).
#'   Completed batches are checkpointed in `<output>.parquet.parts/`, so a
#'   failed run resumes from the last good batch when re-run.
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
#' Requires `openrouteservice`, `sf`, `dplyr`, `purrr`, `janitor`, `duckdb`, `DBI`, `glue`.
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
  boundary_crs = "EPSG:4326",
  batch_size = 5,
  save_dir = dirs$isochrones,
  crs = CRS_STP,
  dry_run = TRUE,
  overwrite = FALSE,
  max_retries = 3,
  ...
) {
  # 1. Dependency Check
  required_pkgs <- c(
    "openrouteservice",
    "sf",
    "dplyr",
    "purrr",
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
  target_dir <- save_dir
  if (!dir.exists(target_dir)) {
    dir.create(target_dir, recursive = TRUE)
  }
  out_fp <- file.path(target_dir, paste0(name, ".parquet"))

  # 3. Cache Check
  if (file.exists(out_fp) && !overwrite && !dry_run) {
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
      DBI::dbExecute(conn, "SET geometry_always_xy = true")
      # DBI::dbExecute(conn, "CALL register_geoarrow_extensions()")

      # --- QUERY CONSTRUCTION ---
      if (!is.null(boundary_path)) {
        # Project boundary into analysis CRS; transform points at ST_Intersects time.
        # ST_X/ST_Y are extracted from the original EPSG:4326 geometry for the ORS API.
        query_view <- glue::glue(
          "
          CREATE OR REPLACE VIEW input_points AS
          WITH region_source AS (
            SELECT ST_Transform(geometry, '{boundary_crs}', '{crs}') as geom
            FROM read_parquet('{boundary_path}')
          ),
          region_unified AS (
            SELECT ST_Union_Agg(geom) as geom
            FROM region_source
          )
          SELECT
            ST_X(pts.geometry) as lon,
            ST_Y(pts.geometry) as lat
          FROM read_parquet('{path}') pts, region_unified
          WHERE
            {input_filter}
            AND ST_Intersects(
              ST_Transform(pts.geometry, 'EPSG:4326', '{crs}'),
              region_unified.geom
            )
        "
        )
        message(
          "   🛡️  Filtering | SQL: [",
          input_filter,
          "] | Boundary: [",
          basename(boundary_path),
          "] | Analysis CRS: [",
          crs,
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

      # Fetch the points ONCE, in a stable order, and batch them in R. Batch i
      # always covers the same points, and the boundary filter runs a single
      # time instead of once per API batch.
      pts <- DBI::dbGetQuery(
        conn,
        "SELECT lon, lat FROM input_points ORDER BY lon, lat"
      )
      total_rows <- nrow(pts)
      batches <- split(
        seq_len(total_rows),
        ceiling(seq_len(total_rows) / batch_size)
      )
      num_batches <- length(batches)
      batch_coords <- function(i) {
        purrr::array_branch(as.matrix(pts[batches[[i]], c("lon", "lat")]), 1)
      }

      # --- DRY RUN ---
      if (dry_run) {
        message("⚠️  DRY RUN: API Request Preview (Streaming Mode)")
        message("------------------------------------------------")
        message(paste("   Input File:   ", basename(path)))
        message(paste("   Total Points: ", total_rows))
        message(paste("   Batch Size:   ", batch_size))
        message(paste("   Num Batches:  ", num_batches))

        if (num_batches > 0) {
          message("   Sample Batch 1 (Coordinates):")
          print(batch_coords(1))
        }
        return(invisible(NULL))
      }

      # Checkpoint each batch to disk so a crash or ORS outage resumes where
      # it stopped. The checkpoint is discarded if the request signature
      # (profile, range, filter, ...) differs from the one that wrote it.
      parts_dir <- paste0(out_fp, ".parts")
      sig_fp <- file.path(parts_dir, "signature.rds")
      sig <- list(profile, range, input_filter, batch_size, total_rows, list(...))
      if (dir.exists(parts_dir) && !identical(tryCatch(readRDS(sig_fp), error = function(e) NULL), sig)) {
        message("   ♻️  Stale checkpoint found, discarding")
        unlink(parts_dir, recursive = TRUE)
      }
      dir.create(parts_dir, recursive = TRUE, showWarnings = FALSE)
      saveRDS(sig, sig_fp)

      n_done <- length(list.files(parts_dir, pattern = "^batch_"))
      if (n_done > 0) message("   ▶️  Resuming: ", n_done, "/", num_batches, " batches already done")
      message(paste("   Streaming", num_batches, "batches..."))

      # 4. Process Batches
      # A batch is retried; if it still fails the whole layer fails, so a
      # partial isochrone layer is never saved (and then cached as complete).
      results_list <- purrr::map(
        seq_len(num_batches),
        function(i) {
          part_fp <- file.path(parts_dir, sprintf("batch_%05d.rds", i))
          if (file.exists(part_fp)) return(readRDS(part_fp))

          res <- NULL
          for (attempt in seq_len(max_retries)) {
            res <- tryCatch(
              openrouteservice::ors_isochrones(
                locations = batch_coords(i),
                profile = profile,
                range = range,
                output = "sf",
                ...
              ),
              error = function(e) {
                message("   ⚠️ Batch ", i, " attempt ", attempt, "/", max_retries, " failed: ", conditionMessage(e))
                NULL
              }
            )
            if (!is.null(res)) break
            Sys.sleep(2 * attempt)
          }
          if (is.null(res)) {
            stop("Batch ", i, "/", num_batches, " failed after ", max_retries,
                 " attempts. Re-run to resume from the saved batches.")
          }
          saveRDS(res, part_fp)
          res
        },
        .progress = TRUE
      )

      # 5. Save Results
      final_iso <- dplyr::bind_rows(results_list)

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

        # Write via DuckDB so the output uses null CRS (DuckDB-readable) instead
        # of the WKT-string CRS that geoarrow writes, which DuckDB 1.5 rejects.
        df_out <- sf::st_drop_geometry(final_iso)
        df_out[["geometry"]] <- sf::st_as_binary(sf::st_geometry(final_iso))
        duckdb::duckdb_register(conn, "_iso_write", df_out)
        tmp_fp <- paste0(out_fp, ".tmp")
        unlink(tmp_fp)
        DBI::dbExecute(
          conn,
          glue::glue(
            "COPY (SELECT * EXCLUDE geometry, ST_GeomFromWKB(geometry) AS geometry FROM _iso_write) TO '{tmp_fp}' (FORMAT PARQUET)"
          )
        )
        duckdb::duckdb_unregister(conn, "_iso_write")
        publish_output(tmp_fp, out_fp)
        unlink(parts_dir, recursive = TRUE)
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
