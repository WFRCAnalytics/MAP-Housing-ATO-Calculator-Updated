# ============================================================
# REMM GDB Diagnostic
# Run each section manually in Positron. Do NOT source() all at once.
# ============================================================

library(duckdb)
library(DBI)
library(glue)

# Paths — unzipped GDB (avoids vsizip overhead, same bytes as the zip)
gdb_dir  <- normalizePath("_data/raw/remm_base_year.gdb")
dsn      <- gsub("\\\\", "/", gdb_dir)

con <- DBI::dbConnect(duckdb::duckdb())
DBI::dbExecute(con, "INSTALL spatial; LOAD spatial;")
DBI::dbExecute(con, "SET geometry_always_xy = true")

# ─────────────────────────────────────────────────────────────
# SECTION 1: What GDAL drivers does DuckDB have for FileGDB?
# ─────────────────────────────────────────────────────────────
cat("\n=== GDAL drivers available for GDB ===\n")
DBI::dbGetQuery(con, "
  SELECT short_name, long_name, can_open
  FROM ST_Drivers()
  WHERE long_name ILIKE '%geodatabase%' OR short_name ILIKE '%gdb%'
") |> print()

# ─────────────────────────────────────────────────────────────
# SECTION 2: What layers exist and what geometry type does GDAL report?
# ─────────────────────────────────────────────────────────────
cat("\n=== Layers and reported geometry types ===\n")
DBI::dbGetQuery(con, glue("
  SELECT unnest(layers) AS layer
  FROM ST_Read_Meta('{dsn}')
")) |> print()

# ─────────────────────────────────────────────────────────────
# SECTION 3: PARCELS — count rows where WKB can't be parsed
# keep_wkb=true: DuckDB reads raw bytes without type-checking (no crash).
# TRY(ST_GeomFromWKB(...)): parse per row; unsupported types return NULL.
# ─────────────────────────────────────────────────────────────
cat("\n=== PARCELS: WKB parse failure count ===\n")
DBI::dbGetQuery(con, glue("
  SELECT
    COUNT(*)                                                          AS total_rows,
    SUM(CASE WHEN TRY(ST_GeomFromWKB(geometry)) IS NULL THEN 1 ELSE 0 END) AS failed_rows,
    SUM(CASE WHEN TRY(ST_GeomFromWKB(geometry)) IS NOT NULL THEN 1 ELSE 0 END) AS ok_rows
  FROM ST_Read('{dsn}', layer = 'parcels', keep_wkb = true)
")) |> print()

# ─────────────────────────────────────────────────────────────
# SECTION 4: BUILDINGS — check first 5000 rows only (safe, no crash)
# ─────────────────────────────────────────────────────────────
cat("\n=== BUILDINGS: WKB parse failure count (first 5000 rows) ===\n")
DBI::dbGetQuery(con, glue("
  SELECT
    COUNT(*)                                                          AS total_rows,
    SUM(CASE WHEN TRY(ST_GeomFromWKB(geometry)) IS NULL THEN 1 ELSE 0 END) AS failed_rows,
    SUM(CASE WHEN TRY(ST_GeomFromWKB(geometry)) IS NOT NULL THEN 1 ELSE 0 END) AS ok_rows
  FROM (
    SELECT geometry
    FROM ST_Read('{dsn}', layer = 'buildings', keep_wkb = true)
    LIMIT 5000
  )
")) |> print()

# ─────────────────────────────────────────────────────────────
# SECTION 5: BUILDINGS — check if failure distributes late in the scan
# i.e. does it only fail after a certain row offset? (explains 63% progress)
# ─────────────────────────────────────────────────────────────
cat("\n=== BUILDINGS: WKB failures by offset (batches of 10k) ===\n")
for (offset in c(0, 10000, 50000, 100000)) {
  res <- DBI::dbGetQuery(con, glue("
    SELECT
      {offset} AS offset,
      COUNT(*) AS rows_in_batch,
      SUM(CASE WHEN TRY(ST_GeomFromWKB(geometry)) IS NULL THEN 1 ELSE 0 END) AS failed
    FROM (
      SELECT geometry
      FROM ST_Read('{dsn}', layer = 'buildings', keep_wkb = true)
      LIMIT 10000 OFFSET {offset}
    )
  "))
  print(res)
}

DBI::dbDisconnect(con, shutdown = TRUE)
