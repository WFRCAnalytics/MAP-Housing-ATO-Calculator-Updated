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

# ==============================================================================
# 1. GLOBAL SETUP & DATA LOADING
# ==============================================================================

data_path <- "../_output/h3_scored.parquet"
if (!file.exists(data_path)) {
  data_path <- "h3_scored.parquet"
}

# Load Data
message("Loading data...")
ds_h3 <- arrow::open_dataset(data_path) |>
  sf::st_as_sf(crs = 4326)
message("Data loaded: ", nrow(ds_h3), " rows")

# --- CITY LOOKUP TABLE ---
all_cities_map <- c(
  "Alpine" = "ALP",
  "Alta" = "ALA",
  "American Fork" = "AFK",
  "Bluffdale" = "BDL",
  "Bountiful" = "BTF",
  "Brigham City" = "BGM",
  "Brighton" = "BRT",
  "Cedar Fort" = "CDF",
  "Cedar Hills" = "CHL",
  "Centerville" = "CEN",
  "Charleston" = "CHA",
  "Clearfield" = "CLR",
  "Clinton" = "CLI",
  "Coalville" = "COA",
  "Copperton" = "CMT",
  "Cottonwood Heights" = "COT",
  "Draper" = "DRA",
  "Eagle Mountain" = "EAG",
  "Elk Ridge" = "ELK",
  "Fairfield" = "FFD",
  "Farmington" = "FRM",
  "Farr West" = "FRR",
  "Fruit Heights" = "FRU",
  "Genola" = "GEN",
  "Goshen" = "GOS",
  "Harrisville" = "HAR",
  "Heber City" = "HEB",
  "Herriman" = "HER",
  "Highland" = "HGH",
  "Holladay" = "HOL",
  "Honeyville" = "HON",
  "Hooper" = "HOO",
  "Huntsville" = "HVL",
  "Kamas" = "KAM",
  "Kaysville" = "KAY",
  "Kearns" = "KMT",
  "Layton" = "LAY",
  "Lehi" = "LEH",
  "Lindon" = "LIN",
  "Logan" = "LOG",
  "Mapleton" = "MAP",
  "Marriott-Slaterville" = "MSL",
  "Midvale" = "MID",
  "Midway" = "MWY",
  "Millcreek" = "MLC",
  "Morgan" = "MRG",
  "Murray" = "MUR",
  "North Ogden" = "NOG",
  "North Salt Lake" = "NSL",
  "Ogden" = "OGD",
  "Orem" = "ORE",
  "Park City" = "PKC",
  "Payson" = "PAY",
  "Perry" = "PER",
  "Plain City" = "PLN",
  "Pleasant Grove" = "PGR",
  "Pleasant View" = "PVW",
  "Provo" = "PVO",
  "Riverdale" = "RVD",
  "Riverton" = "RVT",
  "Roy" = "ROY",
  "Rush Valley" = "RUS",
  "Salem" = "SLM",
  "Salt Lake City" = "SLC",
  "Sandy" = "SAN",
  "Santaquin" = "SAQ",
  "Saratoga Springs" = "SAR",
  "South Jordan" = "SJC",
  "South Ogden" = "SOG",
  "South Salt Lake" = "SSL",
  "South Weber" = "SWE",
  "Spanish Fork" = "SFK",
  "Springville" = "SPV",
  "Stockton" = "STK",
  "Sunset" = "SUN",
  "Syracuse" = "SYR",
  "Taylorsville" = "TAY",
  "Tooele" = "TOO",
  "Trenton" = "TRN",
  "Uintah" = "UIN",
  "Vernal" = "VER",
  "Vineyard" = "VIN",
  "Wallsburg" = "WBG",
  "Washington Terrace" = "WTR",
  "Wellington" = "WEL",
  "Wellsville" = "WLV",
  "Wendover" = "WEN",
  "West Bountiful" = "WBO",
  "West Haven" = "WHV",
  "West Jordan" = "WJC",
  "West Point" = "WPT",
  "West Valley City" = "WVC",
  "White City" = "WMT",
  "Willard" = "WIL",
  "Woodland Hills" = "WDL",
  "Woods Cross" = "WCR"
)

