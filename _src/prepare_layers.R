#' Publish a Finished Output Atomically
#'
#' Helpers write to `<out_fp>.tmp` and call this once the write succeeded, so
#' an interrupted write can never be mistaken for a cached layer.
#'
#' @param tmp_fp Temporary file or directory that was just written.
#' @param out_fp Final file or directory path.
#' @return `out_fp`, invisibly.
publish_output <- function(tmp_fp, out_fp) {
  if (!file.exists(tmp_fp)) stop("Nothing was written to: ", tmp_fp)
  if (!dir.exists(tmp_fp) && file.size(tmp_fp) == 0) {
    stop("Empty output written to: ", tmp_fp)
  }
  if (file.exists(out_fp)) unlink(out_fp, recursive = TRUE)
  if (!file.rename(tmp_fp, out_fp)) stop("Could not move ", tmp_fp, " to ", out_fp)
  invisible(out_fp)
}

#' Run Code With a Short-Lived DuckDB Connection
#'
#' Opens an in-memory DuckDB connection with the spatial extension loaded and
#' `geometry_always_xy` set, runs `code(conn)`, and always closes it. Use this
#' instead of `on.exit()` in a notebook chunk: `on.exit()` at the top level of a
#' chunk does not run when the chunk ends, so the connection stays open.
#'
#' @param code Function taking the connection as its only argument.
#' @param h3 Logical. Also load the community H3 extension. Default `FALSE`.
#' @return Whatever `code(conn)` returns.
with_duckdb <- function(code, h3 = FALSE) {
  conn <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(conn, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(conn, "INSTALL spatial; LOAD spatial;")
  DBI::dbExecute(conn, "SET geometry_always_xy = true")
  if (h3) DBI::dbExecute(conn, "INSTALL h3 FROM community; LOAD h3;")
  code(conn)
}

#' Write an sf Object to GeoParquet, Carrying Its CRS Natively
#'
#' The sf object's geometry goes to DuckDB in memory as WKB. WKB has no CRS, so
#' it is cast to `GEOMETRY('<the sf object's own CRS>')`, which makes DuckDB
#' CRS-aware; `ST_Transform(geom, crs)` then reprojects it and DuckDB writes the
#' CRS into the GeoParquet metadata. An sf object without an EPSG CRS is an
#' error, so nothing is guessed.
#'
#' @param sf_obj An sf object with a CRS.
#' @param out_tmp Temporary output path (file, or directory when `partitioning` is set).
#' @param crs Target CRS (EPSG string) for the written geometry.
#' @param partitioning (Optional) Character vector of columns to partition by.
#' @return `out_tmp`, invisibly. Call `publish_output()` afterwards.
write_sf_parquet <- function(sf_obj, out_tmp, crs, partitioning = NULL) {
  src_crs <- sf::st_crs(sf_obj)$srid
  if (is.null(src_crs) || is.na(src_crs) || !nzchar(src_crs)) {
    stop("sf object has no EPSG CRS; refusing to guess one")
  }

  wkb <- sf::st_as_binary(sf::st_geometry(sf_obj))
  class(wkb) <- "blob"
  df_out <- sf::st_drop_geometry(sf_obj)
  df_out[["geometry"]] <- wkb

  part_sql <- ""
  if (!is.null(partitioning)) {
    dir.create(out_tmp, recursive = TRUE, showWarnings = FALSE)
    part_sql <- paste0(", PARTITION_BY (", paste(partitioning, collapse = ", "), ")")
  }

  with_duckdb(function(conn) {
    duckdb::duckdb_register(conn, "_sf_data", df_out)
    DBI::dbExecute(
      conn,
      glue::glue(
        "COPY (
          SELECT * EXCLUDE (geometry),
                 ST_Transform(ST_GeomFromWKB(geometry)::GEOMETRY('{src_crs}'), '{crs}') AS geometry
          FROM _sf_data
        ) TO '{out_tmp}' (FORMAT PARQUET{part_sql})"
      )
    )
  })
  invisible(out_tmp)
}

#' Join TAZ Geometry With the Access-to-Opportunity CSV
#'
#' Joins TAZ polygons with the ATO CSV inside DuckDB. CSV columns that
#' duplicate TAZ fields (TAZID, CO_TAZID, DevAcres) are dropped; the remaining
#' CSV names (Job_byAuto, Job_byTran, ...) are kept as-is because
#' 3-spatial-operations.qmd references them.
#'
#' @param base_fp Parquet path of the TAZ layer.
#' @param csv CSV path relative to `dirs$raw`.
#' @param name Output filename (without extension).
#' @param save_dir Output directory.
#' @param overwrite Logical. Default `FALSE`.
#' @return Path to the saved parquet file.
join_taz_ato <- function(base_fp, csv, name, save_dir, overwrite = FALSE) {
  out_fp <- file.path(save_dir, paste0(name, ".parquet"))
  if (file.exists(out_fp) && !overwrite) {
    message("✅ Exists: ", name)
    return(out_fp)
  }

  csv_fp <- file.path(dirs$raw, csv)
  if (!file.exists(csv_fp)) stop("Input not found: ", csv_fp)
  tmp_fp <- paste0(out_fp, ".tmp")
  unlink(tmp_fp, recursive = TRUE)

  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(con, "INSTALL spatial; LOAD spatial;")
  DBI::dbExecute(con, "SET geometry_always_xy = true")
  DBI::dbExecute(
    con,
    glue::glue(
      "COPY (
        SELECT taz.*, ato.* EXCLUDE (TAZID, CO_TAZID, DevAcres)
        FROM read_parquet('{base_fp}') taz
        LEFT JOIN read_csv('{csv_fp}', header = true) ato
          ON taz.co_tazid = ato.CO_TAZID
      ) TO '{tmp_fp}' (FORMAT PARQUET)"
    )
  )
  publish_output(tmp_fp, out_fp)
  message("💾 Saved Parquet File: ", out_fp)
  out_fp
}

