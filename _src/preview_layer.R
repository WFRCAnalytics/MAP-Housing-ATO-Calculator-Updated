#' Preview a Parquet Spatial Layer
#'
#' Lazy-loads a Parquet file containing spatial data, extracts a sample subset,
#' converts the WKB (Well-Known Binary) geometry column into an sf object,
#' and renders an interactive map using mapgl.
#'
#' @param file_path A string path to the parquet file.
#' @param color A string hex code or color name for the features (default: "steelblue").
#' @param limit An integer for the max number of features to load (default: 1000).
#'   Setting this prevents R from crashing when previewing massive datasets.
#' @param crs The CRS object or EPSG code to assign to the data (default: CRS_PROJ).
#'
#' @return A mapgl object (interactive map) or NULL if the file/column is missing.
#'
#' @section Dependencies:
#' Requires `arrow`, `dplyr`, `sf`, and `mapgl`.
#'
#' @examples
#' \dontrun{
#'   preview_layer("_data/processed/base/parcels.parquet", color = "orange")
#' }
#'
#' @export
preview_layer <- function(
  file_path,
  color = "steelblue",
  limit = 1000,
  crs = CRS_PROJ
) {
  # 1. Dependency Check
  required_pkgs <- c("arrow", "dplyr", "sf", "mapgl")
  missing_pkgs <- required_pkgs[
    !sapply(required_pkgs, requireNamespace, quietly = TRUE)
  ]

  if (length(missing_pkgs) > 0) {
    stop(paste0(
      "❌ Missing required packages for preview_layer: ",
      paste(missing_pkgs, collapse = ", "),
      ". Please install them."
    ))
  }

  # 2. File Check
  if (!file.exists(file_path)) {
    warning(paste("⚠️ File does not exist:", file_path))
    return(NULL)
  }

  tryCatch(
    {
      # 3. Lazy Load & Collect
      # We use arrow::open_dataset() to peek without reading into RAM
      # We use head() to push down the limit query to the file reader
      df_raw <- arrow::open_dataset(file_path) |>
        head(limit) |>
        dplyr::collect()

      # 4. Geometry Parsing
      # Arrow returns geometry as a binary blob (WKB).
      # We must verify the column exists and convert it to 'sfc'
      if (!"geometry" %in% names(df_raw)) {
        stop("Column 'geometry' not found. Is this a spatial parquet?")
      }

      # Convert raw binary -> sfc geometry column
      df_raw$geometry <- sf::st_as_sfc(df_raw$geometry)

      # 5. Convert to SF & Assign CRS
      sf_obj <- sf::st_as_sf(df_raw, crs = crs)

      # 6. Render Map
      mapgl::maplibre_view(
        sf_obj,
        tooltip = names(sf_obj)[1], # Default tooltip to first column
        fill_color = color,
        line_color = "white",
        fill_opacity = 0.6,
        line_width = 1
      )
    },
    error = function(e) {
      message(paste("❌ Could not preview layer:", basename(file_path)))
      message(paste("   Reason:", e$message))
      return(NULL)
    }
  )
}
