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
  try {
    await db.instantiate(EH.mainModule)
  } catch (e) {
    // Browser extensions can intercept the wasm fetch and change its MIME type,
    // breaking WebAssembly.instantiateStreaming(). Workaround: fetch as ArrayBuffer,
    // re-wrap in a Blob with the correct type, and use a blob URL instead.
    // Blob URLs are not interceptable by extensions.
    if (!(e instanceof TypeError) || !e.message.includes('MIME type')) throw e
    const resp = await fetch(EH.mainModule)
    const buf = await resp.arrayBuffer()
    const blobUrl = URL.createObjectURL(new Blob([buf], { type: 'application/wasm' }))
    try {
      await db.instantiate(blobUrl)
    } finally {
      URL.revokeObjectURL(blobUrl)
    }
  }
  _conn = await db.connect()
  return _conn
}

// A single AsyncDuckDBConnection isn't safe for overlapping queries — e.g.
// selecting a second city before the first one's query resolves (two
// separate loadCities() calls, each awaiting its own conn.query() in turn)
// let their queries interleave on the connection and come back truncated:
// a 3-city selection silently returned only the first city's rows. Routing
// every query through this FIFO queue serializes them app-wide, regardless
// of how many callers overlap.
let queryQueue = Promise.resolve()
function runQuery(sql) {
  const result = queryQueue.then(async () => {
    const conn = await getConn()
    return conn.query(sql)
  })
  // Keep the chain alive even if this query fails, so one bad/cancelled
  // query doesn't wedge every query queued after it.
  queryQueue = result.then(() => {}, () => {})
  return result
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
// Excludes the `geom` (WKB) column of the H3 partitions; hexagons are built from h3_index.
const CITY_COLS = '"h3_index","CommCode","BC","OZ","AA","AT","TT","TF","TA","AC","AH","AE","AG","AM","AP"'

export async function fetchCityData(commCode) {
  if (cityCache.has(commCode)) return cityCache.get(commCode)
  const url = `${DATA_BASE_URL}/h3_scored/CommCode=${commCode}/part-0.parquet`
  const table = await runQuery(`SELECT ${CITY_COLS} FROM read_parquet('${url}')`)
  const rows = tableToRows(table)
  cityCache.set(commCode, rows)
  return rows
}

// ── H3 Web Worker singleton ───────────────────────────
let h3Worker = null
let h3RequestId = 0

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
    const id = ++h3RequestId
    // The worker is a shared singleton — without matching `id`, selecting a
    // second city before the first one's response arrives would resolve
    // BOTH pending requests off of whichever response lands first (every
    // listener registered on the worker fires on every message, with no
    // way to tell which request it answers), silently handing the larger
    // selection back the smaller one's hexagons.
    const onMsg = ({ data }) => {
      if (data.id !== id) return
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
    worker.postMessage({ rows, id })
  })

  return { geojson, rows, minScore, maxScore }
}

// ── Geometry text → GeoJSON geometry ────────────────────
// Step 4 (_src/export_layers.R) writes each municipality as WKB in `geometry`
// and the same boundary as GeoJSON text in `geojson`, in lon/lat. The WKB is
// for R/QGIS; this app only parses the text.
function parseGeoJSON(jsonStr) {
  if (!jsonStr) return null
  try {
    const geom = JSON.parse(jsonStr)
    return geom?.coordinates?.length ? geom : null
  } catch { return null }
}

// ── Municipal boundaries — loaded once from parquet, like R Shiny's cities_sf ─
let _munCache = null

export async function loadMunicipalData() {
  if (_munCache) return _munCache
  const url = `${DATA_BASE_URL}/UtahMunicipalBoundaries.parquet`
  const table = await runQuery(
    `SELECT "UGRCODE", "NAME", "geojson" FROM read_parquet('${url}') ORDER BY "NAME"`
  )
  const rows = tableToRows(table)
  const features = rows
    .map(r => {
      const geom = parseGeoJSON(r.geojson)
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
