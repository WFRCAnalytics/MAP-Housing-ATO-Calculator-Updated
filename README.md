# MAP Housing ATO Calculator (Updated)

This repository contains the code to generate data for the https://wfrc.utah.gov/housing-ato-calculator-map/.

It is a complete rebuild of the original [MAP-Housing-ATO-Calculator](https://github.com/WFRCAnalytics/MAP-Housing-ATO-Calculator/). We switched the backend to R, DuckDB, and GeoParquet to handle the heavy spatial lifting more efficiently. The goal was to make the scoring pipeline faster, cleaner, and easier to maintain.

The web application itself can be found in the `_site` folder.

## 🏗️ How it Works

The analysis is split into four sequential Quarto steps. You should run them in order:

### Gather the Data: `1-prepare-data-layers.qmd`

This script grabs all the raw inputs. It downloads Feature Layers from ArcGIS Online (Boundaries, Transit, Amenities) and processes local shapefiles/GDBs (Parcels, TAZs).

-   **Key Output:** Standardized GeoParquet files in `_data/processed/`.

### Process and Prepare the Layers: `2-process-layers.qmd`

Here we prepare the spatial inputs for analysis.

-   **Isochrones:** Calls the OpenRouteService (ORS) API to generate walk/bike/drive isochrones for every amenity (Grocery, Healthcare, Transit, etc.).
-   **Buffers:** Generates distance buffers for active transportation layers.
-   **H3 Grid:** Generates the H3 hexagonal grid for the analysis area.

### Conduct Spatial Operations: `3-spatial-operations.qmd`

This is where the heavy lifting happens. We use DuckDB to perform high-performance spatial joins without loading millions of geometries into R memory.

-   **The Canvas:** We prepare two main targets: Parcels and H3 Cells.
-   **Static Attributes:** Use spatial aggregation to assign centers, building-code, community_code, and county-fips to target canvas.
-   **Amenity Calculation:** Spatially joins the isochrones and buffers to the targets to calculate "Time to X" or "Distance to Y".

### Normalize the Scores: `4-ato-scoring.qmd`

The final step normalizes the raw values into 0-1 scores.

-   **Cost Metrics (e.g., Distance):** Uses Inverse Normalization (`Min / Value`). Closer is better.
-   **Benefit Metrics (e.g., Jobs):** Uses Linear Normalization (`Value / Max`). More is better.
-   **Final Export:** Produces the final Parquet files and a zipped File Geodatabase (`.gdb`) for the web map.

## 🚀 Getting Started

### Prerequisites

-   **R** (`4.5.2` or Higher, latest version recommended)
-   **Packages:** Check `renv.lock` file for package dependencies and the package versions this analysis was conducted on.
-   **OpenRouteService:** You need a local ORS Docker instance running (recommended for speed) or a valid API key. For details check: <https://github.com/GIScience/openrouteservice>

### Installation

We use `pak` (or `renv`) to manage dependencies.

``` r
install.packages("pak")
pak::pak(dependencies = TRUE)
```

``` r
install.packages("renv", dependencies = TRUE)
renv::restore()
```

### Configuration

Check `_environment` (or create one) to set your API keys if you aren't using a local ORS instance:

``` md
ORS_API_KEY=your_key_here
```

## 📂 Project Structure

-   `_src/`: Helper R functions (isochrone generation, previewers).
-   `_data/`:
    -   `raw/`: Where you drop manual inputs (like the REMM GDB).
    -   `processed/`: Cleaned GeoParquets.
    -   `isochrones/`: Output from ORS.
-   `_output/`: Final scored datasets and GDBs.

## Authors

Reach out to [Bill Hereth](https://github.com/bhereth) or [Pukar Bhandari](https://github.com/ar-puuk) at [Wasatch Front Regional Council](https://wfrc.utah.gov/) if you have any questions or suggestions.

## TODO

Use `shiny`, `mapgl` and `pmtiles` packages to build an interactive app.
