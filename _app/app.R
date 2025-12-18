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

# 1. Global Setup
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
    color = "#E41A1C"
  ),
  "w_CU" = list(
    url = "https://services1.arcgis.com/taguadKoI1XFwivx/arcgis/rest/services/WCV_Centers_and_Regional_Land_Uses/FeatureServer/1",
    query = "CenterType = 'Urban Center'",
    type = "polygon",
    color = "#377EB8"
  ),
  "w_CC" = list(
    url = "https://services1.arcgis.com/taguadKoI1XFwivx/arcgis/rest/services/WCV_Centers_and_Regional_Land_Uses/FeatureServer/2",
    query = "CenterType = 'City Center'",
    type = "polygon",
    color = "#4DAF4A"
  ),
  "w_CN" = list(
    url = "https://services1.arcgis.com/taguadKoI1XFwivx/arcgis/rest/services/WCV_Centers_and_Regional_Land_Uses/FeatureServer/3",
    query = "CenterType = 'Neighborhood Center'",
    type = "polygon",
    color = "#984EA3"
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

# --- HELPER: Slider with shinyjs Icon Toggle (NO Checkbox) ---
sliderWithLayer <- function(inputId, label) {
  tagList(
    div(
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
        icon("layer-group")
      )
    ),
    sliderInput(
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

# 2. UI
ui <- page_navbar(
  title = div(
    style = "display: flex; align-items: center;",
    img(src = "logo.png", style = "height:35px; margin-right:10px;"),
    "Wasatch Front Housing ATO Calculator"
  ),
  theme = bs_theme(preset = "flatly"),

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
    chooseSliderSkin("Flat", color = "#2c3e50"),
    tags$style(HTML(
      "
      /* TYPOGRAPHY */
      body { font-family: Arial, 'Open Sans', sans-serif; }
      h1, h2, h3, h4, h5 { font-family: 'Oswald', sans-serif; font-weight: 700; color: #233A57; text-transform: uppercase; }

      /* NAVBAR */
      .navbar { background-color: #233A57 !important; padding: 0px 15px !important; min-height: 40px !important; height: auto !important; }
      .navbar > .container-fluid { padding: 7.5px 0 !important; min-height: 45px !important; display: flex; align-items: center; }
      .navbar-brand { font-family: 'Oswald', sans-serif; font-weight: 700; color: white !important; font-size: 1.5rem; text-transform: uppercase; padding: 0 !important; margin: 0 !important; display: flex; align-items: center; height: 40px; }
      .navbar-nav { display: none !important; }

      /* CONTROLS */
      .control-label, .shiny-input-container label, .step-header {
        font-family: 'Oswald', sans-serif; font-weight: 500; color: #233A57; text-transform: uppercase; font-size: 1rem;
      }
      .accordion-button {
        font-family: 'Oswald', sans-serif; font-weight: 500; color: #5a87c6; text-transform: uppercase; font-size: 0.9rem !important;
      }
      .accordion-body .control-label {
        font-size: 0.85rem !important; color: #444;
      }
      .card-header .form-group { margin: 0 !important; }

      /* LAYER TOGGLE ICON */
      .layer-toggle-btn { color: #ccc; cursor: pointer; font-size: 1.1rem; transition: color 0.3s; margin-left: 8px; }
      .layer-toggle-btn:hover { color: #5a87c6; }
      .layer-toggle-btn.active { color: #2c3e50; }

      .maplibregl-popup-content { padding: 0 !important; border-radius: 4px; overflow: hidden; }
      .shiny-input-container { width: 100% !important; margin-bottom: 0px !important; }
      .form-group { margin-bottom: 5px !important; }
    "
    ))
  ),

  sidebar = sidebar(
    width = 350,
    title = NULL,
    pickerInput(
      "comm_code",
      "Step 1: Select Cities",
      choices = city_choices,
      selected = character(0),
      options = list(`actions-box` = TRUE, `live-search` = TRUE),
      multiple = TRUE
    ),
    hr(),
    pickerInput(
      "land_use_group",
      "Step 2: Filter by Land Use (Optional)",
      choices = names(lu_mappings),
      selected = "All Land Uses",
      multiple = TRUE
    ),
    hr(),
    tags$div(
      class = "mb-2",
      tags$div(
        "Step 3: Customize Accessibility Factors & Priorities",
        class = "step-header"
      ),
      tags$p(
        "Toggle layers using the icon on the right.",
        style = "font-size: 0.9em; color: #6c757d; margin-top: 5px;"
      )
    ),
    div(
      class = "d-flex gap-2 justify-content-between mb-2",
      actionButton(
        "reset_all",
        "Reset All (0)",
        icon = icon("ban"),
        class = "btn-outline-secondary w-50 btn-sm"
      ),
      actionButton(
        "max_all",
        "Max All (1)",
        icon = icon("check-double"),
        class = "btn-outline-primary w-50 btn-sm"
      )
    ),

    accordion(
      open = FALSE,
      accordion_panel(
        "Places (Centers)",
        sliderWithLayer("w_CM", "Metropolitan Centers"),
        sliderWithLayer("w_CU", "Urban Centers"),
        sliderWithLayer("w_CC", "City Centers"),
        sliderWithLayer("w_CN", "Neighborhood Centers")
      ),
      accordion_panel(
        "Employment",
        sliderWithLayer("w_AA", "Auto Access to Jobs"),
        sliderWithLayer("w_AT", "Transit Access to Jobs")
      ),
      accordion_panel(
        "Transportation",
        sliderWithLayer("w_TT", "Transit Stops"),
        sliderWithLayer("w_TF", "Freeway Exits"),
        sliderWithLayer("w_TA", "Active Transportation")
      ),
      accordion_panel(
        "Necessities",
        sliderWithLayer("w_AC", "Childcare Centers"),
        sliderWithLayer("w_AH", "Healthcare Facilities"),
        sliderWithLayer("w_AE", "Education Institutions"),
        sliderWithLayer("w_AG", "Grocery Stores"),
        sliderWithLayer("w_AM", "Community Centers"),
        sliderWithLayer("w_AP", "10-min Walk to Parks")
      )
    ),
    hr(),
    materialSwitch(
      "oz_filter",
      "Limit to Opportunity Zones (OZ)",
      value = FALSE,
      status = "primary"
    )
  ),

  nav_panel(
    "",
    card(
      full_screen = TRUE,
      card_header(
        class = "d-flex justify-content-between align-items-center w-100",
        span(
          "Housing Suitability Map",
          style = "font-family: 'Oswald'; font-size: 1.5rem; color: #233A57;"
        ),
        div(materialSwitch(
          "map_3d",
          "3D View",
          value = TRUE,
          status = "primary",
          inline = TRUE
        ))
      ),
      maplibreOutput("map", height = "100%")
    )
  )
)

# 3. Server Logic
server <- function(input, output, session) {
  all_sliders <- names(layer_defs)

  observeEvent(input$reset_all, {
    for (id in all_sliders) {
      updateSliderInput(session, id, value = 0)
    }
  })
  observeEvent(input$max_all, {
    for (id in all_sliders) {
      updateSliderInput(session, id, value = 1)
    }
  })

  target_bc_codes <- reactive({
    req(input$land_use_group)
    unique(unlist(lu_mappings[input$land_use_group]))
  })

  filtered_data <- reactive({
    req(input$comm_code, target_bc_codes())
    weights <- setNames(
      sapply(all_sliders, function(x) input[[x]]),
      substring(all_sliders, 3)
    )
    total_weight <- sum(weights)

    df <- ds_h3 |>
      filter(CommCode %in% !!input$comm_code) |>
      filter(BC %in% !!target_bc_codes())
    if (input$oz_filter) {
      df <- df |> filter(OZ == 1)
    }

    if (nrow(df) > 0) {
      cols <- names(weights)
      for (c in cols) {
        if (!c %in% names(df)) {
          df[[c]] <- 0
        }
        df[[c]][is.na(df[[c]])] <- 0
      }

      # FIX 1: Drop geometry only for calculation to prevent rowSums error
      df_calc <- sf::st_drop_geometry(df)
      weighted_sum <- rowSums(
        df_calc[, cols, drop = FALSE] *
          weights[col(df_calc[, cols, drop = FALSE])]
      )

      df$score <- if (total_weight == 0) 0 else weighted_sum / total_weight

      df$bc_name <- bc_map[df$BC]
      df$bc_name[is.na(df$bc_name)] <- "Unknown"

      # Tooltip
      c_ac <- "#E41A1C"
      c_ah <- "#377EB8"
      c_ae <- "#4DAF4A"
      c_ag <- "#984EA3"
      c_am <- "#FF7F00"
      c_ap <- "#A65628"
      c_tt <- "#666666"
      c_tf <- "#000000"
      c_ta <- "#2ca25f"
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

  # Initialize Map - Add all sources upfront
  output$map <- renderMaplibre({
    m <- maplibre(
      style = carto_style("dark-matter"),
      center = c(-111.8910, 40.7608),
      zoom = 10,
      pitch = 45
    )

    # Pre-load Sources
    for (lid in names(layer_defs)) {
      def <- layer_defs[[lid]]
      urls <- if (!is.null(def$urls)) def$urls else def$url

      for (i in seq_along(urls)) {
        q <- URLencode(def$query)
        full_url <- paste0(
          urls[i],
          "/query?where=",
          q,
          "&outFields=*&f=geojson"
        )
        suffix <- if (length(urls) > 1) paste0("_", i) else ""
        source_id <- paste0("src_", lid, suffix)

        m <- add_source(m, id = source_id, type = "geojson", data = full_url)
      }
    }
    m
  })

  # --- DYNAMIC LAYER TOGGLE ---
  layer_states <- reactiveValues()
  for (lid in names(layer_defs)) {
    layer_states[[lid]] <- FALSE
  }

  lapply(names(layer_defs), function(lid) {
    observeEvent(input[[paste0("toggle_", lid)]], {
      layer_states[[lid]] <- !layer_states[[lid]]

      if (layer_states[[lid]]) {
        shinyjs::addClass(id = paste0("btn_", lid), class = "active")
      } else {
        shinyjs::removeClass(id = paste0("btn_", lid), class = "active")
      }

      proxy <- maplibre_proxy("map")
      def <- layer_defs[[lid]]
      urls <- if (!is.null(def$urls)) def$urls else def$url

      for (i in seq_along(urls)) {
        suffix <- if (length(urls) > 1) paste0("_", i) else ""
        source_id <- paste0("src_", lid, suffix)
        layer_id <- paste0("lay_", lid, suffix)

        if (layer_states[[lid]]) {
          # ADD LAYER (pointing to pre-loaded source)
          if (def$type == "polygon") {
            proxy |>
              add_fill_layer(
                id = layer_id,
                source = source_id,
                fill_color = def$color,
                fill_opacity = 0.4
              ) |>
              add_line_layer(
                id = paste0(layer_id, "_ol"),
                source = source_id,
                line_color = def$color,
                line_width = 1
              )
          } else if (def$type == "line") {
            proxy |>
              add_line_layer(
                id = layer_id,
                source = source_id,
                line_color = def$color,
                line_width = 2
              )
          } else if (def$type == "point") {
            proxy |>
              add_circle_layer(
                id = layer_id,
                source = source_id,
                circle_color = def$color,
                circle_radius = 4,
                circle_stroke_width = 1,
                circle_stroke_color = "#fff"
              )
          }
        } else {
          # REMOVE LAYER
          proxy |> clear_layer(layer_id)
          if (def$type == "polygon") {
            proxy |> clear_layer(paste0(layer_id, "_ol"))
          }
        }
      }
    })
  })

  observe({
    dat <- filtered_data()
    proxy <- maplibre_proxy("map") |>
      clear_layer("h3_layer_3d") |>
      clear_layer("h3_layer_2d")

    if (nrow(dat) > 0) {
      if (input$map_3d) {
        # FIX 2: Use NAMED arguments for interpolate
        proxy |>
          add_fill_extrusion_layer(
            "h3_layer_3d",
            dat,
            fill_extrusion_color = interpolate(
              column = "score",
              values = c(0, 0.2, 0.4, 0.6, 0.8, 1),
              stops = RColorBrewer::brewer.pal(6, "YlGnBu")
            ),
            fill_extrusion_height = interpolate(
              column = "score",
              values = c(0, 1),
              stops = c(0, 2000)
            ),
            fill_extrusion_opacity = 0.9,
            tooltip = "tooltip_html"
          ) |>
          fit_bounds(dat, animate = TRUE, pitch = 45)
      } else {
        proxy |>
          add_fill_layer(
            "h3_layer_2d",
            dat,
            fill_color = interpolate(
              column = "score",
              values = c(0, 0.2, 0.4, 0.6, 0.8, 1),
              stops = RColorBrewer::brewer.pal(6, "YlGnBu")
            ),
            fill_opacity = 0.8,
            tooltip = "tooltip_html"
          ) |>
          fit_bounds(dat, animate = TRUE, pitch = 0)
      }
    }
  })
}

shinyApp(ui, server)
