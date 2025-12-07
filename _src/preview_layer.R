#' Preview a Parquet Spatial Layer
#'
#' Lazy-loads a Parquet file, extracts a subset (head), converts the WKB
#' geometry to SF, and renders a map using mapgl::maplibre_view.
#'
#' @param file_path A string path to the parquet file.
#' @param ... Additional arguments passed to \code{mapgl::maplibre_view}
#'   (e.g., \code{tooltip}, \code{style}, \code{palette}, \code{n}).
#' @param limit An integer for the max number of features to load.
#'   Default is \code{NULL} (loads all data). If provided, loads the first N rows.
#'
#' @return A mapgl object (interactive map) or NULL if the file/column is missing.
#'
#' @export
preview_layer <- function(
  file_path,
  ...,
  limit = NULL
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
      # 1. Load Data
      ds <- arrow::open_dataset(file_path)

      # Check Metadata
      file_crs <- NULL
      if (!is.null(ds$metadata$geo)) {
        geo_meta <- jsonlite::fromJSON(ds$metadata$geo)
        file_crs <- geo_meta$columns$geometry$crs
      }

      # 2. Collect
      if (!is.null(limit)) {
        df_raw <- ds |> head(limit) |> dplyr::collect()
      } else {
        df_raw <- dplyr::collect(ds)
      }

      # 3. Handle Geometry
      col_names <- names(df_raw)
      geom_col <- col_names[grepl(
        "^(geometry|shape|geom)$",
        col_names,
        ignore.case = TRUE
      )][1]
      if (is.na(geom_col)) {
        stop("No geometry column found.")
      }
      if (geom_col != "geometry") {
        names(df_raw)[names(df_raw) == geom_col] <- "geometry"
      }

      # Fix WKB
      if (!inherits(df_raw$geometry, "sfc")) {
        df_raw$geometry <- sf::st_as_sfc(df_raw$geometry)
      }

      # 4. Create SF & Apply CRS
      sf_obj <- sf::st_as_sf(df_raw)

      # Priority: Metadata CRS > Argument CRS
      if (!is.null(file_crs)) {
        sf::st_crs(sf_obj) <- file_crs
      } else {
        sf::st_crs(sf_obj) <- crs
      }

      # 5. Render
      mapgl::maplibre_view(data = sf_obj, ...)
    },
    error = function(e) {
      message(paste(
        "❌ Preview failed:",
        basename(file_path),
        "\nReason:",
        e$message
      ))
      return(NULL)
    }
  )
}
