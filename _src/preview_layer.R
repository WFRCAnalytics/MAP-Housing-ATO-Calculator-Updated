#' Preview a Parquet Spatial Layer
#'
#' Lazy-loads a Parquet file, extracts a subset (head), converts the WKB
#' geometry to SF, and renders a map.
#'
#' @param file_path A string path to the parquet file.
#' @param color A string hex code or color name for the features (default: "steelblue").
#' @param limit An integer for the max number of features to load.
#'   Default is `NULL` (loads all data). If provided, loads the first N rows.
#' @param crs The CRS object or EPSG code to assign to the data (default: CRS_PROJ).
#'
#' @return A mapgl object (interactive map) or NULL if the file/column is missing.
#'
#' @export
preview_layer <- function(
  file_path,
  color = "steelblue",
  limit = NULL,
  crs = CRS_PROJ
) {
  # 1. Dependency Check
  required_pkgs <- c("arrow", "dplyr", "sf", "mapgl")
  missing_pkgs <- required_pkgs[
    !sapply(required_pkgs, requireNamespace, quietly = TRUE)
  ]

  if (length(missing_pkgs) > 0) {
    stop(paste0(
      "❌ Missing required packages: ",
      paste(missing_pkgs, collapse = ", ")
    ))
  }

  if (!file.exists(file_path)) {
    warning(paste("⚠️ File not found:", file_path))
    return(NULL)
  }

  tryCatch(
    {
      # 2. Lazy Load
      ds <- arrow::open_dataset(file_path)

      # 3. Apply Limit (Head) or Collect All
      # We use the Arrow engine (not DuckDB) to ensure WKB binary
      # is preserved as 'raw' vectors, which sf requires.
      if (!is.null(limit)) {
        df_raw <- ds |> head(limit) |> dplyr::collect()
      } else {
        df_raw <- dplyr::collect(ds)
      }

      # 4. Geometry Parsing
      if (!"geometry" %in% names(df_raw)) {
        stop("Column 'geometry' not found.")
      }

      # Explicitly convert binary WKB -> sfc
      df_raw$geometry <- sf::st_as_sfc(df_raw$geometry)

      # 5. Convert to SF
      sf_obj <- sf::st_as_sf(df_raw, crs = crs)

      # 6. Render
      mapgl::maplibre_view(
        sf_obj,
        tooltip = names(sf_obj)[1],
        fill_color = color,
        line_color = "white",
        fill_opacity = 0.6,
        line_width = 1
      )
    },
    error = function(e) {
      message(paste("❌ Preview failed:", basename(file_path)))
      message(paste("   Reason:", e$message))
      return(NULL)
    }
  )
}
