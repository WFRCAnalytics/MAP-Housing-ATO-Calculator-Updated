# DuckDB 1.5 Migration Checklist

**Context:** R package is `duckdb` 1.5.2; CLI is 1.5.3. Both are the same generation.

Three breaking changes from the DuckDB 1.5 release directly affect this pipeline:

1. **`GEOMETRY` is now a built-in core type** — GeoArrow ↔ DuckDB conversion is natively handled. The `geoarrow` R package's `register_geoarrow_extensions()` DuckDB table function no longer exists (confirmed: errors with "Table Function with name register_geoarrow_extensions does not exist").
2. **`geometry_always_xy` axis-order transition** — In v1.5 affected functions emit a deprecation warning. In v2.0 they will error. The affected functions (`ST_Distance_Spheroid`, `ST_Area_Spheroid`, `ST_Transform`, etc.) must use `always_xy := true` inline **or** have the session setting enabled.
3. **`ST_GeomFromWKB` / `ST_AsWKB` wrappers** — With GEOMETRY as a built-in type, parquet columns with GeoArrow encoding are now automatically typed as GEOMETRY on read. Wrapping them in `ST_GeomFromWKB()` (which expects raw WKB bytes, not a GEOMETRY) may now fail.

---

## Status Summary

| Priority | File | Change | Status |
|---|---|---|---|
| 🔴 Breaking | `2-process-layers.qmd` | Remove `CALL register_geoarrow_extensions()` (×2 active) | ✅ Done |
| 🔴 Breaking | `3-spatial-operations.qmd` | Remove `CALL register_geoarrow_extensions()` (×1) | ✅ Done |
| 🔴 Breaking | `4-ato-scoring.qmd` | Remove `CALL register_geoarrow_extensions()` (×1) | ✅ Done |
| 🟡 Warning→Error in v2.0 | `_src/process_isochrones.R` | Add `always_xy := true` to bare `ST_Transform` | ✅ Done |
| 🟡 Warning→Error in v2.0 | All init-db chunks | Add `SET geometry_always_xy = true` to session setup | ✅ Done |
| 🟠 Test needed | `3-spatial-operations.qmd` | `ST_GeomFromWKB(geometry)` may be redundant | ✅ Done |
| 🟠 Test needed | `_src/create_buffer.R` | `ST_GeomFromWKB` + `ST_AsWKB` wrappers may be redundant | ✅ Done |
| ✅ Already correct | `2-process-layers.qmd` | All `ST_Transform` calls use `always_xy := true` | Done |
| ✅ Already correct | `3-spatial-operations.qmd` | All `ST_Transform` calls use `always_xy := true` | Done |
| ✅ Already correct | `_src/process_isochrones.R` | `register_geoarrow_extensions` already commented out | Done |

---

## 🔴 Breaking Changes (Fix Before Next Run)

### 1. Remove `CALL register_geoarrow_extensions()`

This function no longer exists in DuckDB 1.5. GeoArrow ↔ GEOMETRY conversion is now handled natively by the core engine. Simply delete these lines.

#### `2-process-layers.qmd`

**Occurrence 1 — `prep-boundary` chunk (~line 302):**
```r
# REMOVE this line:
DBI::dbExecute(conn, "CALL register_geoarrow_extensions()")
```

**Occurrence 2 — `gen-h3-grid` chunk (~line 442):**
```r
# REMOVE this line:
DBI::dbExecute(conn, "CALL register_geoarrow_extensions()")
```

*(Two other occurrences on lines ~228 and ~380 are already in `r` (non-evaluated) blocks — leave as-is.)*

#### `3-spatial-operations.qmd`

**`init-db` chunk (~line 154):**
```r
# REMOVE this line:
DBI::dbExecute(conn, "CALL register_geoarrow_extensions()")
```

#### `4-ato-scoring.qmd`

**`init-db` chunk (~line 107):**
```r
# REMOVE this line:
DBI::dbExecute(conn, "CALL register_geoarrow_extensions()")
```

