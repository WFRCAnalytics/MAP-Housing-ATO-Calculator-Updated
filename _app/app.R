library(shiny)
library(bslib)
library(arrow)
library(geoarrow)
library(dplyr)
library(sf)
library(mapgl)
library(shinyWidgets)
library(RColorBrewer)
library(shinyjs)
library(utils)
library(waiter)
library(capture)

# ==============================================================================
# 1. GLOBAL SETUP & DATA LOADING
# ==============================================================================

# 1. Define target paths
data_path <- "data/h3_scored"
cities_path <- "data/UtahMunicipalBoundaries.parquet"
boundary_path <- "data/Analysis_Boundary_WFRC_MAG.parquet"

# Load H3 Data (LAZY CONNECTION)
message("Connecting to H3 dataset...")
# Do NOT call st_as_sf() here. It triggers a full load.
ds_h3 <- arrow::open_dataset(data_path)

message("H3 Dataset connected.")

# Store column names available in H3 for strict score validation in client-side expression
available_h3_cols <- names(ds_h3)

# Load City Boundaries (Arrow -> sf pipeline)
message("Loading City Boundaries...")
if (file.exists(cities_path)) {
  # CORRECTED: Read with arrow, then convert to sf
  cities_sf <- arrow::open_dataset(cities_path) |>
    sf::st_as_sf(crs = 4326)

  # Prepare Lookup Map
  cities_sf <- cities_sf[order(cities_sf$NAME), ]
  city_choices <- stats::setNames(cities_sf$UGRCODE, cities_sf$NAME)
} else {
  message("Warning: City boundaries file not found.")
  cities_sf <- NULL
  city_choices <- character(0)
}

# Load Regional Boundary (Arrow -> sf pipeline)
message("Loading Regional Boundary...")
if (file.exists(boundary_path)) {
  # CORRECTED: Read with arrow, then convert to sf
  bound_sf <- arrow::open_dataset(boundary_path) |>
    sf::st_as_sf(crs = 4326)
} else {
  message("Warning: Regional boundary file not found.")
  bound_sf <- NULL
}

# Internal Mappings
lu_mappings <- list(
  "All Land Uses" = c(
    "AG",
    "EM",
    "OS",
    "CH",
    "SF",
    "MF",
    "GQ",
    "GO",
    "ED",
    "HE",
    "RE",
    "OF",
    "IN",
    "OT",
    "UT",
    "NB",
    "NO"
  ),
  "Residential" = c("CH", "SF"),
  "All Other" = c(
    "AG",
    "EM",
    "OS",
    "MF",
    "GQ",
    "GO",
    "ED",
    "HE",
    "RE",
    "OF",
    "IN",
    "OT",
    "UT",
    "NB",
    "NO"
  )
)

bc_map <- c(
  "AG" = "Agriculture",
  "EM" = "Empty/Vacant",
  "OS" = "Open Space",
  "CH" = "Church/Religious",
  "SF" = "Single Family",
  "MF" = "Multi-Family",
  "GQ" = "Group Quarters",
  "GO" = "Government",
  "ED" = "Education",
  "HE" = "Health",
  "RE" = "Retail",
  "OF" = "Office",
  "IN" = "Industrial",
  "OT" = "Other",
  "UT" = "Utilities",
  "NB" = "No Build",
  "NO" = "None"
)

# --- LAYER CONFIGURATION ---
layer_defs <- list(
  # Places
  "w_CM" = list(
    url = "https://services1.arcgis.com/taguadKoI1XFwivx/arcgis/rest/services/WCV_Centers_and_Regional_Land_Uses/FeatureServer/0",
    query = "CenterType = 'Metropolitan Center'",
    type = "polygon",
    color = "#a62966"
  ),
  "w_CU" = list(
    url = "https://services1.arcgis.com/taguadKoI1XFwivx/arcgis/rest/services/WCV_Centers_and_Regional_Land_Uses/FeatureServer/0",
    query = "CenterType = 'Urban Center'",
    type = "polygon",
    color = "#e8572d"
  ),
  "w_CC" = list(
    url = "https://services1.arcgis.com/taguadKoI1XFwivx/arcgis/rest/services/WCV_Centers_and_Regional_Land_Uses/FeatureServer/0",
    query = "CenterType = 'City Center'",
    type = "polygon",
    color = "#f3a13e"
  ),
  "w_CN" = list(
    url = "https://services1.arcgis.com/taguadKoI1XFwivx/arcgis/rest/services/WCV_Centers_and_Regional_Land_Uses/FeatureServer/0",
    query = "CenterType = 'Neighborhood Center'",
    type = "polygon",
    color = "#f8dc26"
  ),
  # Employment
  "w_AA" = list(
    url = "https://services1.arcgis.com/taguadKoI1XFwivx/ArcGIS/rest/services/AccessToOpportunities_gdb/FeatureServer/0",
    query = "1=1",
    type = "polygon",
    # 5-Class Red-Purple Gradient (Auto Access)
    # Breaks: 0, 163k, 258k, 371k, 509k
    color = list(
      "interpolate",
      list("linear"),
      list("get", "JOBAUTO_50"),
      0,
      "#feebe2", # 0 - 163k (Very Light)
      163245,
      "#fbb4b9", # 163k - 258k
      258193,
      "#f768a1", # 258k - 371k
      371250,
      "#c51b8a", # 371k - 509k
      508914,
      "#7a0177" # 509k+ (Deepest)
    ),
    limit = 3600 # Approx 3,546
  ),
  "w_AT" = list(
    url = "https://services1.arcgis.com/taguadKoI1XFwivx/ArcGIS/rest/services/AccessToOpportunities_gdb/FeatureServer/0",
    query = "1=1",
    type = "polygon",
    # 5-Class Purples Gradient (Transit Access)
    # Breaks: 0, 11k, 33k, 63k, 113k
    color = list(
      "interpolate",
      list("linear"),
      list("get", "JOBTRANSIT_50"),
      0,
      "#f2f0f7", # 0 - 11k (Very Light)
      11768,
      "#cbc9e2", # 11k - 33k
      33817,
      "#9e9ac8", # 33k - 63k
      63893,
      "#756bb1", # 63k - 113k
      113254,
      "#54278f" # 113k+ (Deepest)
    ),
    limit = 3600 # Approx 3,546
  ),
  # Transportation
  "w_TT" = list(
    url = "https://maps.rideuta.com/server/rest/services/Hosted/UTA_Stops_and_Most_Recent_Ridership/FeatureServer/0",
    query = "1=1",
    type = "point",
    color = "#666666",
    limit = 6000 # Approx 5,568
  ),
  "w_TF" = list(
    url = "https://services.arcgis.com/pA2nEVnB6tquxgOW/arcgis/rest/services/Freeway_Exit_Locations/FeatureServer/0",
    query = "exitnbr IS NULL Or exitnbr IN ('002', '1', '10', '102', '104', '11', '111', '113', '114', '115', '117', '118', '12', '120', '121', '124', '125', '126', '127', '128', '129', '13', '130', '131', '132', '133', '134', '137', '14', '15', '15A', '15B', '15C', '16', '17', '18', '2', '20', '21', '22', '23', '242', '244', '248', '25', '250', '253', '257', '26', '260', '261', '263', '265', '269', '27', '271', '272', '273', '275', '276', '278', '279', '282', '284', '288', '289', '29', '291', '292', '293', '295', '297', '298', '3', '300', '301', '303', '304', '305', '305A', '305B', '305C', '305D', '306', '307', '308', '309', '310', '311', '312', '313', '314', '315', '316', '317', '319', '321', '322', '324', '325', '328', '330', '331', '332', '334', '335', '338', '339', '340', '341', '342', '343', '344', '346', '349', '351', '357', '362', '363', '365', '372', '395', '396', '397', '4', '404', '405', '5', '6', '7', '70', '8', '81', '85', '87', '9')",
    type = "point",
    color = "#000000"
  ),
  "w_TA" = list(
    url = "https://services1.arcgis.com/99lidPhWCzftIe9K/ArcGIS/rest/services/Bikeways/FeatureServer/0",
    query = "(Facility1 like '%(1A)%' or Facility1 like '%(1B)%' or Facility1 like '%(2A)%' or Facility1 like '%(2B)%' or Facility1 like '%(2C)%' or Facility1 like '%Trail%') AND COUNTY IN ('BOX ELDER', 'WEBER', 'DAVIS', 'SALT LAKE', 'UTAH')",
    type = "line",
    color = "#2ca25f",
    limit = 8000 # Approx 8,000
  ),
  # Necessities
  "w_AC" = list(
    url = "https://services1.arcgis.com/taguadKoI1XFwivx/arcgis/rest/services/Utah_Child_Care_Centers/FeatureServer/0",
    query = "COUNTY IN ('BOX ELDER', 'WEBER', 'DAVIS', 'SALT LAKE', 'UTAH')",
    type = "point",
    color = "#E41A1C"
  ),
  "w_AH" = list(
    url = "https://services1.arcgis.com/99lidPhWCzftIe9K/ArcGIS/rest/services/LicensedHealthCareFacilities/FeatureServer/0",
    query = "COUNTY IN ('Box Elder', 'Weber', 'Davis', 'Salt Lake', 'Utah')",
    type = "point",
    color = "#377EB8"
  ),
  "w_AE" = list(
    urls = c(
      "https://services1.arcgis.com/99lidPhWCzftIe9K/ArcGIS/rest/services/Schools_PreKto12/FeatureServer/0",
      "https://services1.arcgis.com/99lidPhWCzftIe9K/ArcGIS/rest/services/Schools_HigherEducation/FeatureServer/0"
    ),
    query = "1=1",
    type = "point",
    color = "#4DAF4A"
  ),
  "w_AG" = list(
    url = "https://services1.arcgis.com/taguadKoI1XFwivx/ArcGIS/rest/services/UtahGroceryAndFoodStores_DAF/FeatureServer/0",
    query = "POINT_X BETWEEN 406532.6 AND 449162.9 AND POINT_Y BETWEEN 4425359 AND 4597055",
    type = "point",
    color = "#e7298a"
  ),
  "w_AM" = list(
    url = "https://services1.arcgis.com/taguadKoI1XFwivx/arcgis/rest/services/Community_Centers/FeatureServer/0",
    query = "County IN ('Box Elder', 'Weber', 'Davis', 'Salt Lake', 'Utah')",
    type = "point",
    color = "#FF7F00"
  ),
  "w_AP" = list(
    url = "https://services1.arcgis.com/99lidPhWCzftIe9K/ArcGIS/rest/services/UtahParksLocal/FeatureServer/0",
    query = "COUNTY IN ('BOX ELDER', 'WEBER', 'DAVIS', 'SALT LAKE', 'UTAH')",
    type = "polygon",
    color = "#A65628"
  )
)

