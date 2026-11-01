#' Export the Scored Layers (File Geodatabase and App Data)
#'
#' Everything here is plain DuckDB SQL (no arrow, geoarrow or sf). The step 3/4
#' tables are in EPSG:26912; the apps and the geodatabase want lon/lat, so each
#' function reprojects with `ST_Transform(..., 'EPSG:4326')` on the way out.
#' DuckDB writes geometry as WKB and records the CRS in the GeoParquet metadata.

#' Write a Scored Parquet Layer to a File Geodatabase
#'
#' Streams the layer through GDAL inside DuckDB, so the 600k+ polygons never
#' load into R. Any existing geodatabase at `gdb_path` is replaced.
#'
#' @param conn DuckDB connection with `spatial` loaded.
#' @param src Parquet file with a `geom` column.
#' @param gdb_path Output `.gdb` directory.
#' @param layer Layer name inside the geodatabase.
#' @param crs Output CRS. Default `"EPSG:4326"`.
#' @return `gdb_path`, invisibly.
export_gdb <- function(conn, src, gdb_path, layer, crs = "EPSG:4326") {
  if (fs::dir_exists(gdb_path)) fs::dir_delete(gdb_path)
  DBI::dbExecute(
    conn,
    glue::glue(
      "
    COPY (
      SELECT * EXCLUDE (geom), ST_Multi(ST_Transform(geom, '{crs}')) AS geom
      FROM read_parquet('{src}')
    ) TO '{gdb_path}'
      WITH (FORMAT GDAL, DRIVER 'OpenFileGDB', GEOMETRY_TYPE 'MULTIPOLYGON', LAYER_NAME '{layer}')
  "
    )
  )
  invisible(gdb_path)
}

#' Write the Scored H3 Table as One Parquet File per Municipality
#'
#' Layout read by both apps: `<dst>/CommCode=<code>/part-0.parquet`. The
#' `CommCode` column lives in the folder name, not in the files. Cells outside
#' every municipality (`CommCode IS NULL`) are left out. Any existing `dst` is
#' replaced.
#'
#' @param conn DuckDB connection.
#' @param table_name Scored table with `CommCode` and a UTM `geom` column.
#' @param dst Output folder.
#' @param crs Output CRS. Default `"EPSG:4326"`.
#' @return `dst`, invisibly.
write_h3_partitioned <- function(conn, table_name, dst, crs = "EPSG:4326") {
  if (fs::dir_exists(dst)) fs::dir_delete(dst)
  DBI::dbExecute(
    conn,
    glue::glue(
      "
    COPY (
      SELECT * EXCLUDE (geom), ST_Transform(geom, '{crs}') AS geom
      FROM {table_name}
      WHERE CommCode IS NOT NULL
    ) TO '{dst}' (FORMAT PARQUET, PARTITION_BY (CommCode), FILENAME_PATTERN 'part-{{i}}')
  "
    )
  )
  invisible(dst)
}

#' Write the Municipal Boundaries Used by the Apps
#'
#' One row per municipality that has scored cells, with `UGRCODE`, `NAME`, the
#' boundary as WKB (`geometry`) and the same boundary as GeoJSON text
#' (`geojson`), which the Vite app parses directly. Sorted by `NAME`.
#'
#' @param conn DuckDB connection with `spatial` loaded.
#' @param table_name Scored table with `CommCode`.
#' @param src Processed municipal boundary parquet (`ugrcode`, `name`, `geometry`).
#' @param out_path Output parquet file.
#' @param crs Output CRS. Default `"EPSG:4326"`.
#' @return `out_path`, invisibly.
write_municipalities <- function(conn, table_name, src, out_path, crs = "EPSG:4326") {
  DBI::dbExecute(
    conn,
    glue::glue(
      "
    COPY (
      SELECT UGRCODE, NAME, geometry, ST_AsGeoJSON(geometry) AS geojson
      FROM (
        SELECT ugrcode AS UGRCODE, name AS NAME, ST_Transform(geometry, '{crs}') AS geometry
        FROM read_parquet('{src}')
        WHERE ugrcode IN (SELECT DISTINCT CommCode FROM {table_name} WHERE CommCode IS NOT NULL)
      )
      ORDER BY NAME
    ) TO '{out_path}' (FORMAT PARQUET)
  "
    )
  )
  invisible(out_path)
}

#' Write the Regional Boundary Used by the Apps
#'
#' @param conn DuckDB connection with `spatial` loaded.
#' @param src Processed regional boundary parquet (UTM, `geometry` column).
#' @param out_path Output parquet file.
#' @param crs Output CRS. Default `"EPSG:4326"`.
#' @return `out_path`, invisibly.
write_boundary <- function(conn, src, out_path, crs = "EPSG:4326") {
  DBI::dbExecute(
    conn,
    glue::glue(
      "
    COPY (
      SELECT * EXCLUDE (geometry), ST_Transform(geometry, '{crs}') AS geometry
      FROM read_parquet('{src}')
    ) TO '{out_path}' (FORMAT PARQUET)
  "
    )
  )
  invisible(out_path)
}
