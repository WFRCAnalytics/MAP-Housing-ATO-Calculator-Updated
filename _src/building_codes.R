#' Building Type -> Building Code Mapping
#'
#' REMM `building_type` names and their two-letter codes. Any building type not
#' listed here (including NULL) becomes `"OT"` (other).
BUILDING_CODE_MAP <- data.frame(
  full_name = c(
    "Agriculture", "Church", "Commons", "Educational", "Empty - Buildable",
    "Empty Buildable", "Governmental", "Group Quarters", "Healthcare",
    "Industrial", "Mixed Use", "Multi Family Res", "No Build", "Office",
    "Open Space Non-Buildable", "Other", "Retail", "Single Family Res",
    "Utilities"
  ),
  abbr = c(
    "AG", "CH", "OS", "ED", "EM", "EM", "GO", "GQ", "HE", "IN", "MU", "MF",
    "NB", "OF", "OS", "OT", "RE", "SF", "UT"
  )
)

#' Assign a Building Code (BC) to Parcels and H3 Cells
#'
#' Adds a `BC` column to `targets_parcels` and `targets_h3`. Anything without a
#' code (a parcel with no buildings, a cell nothing could be inferred for, an
#' unmapped building type) is `"OT"`, because the column is added with
#' `DEFAULT 'OT'`.
#'
#' **Parcels** get the code of their largest building (`building_sqft`); equal
#' footage is broken alphabetically by code.
#'
#' **H3 cells** are filled in three steps, each only for cells the previous
#' one left empty:
#' 1. The most common code among the buildings inside the cell. A tie goes to
#'    the code with more total building square footage, then alphabetically.
#' 2. The code of the parcel under the cell centre (large parcels and lots
#'    whose buildings are in a neighbouring cell). A centre on a shared parcel
#'    edge takes the alphabetically first code.
#' 3. The most common code among the six neighbours, if at least four of them
#'    have one (fills holes, leaves coastlines and edges alone). A tie goes to
#'    the alphabetically first code.
#'
#' Requires the tables `targets_parcels` (`parcel_id`, `geom`), `targets_h3`
#' (`h3_index`) and `points_h3` (`h3_index`, `geom`), and `timed_step()`
#' (from `process_amenities.R`).
#'
#' @param conn DuckDB connection with `spatial` and `h3` loaded and
#'   `geometry_always_xy` set.
#' @param fp_buildings Path to the REMM buildings parquet (UTM, with
#'   `parcel_id`, `building_type`, `building_sqft`).
#' @param res H3 resolution of the grid.
#' @param crs_wgs CRS used to look up each building's H3 cell. Default `"EPSG:4326"`.
#' @return `NULL`, invisibly.
assign_building_codes <- function(conn, fp_buildings, res, crs_wgs = "EPSG:4326") {
  message("🏗️ Assigning building codes...")
  DBI::dbWriteTable(conn, "bc_map", BUILDING_CODE_MAP, overwrite = TRUE)

  # One row per building: its code, size and H3 cell
  timed_step(
    "buildings: code + H3 cell",
    DBI::dbExecute(
      conn,
      glue::glue(
        "
      CREATE OR REPLACE TEMP TABLE points_buildings AS
      SELECT
        b.parcel_id,
        b.building_sqft,
        COALESCE(m.abbr, 'OT') AS bc,
        CAST(h3_latlng_to_cell(ST_Y(b.c), ST_X(b.c), {res}) AS UBIGINT) AS h3_index
      FROM (
        SELECT parcel_id, building_type, building_sqft,
               ST_Transform(ST_Centroid(geometry), '{crs_wgs}') AS c
        FROM read_parquet('{fp_buildings}')
        WHERE ST_IsValid(geometry)
      ) b
      LEFT JOIN bc_map m ON b.building_type = m.full_name
    "
      )
    )
  )

  # Parcels: the largest building
  timed_step("parcels BC", {
    DBI::dbExecute(
      conn,
      "
      CREATE OR REPLACE TEMP TABLE parcel_bc AS
      SELECT parcel_id, bc
      FROM points_buildings
      QUALIFY ROW_NUMBER() OVER (
        PARTITION BY parcel_id
        ORDER BY building_sqft DESC NULLS LAST, bc
      ) = 1
    "
    )
    DBI::dbExecute(conn, "ALTER TABLE targets_parcels DROP COLUMN IF EXISTS BC")
    DBI::dbExecute(conn, "ALTER TABLE targets_parcels ADD COLUMN BC VARCHAR DEFAULT 'OT'")
    DBI::dbExecute(
      conn,
      "
      UPDATE targets_parcels
      SET BC = parcel_bc.bc
      FROM parcel_bc
      WHERE targets_parcels.parcel_id = parcel_bc.parcel_id
    "
    )
  })

  # H3 cells: buildings in the cell, then the parcel under the centre, then the neighbours
  timed_step("H3 BC", {
    DBI::dbExecute(
      conn,
      "
      CREATE OR REPLACE TEMP TABLE h3_bc AS
      WITH
      by_buildings AS (
        SELECT h3_index, bc
        FROM (
          SELECT h3_index, bc, COUNT(*) AS n, SUM(building_sqft) AS sqft
          FROM points_buildings
          GROUP BY h3_index, bc
        )
        QUALIFY ROW_NUMBER() OVER (
          PARTITION BY h3_index
          ORDER BY n DESC, sqft DESC NULLS LAST, bc
        ) = 1
      ),
      empty_cells AS (
        SELECT h3_index, geom FROM points_h3 ANTI JOIN by_buildings USING (h3_index)
      ),
      by_parcel AS (
        SELECT c.h3_index, MIN(pb.bc) AS bc
        FROM empty_cells c
        JOIN targets_parcels p ON ST_Intersects(c.geom, p.geom)
        JOIN parcel_bc pb ON p.parcel_id = pb.parcel_id
        GROUP BY c.h3_index
      ),
      filled AS (
        SELECT * FROM by_buildings
        UNION ALL
        SELECT * FROM by_parcel
      ),
      by_neighbours AS (
        SELECT h3_index, bc
        FROM (
          SELECT e.h3_index, f.bc, COUNT(*) AS votes
          FROM (SELECT h3_index FROM targets_h3 ANTI JOIN filled USING (h3_index)) e
          CROSS JOIN LATERAL (
            SELECT unnest(h3_grid_disk(e.h3_index, 1)) AS neighbour
          ) g
          JOIN filled f ON g.neighbour = f.h3_index
          GROUP BY e.h3_index, f.bc
        )
        QUALIFY SUM(votes) OVER (PARTITION BY h3_index) >= 4
            AND ROW_NUMBER() OVER (PARTITION BY h3_index ORDER BY votes DESC, bc) = 1
      )
      SELECT * FROM filled
      UNION ALL
      SELECT * FROM by_neighbours
    "
    )
    DBI::dbExecute(conn, "ALTER TABLE targets_h3 DROP COLUMN IF EXISTS BC")
    DBI::dbExecute(conn, "ALTER TABLE targets_h3 ADD COLUMN BC VARCHAR DEFAULT 'OT'")
    DBI::dbExecute(
      conn,
      "
      UPDATE targets_h3
      SET BC = h3_bc.bc
      FROM h3_bc
      WHERE targets_h3.h3_index = h3_bc.h3_index
    "
    )
  })

  DBI::dbExecute(conn, "DROP TABLE points_buildings; DROP TABLE parcel_bc; DROP TABLE h3_bc; DROP TABLE bc_map")
  invisible(NULL)
}