layer_names <- c(
  "w_CM" = "Metropolitan Centers",
  "w_CU" = "Urban Centers",
  "w_CC" = "City Centers",
  "w_CN" = "Neighborhood Centers",
  "w_AA" = "Auto Access to Jobs",
  "w_AT" = "Transit Access to Jobs",
  "w_TT" = "Transit Stops",
  "w_TF" = "Freeway Exits",
  "w_TA" = "Active Transportation",
  "w_AC" = "Childcare Centers",
  "w_AH" = "Healthcare Facilities",
  "w_AE" = "Education Institutions",
  "w_AG" = "Grocery Stores",
  "w_AM" = "Community Centers",
  "w_AP" = "Public Parks"
)

# --- NEW: Tooltip Descriptions ---
layer_help_text <- list(
  "w_CM" = "Regional centers designated for highest density growth and activity.",
  "w_CU" = "Centers serving sub-regional areas with high density commercial and housing.",
  "w_CC" = "Centers serving specific cities with moderate density and mixed use.",
  "w_CN" = "Local centers serving immediate neighborhoods.",
  "w_AA" = "Number of jobs accessible by car within a 40-minute drive.",
  "w_AT" = "Number of jobs accessible by public transit within a 60-minute ride.",
  "w_TT" = "Proximity to UTA bus stops, TRAX stations, and FrontRunner stations.",
  "w_TF" = "Proximity to freeway entrance and exit ramps.",
  "w_TA" = "Proximity to separated or buffered bike lanes, and multi-use trails.",
  "w_AC" = "Proximity to licensed childcare facilities.",
  "w_AH" = "Proximity to hospitals, clinics, and medical facilities.",
  "w_AE" = "Proximity to K-12 schools and higher education institutions.",
  "w_AG" = "Proximity to supermarkets and grocery stores.",
  "w_AM" = "Proximity to community halls, recreation centers, and libraries.",
  "w_AP" = "Proximity to public parks and open spaces."
)

sliderWithLayer <- function(inputId, label) {
  # Lookup help text; default to empty if missing
  help_msg <- layer_help_text[[inputId]]
  if (is.null(help_msg)) {
    help_msg <- "Adjust the importance of this factor."
  }

  shiny::tagList(
    shiny::div(
      class = "d-flex justify-content-between align-items-center mb-1",

      # --- LEFT SIDE: Label + Tooltip Grouped ---
      shiny::div(
        class = "d-flex align-items-center",
        tags$label(
          label,
          class = "control-label",
          `for` = inputId,
          # Add right margin to separate text from the question mark
          style = "margin-bottom: 0; margin-right: 8px;"
        ),
        bslib::tooltip(
          trigger = shiny::tags$i(
            class = "fa-regular fa-circle-question",
            # Subtler styling for the help icon
            style = "color: #9aa5b1; cursor: help; font-size: 0.85rem;"
          ),
          help_msg,
          placement = "top"
        )
      ),

      # --- RIGHT SIDE: Visibility Toggle ---
      tags$a(
        id = paste0("btn_", inputId),
        class = "layer-toggle-btn",
        onclick = sprintf(
          "Shiny.setInputValue('%s', Math.random());",
          paste0("toggle_", inputId)
        ),
        title = "Toggle Reference Layer",
        tags$i(class = "fa-solid fa-eye-slash")
      )
    ),
    shiny::sliderInput(
      inputId,
      label = NULL,
      min = 0,
      max = 1,
      value = 0.5,
      step = 0.1,
      width = "100%"
    )
  )
}

# TODO: --- REVERTIBLE CHANGE: Helper function for Toggle-Only Layers ---
toggleOnlyLayer <- function(inputId, label) {
  help_msg <- layer_help_text[[inputId]]
  if (is.null(help_msg)) {
    help_msg <- "Toggle this reference layer."
  }

  shiny::div(
    class = "d-flex justify-content-between align-items-center mb-2", # mb-2 for spacing
    shiny::div(
      class = "d-flex align-items-center",
      tags$label(
        label,
        class = "control-label",
        style = "margin-bottom: 0; margin-right: 8px;"
      ),
      bslib::tooltip(
        trigger = shiny::tags$i(
          class = "fa-regular fa-circle-question",
          style = "color: #9aa5b1; cursor: help; font-size: 0.85rem;"
        ),
        help_msg,
        placement = "top"
      )
    ),
    tags$a(
      id = paste0("btn_", inputId),
      class = "layer-toggle-btn",
      onclick = sprintf(
        "Shiny.setInputValue('%s', Math.random());",
        paste0("toggle_", inputId)
      ),
      title = "Toggle Reference Layer",
      tags$i(class = "fa-solid fa-eye-slash")
    )
  )
}
# -----------------------------------------------------------------