#' Prepare Every Layer Declared in sources.yml
#'
#' Loops over the manifest, dispatches each entry to the matching helper
#' (`download_feature_layer`, `process_local_layer` or `join_taz_ato`), and
#' keeps going if one layer fails. Layers that already exist are skipped by
#' the helpers, so re-running only retries what is missing or failed.
#'
#' @param sources Named list from `yaml::read_yaml("sources.yml")$layers`.
#' @param sub_dirs Named list of output directories; `entry$save_dir` is a name in it.
#' @param crs Target CRS (EPSG string).
#' @param only (Optional) Character vector of layer keys to run.
#' @param overwrite Logical. Re-create layers even if they exist. Default `FALSE`.
#'
#' @return A data frame with one row per layer: key, status
#'   (`ok`, `cached`, `failed`), seconds, path, error.
prepare_layers <- function(
  sources,
  sub_dirs,
  crs = CRS_UTM,
  only = NULL,
  overwrite = FALSE
) {
  keys <- if (is.null(only)) names(sources) else only
  unknown <- setdiff(keys, names(sources))
  if (length(unknown) > 0) {
    stop("Unknown layer key(s): ", paste(unknown, collapse = ", "))
  }

  rows <- lapply(keys, function(key) {
    entry <- sources[[key]]
    save_dir <- sub_dirs[[entry$save_dir]]
    if (is.null(save_dir)) {
      return(data.frame(
        key = key, status = "failed", seconds = 0, path = NA_character_,
        error = paste0("Unknown save_dir: ", entry$save_dir)
      ))
    }

    expected_fp <- if (is.null(entry$partitioning)) {
      file.path(save_dir, paste0(entry$name, ".parquet"))
    } else {
      file.path(save_dir, entry$name)
    }
    was_cached <- file.exists(expected_fp) && !overwrite

    t0 <- Sys.time()
    result <- tryCatch(
      {
        fp <- switch(
          entry$type,
          arcgis = download_feature_layer(
            url = entry$url,
            name = entry$name,
            save_dir = save_dir,
            where = entry$where %||% "1=1",
            crs = crs,
            partitioning = entry$partitioning,
            overwrite = overwrite
          ),
          local = process_local_layer(
            path = entry$path,
            name = entry$name,
            save_dir = save_dir,
            layer = entry$layer,
            query = entry$query %||% NA,
            crs = crs,
            read_mode = entry$read_mode %||% "auto",
            partitioning = entry$partitioning,
            overwrite = overwrite
          ),
          join = {
            base <- sources[[entry$base]]
            base_fp <- file.path(sub_dirs[[base$save_dir]], paste0(base$name, ".parquet"))
            if (!file.exists(base_fp)) stop("Base layer missing: ", entry$base)
            join_taz_ato(base_fp, entry$csv, entry$name, save_dir, overwrite)
          },
          stop("Unknown type: ", entry$type)
        )
        if (is.null(fp)) stop("Input missing (see warning above)")
        list(fp = fp, error = NA_character_)
      },
      error = function(e) {
        message("❌ ", key, ": ", conditionMessage(e))
        list(fp = NA_character_, error = conditionMessage(e))
      }
    )

    data.frame(
      key = key,
      status = if (!is.na(result$error)) "failed" else if (was_cached) "cached" else "ok",
      seconds = round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1),
      path = result$fp,
      error = result$error
    )
  })

  status <- do.call(rbind, rows)
  n_failed <- sum(status$status == "failed")
  if (n_failed > 0) {
    warning(n_failed, " layer(s) failed: ", paste(status$key[status$status == "failed"], collapse = ", "))
  }
  status
}

#' Preview a Layer From the Manifest
#'
#' Looks up the layer's output path in the `prepare_layers()` status table and
#' calls `preview_layer()` with the `preview:` options from sources.yml.
#'
#' @param key Layer key in sources.yml.
#' @param status Data frame returned by `prepare_layers()`.
#' @param sources Named list from sources.yml.
preview_source <- function(key, status, sources) {
  fp <- status$path[status$key == key]
  if (length(fp) != 1 || is.na(fp)) stop("No output available for: ", key)
  opts <- sources[[key]]$preview %||% list()
  do.call(preview_layer, c(list(fp), opts))
}
