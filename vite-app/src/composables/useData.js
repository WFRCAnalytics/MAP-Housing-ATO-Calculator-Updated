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

// ── WKB hex → GeoJSON geometry (Polygon / MultiPolygon) ──
// R writes sf geometry as WKB binary; DuckDB hex() encodes it for JS parsing.
function wkbToGeoJSON(hexStr) {
  if (!hexStr) return null
  const bytes = new Uint8Array(hexStr.length / 2)
  for (let i = 0; i < bytes.length; i++)
    bytes[i] = parseInt(hexStr.slice(i * 2, i * 2 + 2), 16)
  const dv = new DataView(bytes.buffer)
  let p = 0
  let le = true

  const u8  = () => dv.getUint8(p++)
  const u32 = () => { const v = dv.getUint32(p, le); p += 4; return v }
  const f64 = () => { const v = dv.getFloat64(p, le); p += 8; return v }

  function readGeom() {
    le = u8() === 1
    let type = u32()
    if (type & 0x20000000) { p += 4; type &= ~0x20000000 } // EWKB SRID
    if (type === 3) { // Polygon
      const rings = []
      const nRings = u32()
      for (let i = 0; i < nRings; i++) {
        const n = u32(); const pts = []
        for (let j = 0; j < n; j++) pts.push([f64(), f64()])
        rings.push(pts)
      }
      return { type: 'Polygon', coordinates: rings }
    }
    if (type === 6) { // MultiPolygon
      const n = u32(); const polys = []
      for (let i = 0; i < n; i++) polys.push(readGeom().coordinates)
      return { type: 'MultiPolygon', coordinates: polys }
    }
    return null
  }
  try { return readGeom() } catch { return null }
}

// ── Municipal boundaries — loaded once from parquet, like R Shiny's cities_sf ─
let _munCache = null

export async function loadMunicipalData() {
  if (_munCache) return _munCache
  const conn = await getConn()
  const url = `${DATA_BASE_URL}/UtahMunicipalBoundaries.parquet`
  const table = await conn.query(
    `SELECT "UGRCODE", "NAME", hex("geometry") AS geom_hex FROM read_parquet('${url}') ORDER BY "NAME"`
  )
  const rows = tableToRows(table)
  const features = rows
    .map(r => {
      const geom = wkbToGeoJSON(r.geom_hex)
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
