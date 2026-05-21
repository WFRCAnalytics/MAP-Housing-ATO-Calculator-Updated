#' Generate Spatial Buffers using DuckDB
#'
#' Reads a Parquet file (from PROCESSED), buffers geometries using DuckDB,
#' and saves the result as a new Parquet file in PROCESSED.
#'
#' @param input_parquet Full path to input Parquet file.
#' @param output_name Desired output filename (without extension).
#' @param dist_meters Buffer distance in meters.
#' @export
create_buffer <- function(
  input_parquet,
  output_name,
  dist_meters,
  processed_dir = dirs$processed
) {
  # 1. Dependency Check
  required_pkgs <- c("duckdb", "duckspatial", "glue", "DBI")
  missing_pkgs <- required_pkgs[
    !sapply(required_pkgs, requireNamespace, quietly = TRUE)
  ]
  if (length(missing_pkgs) > 0) {
    stop("Missing packages: ", paste(missing_pkgs, collapse = ", "))
  }

  # 2. Path Setup
  if (!dir.exists(processed_dir)) {
    dir.create(processed_dir, recursive = TRUE)
  }
  output_fp <- file.path(processed_dir, paste0(output_name, ".parquet"))

  # 3. Cache Check
  if (file.exists(output_fp)) {
    message(paste("✅ Buffer exists:", output_name))
    return(output_fp)
  }

  message(paste("⭕ Buffering:", output_name, "| Dist:", dist_meters, "m"))

  # 4. Execution
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  tryCatch(
    {
      duckspatial::ddbs_load(con)

      query <- glue::glue(
        "
      COPY (
        SELECT
          *,
          ST_Buffer(geometry, {dist_meters}) as geometry
        FROM read_parquet('{input_parquet}')
      ) TO '{output_fp}' (FORMAT PARQUET)
    "
      )

      DBI::dbExecute(con, query)
      message(paste("💾 Saved Buffer:", output_fp))
      return(output_fp)
    },
    error = function(e) {
      stop(paste("❌ Error buffering:", output_name, "\nReason:", e$message))
    }
  )
}
