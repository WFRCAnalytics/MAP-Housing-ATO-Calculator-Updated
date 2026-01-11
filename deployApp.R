library(dplyr)
library(rsconnect)
library(arrow)
library(geoarrow)
library(sf)
library(tools)

src_h3 <- "_output/h3_scored.parquet"
dst_h3 <- "_app/data/h3_scored"

src_mun <- "https://services1.arcgis.com/99lidPhWCzftIe9K/ArcGIS/rest/services/UtahMunicipalBoundaries/FeatureServer/0"
dst_mun <- "_app/data/UtahMunicipalBoundaries.parquet"

src_bnd <- "_data/processed/base_layers/Analysis_Boundary_WFRC_MAG.parquet"
dst_bnd <- "_app/data/Analysis_Boundary_WFRC_MAG.parquet"

# If this is the first time deploying fromt the device, you have to run the following.
# rsconnect::setAccountInfo(name="<ACCOUNT>", token="<TOKEN>", secret="<SECRET>")

# Check Reference at: https://shiny.posit.co/r/articles/share/shinyapps/ for details.
# Check https://www.shinyapps.io/admin/#/tokens for the ACCOUNT, TOKEN, and SECRET

# 1. Sync Parquet File
if (!dir.exists(dst_h3)) {
  message("Updating data file...")
  arrow::open_dataset(src_h3) |>
    dplyr::filter(!is.na(CommCode)) |>
    sf::st_as_sf(crs = 4326) |>
    arrow::write_dataset(
      path = dst_h3,
      partitioning = "CommCode"
    )
}

# 2. Download Municipalities
if (!file.exists(dst_mun)) {
  message("Updating city boundary...")

  # A. Extract unique CommCodes from your H3 dataset
  mun_codes <- arrow::open_dataset(dst_h3) |>
    dplyr::select(CommCode) |>
    dplyr::distinct() |>
    dplyr::filter(!is.na(CommCode)) |>
    dplyr::collect() |>
    pull(CommCode)

  # B. Construct the Where Clause
  where_clause <- paste0(
    "UGRCODE IN ('",
    paste(mun_codes, collapse = "','"),
    "')"
  )

  # C. Build the Query URL
  query_url <- URLencode(paste0(
    src_mun,
    "/query?",
    "where=",
    where_clause,
    "&outFields=UGRCODE,NAME", # Fetch the fields we need
    "&f=geojson", # Request GeoJSON format (sf reads this easily)
    "&outSR=4326" # Ensure WGS84 coordinates
  ))

  # D. Read directly into sf, then write to Parquet
  # st_read can read directly from a URL string
  sf::st_read(query_url, quiet = TRUE) |>
    sf::st_transform(4326) |> # Ensure CRS is correct
    arrow::write_parquet(dst_mun) # Write to Parquet

  message("City boundaries saved to: ", dst_mun)
}

# 3. Regional Boundary
if (
  !file.exists(dst_bnd) || (tools::md5sum(src_bnd) != tools::md5sum(dst_bnd))
) {
  message("Updating regional boundary file...")
  file.copy(src_bnd, dst_bnd, overwrite = TRUE)
}

# Deploy
rsconnect::deployApp(
  appDir = "_app",
  appName = "Housing-ATO-Calculator",
  appTitle = "Wasatch Front Housing ATO Calculator",
  # appId = 16342069,
  account = "wfrc",
  forceUpdate = TRUE
)