present_codes <- unique(ds_h3$CommCode)
city_choices <- all_cities_map[all_cities_map %in% present_codes]
city_choices <- city_choices[order(names(city_choices))]

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
    color = "#FF7F00"
  ),
  "w_AT" = list(
    url = "https://services1.arcgis.com/taguadKoI1XFwivx/ArcGIS/rest/services/AccessToOpportunities_gdb/FeatureServer/0",
    query = "1=1",
    type = "polygon",
    color = "#FFFF33"
  ),
  # Transportation
  "w_TT" = list(
    url = "https://maps.rideuta.com/server/rest/services/Hosted/UTA_Stops_and_Most_Recent_Ridership/FeatureServer/0",
    query = "1=1",
    type = "point",
    color = "#666666"
  ),
  "w_TF" = list(
    url = "https://services.arcgis.com/pA2nEVnB6tquxgOW/arcgis/rest/services/Freeway_Exit_Locations/FeatureServer/0",
    query = "1=1",
    type = "point",
    color = "#000000"
  ),
  "w_TA" = list(
    url = "https://services1.arcgis.com/99lidPhWCzftIe9K/ArcGIS/rest/services/Bikeways/FeatureServer/0",
    query = "Facility1 like '%(1A)%' or Facility1 like '%(1B)%' or Facility1 like '%(2A)%' or Facility1 like '%(2B)%' or Facility1 like '%(2C)%' or Facility1 like '%Trail%'",
    type = "line",
    color = "#2ca25f"
  ),
  # Necessities
  "w_AC" = list(
    url = "https://services1.arcgis.com/taguadKoI1XFwivx/arcgis/rest/services/Utah_Child_Care_Centers/FeatureServer/0",
    query = "1=1",
    type = "point",
    color = "#E41A1C"
  ),
  "w_AH" = list(
    url = "https://services1.arcgis.com/99lidPhWCzftIe9K/ArcGIS/rest/services/LicensedHealthCareFacilities/FeatureServer/0",
    query = "1=1",
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
    url = "https://services1.arcgis.com/taguadKoI1XFwivx/arcgis/rest/services/Residential_Accessibility_WFL1/FeatureServer/374",
    query = "1=1",
    type = "point",
    color = "#984EA3"
  ),
  "w_AM" = list(
    url = "https://services1.arcgis.com/taguadKoI1XFwivx/arcgis/rest/services/Community_Centers/FeatureServer/0",
    query = "1=1",
    type = "point",
    color = "#FF7F00"
  ),
  "w_AP" = list(
    url = "https://services1.arcgis.com/taguadKoI1XFwivx/ArcGIS/rest/services/ParkEdits/FeatureServer/0",
    query = "1=1",
    type = "polygon",
    color = "#A65628"
  )
)

