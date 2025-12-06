#' Process Vector File to Parquet
#'
#' Reads a vector file from the RAW directory (or a remote URL), cleans it,
#' projects it, and saves it as a Parquet file in the PROCESSED directory.
#'
#' @param path Path relative to `dirs$raw` OR a full URL.
#' @param name Desired output filename (without extension).
#' @param save_dir Directory to save the Parquet file. Defaults to `dirs$processed`.
#' @param layer (Optional) Layer name if reading from a multi-layer source (e.g. GDB).
#' @param crs Target EPSG code (default: `CRS_PROJ`).
#' @param read_mode How to read the file. Options:
#'   - "auto": (Default) Tries to guess based on extension/prefix.
#'   - "standard": Standard local file read (e.g. .shp, .gdb).
#'   - "zip": Local zip file (/vsizip/).
#'   - "url": Remote file (/vsicurl/).
#'   - "remote_zip": Remote zip file (/vsizip//vsicurl/).
#' @param partitioning Character vector of columns to partition by (e.g. "co_name").
#' @param ... Additional arguments passed to \code{arrow::write_dataset} or \code{arrow::write_parquet}
#'   (e.g., \code{compression = "snappy"}, \code{hive_style = FALSE}).
#'
#' @return A string containing the full path to the saved file or directory.
#' @export
process_local_layer <- function(
  path,
  name,
  save_dir = dirs$processed,
  layer = NULL,
  crs = CRS_PROJ,
  read_mode = "auto",
  partitioning = NULL,
  ...
) {
  # 1. Dependency Check
  required_pkgs <- c("sf", "janitor", "arrow")
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

  # 2. Path Setup
  if (!is.null(partitioning)) {
    out_fp <- file.path(save_dir, name)
  } else {
    out_fp <- file.path(save_dir, paste0(name, ".parquet"))
  }

  # 3. Cache Check
  if (file.exists(out_fp)) {
    message(paste("✅ Exists:", name))
    return(out_fp)
  }

  # 4. Resolve Mode & DSN
  dsn_path <- NULL

  # Helper booleans
  is_url_str <- grepl("^(http|ftp)s?://", path)
  is_zip_str <- grepl("\\.zip$", path, ignore.case = TRUE)

  # Auto-detect mode if not specified
  if (read_mode == "auto") {
    if (is_url_str && is_zip_str) {
      read_mode <- "remote_zip"
    } else if (is_url_str) {
      read_mode <- "url"
    } else if (is_zip_str) {
      read_mode <- "zip"
    } else {
      read_mode <- "standard"
    }
  }

  # Construct DSN based on Mode
  if (read_mode == "remote_zip") {
    message(paste("🌐 Reading Remote Zip:", path))
    dsn_path <- paste0("/vsizip//vsicurl/", path)
  } else if (read_mode == "url") {
    message(paste("🌐 Reading Remote URL:", path))
    dsn_path <- paste0("/vsicurl/", path)
  } else if (read_mode == "zip") {
    # Local Zip: Prepend Raw Directory + vsizip
    input_path <- file.path(dirs$raw, path)
    if (!file.exists(input_path)) {
      warning("Input not found:", input_path)
      return(NULL)
    }

    message(paste("📦 Reading Local Zip:", path))
    dsn_path <- paste0("/vsizip/", input_path)
  } else {
    # Standard: Prepend Raw Directory
    input_path <- file.path(dirs$raw, path)
    if (!file.exists(input_path)) {
      warning("Input not found:", input_path)
      return(NULL)
    }

    message(paste("⚙️ Processing:", name))
    dsn_path <- input_path
  }

  # 5. Execution
  tryCatch(
    {
      # Read
      # We add options to ignore the expensive hole-sorting check
      # This makes reading massive/complex polygons much faster
      if (!is.null(layer)) {
        sf_obj <- sf::st_read(
          dsn = dsn_path,
          layer = layer,
          quiet = TRUE
        )
      } else {
        sf_obj <- sf::st_read(
          dsn = dsn_path,
          quiet = TRUE
        )
      }

      # 1. Standardize Names & Drop Z/M
      sf_obj <- sf_obj |>
        janitor::clean_names() |>
        sf::st_zm(drop = TRUE)

      # 2. Linearize Curved Geometries ONLY
      # We check specific types present, not the summary "GEOMETRY"
      present_types <- sf::st_geometry_type(sf_obj) |>
        unique() |>
        as.character()

      # Check if any "bad" types (Curves/Surfaces) exist
      has_curves <- any(grepl("CURVE|SURFACE|ARC", present_types))

      if (has_curves) {
        target_cast <- NULL

        # If it's a Polygon-type curve (CURVEPOLYGON, MULTISURFACE)
        if (any(grepl("POLYGON|SURFACE", present_types))) {
          target_cast <- "MULTIPOLYGON"
          # If it's a Line-type curve (MULTICURVE, CIRCULARSTRING, COMPOUNDCURVE)
          # We check for CURVE here specifically for lines if it wasn't a polygon
        } else if (any(grepl("LINE|STRING|ARC|CURVE", present_types))) {
          target_cast <- "MULTILINESTRING"
        }

        if (!is.null(target_cast)) {
          message(paste("   ⚠️ Linearizing curved geometry to:", target_cast))
          sf_obj <- sf::st_cast(sf_obj, target_cast)
        }
      }

      # 3. Final Fixes & Project

      sf_obj <- sf_obj |>
        sf::st_make_valid() |>
        sf::st_transform(crs)

      # 4. Standardize Geometry Name
      sf::st_geometry(sf_obj) <- "geometry"

      # Write (Conditional with Ellipsis)
      if (!is.null(partitioning)) {
        arrow::write_dataset(
          dataset = sf_obj,
          path = out_fp,
          format = "parquet",
          partitioning = partitioning,
          existing_data_behavior = "overwrite",
          ...
        )
        message(paste("💾 Saved Partitioned Dataset:", out_fp))
      } else {
        arrow::write_parquet(
          x = sf_obj,
          sink = out_fp,
          ...
        )
        message(paste("💾 Saved Parquet File:", out_fp))
      }

      return(out_fp)
    },
    error = function(e) {
      warning(paste("❌ Error processing", name, ":", e$message))
      return(NULL)
    }
  )
}
