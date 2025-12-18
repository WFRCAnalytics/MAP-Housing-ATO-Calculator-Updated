library(shiny)
library(bslib)
library(arrow)
library(geoarrow)
library(dplyr)
library(sf)
library(mapgl)
library(shinyWidgets)
library(RColorBrewer)

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

# 2. UI
ui <- page_navbar(
  title = div(
    style = "display: flex; align-items: center;", # Flex align for logo/text
    img(src = "logo.png", style = "height:35px; margin-right:10px;"),
    "Wasatch Front Housing ATO Calculator"
  ),
  theme = bs_theme(preset = "flatly"),

  header = tags$head(
    # 1. Google Fonts
    tags$link(
      rel = "stylesheet",
      href = "https://fonts.googleapis.com/css2?family=Oswald:wght@300;400;500;700&display=swap"
    ),

    # 2. Slider Skin
    chooseSliderSkin("Flat", color = "#2c3e50"),

    # 3. Custom CSS
    tags$style(HTML(
      "
      /* --- TYPOGRAPHY --- */
      body {
        font-family: Arial, 'Open Sans', sans-serif;
      }
      h1, h2, h3, h4, h5, .h1, .h2, .h3, .h4, .h5 {
        font-family: 'Oswald', sans-serif;
        font-weight: 700;
        color: #233A57;
        text-transform: uppercase;
      }

      /* --- NAVBAR STYLING --- */
      .navbar {
        background-color: #233A57 !important;
        /* ZERO padding, Min height removed to allow tight fit */
        padding: 7.5px 15px !important;
        min-height: 40px !important;
        height: auto !important;
      }

      /* Force the inner container to have no padding */
      .navbar > .container-fluid {
         padding-top: 7.5 !important;
         padding-bottom: 7.5 !important;
         min-height: 45px !important;
         display: flex;
         align-items: center;
      }

      /* Navbar Brand (Title/Logo Area) */
      .navbar-brand {
        font-family: 'Oswald', sans-serif;
        font-weight: 700;
        color: white !important;
        font-size: 1.5rem;
        text-transform: uppercase;
        /* Remove default bootstrap padding/margins */
        padding-top: 0px !important;
        padding-bottom: 0px !important;
        margin-right: 0 !important;
        display: flex;
        align-items: center;
        height: 40px; /* Explicit height matching min-height */
      }

      /* HIDE NAVBAR TABS (User Request) */
      .navbar-nav {
        display: none !important;
      }

      /* --- SIDEBAR & INPUTS --- */
      .control-label, .shiny-input-container label, .step-header {
        font-family: 'Oswald', sans-serif;
        font-weight: 500;
        color: #233A57;
        text-transform: uppercase;
        font-size: 1rem;
      }

      /* Accordion Headers */
      .accordion-button {
        font-family: 'Oswald', sans-serif;
        font-weight: 500;
        color: #5a87c6;
        text-transform: uppercase;
        font-size: 0.9rem !important;
      }

      /* Slider Labels inside Accordion */
      .accordion-body .control-label {
        font-size: 0.85rem !important;
        color: #444;
      }

      /* --- ALIGNMENT FIXES --- */
      .card-header .form-group {
        margin-bottom: 0 !important;
        margin-top: 0 !important;
      }

      /* Button Styling */
      .btn-outline-secondary, .btn-outline-primary {
        font-family: 'Oswald', sans-serif;
        text-transform: uppercase;
        font-weight: 600;
      }

      /* Tooltip */
      .maplibregl-popup-content {
        padding: 0 !important;
        border-radius: 4px;
        overflow: hidden;
      }

      .shiny-input-container {
        width: 100% !important;
      }
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

    pickerInput(
      "land_use_group",
      "Step 2: Filter by Land Use (Optional)",
      choices = names(lu_mappings),
      selected = "All Land Uses",
      multiple = FALSE
    ),

    tags$div(
      class = "mb-2",
      tags$div(
        "Step 3: Customize Accessibility Factors & Priorities",
        class = "step-header"
      ),
      tags$p(
        "Please indicate your priority level for each of the following measures of accessibility.",
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
        sliderInput("w_CM", "Metropolitan Centers", 0, 1, 0.5, step = 0.1),
        sliderInput("w_CU", "Urban Centers", 0, 1, 0.5, step = 0.1),
        sliderInput("w_CC", "City Centers", 0, 1, 0.5, step = 0.1),
        sliderInput("w_CN", "Neighborhood Centers", 0, 1, 0.5, step = 0.1)
      ),

      accordion_panel(
        "Employment",
        sliderInput("w_AA", "Auto Access to Jobs", 0, 1, 0.5, step = 0.1),
        sliderInput("w_AT", "Transit Access to Jobs", 0, 1, 0.5, step = 0.1)
      ),

      accordion_panel(
        "Transportation",
        sliderInput("w_TT", "Transit Stops", 0, 1, 0.5, step = 0.1),
        sliderInput("w_TF", "Freeway Exits", 0, 1, 0.5, step = 0.1),
        sliderInput("w_TA", "Active Transportation", 0, 1, 0.5, step = 0.1)
      ),

      accordion_panel(
        "Necessities",
        sliderInput("w_AC", "Childcare Centers", 0, 1, 0.5, step = 0.1),
        sliderInput("w_AH", "Healthcare Facilities", 0, 1, 0.5, step = 0.1),
        sliderInput("w_AE", "Education Institutions", 0, 1, 0.5, step = 0.1),
        sliderInput("w_AG", "Grocery Stores", 0, 1, 0.5, step = 0.1),
        sliderInput("w_AM", "Community Centers", 0, 1, 0.5, step = 0.1),
        sliderInput("w_AP", "10-min Walk to Parks", 0, 1, 0.5, step = 0.1)
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
          style = "font-family: 'Oswald', sans-serif; font-size: 1.5rem; color: #233A57;"
        ),
        div(
          materialSwitch(
            "map_3d",
            "3D View",
            value = TRUE,
            status = "primary",
            inline = TRUE
          )
        )
      ),
      maplibreOutput("map", height = "100%")
    )
  )
)

# 3. Server Logic
server <- function(input, output, session) {
  all_sliders <- c(
    "w_CM",
    "w_CU",
    "w_CC",
    "w_CN",
    "w_AA",
    "w_AT",
    "w_TT",
    "w_TF",
    "w_TA",
    "w_AC",
    "w_AH",
    "w_AE",
    "w_AG",
    "w_AM",
    "w_AP"
  )

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

    weights <- c(
      CM = input$w_CM,
      CU = input$w_CU,
      CC = input$w_CC,
      CN = input$w_CN,
      AA = input$w_AA,
      AT = input$w_AT,
      TT = input$w_TT,
      TF = input$w_TF,
      TA = input$w_TA,
      AC = input$w_AC,
      AH = input$w_AH,
      AE = input$w_AE,
      AG = input$w_AG,
      AM = input$w_AM,
      AP = input$w_AP
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
        if (!c %in% names(df)) df[[c]] <- 0
      }

      weighted_sum <-
        (df$CM * weights["CM"]) +
        (df$CU * weights["CU"]) +
        (df$CC * weights["CC"]) +
        (df$CN * weights["CN"]) +
        (df$AA * weights["AA"]) +
        (df$AT * weights["AT"]) +
        (df$TT * weights["TT"]) +
        (df$TF * weights["TF"]) +
        (df$TA * weights["TA"]) +
        (df$AC * weights["AC"]) +
        (df$AH * weights["AH"]) +
        (df$AE * weights["AE"]) +
        (df$AG * weights["AG"]) +
        (df$AM * weights["AM"]) +
        (df$AP * weights["AP"])

      if (total_weight == 0) {
        df$score <- 0
      } else {
        df$score <- weighted_sum / total_weight
      }

      # --- CREATE TOOLTIP HTML ---
      c_ac <- "#E41A1C"
      c_ah <- "#377EB8"
      c_ae <- "#4DAF4A"
      c_ag <- "#984EA3"
      c_am <- "#FF7F00"
      c_ap <- "#A65628"

      df$tooltip_html <- paste0(
        "<div style='font-family: sans-serif; padding: 10px; background: white; border-radius: 4px; box-shadow: 0 2px 10px rgba(0,0,0,0.2);'>",
        "<div style='margin-bottom:8px; font-weight:bold; font-size:14px; border-bottom:1px solid #eee; padding-bottom:4px; color:#333;'>",
        "Score: ",
        round(df$score, 2),
        "</div>",
        "<div style='display: flex; gap: 6px; height: 60px; align-items: flex-end; justify-content: space-between;'>",
        "<div style='display:flex; flex-direction:column; align-items:center; width: 15px;'>",
        "<div style='width:100%; border-radius:2px 2px 0 0; background:",
        c_ac,
        "; height:",
        round(df$AC * 100),
        "%;'></div>",
        "<div style='font-size:14px; line-height:1; margin-top:2px;'>🧸</div>",
        "</div>",
        "<div style='display:flex; flex-direction:column; align-items:center; width: 15px;'>",
        "<div style='width:100%; border-radius:2px 2px 0 0; background:",
        c_ah,
        "; height:",
        round(df$AH * 100),
        "%;'></div>",
        "<div style='font-size:14px; line-height:1; margin-top:2px;'>🏥</div>",
        "</div>",
        "<div style='display:flex; flex-direction:column; align-items:center; width: 15px;'>",
        "<div style='width:100%; border-radius:2px 2px 0 0; background:",
        c_ae,
        "; height:",
        round(df$AE * 100),
        "%;'></div>",
        "<div style='font-size:14px; line-height:1; margin-top:2px;'>🎓</div>",
        "</div>",
        "<div style='display:flex; flex-direction:column; align-items:center; width: 15px;'>",
        "<div style='width:100%; border-radius:2px 2px 0 0; background:",
        c_ag,
        "; height:",
        round(df$AG * 100),
        "%;'></div>",
        "<div style='font-size:14px; line-height:1; margin-top:2px;'>🛒</div>",
        "</div>",
        "<div style='display:flex; flex-direction:column; align-items:center; width: 15px;'>",
        "<div style='width:100%; border-radius:2px 2px 0 0; background:",
        c_am,
        "; height:",
        round(df$AM * 100),
        "%;'></div>",
        "<div style='font-size:14px; line-height:1; margin-top:2px;'>🏛️</div>",
        "</div>",
        "<div style='display:flex; flex-direction:column; align-items:center; width: 15px;'>",
        "<div style='width:100%; border-radius:2px 2px 0 0; background:",
        c_ap,
        "; height:",
        round(df$AP * 100),
        "%;'></div>",
        "<div style='font-size:14px; line-height:1; margin-top:2px;'>🌳</div>",
        "</div>",
        "</div>",
        "</div>"
      )
    }

    return(df)
  })

  output$map <- renderMaplibre({
    maplibre(
      style = carto_style("voyager"),
      center = c(-111.8910, 40.7608),
      zoom = 10,
      pitch = 0
    )
  })

  observe({
    dat <- filtered_data()

    proxy <- maplibre_proxy("map") |>
      clear_layer("h3_layer_3d") |>
      clear_layer("h3_layer_2d")

    if (nrow(dat) > 0) {
      if (input$map_3d) {
        proxy |>
          add_fill_extrusion_layer(
            id = "h3_layer_3d",
            source = dat,
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
            id = "h3_layer_2d",
            source = dat,
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