---

## 🟡 Deprecation Warnings → Error in v2.0 (Fix Before v2.0 Ships)

### 2. Set `geometry_always_xy = true` at session level

The code already uses `always_xy := true` inline in every `ST_Transform` call (correct!). Adding the session-level setting additionally suppresses deprecation warnings from any other affected spatial functions and future-proofs for v2.0.

Add this immediately after loading the spatial extension in each `init-db` / connection block:

```r
DBI::dbExecute(conn, "SET geometry_always_xy = true")
```

**Where to add it:**

| File | Chunk | After which line |
|---|---|---|
| `2-process-layers.qmd` | `prep-boundary` | After `INSTALL spatial; LOAD spatial;` |
| `2-process-layers.qmd` | `gen-h3-grid` | After `INSTALL spatial; LOAD spatial;` |
| `3-spatial-operations.qmd` | `init-db` | After `INSTALL spatial; LOAD spatial;` |
| `4-ato-scoring.qmd` | `init-db` | After `INSTALL spatial; LOAD spatial;` |

### 3. `_src/process_isochrones.R` — Add `always_xy := true` to bare `ST_Transform`

**File:** `_src/process_isochrones.R`, ~line 126

```r
# Current (will warn in v1.5, error in v2.0):
glue::glue("ST_Transform(geom, '{boundary_crs}', 'EPSG:4326')")

# Fix:
glue::glue("ST_Transform(geom, '{boundary_crs}', 'EPSG:4326', always_xy := true)")
```

---

## 🟠 Needs Testing (Run and Verify)

### 4. `ST_GeomFromWKB(geometry)` in spatial operations

**File:** `3-spatial-operations.qmd`, `load-h3` chunk (~line 182)

```sql
-- Current:
ST_Transform(ST_GeomFromWKB(geometry), '{CRS_WGS}', '{CRS_UTM}', always_xy := true) as geom

-- Possible fix if geometry is already GEOMETRY type:
ST_Transform(geometry, '{CRS_WGS}', '{CRS_UTM}', always_xy := true) as geom
```

**Test:** Run `load-h3` chunk and check if it errors. If `ST_GeomFromWKB` raises a type mismatch (GEOMETRY vs BLOB), remove the `ST_GeomFromWKB()` wrapper.

### 5. `ST_GeomFromWKB` + `ST_AsWKB` in create_buffer

**File:** `_src/create_buffer.R`, ~line 52

```sql
-- Current:
ST_AsWKB(ST_Buffer(ST_GeomFromWKB(geometry), {dist_meters})) as geometry

-- Possible fix if geometry is already GEOMETRY type:
ST_Buffer(geometry, {dist_meters}) as geometry
```

**Test:** Run `create_buffer()` on any layer. If it errors with a type mismatch, remove both wrappers. `ST_Buffer` can accept GEOMETRY directly and DuckDB 1.5 will write it to parquet as GEOMETRY natively.

---

## ✅ Already Correct (No Action Needed)

- **`2-process-layers.qmd`** — All `ST_Transform` calls use `always_xy := true` (lines ~337, ~454, ~646, ~652, ~688, ~689). ✅
- **`3-spatial-operations.qmd`** — All `ST_Transform` calls use `always_xy := true` (lines ~182, ~244, ~297, ~304, ~408, ~651, ~802, ~1004, ~1020). ✅
- **`_src/process_isochrones.R`** — `register_geoarrow_extensions` already commented out. ✅
- **`4-ato-scoring.qmd` `sync-app-data` chunk** — Uses `ST_AsText(geometry)` which is unaffected by the axis-order change (WKT output is always lon/lat). ✅

---

## Execution Order

1. Fix all 🔴 items first (remove `register_geoarrow_extensions` lines) — these error immediately.
2. Add `geometry_always_xy = true` to all session setups.
3. Fix `process_isochrones.R` `ST_Transform`.
4. Run steps 2 → 3 → 4 in sequence and observe whether 🟠 items error. Fix them if they do.
