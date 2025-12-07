#' Convert SF Object to Arrow Table with GeoParquet Metadata
#'
#' Converts an sf object to an Arrow Table and manually injects the
#' GeoParquet 1.0.0 JSON metadata so tools like QGIS and DuckDB
#' can auto-detect the CRS.
#'
#' @param sf_obj An sf object.
#' @return An arrow::Table with "geo" metadata.
#' @export
as_geoparquet_table <- function(sf_obj) {
  # 1. Capture Spatial Metadata
  geom_col_name <- attr(sf_obj, "sf_column")
  if (is.null(geom_col_name)) {
    stop("Input is not a valid sf object.")
  }

  crs_obj <- sf::st_crs(sf_obj)
  bbox <- sf::st_bbox(sf_obj)

  # Cast factor -> character to prevent "argument is not a character vector" error
  geometry_types <- unique(as.character(sf::st_geometry_type(sf_obj)))

  # 2. Convert Geometry to WKB (Raw Binary)
  wkb_geometry <- sf::st_as_binary(sf::st_geometry(sf_obj))
  wkb_geometry <- unclass(wkb_geometry) # Strip "WKB" class for arrow

  # 3. Create DataFrame for Arrow
  df <- as.data.frame(sf_obj)
  df[[geom_col_name]] <- wkb_geometry

  # 4. Convert to Arrow Table
  table <- arrow::as_arrow_table(df)

  # 5. Construct Metadata (GeoParquet 1.0.0 Spec)
  crs_def <- if (!is.na(crs_obj$wkt)) crs_obj$wkt else NULL

  geo_meta <- list(
    version = "1.0.0",
    primary_column = geom_col_name,
    columns = list()
  )

  geo_meta$columns[[geom_col_name]] <- list(
    encoding = "WKB",
    geometry_types = as.list(geometry_types),
    crs = crs_def,
    bbox = as.numeric(bbox)
  )

  # 6. Inject Metadata
  json_meta <- jsonlite::toJSON(geo_meta, auto_unbox = TRUE)
  existing_meta <- table$metadata
  existing_meta[["geo"]] <- as.character(json_meta)
  table$metadata <- existing_meta

  return(table)
}