# --- HELPER: Slider with shinyjs Icon Toggle ---
sliderWithLayer <- function(inputId, label) {
  shiny::tagList(
    shiny::div(
      class = "d-flex justify-content-between align-items-center mb-1",
      tags$label(
        label,
        class = "control-label",
        `for` = inputId,
        style = "margin-bottom: 0;"
      ),
      tags$a(
        id = paste0("btn_", inputId),
        class = "layer-toggle-btn",
        onclick = sprintf(
          "Shiny.setInputValue('%s', Math.random());",
          paste0("toggle_", inputId)
        ),
        title = "Toggle Reference Layer",
        shiny::icon("layer-group")
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
    tags$link(
      rel = "stylesheet",
      href = "https://fonts.googleapis.com/css2?family=Oswald:wght@300;400;500;700&display=swap"
    ),
    tags$link(
      rel = "stylesheet",
      href = "https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.2/css/all.min.css"
    ),
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

      /* --- SPLASH SCREEN STYLES --- */
      .modal-content {
        border: none;
        border-radius: 12px;
        box-shadow: 0 15px 35px rgba(0,0,0,0.25);
        overflow: hidden;
      }
      .splash-header {
        background: linear-gradient(135deg, #233A57 0%, #3a5c85 100%);
        color: white;
        padding: 30px 25px;
        text-align: center;
        position: relative;
      }
      .splash-header h2 {
        font-family: 'Oswald', sans-serif;
        color: white;
        margin: 0;
        letter-spacing: 1px;
      }
      .splash-body {
        padding: 25px 35px;
        font-family: 'Open Sans', sans-serif;
        color: #444;
      }
      .feature-grid {
        display: flex;
        gap: 20px;
        margin: 25px 0;
        text-align: center;
      }
      .feature-item {
        flex: 1;
        padding: 15px;
        background: #f8f9fa;
        border-radius: 8px;
        transition: transform 0.2s;
      }
      .feature-item:hover {
        transform: translateY(-3px);
        background: #f0f4f8;
      }
      .feature-icon {
        font-size: 1.8rem;
        color: #e8572d; /* Orange accent */
        margin-bottom: 10px;
      }
      .feature-title {
        font-weight: 700;
        font-size: 0.9rem;
        text-transform: uppercase;
        color: #233A57;
        margin-bottom: 5px;
      }
      .instruction-box {
        background-color: #eef6fc;
        border-left: 4px solid #377EB8;
        padding: 15px;
        margin: 20px 0;
        font-size: 0.95rem;
        line-height: 1.5;
      }
      .splash-footer {
        background-color: #f1f1f1;
        padding: 15px 35px;
        font-size: 0.85rem;
        border-top: 1px solid #ddd;
      }
      .btn-get-started {
        background-color: #233A57;
        color: white;
        font-family: 'Oswald', sans-serif;
        font-size: 1.1rem;
        padding: 10px 40px;
        border-radius: 30px;
        border: none;
        transition: all 0.3s;
        width: 100%;
      }
      .btn-get-started:hover {
        background-color: #e8572d; /* Orange hover */
        color: white;
        transform: scale(1.02);
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
      selected = character(0),
      options = list(`actions-box` = TRUE, `live-search` = TRUE),
      multiple = TRUE
    ),
    shinyWidgets::pickerInput(
      "land_use_group",
      "Step 2: Filter by Land Use (Optional)",
      choices = names(lu_mappings),
      selected = "All Land Uses",
      multiple = TRUE
    ),
    tags$div(
      class = "mb-2",
      tags$div(
        "Step 3: Customize Accessibility Factors & Priorities",
        class = "step-header"
      ),
      tags$p(
        HTML(
          "Please indicate your priority level for each of the following measures of accessibility.<br>Toggle layers using the icon on the right."
        ),
        style = "font-size: 0.9em; color: #6c757d; margin-top: 5px;"
      )
    ),
    bslib::accordion(
      open = FALSE,
      bslib::accordion_panel(
        "Places (Centers)",
        sliderWithLayer("w_CM", "Metropolitan Centers"),
        sliderWithLayer("w_CU", "Urban Centers"),
        sliderWithLayer("w_CC", "City Centers"),
        sliderWithLayer("w_CN", "Neighborhood Centers")
      ),
      bslib::accordion_panel(
        "Employment",
        sliderWithLayer("w_AA", "Auto Access to Jobs"),
        sliderWithLayer("w_AT", "Transit Access to Jobs")
      ),
      bslib::accordion_panel(
        "Transportation",
        sliderWithLayer("w_TT", "Transit Stops"),
        sliderWithLayer("w_TF", "Freeway Exits"),
        sliderWithLayer("w_TA", "Active Transportation")
      ),
      bslib::accordion_panel(
        "Necessities",
        sliderWithLayer("w_AC", "Childcare Centers"),
        sliderWithLayer("w_AH", "Healthcare Facilities"),
        sliderWithLayer("w_AE", "Education Institutions"),
        sliderWithLayer("w_AG", "Grocery Stores"),
        sliderWithLayer("w_AM", "Community Centers"),
        sliderWithLayer("w_AP", "10-min Walk to Parks")
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
        # 1. Main Header Container: Flex row, vertically centered
        class = "d-flex align-items-center w-100",

        # 2. Left Side (Title)
        # 'me-auto' pushes all subsequent items (the controls) to the far right
        shiny::span(
          "Housing Accessibility Map",
          class = "me-auto",
          style = "font-family: 'Oswald'; font-size: 1.5rem; color: #233A57;"
        ),

        # 3. Right Side (Controls Container)
        shiny::div(
          class = "d-flex align-items-center",
          style = "gap: 20px;", # Adds space between Z-Scale and 3D Switch

          # --- Z-Scale Input Group ---
          shiny::div(
            class = "d-flex align-items-center",
            style = "gap: 8px;",
            tags$label(
              "Z-SCALE:",
              `for` = "z_mult",
              class = "control-label m-0",
              style = "font-size: 1rem; font-weight: 700; color: #233A57; white-space: nowrap;"
            ),
            # Fixed width wrapper to prevent 'width: 100%' expansion
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

          # --- 3D Toggle ---
          shiny::div(
            style = "white-space: nowrap;",
            shinyWidgets::materialSwitch(
              "map_3d",
              "3D View",
              value = TRUE,
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
  # --- SPLASH SCREEN ---
  shiny::showModal(shiny::modalDialog(
    title = NULL,
    easyClose = FALSE,
    size = "l",
    footer = NULL,

    # Custom HTML Content
    shiny::div(
      # 1. Hero Header
      shiny::div(
        class = "splash-header",
        shiny::div(
          style = "margin-bottom: 15px;",
          shiny::img(src = "logo.png", style = "height: 60px; width: auto;")
        ),
        shiny::h2("Housing ATO Calculator")
      ),

      # 2. Body Content
      shiny::div(
        class = "splash-body",
        shiny::p(
          "The Housing Access to Opportunities (ATO) Calculator is designed to assist housing and land use planning efforts across the Wasatch Front.",
          style = "font-size: 1.1rem; text-align: center; margin-bottom: 20px;"
        ),

        # Three Pillars Icons
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

        # How it works box
        shiny::div(
          class = "instruction-box",
          shiny::icon("circle-info"),
          shiny::tags$strong(" How it works:"),
          shiny::br(),
          "1. Start by selecting your ",
          shiny::tags$strong("community"),
          " (one or more) from the sidebar.",
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

        # Get Started Button
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

      # 3. Footer / Attribution
      shiny::div(
        class = "splash-footer",
        shiny::fluidRow(
          shiny::column(
            6,
            shiny::tags$strong("Questions or Comments?"),
            shiny::br(),
            shiny::a(
              href = "mailto:analytics@wfrc.utah.gov",
              shiny::icon("envelope"),
              " WFRC Analytics Team (analytics@wfrc.utah.gov)",
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
    )
  ))

  # Close Modal Observer
  shiny::observeEvent(input$close_splash, {
    shiny::removeModal()
  })

  # --- MAIN APP LOGIC ---

  all_sliders <- names(layer_defs)

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

  target_bc_codes <- shiny::reactive({
    shiny::req(input$land_use_group)
    unique(unlist(lu_mappings[input$land_use_group]))
  })

  filtered_data <- shiny::reactive({
    shiny::req(input$comm_code, target_bc_codes())
    weights <- stats::setNames(
      sapply(all_sliders, function(x) input[[x]]),
      substring(all_sliders, 3)
    )
    total_weight <- sum(weights)

    df <- ds_h3 |>
      dplyr::filter(CommCode %in% !!input$comm_code) |>
      dplyr::filter(BC %in% !!target_bc_codes())
    if (input$oz_filter) {
      df <- df |> dplyr::filter(OZ == 1)
    }

    if (nrow(df) > 0) {
      cols <- names(weights)
      for (c in cols) {
        if (!c %in% names(df)) {
          df[[c]] <- 0
        }
        df[[c]][is.na(df[[c]])] <- 0
      }

      df_calc <- sf::st_drop_geometry(df)
      weighted_sum <- rowSums(
        df_calc[, cols, drop = FALSE] *
          weights[col(df_calc[, cols, drop = FALSE])]
      )
      df$score <- if (total_weight == 0) 0 else weighted_sum / total_weight
      df$bc_name <- bc_map[df$BC]
      df$bc_name[is.na(df$bc_name)] <- "Unknown"

      c_ac <- layer_defs$w_AC$color
      c_ah <- layer_defs$w_AH$color
      c_ae <- layer_defs$w_AE$color
      c_ag <- layer_defs$w_AG$color
      c_am <- layer_defs$w_AM$color
      c_ap <- layer_defs$w_AP$color
      c_tt <- layer_defs$w_TT$color
      c_tf <- layer_defs$w_TF$color
      c_ta <- layer_defs$w_TA$color
      MAX_H <- 40

      df$tooltip_html <- paste0(
        "<div style='font-family: sans-serif; padding: 12px; background: white; border-radius: 4px; box-shadow: 0 4px 15px rgba(0,0,0,0.2); min-width: 200px;'>",
        "<div style='margin-bottom:10px; border-bottom:1px solid #eee; padding-bottom:6px;'>",
        "<div style='font-weight:bold; font-size:16px; color:#233A57;'>Score: ",
        round(df$score, 2),
        "</div>",
        "<div style='font-size:12px; color:#666; margin-top:2px;'>Type: ",
        df$bc_name,
        "</div>",
        "</div>",
        "<div style='font-size:10px; font-weight:bold; color:#999; margin-bottom:4px;'>NECESSITIES</div>",
        "<div style='display: flex; gap: 6px; height: 55px; align-items: flex-end; justify-content: space-between; margin-bottom: 12px;'>",
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
        ";'><i class='fa-solid fa-building'></i></div></div>",
        "<div style='display:flex; flex-direction:column; align-items:center; width: 18px;'><div style='width:100%; border-radius:2px 2px 0 0; background:",
        c_ap,
        "; min-height: 1px; height:",
        round(df$AP * MAX_H),
        "px;'></div><div style='font-size:12px; margin-top:2px; color:",
        c_ap,
        ";'><i class='fa-solid fa-tree'></i></div></div>",
        "</div>",
        "<div style='font-size:10px; font-weight:bold; color:#999; margin-bottom:4px;'>TRANSPORTATION</div>",
        "<div style='display: flex; gap: 10px; height: 55px; align-items: flex-end; justify-content: flex-start;'>",
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
        "</div>",
        "</div>"
      )
    }
    return(df)
  })

  output$map <- mapgl::renderMaplibre({
    m <- mapgl::maplibre(
      style = mapgl::carto_style("positron"),
      center = c(-111.8910, 40.7608),
      zoom = 10,
      pitch = 45
    )
    for (lid in names(layer_defs)) {
      def <- layer_defs[[lid]]
      urls <- if (!is.null(def$urls)) def$urls else def$url
      for (i in seq_along(urls)) {
        q <- utils::URLencode(def$query)
        full_url <- paste0(
          urls[i],
          "/query?where=",
          q,
          "&outFields=*&f=geojson"
        )
        suffix <- if (length(urls) > 1) paste0("_", i) else ""
        m <- mapgl::add_source(
          m,
          id = paste0("src_", lid, suffix),
          type = "geojson",
          data = full_url
        )
      }
    }
    m
  })

  layer_states <- shiny::reactiveValues()
  for (lid in names(layer_defs)) {
    layer_states[[lid]] <- FALSE
  }

  lapply(names(layer_defs), function(lid) {
    shiny::observeEvent(input[[paste0("toggle_", lid)]], {
      layer_states[[lid]] <- !layer_states[[lid]]
      if (layer_states[[lid]]) {
        shinyjs::addClass(id = paste0("btn_", lid), class = "active")
      } else {
        shinyjs::removeClass(id = paste0("btn_", lid), class = "active")
      }

      proxy <- mapgl::maplibre_proxy("map")
      def <- layer_defs[[lid]]
      urls <- if (!is.null(def$urls)) def$urls else def$url

      for (i in seq_along(urls)) {
        suffix <- if (length(urls) > 1) paste0("_", i) else ""
        source_id <- paste0("src_", lid, suffix)
        layer_id <- paste0("lay_", lid, suffix)

        if (layer_states[[lid]]) {
          if (def$type == "polygon") {
            proxy |>
              mapgl::add_fill_layer(
                id = layer_id,
                source = source_id,
                fill_color = def$color,
                fill_opacity = 0.4
              ) |>
              mapgl::add_line_layer(
                id = paste0(layer_id, "_ol"),
                source = source_id,
                line_color = def$color,
                line_width = 1
              )
          } else if (def$type == "line") {
            proxy |>
              mapgl::add_line_layer(
                id = layer_id,
                source = source_id,
                line_color = def$color,
                line_width = 2
              )
          } else if (def$type == "point") {
            proxy |>
              mapgl::add_circle_layer(
                id = layer_id,
                source = source_id,
                circle_color = def$color,
                circle_radius = 5,
                circle_stroke_width = 1,
                circle_stroke_color = "#fff"
              )
          }
        } else {
          proxy |> mapgl::clear_layer(layer_id)
          if (def$type == "polygon") {
            proxy |> mapgl::clear_layer(paste0(layer_id, "_ol"))
          }
        }
      }
    })
  })

  shiny::observe({
    dat <- filtered_data()
    proxy <- mapgl::maplibre_proxy("map") |>
      mapgl::clear_layer("h3_layer_3d") |>
      mapgl::clear_layer("h3_layer_2d")

    if (nrow(dat) > 0) {
      if (input$map_3d) {
        # --- DYNAMIC EXTRUSION LOGIC ---
        extrusion_val <- if (is.numeric(input$z_mult)) {
          input$z_mult * 1000
        } else {
          2000
        }

        proxy |>
          mapgl::add_fill_extrusion_layer(
            "h3_layer_3d",
            dat,
            fill_extrusion_color = mapgl::interpolate(
              column = "score",
              values = c(0, 0.2, 0.4, 0.6, 0.8, 1),
              stops = RColorBrewer::brewer.pal(6, "YlGnBu")
            ),
            fill_extrusion_height = mapgl::interpolate(
              column = "score",
              values = c(0, 1),
              stops = c(0, extrusion_val)
            ),
            fill_extrusion_opacity = 0.9,
            tooltip = "tooltip_html"
          ) |>
          mapgl::fit_bounds(dat, animate = TRUE, pitch = 45)
      } else {
        proxy |>
          mapgl::add_fill_layer(
            "h3_layer_2d",
            dat,
            fill_color = mapgl::interpolate(
              column = "score",
              values = c(0, 0.2, 0.4, 0.6, 0.8, 1),
              stops = RColorBrewer::brewer.pal(6, "YlGnBu")
            ),
            fill_opacity = 0.8,
            tooltip = "tooltip_html"
          ) |>
          mapgl::fit_bounds(dat, animate = TRUE, pitch = 0)
      }
    }
  })
}

shiny::shinyApp(ui, server)
