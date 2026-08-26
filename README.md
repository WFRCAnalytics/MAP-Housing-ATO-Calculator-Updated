# MAP Housing ATO Calculator (Updated)

Scores every parcel and H3 hexagon in the Wasatch Front / MAG region on **access to opportunity** — jobs, transit, and everyday necessities — to support housing and land-use planning. Powers the interactive map at https://wfrc.utah.gov/housing-ato-calculator-map/.

This is a complete rebuild of the original [MAP-Housing-ATO-Calculator](https://github.com/WFRCAnalytics/MAP-Housing-ATO-Calculator/). The backend now runs on R, DuckDB, and GeoParquet instead of loading millions of geometries into R memory, so the scoring pipeline is faster, cleaner, and easier to maintain.

## Accessibility Factors

Eleven factors, grouped into three categories, each scored 0–1 per parcel/hexagon. Users weight these interactively in the two apps described in [Interactive apps](#interactive-apps) below.

| Group | Factor | What it measures |
|---|---|---|
| Employment | **Auto Access to Jobs** (`AA`) | Jobs reachable by car (TAZ-level job counts, [Access to Opportunities](https://services1.arcgis.com/taguadKoI1XFwivx/ArcGIS/rest/services/AccessToOpportunities_gdb/FeatureServer/0)) |
| Employment | **Transit Access to Jobs** (`AT`) | Jobs reachable by public transit (same TAZ source) |
| Transportation | **Transit Stops** (`TT`) | Proximity to UTA bus stops, TRAX, and FrontRunner (composite of local/rapid/commuter rail) |
| Transportation | **Freeway Exits** (`TF`) | Drive-time proximity to freeway on/off-ramps |
| Transportation | **Active Transportation** (`TA`) | Proximity to separated/buffered bike lanes and multi-use trails (composite) |
| Necessities | **Childcare Centers** (`AC`) | Proximity to licensed childcare facilities |
| Necessities | **Healthcare Facilities** (`AH`) | Proximity to hospitals, clinics, and medical facilities |
| Necessities | **Education Institutions** (`AE`) | Proximity to K-12 and higher-ed (composite) |
| Necessities | **Grocery Stores** (`AG`) | Proximity to supermarkets and grocery stores |
| Necessities | **Community Centers** (`AM`) | Proximity to community halls, recreation centers, libraries |
| Necessities | **Public Parks** (`AP`) | Proximity to public parks and open space |

The apps also display four **Wasatch Choice Center** overlays (`CM`/`CU`/`CC`/`CN` — Metropolitan/Urban/City/Neighborhood centers) and an **Opportunity Zone** overlay (`OZ`). These are reference/context layers only — they are not part of the weighted score.

## Methodology

The pipeline runs as four sequential Quarto steps (`1-prepare-data-layers.qmd` → `4-ato-scoring.qmd`), summarized here; see [Running the pipeline](#running-the-pipeline) for execution details.

### Isochrones and buffers

Each proximity factor is computed one of two ways:

- **Isochrones** (`TT_*`, `TF`, `AC`, `AH`, `AG`, `AM`, `AE_*`, `AP`) — [OpenRouteService](https://github.com/GIScience/openrouteservice) generates travel-time polygons per amenity at **5, 10, 15, 30, and ~60 minutes** (`range = c(300, 600, 900, 1800, 3599)` seconds), using whichever travel profile fits the amenity (walking for most daily-needs amenities, cycling for commuter-rail and higher-ed access, driving for healthcare and freeway exits — trip types where the underlying isochrones are inherently longer/faster-mode journeys). A parcel/hexagon is assigned the smallest time band whose polygon contains it.
- **Buffers** (`TA_class1`, `TA_class2`, `TA_trails`) — straight-line distance bands at **0.25, 0.5, 0.75, 1.5, and 3.0 miles** from WFRC's Bikeways layer, split by facility class (1A/1B = separated/protected, 2A/2B/2C = buffered/striped, trails = shared-use paths). A parcel/hexagon is assigned the smallest distance band it falls within.

Both are computed via `ST_Intersects`/`ST_DWithin` in DuckDB, iterating bands smallest-first and only updating rows that haven't already matched a closer band.

### The canvas: parcels and H3 grid

Two target geometries carry every score: **REMM parcels** (WFRC's Real Estate Market Model, parcel-level) and an **H3 hexagon grid at resolution 10** covering the region, built from the WFRC/MAG regional boundary. Each parcel is represented by an interior point (`ST_PointOnSurface`, not centroid — this keeps the sample point inside U-shaped or non-convex parcels) for the spatial joins; H3 cells use the true polygon.

### Building code / land use assignment

Each parcel/hexagon is tagged with a **building code** (`BC` — e.g. `SF` single-family, `MF` multi-family, `RE` retail, `IN` industrial, `OS` open space; see [Output columns](#output-columns) for the full list) via a four-pass hybrid approach, since neither building points nor parcel polygons alone cover every case cleanly:

1. **Aggregation** — join REMM buildings to parcels/hexes by spatial index, prioritizing the largest building by square footage where multiple buildings share a cell (handles mixed-use and multi-building parcels).
2. **Spatial backfill** — for cells still missing a code (typically large parcels where the H3 cell center falls far from any building centroid), sample the parcel polygon directly at the H3 cell center.
3. **Spatial voting (KNN)** — for cells still empty, check the 6 immediate H3 neighbors; if 4+ have a value, treat the gap as a data glitch and fill it from the neighborhood majority. Fewer than 4 is treated as a genuine edge (e.g. coastline) and left alone.
4. **Catch-all** — anything still null is forced to `OT` (Other) rather than left as a silent gap.

### Job access (`AA`, `AT`)

Auto and transit job-access counts are attached directly from WFRC's TAZ-level [Access to Opportunities](https://services1.arcgis.com/taguadKoI1XFwivx/ArcGIS/rest/services/AccessToOpportunities_gdb/FeatureServer/0) layer via point-in-polygon join — no isochrone needed, since the source data is already a travel-time-weighted job count per TAZ.

### Normalization

Every raw metric is normalized to 0–1 using one of two rules, chosen by column prefix:

```
Cost metrics    (TT_, TF, TA_, AC, AH, AG, AM, AE_, AP) → Min(value > 0) / value   — closer is better
Benefit metrics (AA, AT)                                → value / Max(value)       — more is better
```

Cost metrics are travel time/distance — a parcel at or below the regional minimum scores 1.0; farther parcels decay toward 0. Benefit metrics are job counts — the regional maximum scores 1.0. `NULL` (never reached within any isochrone/buffer band) scores 0 for cost metrics.

### Composite scores

Three factors are built from multiple sub-layers, combined as a **weighted max** (the best-served sub-layer dominates, rather than averaging them down):

```
TT = max(TT_Local × 0.5, TT_Rapid × 0.8, TT_CRT × 1.0)
AE = max(AE_K12 × 0.8, AE_High × 1.0)
TA = max(TA_class2 × 0.5, TA_class1 × 1.0, TA_trails × 1.0)
```

(All sub-layer values are already normalized 0–1 before the weights are applied.)

## Configuration

The key tunable values live in `2-process-layers.qmd` (isochrone/buffer bands, H3 resolution) and `4-ato-scoring.qmd` (cost/benefit column-prefix regex, composite weights):

```r
H3_RES <- 10                                  # H3 grid resolution
range  <- c(300, 600, 900, 1800, 3599)        # Isochrone bands, seconds (5/10/15/30/~60 min)
TA_buffer_opts <- c(0.25, 0.5, 0.75, 1.5, 3.0) # Bikeway buffer bands, miles

is_cost <- "^(TT_|AC|AH|AG|AM|AE_|TA_|TF|AP)"  # Column-prefix regex → cost (inverse) normalization
```

## Data sources

Most layers are ArcGIS Feature Services, fetched and cached as GeoParquet in `_data/processed/`; a couple are local files dropped into `_data/raw/` (noted below).

| Source | Used for |
|---|---|
| [Utah Municipal Boundaries](https://services1.arcgis.com/99lidPhWCzftIe9K/ArcGIS/rest/services/UtahMunicipalBoundaries/FeatureServer/0) | City selector, `CommCode` assignment |
| [Utah County Boundaries](https://services1.arcgis.com/99lidPhWCzftIe9K/ArcGIS/rest/services/UtahCountyBoundaries/FeatureServer/0) | County FIPS assignment |
| [Regional Boundary Components (WFRC/MAG)](https://services1.arcgis.com/taguadKoI1XFwivx/ArcGIS/rest/services/RegionalBoundaryComponents/FeatureServer/0) | Study-area extent, H3 grid generation |
| REMM Parcels & Buildings | Parcel target canvas, building codes (local GDB — see [Setup](#setup)) |
| Wasatch Front & Utah Statewide TAZs | Job access source geography |
| [Access to Opportunities](https://services1.arcgis.com/taguadKoI1XFwivx/ArcGIS/rest/services/AccessToOpportunities_gdb/FeatureServer/0) | `AA` / `AT` job access counts |
| [Wasatch Choice Vision Centers](https://services1.arcgis.com/taguadKoI1XFwivx/arcgis/rest/services/WCV_Centers_and_Regional_Land_Uses/FeatureServer/0) | `CM`/`CU`/`CC`/`CN` center overlays |
| [Utah Qualified Opportunity Zones](https://services1.arcgis.com/taguadKoI1XFwivx/arcgis/rest/services/Utah_Qualified_Opportunity_Zones/FeatureServer/0) | `OZ` overlay |
| [UTA Routes](https://maps.rideuta.com/server/rest/services/Hosted/UTA_Routes_and_Most_Recent_Ridership/FeatureServer/0) / [UTA Stops](https://maps.rideuta.com/server/rest/services/Hosted/UTA_Stops_and_Most_Recent_Ridership/FeatureServer/0) | `TT_*` transit isochrones |
| [Bikeways](https://services1.arcgis.com/99lidPhWCzftIe9K/ArcGIS/rest/services/Bikeways/FeatureServer/0) | `TA_*` buffer bands |
| [Freeway Exit Locations](https://services.arcgis.com/pA2nEVnB6tquxgOW/arcgis/rest/services/Freeway_Exit_Locations/FeatureServer/0) | `TF` isochrone |
| [Schools PreK-12](https://services1.arcgis.com/99lidPhWCzftIe9K/ArcGIS/rest/services/Schools_PreKto12/FeatureServer/0) / [Higher Education](https://services1.arcgis.com/99lidPhWCzftIe9K/ArcGIS/rest/services/Schools_HigherEducation/FeatureServer/0) | `AE_K12` / `AE_High` isochrones |
| [Licensed Health Care Facilities](https://services1.arcgis.com/99lidPhWCzftIe9K/ArcGIS/rest/services/LicensedHealthCareFacilities/FeatureServer/0) | `AH` isochrone |
| HIFLD Open Child Care Centers (local file, filtered to `STATE = 'UT'`) | `AC` isochrone |
| [Utah Grocery and Food Stores](https://services1.arcgis.com/taguadKoI1XFwivx/ArcGIS/rest/services/UtahGroceryAndFoodStores_DAF/FeatureServer/0) | `AG` isochrone |
| [Community Centers](https://services1.arcgis.com/taguadKoI1XFwivx/ArcGIS/rest/services/Residential_Accessibility_WFL1/FeatureServer/412) ⚠️ placeholder, flagged in code to be replaced with a UGRC source | `AM` isochrone |
| [Access to Parks](https://services1.arcgis.com/taguadKoI1XFwivx/ArcGIS/rest/services/AccessToParks_082024_gdb/FeatureServer/0) | `AP` graded park-access layer |

## Interactive apps

Two apps consume the scored output from `_output/`/`_app/data/` — pick whichever stack you're working in. Both read the same `h3_scored` GeoParquet the pipeline produces and let a user weight the eleven factors above interactively to generate a custom suitability heat map.

| | Shiny app (`_app/`) | Vite app (`vite-app/`) |
|---|---|---|
| Stack | R, `shiny`, `bslib`, `mapgl` | Vue 3, MapLibre GL, DuckDB-WASM |
| Run locally | `shiny::runApp("_app")` | `cd vite-app && npm install && npm run dev` |
| Deployed at | [shinyapps.io](https://www.shinyapps.io/) (`housing-site-evaluator`) | GitHub Pages / WFRC FTP (see `.github/workflows/deploy.yml`) |

## Getting Started

### Prerequisites

- **R** (`4.5.2` or higher, latest version recommended)
- **Packages:** see `renv.lock` for exact versions this pipeline was built against.
- **OpenRouteService:** a local ORS Docker instance (recommended for speed) or a valid API key — see <https://github.com/GIScience/openrouteservice>.
- **Node.js** (only if you're working on `vite-app/`).

### Setup

```r
install.packages("pak") # https://github.com/r-lib/pak
pak::pak("renv", dependencies = TRUE)
renv::restore()
```

Drop the REMM parcels/buildings GDB into `_data/raw/` (not tracked by git — see `.gitignore`).

### Configuration

Create `_environment` with your API key if you aren't running a local ORS instance:

```
ORS_API_KEY=your_key_here
```

## Running the pipeline

Run the four Quarto steps in order — each writes standardized GeoParquet that the next step reads:

1. **`1-prepare-data-layers.qmd`** — downloads ArcGIS Feature Layers and processes local shapefiles/GDBs (Parcels, TAZs) into `_data/processed/`.
2. **`2-process-layers.qmd`** — calls ORS to generate isochrones, builds bikeway buffers, generates the H3 grid.
3. **`3-spatial-operations.qmd`** — builds the parcel/H3 canvas, assigns building codes and job access, spatially joins every isochrone/buffer to produce raw metric columns.
4. **`4-ato-scoring.qmd`** — normalizes raw metrics to 0–1 scores (see [Normalization](#normalization)), exports final Parquet + a zipped File Geodatabase, and syncs scored data into both apps' `data/` directories.

> Run chunks manually inside Positron/RStudio rather than via `Rscript` — some dependencies (`geoarrow`, `renv`) only resolve correctly inside the IDE's R session.

## Project Structure

```
_src/                 # Helper R functions (isochrone generation, previewers)
_data/
  raw/                 # Manual inputs (REMM GDB) — not tracked by git
  processed/           # Cleaned GeoParquets from step 1
  isochrones/          # ORS output from step 2
_output/               # Final scored Parquet + zipped GDB from step 4
_app/                  # Shiny web app (see Interactive apps)
vite-app/              # Vite/Vue web app (see Interactive apps)
1-4-*.qmd              # The four pipeline steps
index.qmd              # Quarto analytics/documentation site (_site/, not the interactive apps)
```

## Output columns

`h3_scored`/`parcels_scored` contain, per row:

| Column(s) | Description |
|---|---|
| `AA`, `AT`, `TT`, `TF`, `TA`, `AC`, `AH`, `AE`, `AG`, `AM`, `AP` | The 11 normalized (0–1) accessibility factors — see [Accessibility Factors](#accessibility-factors) |
| `TT_Local`, `TT_Rapid`, `TT_CRT` | `TT` sub-components (before compositing) |
| `AE_K12`, `AE_High` | `AE` sub-components (before compositing) |
| `TA_class1`, `TA_class2`, `TA_trails` | `TA` sub-components (before compositing) |
| `OZ`, `CM`, `CU`, `CC`, `CN` | Binary reference overlays (Opportunity Zone; Metro/Urban/City/Neighborhood centers) — not part of the score |
| `BC` | Building code / land use (`SF`, `MF`, `RE`, `IN`, `OS`, `OT`, …) |
| `CommCode` | Municipality code (partition key for app data) |
| `COUNTYNBR` | County FIPS |
| `h3_index` / `parcel_id` | Row identifier (H3 cell string or parcel ID) |
| `geometry` | H3 hexagon or parcel polygon (WGS84) |

## Authors

Reach out to [Bill Hereth](https://github.com/bhereth) or [Pukar Bhandari](https://github.com/ar-puuk) at [Wasatch Front Regional Council](https://wfrc.utah.gov/) if you have any questions or suggestions.
