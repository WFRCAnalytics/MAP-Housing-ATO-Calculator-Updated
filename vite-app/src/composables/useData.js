import { DATA_BASE_URL } from '../config/constants.js'
import { computeScores } from './useScoring.js'

// ── DuckDB singleton (eh bundle — no COOP/COEP needed) ─
let _conn = null

async function getConn() {
  if (_conn) return _conn
  const duckdb = await import('@duckdb/duckdb-wasm')
  const EH = {
    mainModule: new URL('@duckdb/duckdb-wasm/dist/duckdb-eh.wasm', import.meta.url).href,
    mainWorker: new URL('@duckdb/duckdb-wasm/dist/duckdb-browser-eh.worker.js', import.meta.url).href,
  }
  const worker = new Worker(EH.mainWorker)
  const db = new duckdb.AsyncDuckDB(new duckdb.ConsoleLogger(duckdb.LogLevel.WARNING), worker)
  await db.instantiate(EH.mainModule)
  _conn = await db.connect()
  return _conn
}

// ── Arrow table → plain JS row array ──────────────────
// Only passes through primitives — drops geometry/binary/complex Arrow types
// that would fail postMessage's structured clone algorithm.
function tableToRows(table) {
  const n = table.numRows
  const fields = table.schema.fields
  const cols = fields.map(f => table.getChild(f.name))
  const rows = new Array(n)
  for (let i = 0; i < n; i++) {
    const row = {}
    for (let j = 0; j < fields.length; j++) {
      const v = cols[j]?.get(i) ?? null
      row[fields[j].name] =
        v === null                                                   ? null
        : typeof v === 'bigint'                                      ? Number(v)
        : typeof v === 'string' || typeof v === 'number' || typeof v === 'boolean' ? v
        : null  // drop geometry/binary/complex Arrow objects
    }
    rows[i] = row
  }
  return rows
}

// ── City parquet cache (commCode → row[]) ─────────────
const cityCache = new Map()

// Quote all identifiers to avoid DuckDB reserved-word conflicts (AT, AA, etc.)
// Excludes the geometry/WKB column added by st_as_sf() in R.
const CITY_COLS = '"h3_index","CommCode","BC","OZ","AA","AT","TT","TF","TA","AC","AH","AE","AG","AM","AP"'

export async function fetchCityData(commCode) {
  if (cityCache.has(commCode)) return cityCache.get(commCode)
  const conn = await getConn()
  const url = `${DATA_BASE_URL}/h3_scored/CommCode=${commCode}/part-0.parquet`
  const table = await conn.query(`SELECT ${CITY_COLS} FROM read_parquet('${url}')`)
  const rows = tableToRows(table)
  cityCache.set(commCode, rows)
  return rows
}

// ── H3 Web Worker singleton ───────────────────────────
let h3Worker = null

function getH3Worker() {
  if (!h3Worker) {
    h3Worker = new Worker(new URL('../workers/h3-worker.js', import.meta.url), { type: 'module' })
  }
  return h3Worker
}

// ── Load one or more cities → scored GeoJSON ──────────
export async function loadCities(commCodes, weights) {
  if (!commCodes?.length) {
    return { geojson: { type: 'FeatureCollection', features: [] }, rows: [], minScore: 0, maxScore: 1 }
  }

  // Fetch sequentially to avoid concurrent queries on single DuckDB connection.
  // Cache hits are synchronous, so re-selections are instant.
  const allRows = []
  for (const code of commCodes) {
    const rows = await fetchCityData(code)
    allRows.push(...rows)
  }

  const { rows, minScore, maxScore } = computeScores(allRows, weights)

  const geojson = await new Promise((resolve, reject) => {
    const worker = getH3Worker()
    const onMsg = ({ data }) => {
      worker.removeEventListener('message', onMsg)
      worker.removeEventListener('error', onErr)
      resolve({ type: 'FeatureCollection', features: data.features })
    }
    const onErr = err => {
      worker.removeEventListener('message', onMsg)
      worker.removeEventListener('error', onErr)
      reject(err)
    }
    worker.addEventListener('message', onMsg)
    worker.addEventListener('error', onErr)
    worker.postMessage({ rows })
  })

  return { geojson, rows, minScore, maxScore }
}

// ── GeoArrow struct → GeoJSON geometry ──────────────────
// arrow::write_parquet() on an sf object stores geometry as GeoArrow native:
// STRUCT(x DOUBLE, y DOUBLE)[][][] = [polygon][ring][point].
// DuckDB's to_json() serializes this as [[[{x,y},...],...],...] for JS parsing.
function structToGeoJSON(jsonStr) {
  if (!jsonStr) return null
  try {
    const data = JSON.parse(jsonStr)
    if (!Array.isArray(data) || data.length === 0) return null
    const rings2d = rings => rings.map(ring => ring.map(pt => [pt.x, pt.y]))
    if (data.length === 1) {
      return { type: 'Polygon', coordinates: rings2d(data[0]) }
    }
    return { type: 'MultiPolygon', coordinates: data.map(poly => rings2d(poly)) }
  } catch { return null }
}

// ── Municipal boundaries — loaded once from parquet, like R Shiny's cities_sf ─
let _munCache = null

export async function loadMunicipalData() {
  if (_munCache) return _munCache
  const conn = await getConn()
  const url = `${DATA_BASE_URL}/UtahMunicipalBoundaries.parquet`
  const table = await conn.query(
    `SELECT "UGRCODE", "NAME", CAST(to_json("geometry") AS VARCHAR) AS geom_json FROM read_parquet('${url}') ORDER BY "NAME"`
  )
  const rows = tableToRows(table)
  const features = rows
    .map(r => {
      const geom = structToGeoJSON(r.geom_json)
      return geom
        ? { type: 'Feature', geometry: geom, properties: { UGRCODE: String(r.UGRCODE), NAME: String(r.NAME) } }
        : null
    })
    .filter(Boolean)
  _munCache = {
    cities:  rows.map(r => ({ value: String(r.UGRCODE), label: String(r.NAME) })),
    geojson: { type: 'FeatureCollection', features },
  }
  return _munCache
}
