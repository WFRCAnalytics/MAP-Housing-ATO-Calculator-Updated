#' Process Vector File to Parquet
#'
#' Reads a vector file from the RAW directory (or a remote URL), cleans it,
#' projects it, and saves it as a Parquet file in the PROCESSED directory.
#'
#' @param path Path relative to `dirs$raw` OR a full URL.
#' @param name Desired output filename (without extension).
#' @param save_dir Directory to save the Parquet file. Defaults to `dirs$processed`.
#' @param layer (Optional) Layer name if reading from a multi-layer source (e.g. GDB).
#' @param query (Optional) An SQL query string to select/filter records using the
#'   OGR SQL engine (e.g., "SELECT * FROM layer WHERE id > 5"). If provided,
#'   this overrides the `layer` argument in many drivers. Default \code{NA}.
#' @param crs Target EPSG code (default: `CRS_PROJ`).
#' @param read_mode How to read the file. Options:
#'   - "auto": (Default) Tries to guess based on extension/prefix.
#'   - "standard": Standard local file read (e.g. .shp, .gdb).
#'   - "zip": Local zip file (/vsizip/).
#'   - "url": Remote file (/vsicurl/).
#'   - "remote_zip": Remote zip file (/vsizip//vsicurl/).
#' @param partitioning Character vector of columns to partition by (e.g. "co_name").
#' @param overwrite Logical. If \code{TRUE}, overwrites existing files. Default \code{FALSE}.
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
  query = NA,
  crs = CRS_PROJ,
  read_mode = "auto",
  partitioning = NULL,
  overwrite = FALSE,
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
  if (file.exists(out_fp) && !overwrite) {
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
      # If 'query' is provided, pass it to st_read.
      # Note: For some drivers, providing 'query' creates a new layer result, so 'layer' might be ignored.
      if (!is.na(query)) {
        sf_obj <- sf::st_read(dsn = dsn_path, query = query, quiet = TRUE)
      } else if (!is.null(layer)) {
        sf_obj <- sf::st_read(dsn = dsn_path, layer = layer, quiet = TRUE)
      } else {
        sf_obj <- sf::st_read(dsn = dsn_path, quiet = TRUE)
      }
      # 1. Standardize Names & Drop Z/M
      sf_obj <- sf_obj |>
        janitor::clean_names() |>
        sf::st_zm(drop = TRUE)

      # 2. Linearize Curved Geometries ONLY
      # Instead of checking every row, we check the class of the geometry column.

      current_types <- unique(as.character(sf::st_geometry_type(sf_obj)))

      # Define Complex Types that need Linearization
      complex_polys <- c(
        "CURVEPOLYGON",
        "MULTISURFACE",
        "SURFACE",
        "POLYHEDRALSURFACE",
        "TIN"
      )
      complex_lines <- c(
        "CIRCULARSTRING",
        "COMPOUNDCURVE",
        "MULTICURVE",
        "CURVE"
      )

      # Conditional Casting
      if (any(current_types %in% complex_polys)) {
        # Convert Curves/Surfaces -> MultiPolygon
        sf_obj <- sf::st_cast(sf_obj, "MULTIPOLYGON")
      } else if (any(current_types %in% complex_lines)) {
        # Convert Curved Lines -> MultiLineString
        sf_obj <- sf::st_cast(sf_obj, "MULTILINESTRING")
      }
      # ELSE: Do nothing. Keep Point as Point, Polygon as Polygon.

      # if (grepl("POLYGON|SURFACE", geom_class_str, ignore.case = TRUE)) {
      #   # If it's any kind of Polygon/Surface (including CurvePolygon), we force MULTIPOLYGON.
      #   sf_obj <- sf::st_cast(sf_obj, "MULTIPOLYGON")
      # } else if (grepl("LINE|CURVE", geom_class_str, ignore.case = TRUE)) {
      #   # If it's Line/Curve (including MultiCurve), we force MULTILINESTRING.
      #   sf_obj <- sf::st_cast(sf_obj, "MULTILINESTRING")
      # }

      # if (any(grepl("CURVE|SURFACE|ARC", geom_class_str, ignore.case = TRUE))) {
      #   target <- if (
      #     any(grepl("POLYGON|SURFACE", , geom_class_str, ignore.case = TRUE))
      #   ) {
      #     "MULTIPOLYGON"
      #   } else {
      #     "MULTILINESTRING"
      #   }
      #   sf_obj <- sf::st_cast(sf_obj, target)
      # }

      # 3. Final Fixes & Project
      sf_obj <- sf_obj |>
        sf::st_make_valid() |>
        sf::st_transform(crs)

      # 4. Standardize Geometry Name
      sf::st_geometry(sf_obj) <- "geometry"

      # Prepare GeoParquet
      arrow_table <- as_geoparquet_table(sf_obj)

      # Write (Conditional with Ellipsis)
      if (!is.null(partitioning)) {
        # Ensure directory clean/create for partitioning
        if (dir.exists(out_fp)) {
          fs::dir_delete(out_fp)
        }

        arrow::write_dataset(
          dataset = arrow_table,
          path = out_fp,
          format = "parquet",
          partitioning = partitioning,
          existing_data_behavior = "overwrite",
          ...
        )
        message(paste("💾 Saved Partitioned Dataset:", out_fp))
      } else {
        arrow::write_parquet(
          x = arrow_table,
          sink = out_fp,
          ...
        )
        message(paste("💾 Saved Parquet File:", out_fp))
      }

      # MEMORY OPTIMIZATION:
      # Explicitly remove the huge object and run GC immediately
      rm(sf_obj, arrow_table)
      gc()

      return(out_fp)
    },
    error = function(e) {
      warning(paste("❌ Error processing", name, ":", e$message))
      return(NULL)
    }
  )
}