# ==============================================================================
# 2. UI
# ==============================================================================
ui <- bslib::page_navbar(
  title = shiny::div(
    style = "display: flex; align-items: center;",
    shiny::img(src = "logo.png", style = "height:35px; margin-right:10px;"),
    "Wasatch Front Housing ATO Calculator"
  ),
  theme = bslib::bs_theme(preset = "flatly"),
  header = tags$head(
    useShinyjs(),
    waiter::use_waiter(),
    tags$link(
      rel = "stylesheet",
      href = "https://fonts.googleapis.com/css2?family=Oswald:wght@300;400;500;700&display=swap"
    ),
    tags$link(
      rel = "stylesheet",
      href = "https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.2/css/all.min.css"
    ),

    # --- Syntax Highlighting Libraries ---
    # CHANGED: Switched to 'atom-one-dark' for better contrast and color
    tags$link(
      rel = "stylesheet",
      href = "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/atom-one-dark.min.css"
    ),
    tags$script(
      src = "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"
    ),
    tags$script(
      src = "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/r.min.js"
    ),
    tags$script(
      src = "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/python.min.js"
    ),
    # --------------------------------------------------------

    # --- DOWNLOAD SCREENSHOT ---
    tags$script(
      src = "https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"
    ),
    tags$script(HTML(
      "
      function downloadMap() {
        // 1. Target the element (we use the map ID)
        var element = document.querySelector('#map');

        // 2. Use html2canvas with CORS enabled
        html2canvas(element, {
          useCORS: true,        // FORCE Cross-Origin images to load
          allowTaint: true,     // Allow 'tainted' canvas reading
          backgroundColor: null, // Transparent background
          scale: 2,  // Increase resolution
        }).then(canvas => {
          // 3. Create a fake link to trigger download
          var link = document.createElement('a');
          link.download = 'ATO_Housing_Map.png';
          link.href = canvas.toDataURL('image/png');
          link.click();
        });
      }
    "
    )),
    shinyWidgets::chooseSliderSkin("Flat", color = "#2c3e50"),
    tags$style(shiny::HTML(
      "
      body { font-family: Arial, 'Open Sans', sans-serif; }
      h1, h2, h3, h4, h5 { font-family: 'Oswald', sans-serif; font-weight: 700; color: #233A57; text-transform: uppercase; }
      .navbar { background-color: #233A57 !important; padding: 0px 15px !important; min-height: 40px !important; height: auto !important; }
      .navbar > .container-fluid { padding: 7.5px 0 !important; min-height: 45px !important; display: flex; align-items: center; }
      .navbar-brand { font-family: 'Oswald', sans-serif; font-weight: 700; color: white !important; font-size: 1.5rem; text-transform: uppercase; padding: 0 !important; margin: 0 !important; display: flex; align-items: center; height: 40px; }
      .navbar-nav { display: none !important; }
      .control-label, .shiny-input-container label, .step-header { font-family: 'Oswald', sans-serif; font-weight: 500; color: #233A57; text-transform: uppercase; font-size: 1rem; }
      .accordion-button { font-family: 'Oswald', sans-serif; font-weight: 500; color: #5a87c6; text-transform: uppercase; font-size: 0.9rem !important; }
      .accordion-body .control-label { font-size: 0.85rem !important; color: #444; }
      .card-header .form-group { margin: 0 !important; }
      .layer-toggle-btn { color: #ccc; cursor: pointer; font-size: 1.1rem; transition: color 0.3s; margin-left: 8px; }
      .layer-toggle-btn:hover { color: #5a87c6; }
      .layer-toggle-btn.active { color: #2c3e50; }
      .maplibregl-popup-content { padding: 0 !important; border-radius: 4px; overflow: hidden; }
      .shiny-input-container { width: 100% !important; margin-bottom: 0px !important; }
      .form-group { margin-bottom: 5px !important; }
      .modal-content { border: none; border-radius: 12px; box-shadow: 0 15px 35px rgba(0,0,0,0.25); overflow: hidden; }
      .splash-header { background: linear-gradient(135deg, #233A57 0%, #3a5c85 100%); color: white; padding: 30px 25px; text-align: center; position: relative; }
      .splash-header h2 { font-family: 'Oswald', sans-serif; color: white; margin: 0; letter-spacing: 1px; }
      .splash-body { padding: 25px 35px; font-family: 'Open Sans', sans-serif; color: #444; }
      .feature-grid { display: flex; gap: 20px; margin: 25px 0; text-align: center; }
      .feature-item { flex: 1; padding: 15px; background: #f8f9fa; border-radius: 8px; transition: transform 0.2s; }
      .feature-item:hover { transform: translateY(-3px); background: #f0f4f8; }
      .feature-icon { font-size: 1.8rem; color: #e8572d; margin-bottom: 10px; }
      .feature-title { font-weight: 700; font-size: 0.9rem; text-transform: uppercase; color: #233A57; margin-bottom: 5px; }
      .instruction-box { background-color: #eef6fc; border-left: 4px solid #377EB8; padding: 15px; margin: 20px 0; font-size: 0.95rem; line-height: 1.5; }
      .splash-footer { background-color: #f1f1f1; padding: 15px 35px; font-size: 0.85rem; border-top: 1px solid #ddd; }
      .btn-get-started { background-color: #233A57; color: white; font-family: 'Oswald', sans-serif; font-size: 1.1rem; padding: 10px 40px; border-radius: 30px; border: none; transition: all 0.3s; width: 100%; }
      .btn-get-started:hover { background-color: #e8572d; color: white; transform: scale(1.02); }

      /* --- WAITER / LOADING PILL STYLING --- */

      /* 1. The Container (The Pill) */
      .waiter-overlay-content {
        background: rgba(255, 255, 255, 0.85) !important; /* High opacity for legibility */
        backdrop-filter: blur(12px);                      /* Frosted glass effect */
        -webkit-backdrop-filter: blur(12px);              /* Safari support */
        border: 1px solid rgba(255, 255, 255, 0.9);       /* Subtle border */
        border-radius: 50px;                              /* Full pill shape */
        padding: 12px 28px;                               /* Sizing */
        box-shadow: 0 10px 30px rgba(0,0,0,0.15);         /* Soft, floating shadow */

        /* Flexbox for perfect alignment */
        display: flex !important;
        align-items: center;
        justify-content: center;
        gap: 15px;
      }

      /* 2. The Text */
      .waiter-text {
        color: #233A57;
        font-family: 'Oswald', sans-serif;
        font-size: 1rem;
        font-weight: 500;
        letter-spacing: 0.5px;
        margin: 0;
        white-space: nowrap;
      }

      /* 3. The Spinner Color Override */
      .waiter-spinner {
        color: #233A57 !important; /* Matches Brand Blue */
        font-size: 20px !important;
        display: flex;
        align-items: center;
      }

      /* Force 'disabled' links to strictly ignore mouse clicks */
      .btn.disabled {
        pointer-events: none !important;
        cursor: not-allowed !important;
        opacity: 0.65 !important;
      }
    "
    ))
  ),
  sidebar = bslib::sidebar(
    width = 350,
    title = NULL,
    shinyWidgets::pickerInput(
      "comm_code",
      "Step 1: Select Cities",
      choices = city_choices,
      selected = NULL,
      options = list(`actions-box` = TRUE, `live-search` = TRUE),
      multiple = TRUE
    ),
    shinyWidgets::pickerInput(
      "land_use_group",
      "Step 2: Filter by Land Use",
      choices = names(lu_mappings),
      selected = "All Land Uses",
      multiple = FALSE
    ),
    bslib::accordion(
      open = FALSE, # Keep collapsed to save space by default
      bslib::accordion_panel(
        "Wasatch Choice Centers (Overlay)",
        toggleOnlyLayer("w_CM", "Metropolitan Centers"),
        toggleOnlyLayer("w_CU", "Urban Centers"),
        toggleOnlyLayer("w_CC", "City Centers"),
        toggleOnlyLayer("w_CN", "Neighborhood Centers")
      )
    ),
    tags$div(
      class = "mb-2",
      tags$div(
        "Step 3: Customize Accessibility Priorities",
        class = "step-header"
      ),
      tags$p(
        HTML(
          "Indicate priority level for each factor.<br>Toggle layers using the icon on the right."
        ),
        style = "font-size: 0.9em; color: #6c757d; margin-top: 5px;"
      )
    ),
    bslib::accordion(
      open = FALSE,
      # bslib::accordion_panel(
      #   "Places (Centers)",

      #   # TODO: --- REVERTIBLE CHANGE: Remove Sliders, Keep Toggles ---
      #   # ORIGINAL CODE:
      #   # sliderWithLayer("w_CM", "Metropolitan Centers"),
      #   # sliderWithLayer("w_CU", "Urban Centers"),
      #   # sliderWithLayer("w_CC", "City Centers"),
      #   # sliderWithLayer("w_CN", "Neighborhood Centers")

      #   # NEW CODE:
      #   toggleOnlyLayer("w_CM", "Metropolitan Centers"),
      #   toggleOnlyLayer("w_CU", "Urban Centers"),
      #   toggleOnlyLayer("w_CC", "City Centers"),
      #   toggleOnlyLayer("w_CN", "Neighborhood Centers")
      #   # -------------------------------------------------------
      # ),
      bslib::accordion_panel(
        "Employment",
        sliderWithLayer(
          "w_AA",
          shiny::HTML(
            "<i class='fa-solid fa-car' style='width: 24px; text-align: center; margin-right: 4px; color: #233A57;'></i> Auto Access to Jobs"
          )
        ),
        sliderWithLayer(
          "w_AT",
          shiny::HTML(
            "<i class='fa-solid fa-train' style='width: 24px; text-align: center; margin-right: 4px; color: #233A57;'></i> Transit Access to Jobs"
          )
        )
      ),
      bslib::accordion_panel(
        "Transportation",
        sliderWithLayer(
          "w_TT",
          shiny::HTML(
            "<i class='fa-solid fa-bus' style='width: 24px; text-align: center; margin-right: 4px; color: #233A57;'></i> Transit Stops"
          )
        ),
        sliderWithLayer(
          "w_TF",
          shiny::HTML(
            "<i class='fa-solid fa-road' style='width: 24px; text-align: center; margin-right: 4px; color: #233A57;'></i> Freeway Exits"
          )
        ),
        sliderWithLayer(
          "w_TA",
          shiny::HTML(
            "<i class='fa-solid fa-bicycle' style='width: 24px; text-align: center; margin-right: 4px; color: #233A57;'></i> Active Transportation"
          )
        )
      ),
      bslib::accordion_panel(
        "Necessities",
        sliderWithLayer(
          "w_AC",
          shiny::HTML(
            "<i class='fa-solid fa-baby' style='width: 24px; text-align: center; margin-right: 4px; color: #233A57;'></i> Childcare Centers"
          )
        ),
        sliderWithLayer(
          "w_AH",
          shiny::HTML(
            "<i class='fa-solid fa-heart-pulse' style='width: 24px; text-align: center; margin-right: 4px; color: #233A57;'></i> Healthcare Facilities"
          )
        ),
        sliderWithLayer(
          "w_AE",
          shiny::HTML(
            "<i class='fa-solid fa-graduation-cap' style='width: 24px; text-align: center; margin-right: 4px; color: #233A57;'></i> Education Institutions"
          )
        ),
        sliderWithLayer(
          "w_AG",
          shiny::HTML(
            "<i class='fa-solid fa-cart-shopping' style='width: 24px; text-align: center; margin-right: 4px; color: #233A57;'></i> Grocery Stores"
          )
        ),
        sliderWithLayer(
          "w_AM",
          shiny::HTML(
            "<i class='fa-solid fa-landmark' style='width: 24px; text-align: center; margin-right: 4px; color: #233A57;'></i> Community Centers"
          )
        ),
        sliderWithLayer(
          "w_AP",
          shiny::HTML(
            "<i class='fa-solid fa-tree' style='width: 24px; text-align: center; margin-right: 4px; color: #233A57;'></i> Public Parks"
          )
        )
      )
    ),
    shiny::div(
      class = "d-flex gap-2 justify-content-between mb-2",
      shiny::actionButton(
        "reset_all",
        "Reset All (0)",
        icon = shiny::icon("ban"),
        class = "btn-outline-secondary w-50 btn-sm"
      ),
      shiny::actionButton(
        "max_all",
        "Max All (1)",
        icon = shiny::icon("check-double"),
        class = "btn-outline-primary w-50 btn-sm"
      )
    ),
    shiny::hr(),
    shinyWidgets::materialSwitch(
      "oz_filter",
      "Limit to Opportunity Zones (OZ)",
      value = FALSE,
      status = "primary"
    )
  ),
  bslib::nav_panel(
    "",
    bslib::card(
      full_screen = TRUE,
      bslib::card_header(
        class = "d-flex align-items-center w-100",
        # shiny::span(
        #   "Housing Accessibility Map",
        #   class = "me-auto",
        #   style = "font-family: 'Oswald'; font-size: 1.5rem; color: #233A57;"
        # ),

        # --- Data Download Button ---
        shiny::uiOutput("ui_btn_dl_data"),

        # --- Map Download Button ---
        tags$button(
          id = "btn_dl_map",
          # CHANGE: Added 'disabled' to class list
          class = "btn btn-outline-primary btn-sm me-auto disabled",
          style = "font-family: 'Oswald', sans-serif; font-weight: 500; cursor: pointer;",
          onclick = "downloadMap()",
          shiny::icon("camera"),
          " Download Map"
        ),

        shiny::div(
          class = "d-flex align-items-center",
          style = "gap: 20px;",
          shiny::div(
            class = "d-flex align-items-center",
            style = "gap: 8px;",
            tags$label(
              "Z-SCALE:",
              `for` = "z_mult",
              class = "control-label m-0",
              style = "font-size: 1rem; font-weight: 700; color: #233A57; white-space: nowrap;"
            ),
            shiny::div(
              style = "width: 70px;",
              shiny::numericInput(
                "z_mult",
                label = NULL,
                value = 2,
                min = 0.5,
                step = 0.5
              )
            )
          ),
          shiny::div(
            style = "white-space: nowrap;",
            shinyWidgets::materialSwitch(
              "map_3d",
              "3D View",
              value = FALSE,
              status = "primary",
              inline = TRUE
            )
          )
        )
      ),
      mapgl::maplibreOutput("map", height = "100%")
    )
  )
)

# ==============================================================================
# 3. SERVER LOGIC
# ==============================================================================
server <- function(input, output, session) {
  # --- 1. DEFINE LOADING SCREEN (Floating Pill) ---
  w <- waiter::Waiter$new(
    id = "map",
    html = shiny::tagList(
      # The .waiter-overlay-content class defined in CSS automatically wraps this
      shiny::div(
        class = "waiter-spinner",
        waiter::bs5_spinner(color = "primary")
      ),
      shiny::span(class = "waiter-text", "Updating Map...")
    ),
    # The overlay background: Nearly invisible, just enough to block interaction
    color = "rgba(255, 255, 255, 0.2)"
  )

  # --- SPLASH SCREEN ---
  shiny::showModal(shiny::modalDialog(
    title = NULL,
    easyClose = FALSE,
    size = "l",
    footer = NULL,
    shiny::div(
      class = "splash-header",
      shiny::div(
        style = "margin-bottom: 15px;",
        shiny::img(src = "logo.png", style = "height: 60px; width: auto;")
      ),
      shiny::h2("Housing ATO Calculator")
    ),
    shiny::div(
      class = "splash-body",
      shiny::p(
        "The Housing Access to Opportunities (ATO) Calculator is designed to assist housing and land use planning efforts across the Wasatch Front.",
        style = "font-size: 1.1rem; text-align: center; margin-bottom: 20px;"
      ),
      shiny::div(
        class = "feature-grid",
        shiny::div(
          class = "feature-item",
          shiny::div(class = "feature-icon", shiny::icon("comments")),
          shiny::div(class = "feature-title", "Conversation Starter"),
          shiny::div(
            "Facilitate discussions about housing needs.",
            style = "font-size:0.8rem;"
          )
        ),
        shiny::div(
          class = "feature-item",
          shiny::div(class = "feature-icon", shiny::icon("map-location-dot")),
          shiny::div(class = "feature-title", "Visualization Tool"),
          shiny::div(
            "Explore spatial data interactively.",
            style = "font-size:0.8rem;"
          )
        ),
        shiny::div(
          class = "feature-item",
          shiny::div(class = "feature-icon", shiny::icon("chart-pie")),
          shiny::div(class = "feature-title", "Data-Informed Guide"),
          shiny::div(
            "Plan based on access metrics.",
            style = "font-size:0.8rem;"
          )
        )
      ),
      shiny::div(
        class = "instruction-box",
        shiny::icon("circle-info"),
        shiny::tags$strong(" How it works:"),
        shiny::br(),
        "1. Start by selecting your ",
        shiny::tags$strong("community"),
        " (one or more) from the sidebar, or click on the map.",
        shiny::br(),
        "2. Optionally, filter the map by specific ",
        shiny::tags$strong("land use"),
        " types.",
        shiny::br(),
        "3. Finally, adjust the sliders to ",
        shiny::tags$strong("prioritize the accessibility factors"),
        " that matter most to you.",
        shiny::p(
          "The tool will generate a heat map highlighting locations ranging from the ",
          shiny::tags$strong("most accessibility"),
          " to the ",
          shiny::tags$strong("least accessibility"),
          " based on your specific inputs.",
          style = "margin-top: 8px; margin-bottom: 0;"
        )
      ),
      shiny::div(
        style = "text-align: center; margin-top: 25px;",
        shiny::actionButton(
          "close_splash",
          "GET STARTED",
          class = "btn-get-started",
          onclick = "setTimeout(function(){ $('.modal').modal('hide'); }, 200);"
        )
      )
    ),
    shiny::div(
      class = "splash-footer",
      shiny::fluidRow(
        shiny::column(
          6,
          shiny::tags$strong("Questions or Comments?"),
          shiny::br(),
          shiny::a(
            href = "mailto:christy.dahlberg@wfrc.utah.gov",
            shiny::icon("envelope"),
            " Christy Dahlberg",
            style = "color: #233A57; text-decoration: none;"
          )
        ),
        shiny::column(
          6,
          style = "text-align: right;",
          shiny::span("Built off the Weber Housing Location Explorer."),
          shiny::br(),
          shiny::a(
            "View Methodology Story Map",
            href = "http://bit.ly/weberhousing",
            target = "_blank",
            style = "color: #377EB8; font-weight: bold;"
          )
        )
      )
    )
  ))
  shiny::observeEvent(input$close_splash, {
    shiny::removeModal()
  })

  # --- 7. DATA DOWNLOAD MODAL (PROFESSIONAL STYLE) ---
  shiny::observeEvent(input$trigger_dl_modal, {
    # 1. SHOW THE MODAL
    shiny::showModal(
      shiny::modalDialog(
        title = NULL, # We create a custom header
        footer = NULL, # We create a custom footer
        size = "l",
        easyClose = TRUE,
        fade = TRUE,

        # --- CUSTOM CSS FOR THIS MODAL ---
        shiny::HTML(
          '
          <style>
            /* 1. Modal Reset: Remove default padding so our header touches edges */
            .modal-body { padding: 0 !important; border-radius: 12px; overflow: hidden; }
            .modal-content { border: none; box-shadow: 0 15px 50px rgba(0,0,0,0.3); border-radius: 12px; }

            /* 2. Header: Matching the Splash Screen Brand Look */
            .dl-header {
              background: linear-gradient(135deg, #233A57 0%, #3a5c85 100%);
              color: white;
              padding: 25px 30px;
              display: flex;
              align-items: center;
              justify-content: space-between;
              border-bottom: 4px solid #377EB8; /* Accent border */
            }
            .dl-title-group h2 {
              font-family: "Oswald", sans-serif;
              font-size: 1.6rem;
              margin: 0;
              text-transform: uppercase;
              letter-spacing: 0.5px;
              color: white;
            }
            .dl-title-group p {
              font-family: "Open Sans", sans-serif;
              font-size: 0.9rem;
              margin: 5px 0 0 0;
              opacity: 0.9;
              font-weight: 300;
            }
            .dl-icon {
              font-size: 2.5rem;
              color: #aaddff;
              opacity: 0.8;
            }

            /* 3. Body: Clean Layout */
            .dl-body {
              padding: 25px 30px;
              background-color: #fcfcfc;
              font-family: "Open Sans", sans-serif;
            }
            .dl-intro-box {
              background-color: #eef6fc;
              border-left: 4px solid #377EB8;
              padding: 12px 18px;
              margin-bottom: 20px;
              color: #444;
              font-size: 0.95rem;
            }

            /* 4. Code Blocks: Dark Theme Overrides */
            pre { margin-bottom: 0; border: none; padding: 0; }
            code.hljs {
              border-radius: 6px;
              font-family: "Fira Code", "Consolas", monospace;
              font-size: 0.9em;
              padding: 15px !important;
              background-color: #282c34; /* Atom One Dark BG */
              box-shadow: inset 0 2px 4px rgba(0,0,0,0.2);
            }

            /* 5. Footer: Action Bar */
            .dl-footer {
              background-color: #f1f1f1;
              padding: 15px 30px;
              border-top: 1px solid #ddd;
              text-align: right;
              display: flex;
              justify-content: space-between;
              align-items: center;
            }
            .btn-brand-close {
              background-color: #233A57;
              border: none;
              color: white;
              padding: 8px 25px;
              font-family: "Oswald", sans-serif;
              text-transform: uppercase;
              border-radius: 4px;
              transition: all 0.2s ease;
            }
            .btn-brand-close:hover {
              background-color: #e8572d; /* Brand Orange on Hover */
              color: white;
              transform: translateY(-1px);
              box-shadow: 0 4px 8px rgba(0,0,0,0.15);
            }
            .dl-footer-note {
              font-size: 0.85rem;
              color: #888;
              font-style: italic;
            }
          </style>
        '
        ),

        # --- A. HEADER ---
        shiny::div(
          class = "dl-header",
          shiny::div(
            class = "dl-title-group",
            shiny::tags$h2("Download Started"),
            shiny::tags$p(
              "Your data is being prepared and will download shortly."
            )
          ),
          shiny::div(
            class = "dl-icon",
            shiny::icon("file-csv")
          )
        ),

        # --- B. BODY ---
        shiny::div(
          class = "dl-body",

          # Instruction Box
          shiny::div(
            class = "dl-intro-box",
            shiny::icon("circle-info"),
            " This file contains ",
            shiny::tags$strong("H3 Hexagon Indices"),
            " rather than standard coordinates. Select your preferred tool below to visualize this data."
          ),

          # Tabs
          bslib::navset_card_tab(
            id = "modal_tabs",

            # --- TAB 1: R (h3o) ---
            bslib::nav_panel(
              title = shiny::HTML(
                '<span style="color: #233A57; font-weight:600;"><i class="fa-brands fa-r-project"></i> R Script</span>'
              ),
              shiny::div(
                # shiny::p(
                #   "Use the `h3o` package to parse strings into H3 objects, then convert them to standard simple feature (sf) polygons.",
                #   style = "font-size:0.9rem; color:#555;"
                # ),
                shiny::HTML(
                  '
<pre><code class="language-r"># Install packages if missing
# install.packages(c("sf", "h3o", "readr", "dplyr"))

library(sf)
library(h3o)
library(readr)
library(dplyr)

# 0. Define your folder path
folder_path &lt;- "path/to/folder"

# 1. Read the CSV
df &lt;- read_csv(file.path(folder_path, "ATO_Filtered_Data.csv"))

# 2. Convert Strings to H3 Polygons
sf_data &lt;- df |&gt;
  mutate(
    h3_obj = h3_from_strings(tolower(h3_index)),
    geometry = h3_to_vertexes(h3_obj) |&gt; st_cast("POLYGON")
  ) |&gt;
  st_as_sf()

# 3. Save as GeoJSON
write_sf(sf_data, file.path(folder_path, "ATO_Filtered_Data.geojson"))
</code></pre>'
                )
              )
            ),

            # --- TAB 2: Python (h3-py) ---
            bslib::nav_panel(
              title = shiny::HTML(
                '<span style="color: #233A57; font-weight:600;"><i class="fa-brands fa-python"></i> Python Script</span>'
              ),
              shiny::div(
                # shiny::p(
                #   "We use `h3.cells_to_geo()` to generate a GeoJSON-compliant dictionary (automatically flipping coordinates to lng/lat), which `shapely` converts to a Polygon.",
                #   style = "font-size:0.9rem; color:#555;"
                # ),
                shiny::HTML(
                  '
<pre><code class="language-python"># Install h3 and dependencies
# pip install h3 pandas geopandas shapely

import h3
import pandas as pd
import geopandas as gpd
from shapely.geometry import shape
import os

# 0. Define your folder path
folder_path = "path/to/folder"

# 1. Read Data
df = pd.read_csv(os.path.join(folder_path, "ATO_Filtered_Data.csv"))

# 2. Create Geometry
df["geometry"] = df["h3_index"].apply(lambda x: shape(h3.cells_to_geo([x])))

# 3. Convert to GeoDataFrame
gdf = gpd.GeoDataFrame(df, geometry="geometry", crs="EPSG:4326")

# 4. Save as GeoJSON
gdf.to_file(os.path.join(folder_path, "ATO_Filtered_Data.geojson"), driver="GeoJSON")
</code></pre>'
                )
              )
            ),

            # --- TAB 3: QGIS / ArcGIS (UPDATED) ---
            bslib::nav_panel(
              title = shiny::HTML(
                '<span style="color: #233A57; font-weight:600;"><i class="fa-solid fa-map"></i> QGIS / ArcGIS</span>'
              ),
              shiny::div(
                style = "padding: 10px 5px;",
                shiny::p(
                  shiny::tags$i(
                    class = "fa-solid fa-triangle-exclamation",
                    style = "color:#f39c12;"
                  ),
                  " To visualize this data, load the reference geometry service below, then join your downloaded CSV.",
                  style = "font-size: 0.9rem;"
                ),

                # The URL
                shiny::div(
                  style = "background: #e9ecef; padding: 10px; border-radius: 4px; font-family: monospace; font-size: 0.8rem; word-break: break-all; margin-bottom: 15px; color: #333;",
                  "https://services1.arcgis.com/taguadKoI1XFwivx/ArcGIS/rest/services/HousingSuitability_Centers202512_gdb/FeatureServer/2"
                ),

                shiny::hr(),

                shiny::h5(
                  "Option A: QGIS",
                  style = "font-family:'Oswald'; color:#233A57;"
                ),
                shiny::tags$ul(
                  style = "font-size: 0.9rem; color:#444; line-height: 1.6;",
                  shiny::tags$li(
                    "Go to ",
                    shiny::tags$strong("Layer"),
                    " > ",
                    shiny::tags$strong("Add Layer"),
                    " > ",
                    shiny::tags$strong("Add ArcGIS REST Service Layer...")
                  ),
                  shiny::tags$li(
                    "Click 'New', paste the URL above, and click 'Connect' to add the layer."
                  ),
                  shiny::tags$li(
                    "Import your downloaded CSV and perform a ",
                    shiny::tags$strong("Table Join"),
                    " using the H3 Index column."
                  )
                ),

                shiny::br(),

                shiny::h5(
                  "Option B: ArcGIS Pro",
                  style = "font-family:'Oswald'; color:#233A57;"
                ),
                shiny::tags$ul(
                  style = "font-size: 0.9rem; color:#444; line-height: 1.6;",
                  shiny::tags$li(
                    "Go to the ",
                    shiny::tags$strong("Map"),
                    " tab > ",
                    shiny::tags$strong("Add Data"),
                    " > ",
                    shiny::tags$strong("Data From Path")
                  ),
                  shiny::tags$li(
                    "Paste the URL above and click 'Add'."
                  ),
                  shiny::tags$li(
                    "Import your CSV and use the ",
                    shiny::tags$strong("Add Join"),
                    " tool to append your data using the H3 Index."
                  )
                )
              )
            )
          )
        ),

        # --- C. FOOTER ---
        shiny::div(
          class = "dl-footer",
          shiny::div(
            class = "dl-footer-note",
            "Need help? Contact ",
            shiny::a(
              href = "mailto:analytics@wfrc.utah.gov",
              "analytics@wfrc.utah.gov",
              style = "color: inherit; text-decoration: underline;"
            )
          ),
          shiny::actionButton(
            inputId = "close_modal_dl",
            label = "Done",
            class = "btn-brand-close",
            icon = shiny::icon("check")
          )
        )
      )
    )

    # 2. TRIGGER SYNTAX HIGHLIGHTING
    # Ensure this runs after the animation completes
    shinyjs::runjs(
      "
      setTimeout(function() {
        if (typeof hljs !== 'undefined') {
          document.querySelectorAll('pre code').forEach((el) => {
             hljs.highlightElement(el);
          });
        }
      }, 500);
    "
    )
  })

  active_ref_layers <- shiny::reactiveVal(list())

  # TODO: --- REVERTIBLE CHANGE: Exclude Centers from Scoring Logic ---
  # ORIGINAL CODE:
  # all_sliders <- names(layer_defs)

  # NEW CODE: Explicitly exclude centers so they don't affect the math
  center_layers <- c("w_CM", "w_CU", "w_CC", "w_CN")
  all_sliders <- setdiff(names(layer_defs), center_layers)
  # -------------------------------------------------------------

  # --- ENABLE/DISABLE DOWNLOAD BUTTONS ---
  # --- 1. RENDER DATA BUTTON CONDITIONALLY ---
  output$ui_btn_dl_data <- shiny::renderUI({
    # Check condition
    has_city <- !is.null(input$comm_code) && length(input$comm_code) > 0

    if (has_city) {
      # CASE A: Active Download Button (When city is selected)
      # CHANGE: Added onclick to trigger the modal
      shiny::downloadButton(
        outputId = "btn_dl_data",
        label = " Download Data",
        icon = shiny::icon("table"),
        class = "btn btn-outline-primary btn-sm me-2",
        style = "font-family: 'Oswald', sans-serif; font-weight: 500;",
        onclick = "Shiny.setInputValue('trigger_dl_modal', Math.random());"
      )
    } else {
      # CASE B: Disabled Placeholder (When no city selected)
      tags$button(
        shiny::icon("table"),
        " Download Data",
        class = "btn btn-outline-primary btn-sm me-2 disabled",
        style = "font-family: 'Oswald', sans-serif; font-weight: 500;",
        disabled = "disabled"
      )
    }
  })

  # --- 2. HANDLE MAP BUTTON (Keep this in your existing observer) ---
  # The Map button is standard HTML, so shinyjs works perfectly on it without hacks.
  shiny::observeEvent(
    input$comm_code,
    {
      has_city <- !is.null(input$comm_code) && length(input$comm_code) > 0
      shinyjs::toggleState("btn_dl_map", condition = has_city)
    },
    ignoreNULL = FALSE
  )

  # Debounce sliders for map coloring (FAST)
  debounced_sliders <- shiny::reactive({
    sapply(all_sliders, function(x) input[[x]])
  }) |>
    shiny::debounce(10)

  # --- CLEANUP: Force Clear H3 layers when selection is empty ---
  shiny::observeEvent(
    input$comm_code,
    {
      # Check if selection is empty
      if (is.null(input$comm_code) || length(input$comm_code) == 0) {
        mapgl::maplibre_proxy("map") |>
          mapgl::clear_layer("h3_layer_3d") |>
          mapgl::clear_layer("h3_layer_2d")
      }
    },
    ignoreNULL = FALSE
  ) # <--- Important: Run even when input is NULL

  # --- CLOSE MODAL HANDLER ---
  shiny::observeEvent(input$close_modal_dl, {
    shiny::removeModal()
  })

  shiny::observeEvent(input$reset_all, {
    for (id in all_sliders) {
      shiny::updateSliderInput(session, id, value = 0)
    }
  })
  shiny::observeEvent(input$max_all, {
    for (id in all_sliders) {
      shiny::updateSliderInput(session, id, value = 1)
    }
  })
  shiny::observe({
    shinyjs::toggleState("z_mult", condition = input$map_3d)
  })

  refresh_layer_control <- function(proxy, is_3d, ref_layers_list) {
    heatmap_id <- if (is_3d) "h3_layer_3d" else "h3_layer_2d"
    # GROUPED LAYERS
    control_list <- list(
      "Major Roads" = "lay_roads_tile",
      "Heatmap" = heatmap_id,
      "City Boundaries" = c("lay_cities_fill", "lay_cities_line")
    )
    if (length(ref_layers_list) > 0) {
      control_list <- c(control_list, ref_layers_list)
    }
    proxy |>
      mapgl::clear_controls("layers") |>
      mapgl::add_layers_control(
        position = "top-right",
        layers = control_list,
        collapsible = TRUE,
        active_color = "#233A57"
      )
  }

  target_bc_codes <- shiny::reactive({
    shiny::req(input$land_use_group)
    unique(unlist(lu_mappings[input$land_use_group]))
  })

  # --- Data Processing with PERCENTAGE Tooltip ---
  filtered_data <- shiny::reactive({
    shiny::req(input$comm_code)

    weights <- shiny::isolate({
      stats::setNames(
        sapply(all_sliders, function(x) input[[x]]),
        substring(all_sliders, 3)
      )
    })

    total_weight <- sum(weights)

    # --------------------------------------------------------
    # NEW: Lazy Filtering Pipeline
    # --------------------------------------------------------
    # 1. Start with the arrow dataset connection
    # 2. Apply filters (Arrow pushes these down to the file system)
    # 3. Collect() to load only result into R memory
    # 4. Convert to sf (geoarrow handles the binary geometry column)

    df <- ds_h3 |>
      dplyr::filter(CommCode %in% !!input$comm_code)

    if (input$oz_filter) {
      df <- df |> dplyr::filter(OZ == 1)
    }

    # Execute the query and load to memory
    df <- df |>
      # dplyr::collect() |>
      sf::st_as_sf(crs = 4326)
    # Note: Since geoarrow is loaded, st_as_sf usually detects
    # the WKB geometry column automatically.

    if (nrow(df) > 0) {
      cols <- names(weights)

      # Ensure columns exist (handling potential schema mismatches)
      # In arrow, selecting non-existent columns usually errors,
      # but if they exist in schema but are null, this handles it.
      missing_cols <- setdiff(cols, names(df))
      if (length(missing_cols) > 0) {
        df[missing_cols] <- 0
      }

      df_calc <- sf::st_drop_geometry(df)

      # Handle NAs which might come from parquet nulls
      df_calc[cols][is.na(df_calc[cols])] <- 0

      weighted_sum <- rowSums(
        df_calc[, cols, drop = FALSE] *
          weights[col(df_calc[, cols, drop = FALSE])]
      )
      df$score <- if (total_weight == 0) 0 else weighted_sum / total_weight
      df$bc_name <- bc_map[df$BC]
      df$bc_name[is.na(df$bc_name)] <- "Unknown"

      # --- START CHANGE: Normalization Logic ---
      # Calculate Min/Max for the current filtered dataset
      min_s <- min(df$score, na.rm = TRUE)
      max_s <- max(df$score, na.rm = TRUE)
      rng <- max_s - min_s

      # Handle case where all scores are identical to prevent division by zero
      if (rng == 0) {
        rng <- 1
      }

      # Create Normalized Score (0 to 1)
      df$norm_score <- (df$score - min_s) / rng
      # --- END CHANGE ---

      # --- DYNAMIC COLOR EXTRACTION ---
      # Helper: If it's a list (gradient), grab the LAST element (Max Intensity).
      # If it's a string (static), just use it.
      get_high_color <- function(lid) {
        col_def <- layer_defs[[lid]]$color
        if (is.list(col_def)) {
          # The last element of the MapLibre expression is the highest color
          return(col_def[[length(col_def)]])
        }
        return(col_def)
      }

      # Dynamically fetch colors (Works for both Gradients and Static Hexes)
      c_ac <- get_high_color("w_AC")
      c_ah <- get_high_color("w_AH")
      c_ae <- get_high_color("w_AE")
      c_ag <- get_high_color("w_AG")
      c_am <- get_high_color("w_AM")
      c_ap <- get_high_color("w_AP")

      c_tt <- get_high_color("w_TT")
      c_tf <- get_high_color("w_TF")
      c_ta <- get_high_color("w_TA")

      c_aa <- get_high_color("w_AA") # Automatically grabs the dark red
      c_at <- get_high_color("w_AT") # Automatically grabs the dark blue

      MAX_H <- 40

      df$tooltip_html <- paste0(
        "<div style='font-family: sans-serif; padding: 12px; background: white; border-radius: 4px; box-shadow: 0 4px 15px rgba(0,0,0,0.2); min-width: 160px;'>",
        "<div style='margin-bottom:10px; border-bottom:1px solid #eee; padding-bottom:6px;'>",
        "<div style='font-weight:bold; font-size:16px; color:#233A57;'>ATO Index: ",
        # CHANGED: Use norm_score and force 2 decimals (0.00 - 1.00)
        sprintf("%.2f", df$norm_score),
        "</div>",
        "<div style='font-size:12px; color:#666; margin-top:2px;'>Land Use: ",
        df$bc_name,
        "</div></div>",

        # --- TOP ROW: TRANSPORTATION & JOB ACCESS (SWAPPED UP) ---
        "<div style='display: flex; justify-content: space-between; margin-bottom: 4px;'>",
        "<div style='font-size:8px; font-weight:bold; color:#999;'>TRANSPORTATION</div>",
        "<div style='font-size:8px; font-weight:bold; color:#999; text-align: right;'>JOB ACCESS</div>",
        "</div>",
        "<div style='display: flex; gap: 6px; height: 55px; align-items: flex-end; justify-content: space-between; margin-bottom: 12px;'>",
        # Transport
        "<div style='display:flex; flex-direction:column; align-items:center; width: 18px;'><div style='width:100%; border-radius:2px 2px 0 0; background:",
        c_tt,
        "; min-height: 1px; height:",
        round(df$TT * MAX_H),
        "px;'></div><div style='font-size:12px; margin-top:2px; color:",
        c_tt,
        ";'><i class='fa-solid fa-bus'></i></div></div>",
        "<div style='display:flex; flex-direction:column; align-items:center; width: 18px;'><div style='width:100%; border-radius:2px 2px 0 0; background:",
        c_tf,
        "; min-height: 1px; height:",
        round(df$TF * MAX_H),
        "px;'></div><div style='font-size:12px; margin-top:2px; color:",
        c_tf,
        ";'><i class='fa-solid fa-road'></i></div></div>",
        "<div style='display:flex; flex-direction:column; align-items:center; width: 18px;'><div style='width:100%; border-radius:2px 2px 0 0; background:",
        c_ta,
        "; min-height: 1px; height:",
        round(df$TA * MAX_H),
        "px;'></div><div style='font-size:12px; margin-top:2px; color:",
        c_ta,
        ";'><i class='fa-solid fa-bicycle'></i></div></div>",
        # Buffer
        "<div style='width: 18px;'></div>",
        # Jobs
        "<div style='display:flex; flex-direction:column; align-items:center; width: 18px;'><div style='width:100%; border-radius:2px 2px 0 0; background:",
        c_aa,
        "; min-height: 1px; height:",
        round(df$AA * MAX_H),
        "px;'></div><div style='font-size:12px; margin-top:2px; color:",
        c_aa,
        ";'><i class='fa-solid fa-car'></i></div></div>",
        "<div style='display:flex; flex-direction:column; align-items:center; width: 18px;'><div style='width:100%; border-radius:2px 2px 0 0; background:",
        c_at,
        "; min-height: 1px; height:",
        round(df$AT * MAX_H),
        "px;'></div><div style='font-size:12px; margin-top:2px; color:",
        c_at,
        ";'><i class='fa-solid fa-train'></i></div></div>",
        "</div>",

        # --- BOTTOM ROW: NECESSITIES (SWAPPED DOWN) ---
        "<div style='font-size:8px; font-weight:bold; color:#999; margin-bottom:4px;'>NECESSITIES</div>",
        "<div style='display: flex; gap: 6px; height: 55px; align-items: flex-end; justify-content: space-between;'>",
        "<div style='display:flex; flex-direction:column; align-items:center; width: 18px;'><div style='width:100%; border-radius:2px 2px 0 0; background:",
        c_ac,
        "; min-height: 1px; height:",
        round(df$AC * MAX_H),
        "px;'></div><div style='font-size:12px; margin-top:2px; color:",
        c_ac,
        ";'><i class='fa-solid fa-baby'></i></div></div>",
        "<div style='display:flex; flex-direction:column; align-items:center; width: 18px;'><div style='width:100%; border-radius:2px 2px 0 0; background:",
        c_ah,
        "; min-height: 1px; height:",
        round(df$AH * MAX_H),
        "px;'></div><div style='font-size:12px; margin-top:2px; color:",
        c_ah,
        ";'><i class='fa-solid fa-heart-pulse'></i></div></div>",
        "<div style='display:flex; flex-direction:column; align-items:center; width: 18px;'><div style='width:100%; border-radius:2px 2px 0 0; background:",
        c_ae,
        "; min-height: 1px; height:",
        round(df$AE * MAX_H),
        "px;'></div><div style='font-size:12px; margin-top:2px; color:",
        c_ae,
        ";'><i class='fa-solid fa-graduation-cap'></i></div></div>",
        "<div style='display:flex; flex-direction:column; align-items:center; width: 18px;'><div style='width:100%; border-radius:2px 2px 0 0; background:",
        c_ag,
        "; min-height: 1px; height:",
        round(df$AG * MAX_H),
        "px;'></div><div style='font-size:12px; margin-top:2px; color:",
        c_ag,
        ";'><i class='fa-solid fa-cart-shopping'></i></div></div>",
        "<div style='display:flex; flex-direction:column; align-items:center; width: 18px;'><div style='width:100%; border-radius:2px 2px 0 0; background:",
        c_am,
        "; min-height: 1px; height:",
        round(df$AM * MAX_H),
        "px;'></div><div style='font-size:12px; margin-top:2px; color:",
        c_am,
        ";'><i class='fa-solid fa-landmark'></i></div></div>",
        "<div style='display:flex; flex-direction:column; align-items:center; width: 18px;'><div style='width:100%; border-radius:2px 2px 0 0; background:",
        c_ap,
        "; min-height: 1px; height:",
        round(df$AP * MAX_H),
        "px;'></div><div style='font-size:12px; margin-top:2px; color:",
        c_ap,
        ";'><i class='fa-solid fa-tree'></i></div></div>",
        "</div>",

        "</div>"
      )
    }
    return(df)
  })

  # Add Client sided filter to filter land use
  shiny::observeEvent(input$land_use_group, {
    # Get the codes for the selected group (e.g., "Residential" -> c("SF", "MF"))
    selected_codes <- unique(unlist(lu_mappings[input$land_use_group]))

    # Create a MapLibre Filter Expression: ["in", "BC", "SF", "MF"]
    # The "in" operator checks if the property "BC" matches any value in the list
    filter_expr <- c(list("in", "BC"), as.list(selected_codes))

    # If "All Land Uses" is selected (or nothing), clear the filter
    if (input$land_use_group == "All Land Uses") {
      filter_expr <- NULL
    }

    # Apply Instant Filter
    mapgl::maplibre_proxy("map") |>
      mapgl::set_filter("h3_layer_2d", filter_expr) |>
      mapgl::set_filter("h3_layer_3d", filter_expr)
  })

  # --- HELPER: CLIENT-SIDE EXPRESSION (For Instant Coloring) ---
  build_score_expr <- function(weights) {
    # Extract column names (e.g., "w_AC" -> "AC")
    short_names <- substring(names(weights), 3)

    # Filter to ONLY columns that exist in the H3 dataset
    valid_indices <- which(short_names %in% available_h3_cols)
    valid_names <- short_names[valid_indices]
    valid_weights <- weights[valid_indices]

    # Build the Numerator: (ColA * WeightA) + (ColB * WeightB)...
    terms <- lapply(seq_along(valid_names), function(i) {
      list("*", list("get", valid_names[i]), as.numeric(valid_weights[[i]]))
    })
    numerator <- append(list("+"), terms)

    # Build the Denominator: Sum of Weights
    total_w <- sum(as.numeric(valid_weights))
    if (total_w == 0) {
      total_w <- 1
    }

    # Return Expression: Numerator / Denominator
    list("/", numerator, total_w)
  }

  # --- 3. MAP INITIALIZATION ---
  output$map <- mapgl::renderMaplibre({
    m <- mapgl::maplibre(
      style = mapgl::carto_style("voyager"),
      center = c(-111.8910, 40.7608),
      zoom = 8,
      pitch = 0,
      # preserveDrawingBuffer = TRUE
      canvasContextAttributes = list(
        preserveDrawingBuffer = TRUE
      )
    ) |>
      mapgl::add_navigation_control(position = "top-left") |>
      mapgl::add_scale_control(position = "bottom-left", unit = "imperial") |>
      mapgl::add_geolocate_control(position = "top-left") |>
      mapgl::add_geocoder_control(position = "top-left") |>
      mapgl::add_reset_control(position = "top-left") |>
      mapgl::add_screenshot_control(
        position = "top-left",
        hide_controls = FALSE,
        filename = "ATO_Housing_Map",
        image_scale = 2
      ) |>
      # mapgl::add_draw_control(position = "top-left") |>
      # mapgl::add_features_to_draw(position = "top-left") |>
      # 1. ADD SOURCE FOR ROADS
      mapgl::add_raster_source(
        id = "src_roads_tile",
        tiles = "https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Transportation/MapServer/tile/{z}/{y}/{x}",
        tileSize = 192
      )

    # 2. ADD CITY FILL (BOTTOM LAYER)
    if (!is.null(cities_sf)) {
      m <- m |>
        mapgl::add_fill_layer(
          id = "lay_cities_fill",
          source = cities_sf,
          fill_color = "#CCCCCC",
          # --- CHANGED: Fade fill from 0.5 to 0.0 between Zoom 12 and 15 ---
          fill_opacity = list(
            "interpolate",
            list("linear"),
            list("zoom"),
            12,
            0.5,
            15,
            0.0
          )
        )
    }

    # 3. ADD ROADS (MIDDLE LAYER - On top of fill)
    m <- m |>
      mapgl::add_raster_layer(
        id = "lay_roads_tile",
        source = "src_roads_tile",
        # --- CHANGED: Fade out roads between zoom 12 and 16 ---
        raster_opacity = list(
          "interpolate",
          list("linear"),
          list("zoom"),
          13,
          0.9, # Full opacity (0.9) up to zoom 12
          14,
          0.0 # Completely invisible (0.0) by zoom 16
        ),
        visibility = "visible"
      )

    # 4. ADD CITY LINES (TOP LAYER - On top of roads)
    if (!is.null(cities_sf)) {
      m <- m |>
        mapgl::add_line_layer(
          id = "lay_cities_line",
          source = cities_sf,
          line_color = "#999999",
          line_width = 1.5,
          line_opacity = 0.5
        )
    }

    # ADD LAYERS CONTROL (Grouped Cities)
    m <- m |>
      mapgl::add_layers_control(
        position = "top-right",
        layers = list(
          "Major Roads" = "lay_roads_tile",
          "City Boundaries" = c("lay_cities_fill", "lay_cities_line")
        ),
        collapsible = TRUE,
        active_color = "#233A57"
      )

    # 1. Prepare BBox Filter
    bbox_query_str <- ""
    if (!is.null(bound_sf)) {
      bb <- sf::st_bbox(bound_sf)
      # Format removes scientific notation
      bbox_val <- paste(
        format(as.numeric(bb[c(1, 2, 3, 4)]), scientific = FALSE, trim = TRUE),
        collapse = ","
      )
      bbox_query_str <- paste0(
        "&geometry=",
        bbox_val,
        "&geometryType=esriGeometryEnvelope",
        "&spatialRel=esriSpatialRelIntersects",
        "&inSR=4326"
      )
    }

    for (lid in names(layer_defs)) {
      def <- layer_defs[[lid]]
      urls <- if (!is.null(def$urls)) def$urls else def$url

      # Determine chunks. Server Max is usually 2000.
      target_limit <- if (!is.null(def$limit)) def$limit else 2000
      chunk_size <- 2000

      for (i in seq_along(urls)) {
        # Calculate how many "pages" we need for this URL
        # e.g., if Limit is 3600, offsets will be: 0, 2000
        offsets <- seq(0, target_limit - 1, by = chunk_size)

        for (j in seq_along(offsets)) {
          offset_val <- offsets[j]

          # Construct paginated URL
          q <- utils::URLencode(def$query)
          full_url <- paste0(
            urls[i],
            "/query?where=",
            q,
            "&outFields=*",
            "&f=geojson",
            "&outSR=4326",
            "&resultOffset=",
            offset_val,
            "&resultRecordCount=",
            chunk_size,
            bbox_query_str
          )

          # Create unique ID: e.g., src_w_AA_1_1, src_w_AA_1_2
          suffix <- paste0("_", i, "_", j)

          m <- m |>
            mapgl::add_source(
              id = paste0("src_", lid, suffix),
              type = "geojson",
              data = full_url
            )
        }
      }
    }
    m
  })

  # --- 5. FAST OBSERVER: SLIDER CHANGES (INSTANT UPDATES) ---
  shiny::observeEvent(
    debounced_sliders(),
    {
      shiny::req(input$comm_code)

      # 1. Get current data and weights
      dat <- shiny::isolate(filtered_data())
      w <- debounced_sliders()

      # 2. Re-calculate scores in R to find the new Min/Max
      #    (This vector math is extremely fast, even for 20k+ rows)
      if (nrow(dat) > 0) {
        # Extract the relevant columns from the SF object
        # Note: We use the Short Names (e.g. "AA") derived from slider ID ("w_AA")
        cols <- substring(names(w), 3)

        # Ensure we only use columns that actually exist in the data
        # (Prevents crash if a column is missing)
        valid_cols <- intersect(cols, names(dat))

        if (length(valid_cols) > 0) {
          # Drop geometry for speed
          df_calc <- sf::st_drop_geometry(dat)[, valid_cols, drop = FALSE]

          # Match weights to columns
          current_weights <- w[paste0("w_", valid_cols)]

          # Calculate Weighted Sum
          # Handle NAs by treating them as 0
          df_calc[is.na(df_calc)] <- 0

          weighted_sum <- rowSums(
            df_calc * current_weights[col(df_calc)]
          )

          total_weight <- sum(current_weights)

          # Final Score Vector
          new_scores <- if (total_weight == 0) {
            0
          } else {
            weighted_sum / total_weight
          }

          # 3. Determine Dynamic Range (The "Intensity" Fix)
          min_s <- min(new_scores, na.rm = TRUE)
          max_s <- max(new_scores, na.rm = TRUE)

          # Safety check to prevent div/0 in interpolation
          if (max_s == min_s) {
            max_s <- min_s + 0.0001
          }

          # Create stops based on ACTUAL data range (just like the initial load)
          stops_val <- seq(min_s, max_s, length.out = 6)
        } else {
          # Fallback if no valid columns found
          stops_val <- seq(0, 1, length.out = 6)
        }
      } else {
        stops_val <- seq(0, 1, length.out = 6)
      }

      # 4. Build the MapLibre Expression
      score_expr <- build_score_expr(w)
      pal_colors <- RColorBrewer::brewer.pal(6, "YlGnBu")

      color_expr <- list("interpolate", list("linear"), score_expr)
      for (i in seq_along(stops_val)) {
        color_expr <- append(color_expr, list(stops_val[i], pal_colors[i]))
      }

      # 5. Apply Updates
      proxy <- mapgl::maplibre_proxy("map")

      if (isTRUE(input$map_3d)) {
        proxy |>
          mapgl::set_paint_property(
            "h3_layer_3d",
            "fill-extrusion-color",
            color_expr
          )

        # Update Height (Dynamic Scale)
        extrusion_val <- if (is.numeric(input$z_mult)) {
          input$z_mult * 1000
        } else {
          2000
        }
        height_expr <- list(
          "interpolate",
          list("linear"),
          score_expr,
          0, # Min Score -> Height 0
          0,
          1, # Max Score (theoretical) -> Max Height
          extrusion_val
        )
        proxy |>
          mapgl::set_paint_property(
            "h3_layer_3d",
            "fill-extrusion-height",
            height_expr
          )
      } else {
        proxy |>
          mapgl::set_paint_property("h3_layer_2d", "fill-color", color_expr)
      }
    },
    ignoreInit = TRUE
  )

  # 4a. Map -> Sidebar (CLEANED)
  shiny::observeEvent(input$map_feature_click, {
    click_data <- input$map_feature_click
    layer_id <- if (!is.null(click_data$layerId)) {
      click_data$layerId
    } else {
      click_data$layer
    }

    clicked_code <- NULL
    if (!is.null(layer_id)) {
      if (layer_id == "lay_cities_fill" || layer_id == "lay_cities_line") {
        clicked_code <- click_data$properties$UGRCODE
      } else if (layer_id %in% c("h3_layer_2d", "h3_layer_3d")) {
        clicked_code <- click_data$properties$CommCode
      }
    }

    if (!is.null(clicked_code) && clicked_code %in% city_choices) {
      current_selection <- input$comm_code
      if (is.null(current_selection)) {
        current_selection <- character(0)
      }
      new_selection <- if (clicked_code %in% current_selection) {
        setdiff(current_selection, clicked_code)
      } else {
        c(current_selection, clicked_code)
      }
      shinyWidgets::updatePickerInput(
        session,
        "comm_code",
        selected = new_selection
      )
    }
  })

  # 4b. Sidebar -> Map (Visual Highlight)
  shiny::observeEvent(
    input$comm_code,
    {
      if (!is.null(cities_sf)) {
        proxy <- mapgl::maplibre_proxy("map")
        if (length(input$comm_code) > 0) {
          filter_exp <- as.list(c("in", "UGRCODE", input$comm_code))
          proxy |>
            mapgl::set_paint_property("lay_cities_line", "line-width", 2.5) |>
            mapgl::set_paint_property(
              "lay_cities_line",
              "line-color",
              "#233A57"
            ) |>
            mapgl::set_paint_property("lay_cities_line", "line-opacity", 0.9) |>
            mapgl::set_filter("lay_cities_line", filter_exp)
        } else {
          proxy |>
            mapgl::set_paint_property("lay_cities_line", "line-width", 1) |>
            mapgl::set_paint_property(
              "lay_cities_line",
              "line-color",
              "#999999"
            ) |>
            mapgl::set_paint_property("lay_cities_line", "line-opacity", 0.5) |>
            mapgl::set_filter("lay_cities_line", NULL)
        }
      }
    },
    ignoreNULL = FALSE
  )

  # --- 5. REFERENCE LAYER TOGGLE LOGIC ---
  layer_states <- shiny::reactiveValues()
  for (lid in names(layer_defs)) {
    layer_states[[lid]] <- FALSE
  }

  lapply(names(layer_defs), function(lid) {
    shiny::observeEvent(input[[paste0("toggle_", lid)]], {
      layer_states[[lid]] <- !layer_states[[lid]]

      # Toggle button styling & Icon Switching
      if (layer_states[[lid]]) {
        shinyjs::addClass(id = paste0("btn_", lid), class = "active")
        # --- CHANGED: Remove 'slash', add 'eye' (fa-solid stays) ---
        shinyjs::runjs(sprintf(
          "$('#btn_%s i').removeClass('fa-eye-slash').addClass('fa-eye');",
          lid
        ))
      } else {
        shinyjs::removeClass(id = paste0("btn_", lid), class = "active")
        # --- CHANGED: Remove 'eye', add 'slash' (fa-solid stays) ---
        shinyjs::runjs(sprintf(
          "$('#btn_%s i').removeClass('fa-eye').addClass('fa-eye-slash');",
          lid
        ))
      }

      proxy <- mapgl::maplibre_proxy("map")
      def <- layer_defs[[lid]]
      urls <- if (!is.null(def$urls)) def$urls else def$url

      # Pagination Settings (Must match map logic)
      target_limit <- if (!is.null(def$limit)) def$limit else 2000
      chunk_size <- 2000

      current_ids <- character()

      for (i in seq_along(urls)) {
        offsets <- seq(0, target_limit - 1, by = chunk_size)

        for (j in seq_along(offsets)) {
          suffix <- paste0("_", i, "_", j)
          source_id <- paste0("src_", lid, suffix)
          layer_id <- paste0("lay_", lid, suffix)
          current_ids <- c(current_ids, layer_id)

          if (def$type == "polygon") {
            current_ids <- c(current_ids, paste0(layer_id, "_ol"))
          }

          if (layer_states[[lid]]) {
            # TODO: --- REVERTIBLE CHANGE: Custom Styling for Centers ---
            # ORIGINAL CODE (Implicit):
            # fill_op <- 0.7
            # line_wd <- 1.5

            # NEW CODE: Check if layer is a Center, apply custom styles
            is_center <- lid %in% c("w_CM", "w_CU", "w_CC", "w_CN")

            # If center: 0.1 opacity (almost transparent), otherwise 0.7
            fill_op <- if (is_center) 0.1 else 0.7

            # If center: 4.0 width (double), otherwise 1.5
            line_wd <- if (is_center) 4.0 else 1.5
            # -----------------------------------------------------

            if (def$type == "polygon") {
              proxy <- proxy |>
                mapgl::add_fill_layer(
                  id = layer_id,
                  source = source_id,
                  fill_color = def$color,
                  fill_opacity = fill_op # CHANGED: Uses variable
                ) |>
                mapgl::move_layer(layer_id, "lay_cities_line") |>
                mapgl::add_line_layer(
                  id = paste0(layer_id, "_ol"),
                  source = source_id,
                  line_color = def$color,
                  line_width = line_wd # CHANGED: Uses variable
                ) |>
                mapgl::move_layer(paste0(layer_id, "_ol"), "lay_cities_line")
            } else if (def$type == "line") {
              proxy <- proxy |>
                mapgl::add_line_layer(
                  id = layer_id,
                  source = source_id,
                  line_color = def$color,
                  line_width = 2
                ) |>
                mapgl::move_layer(layer_id, "lay_cities_line")
            } else if (def$type == "point") {
              proxy <- proxy |>
                mapgl::add_circle_layer(
                  id = layer_id,
                  source = source_id,
                  circle_color = def$color,
                  circle_radius = 5,
                  circle_stroke_width = 1,
                  circle_stroke_color = "#fff"
                ) |>
                mapgl::move_layer(layer_id, "lay_cities_line")
            }
          } else {
            proxy <- proxy |> mapgl::clear_layer(layer_id)
            if (def$type == "polygon") {
              proxy <- proxy |> mapgl::clear_layer(paste0(layer_id, "_ol"))
            }
          }
        }
      }

      # Update Layer Control
      current_list <- active_ref_layers()
      human_name <- if (lid %in% names(layer_names)) layer_names[[lid]] else lid

      if (layer_states[[lid]]) {
        current_list[[human_name]] <- current_ids
      } else {
        current_list[[human_name]] <- NULL
      }
      active_ref_layers(current_list)
      refresh_layer_control(proxy, shiny::isolate(input$map_3d), current_list)
    })
  })

  # --- 6. HEATMAP RENDERER (SLOW UPDATE: LEGEND & BRIGHTNESS) ---
  shiny::observe({
    # A. SHOW WAITER
    w$show()

    # 1. INITIALIZE DELAY VARIABLE
    # Start with a safe default (1.0s) in case the data query fails
    # or returns 0 rows.
    delay_ms <- 1000

    # B. ROBUST HIDING
    # Note: on.exit evaluates 'delay_ms' at the moment of exit,
    # so it will pick up the updated value calculated below.
    on.exit({
      shinyjs::delay(delay_ms, w$hide())
    })

    # C. UI RENDER PAUSE
    Sys.sleep(0.1)

    dat <- filtered_data()

    # Note: We clear layers to force a clean redraw with the new relative scale
    proxy <- mapgl::maplibre_proxy("map") |>
      mapgl::clear_layer("h3_layer_3d") |>
      mapgl::clear_layer("h3_layer_2d")

    if (nrow(dat) > 0) {
      # [Logic Block: Calculate Scale & Colors] ---------------------------

      # --- DYNAMIC DELAY CALCULATION ---
      # Base: 1000ms (minimum wait for UI smoothness)
      # Dynamic: +0.15ms per hexagon row
      # Example: 2,000 rows  -> 1000 + 300  = 1.3 seconds
      # Example: 15,000 rows -> 1000 + 2250 = 3.25 seconds (SLC Size)
      delay_ms <- 1000 + (nrow(dat) * 0.15)

      # ----------------------------------------------------

      # 1. CALCULATE RELATIVE SCALE (BRIGHTNESS)
      # Find the actual min/max scores in the current view
      min_s <- min(dat$score, na.rm = TRUE)
      max_s <- max(dat$score, na.rm = TRUE)

      # Prevent errors if max == min
      if (max_s == min_s) {
        max_s <- min_s + 0.0001
      }

      # Create stops based on ACTUAL data range (e.g., 0 to 0.77)
      stops_val <- seq(min_s, max_s, length.out = 6)

      # 2. GENERATE LEGEND LABELS
      # CHANGED: Force labels to be 0.00 to 1.00, formatted to 2 decimals
      legend_labels <- sprintf("%.2f", seq(0, 1, length.out = 6))
      pal_colors <- RColorBrewer::brewer.pal(6, "YlGnBu")

      # 3. CONSTRUCT COLOR EXPRESSION
      # We need to rebuild the expression to use our new dynamic stops
      current_weights <- shiny::isolate(debounced_sliders()) # Use current slider values
      score_expr <- build_score_expr(current_weights)

      color_expr <- list("interpolate", list("linear"), score_expr)
      for (i in seq_along(stops_val)) {
        color_expr <- append(color_expr, list(stops_val[i], pal_colors[i]))
      }
      # -------------------------------------------------------------------

      # 4. RENDER LAYER
      target_layer <- if (input$map_3d) "h3_layer_3d" else "h3_layer_2d"

      if (input$map_3d) {
        extrusion_val <- if (is.numeric(input$z_mult)) {
          input$z_mult * 1000
        } else {
          2000
        }
        height_expr <- list(
          "interpolate",
          list("linear"),
          score_expr,
          0,
          0,
          1,
          extrusion_val
        )

        proxy <- proxy |>
          mapgl::add_fill_extrusion_layer(
            "h3_layer_3d",
            dat,
            fill_extrusion_color = color_expr,
            fill_extrusion_height = height_expr,
            fill_extrusion_opacity = list(
              "interpolate",
              list("linear"),
              list("zoom"),
              14,
              0.9,
              18,
              0.1
            ),
            tooltip = "tooltip_html" # REMOVE: from here
          ) |>
          # ADD THIS: Sets the tooltip column for hover
          # mapgl::set_tooltip("h3_layer_3d", "tooltip_html") |>
          mapgl::move_layer("h3_layer_3d", "lay_roads_tile") |>
          mapgl::fit_bounds(dat, animate = TRUE, pitch = 45)
      } else {
        proxy <- proxy |>
          mapgl::add_fill_layer(
            "h3_layer_2d",
            dat,
            fill_color = color_expr,
            # --- CHANGED: Fade 2D fill from 0.8 to 0.2 between zoom 15 and 18 ---
            fill_opacity = list(
              "interpolate",
              list("linear"),
              list("zoom"),
              14,
              0.9,
              18,
              0.1
            ),
            tooltip = "tooltip_html" # REMOVE from here
          ) |>
          # ADD THIS: Sets the tooltip column for hover
          # mapgl::set_tooltip("h3_layer_2d", "tooltip_html") |>
          mapgl::move_layer("h3_layer_2d", "lay_roads_tile") |>
          mapgl::fit_bounds(dat, animate = TRUE, pitch = 0)
      }

      # 1. Define the Style Object (Matches your previous CSS)
      custom_legend_style <- mapgl::legend_style(
        background_color = "white",
        background_opacity = 0.8, # Previously rgba(..., 0.8)
        border_color = "#cccccc", # Previously border: 1px solid #ccc
        border_width = 1,
        shadow = TRUE,
        shadow_color = "rgba(0,0,0,0.2)", # Previously box-shadow color
        shadow_size = 10, # previously 10px blur
        title_font_family = "Oswald", # Matches your app header font
        font_family = "Open Sans" # Matches your app body font
      )

      # 5. ADD DYNAMIC LEGEND
      proxy |>
        mapgl::move_layer("lay_cities_line") |>
        mapgl::add_legend(
          legend_title = "ATO Index",
          type = "categorical",
          values = legend_labels,
          colors = pal_colors,
          position = "bottom-right",
          layer_id = target_layer,
          add = FALSE,
          style = custom_legend_style
        )

      current_refs <- shiny::isolate(active_ref_layers())
      refresh_layer_control(proxy, input$map_3d, current_refs)
    }
  })

  # --- 8. DATA DOWNLOAD HANDLER ---
  output$btn_dl_data <- shiny::downloadHandler(
    filename = function() {
      "ATO_Filtered_Data.csv"
    },
    content = function(file) {
      shiny::req(input$comm_code)
      shiny::req(length(input$comm_code) > 0)
      shiny::req(filtered_data())

      out_df <- filtered_data() |>
        sf::st_drop_geometry() |>
        dplyr::select(-any_of("tooltip_html")) |>
        # OPTIONAL: Rename your internal H3 column to standard 'h3_index' if it isn't already
        # dplyr::rename(h3_index = H3) |>
        dplyr::as_tibble() # Ensure clean write

      utils::write.csv(out_df, file, row.names = FALSE)
    }
  )
}

shiny::shinyApp(ui, server)
