// v6 dropped the default export (ESM-only build) — namespace import instead.
import * as maplibregl from 'maplibre-gl'
// v6's worker is loaded from a URL it derives from import.meta.url at
// runtime, which "doesn't reliably resolve to the worker file inside the
// bundler's module graph" (MapLibre's own v5→v6 migration guide) — under
// Vite specifically it resolves to our bundled chunk's own URL and 404s.
// The guide's documented Vite fix: import the worker through `?worker&url`
// (NOT plain `?url` — the worker imports a sibling maplibre-gl-shared.mjs,
// which `?worker&url` bundles alongside it into one self-contained chunk;
// plain `?url` emits the worker file alone and it fails on that import) and
// point the library at it explicitly before creating any Map.
import maplibreWorkerUrl from 'maplibre-gl/dist/maplibre-gl-worker.mjs?worker&url'
import MaplibreGeocoder from '@maplibre/maplibre-gl-geocoder'
import '@maplibre/maplibre-gl-geocoder/dist/maplibre-gl-geocoder.css'
import { MAP_CENTER, MAP_ZOOM } from '../config/constants.js'
import { buildUgrcLiteStyle } from './ugrcBasemap.js'

maplibregl.setWorkerUrl(maplibreWorkerUrl)

let mapInstance = null
let _extentBounds = null

export function setExtentBounds(bounds) {
  _extentBounds = bounds
}

// ── Nominatim geocoder API — place/POI search, used as a fallback ────
const nominatimApi = {
  forwardGeocode: async (config) => {
    try {
      const url = `https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(config.query)}&format=geojson&limit=5&countrycodes=us&viewbox=-114.05,42.0,-109.04,36.99&bounded=1`
      const res = await fetch(url, { headers: { 'Accept-Language': 'en' } })
      const geojson = await res.json()
      return {
        features: geojson.features.map(f => {
          const bbox = f.bbox
          const center = bbox
            ? [(bbox[0] + bbox[2]) / 2, (bbox[1] + bbox[3]) / 2]
            : f.geometry.coordinates
          return {
            type: 'Feature',
            geometry: { type: 'Point', coordinates: center },
            place_name: f.properties.display_name,
            text: f.properties.display_name,
            place_type: ['place'],
            center,
            bbox,
          }
        }),
      }
    } catch { return { features: [] } }
  },
}

// ── UGRC geocoder API — via AGRC's "masquerade" proxy, which impersonates
// an Esri locator (findAddressCandidates/suggest) in front of UGRC data.
// Public, unauthenticated, CORS-enabled — no API key needed.
// https://github.com/agrc/masquerade
const MASQUERADE_URL = 'https://masquerade.ugrc.utah.gov/arcgis/rest/services/UtahLocator/GeocodeServer'

function candidatesToFeatures(candidates) {
  return candidates.map(c => {
    const center = [c.location.x, c.location.y]
    return {
      type: 'Feature',
      geometry: { type: 'Point', coordinates: center },
      place_name: c.address,
      text: c.address,
      place_type: ['address'],
      center,
    }
  })
}

async function findAddressCandidates(text, magicKey) {
  const params = new URLSearchParams({ SingleLine: text, outSR: '4326', f: 'json' })
  if (magicKey) params.set('magicKey', magicKey)
  const res = await fetch(`${MASQUERADE_URL}/findAddressCandidates?${params}`)
  const body = await res.json()
  return body.candidates ?? []
}

async function suggest(text, signal) {
  const params = new URLSearchParams({ text, f: 'json' })
  const res = await fetch(`${MASQUERADE_URL}/suggest?${params}`, { signal })
  const { suggestions = [] } = await res.json()
  return suggestions
}

// suggest() only returns {text, magicKey} pairs, not coordinates — the text
// is needed again alongside the magicKey to resolve a candidate, but
// maplibre-gl-geocoder's searchByPlaceId only hands back the magicKey (see
// getSuggestions/searchByPlaceId below). Stash the pairing here so selection
// can look it up instead of re-querying.
const magicKeyToText = new Map()

// Cancel a still-in-flight suggest() when the user keeps typing, instead of
// letting it resolve later and stomp newer results — also keeps typing
// bursts from piling up parallel requests against masquerade's connection
// limit.
let suggestAbortController = null

// A call that's already past the (abortable) suggest() fetch can still be
// sitting in the slower, non-abortable Nominatim fallback below when a
// newer keystroke supersedes it. Track a sequence number so any call can
// tell, right before it would render, whether it's still the latest —
// otherwise it never resolves rather than overwriting newer results.
let requestSeq = 0

const ugrcApi = {
  // Runs on every keystroke (maplibre-gl-geocoder debounces ~200ms). Only
  // hits the cheap /suggest endpoint — no coordinate resolution — so typing
  // stays fast. Coordinates are resolved lazily, once, only for the single
  // suggestion the user actually picks (searchByPlaceId, below).
  getSuggestions: async (config) => {
    const seq = ++requestSeq
    suggestAbortController?.abort()
    const controller = new AbortController()
    suggestAbortController = controller

    let suggestions = []
    try {
      suggestions = await suggest(config.query, controller.signal)
    } catch { /* aborted or network error — fall through to empty */ }

    // Superseded by a newer keystroke while we were waiting — never
    // resolve, so this stale response can't stomp whatever the newer call
    // has already rendered (or is about to).
    if (seq !== requestSeq) return new Promise(() => {})

    if (suggestions.length) {
      suggestions.forEach(s => magicKeyToText.set(s.magicKey, s.text))
      return { suggestions: suggestions.slice(0, 5).map(s => ({ text: s.text, placeId: s.magicKey })) }
    }

    // No UGRC suggestions (e.g. a business/POI name UGRC doesn't index) —
    // fall back to Nominatim, whose results already carry full geometry, so
    // picking one needs no further round trip.
    const { features } = await nominatimApi.forwardGeocode(config)
    if (seq !== requestSeq) return new Promise(() => {})

    // Nominatim does full-text search, not prefix completion, so it's
    // often blank for a still-incomplete word (e.g. "...Jack" before
    // "Jackson" is finished) even though the address is real. Leave
    // whatever suggestions are already showing rather than flashing "No
    // results found" mid-word — Enter still runs the fuller forwardGeocode
    // lookup for a definitive answer.
    if (!features.length) return new Promise(() => {})
    return { suggestions: features }
  },

  // Called once, only when the user picks a UGRC suggestion from the list.
  searchByPlaceId: async (config) => {
    const magicKey = config.query
    const text = magicKeyToText.get(magicKey) ?? ''
    const candidates = await findAddressCandidates(text, magicKey)
    return { features: candidatesToFeatures(candidates) }
  },

  // Only reached when the user types a complete address and hits Enter
  // without picking a suggestion first.
  forwardGeocode: async (config) => {
    try {
      // A complete "street, city/zip" query resolves directly.
      let candidates = await findAddressCandidates(config.query)

      // Partial text or a bare place name (e.g. "Sugar House") needs the
      // suggest endpoint, then a follow-up lookup per suggestion (via its
      // magicKey) to get coordinates.
      if (!candidates.length) {
        const suggestions = await suggest(config.query)
        const resolved = await Promise.all(
          suggestions.slice(0, 5).map(s => findAddressCandidates(s.text, s.magicKey))
        )
        candidates = resolved.flat()
      }

      if (candidates.length) return { features: candidatesToFeatures(candidates) }
    } catch { /* fall through to Nominatim */ }

    // No UGRC match — fall back to Nominatim.
    return nominatimApi.forwardGeocode(config)
  },
}

// ── Custom: zoom to current selection extent ──────────
class ZoomToExtentControl {
  onAdd(map) {
    this._map = map
    this._container = document.createElement('div')
    this._container.className = 'maplibregl-ctrl maplibregl-ctrl-group'
    const btn = document.createElement('button')
    btn.title = 'Zoom to selected area'
    btn.setAttribute('aria-label', 'Zoom to selected area')
    btn.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="15 3 21 3 21 9"></polyline><polyline points="9 21 3 21 3 15"></polyline><line x1="21" y1="3" x2="14" y2="10"></line><line x1="3" y1="21" x2="10" y2="14"></line></svg>`
    btn.onclick = () => {
      if (_extentBounds) {
        map.fitBounds(_extentBounds, { padding: 40, maxZoom: 13, duration: 800 })
      }
    }
    this._container.appendChild(btn)
    return this._container
  }
  onRemove() { this._container.parentNode?.removeChild(this._container); this._map = null }
}

// ── Custom: reset bearing + pitch to orthogonal ───────
class TiltResetControl {
  onAdd(map) {
    this._container = document.createElement('div')
    this._container.className = 'maplibregl-ctrl maplibregl-ctrl-group'
    const btn = document.createElement('button')
    btn.title = 'Reset tilt & north'
    btn.setAttribute('aria-label', 'Reset tilt & north')
    btn.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polygon points="3 11 22 2 13 21 11 13 3 11"></polygon></svg>`
    btn.onclick = () => map.easeTo({ bearing: 0, pitch: 0, duration: 400 })
    this._container.appendChild(btn)
    return this._container
  }
  onRemove() { this._container.parentNode?.removeChild(this._container) }
}


export async function initMap(containerId) {
  const style = await buildUgrcLiteStyle()

  mapInstance = new maplibregl.Map({
    container: containerId,
    style,
    center: MAP_CENTER,
    zoom: MAP_ZOOM,
    preserveDrawingBuffer: true,
  })

  // top-left — order determines top-to-bottom stacking (first = topmost)
  // 1. Address search
  mapInstance.addControl(
    new MaplibreGeocoder(ugrcApi, {
      maplibregl,
      placeholder: 'Search address…',
      proximity: { longitude: MAP_CENTER[0], latitude: MAP_CENTER[1] },
      zoom: 16,
      flyTo: { duration: 1500, maxZoom: 16 },
      showResultsWhileTyping: true,
      minLength: 3,
    }),
    'top-left'
  )
  // 2. Locate me
  mapInstance.addControl(new maplibregl.GeolocateControl({ trackUserLocation: false }), 'top-left')
  // 3. Zoom + compass
  mapInstance.addControl(new maplibregl.NavigationControl(), 'top-left')
  // 4. Reset north + tilt
  mapInstance.addControl(new TiltResetControl(), 'top-left')
  // 5. Zoom to selection extent
  mapInstance.addControl(new ZoomToExtentControl(), 'top-left')

  // bottom-left
  mapInstance.addControl(new maplibregl.ScaleControl({ unit: 'imperial' }), 'bottom-left')

  return mapInstance
}

export function getMap() {
  return mapInstance
}


export function updateH3Data(map, geojson) {
  const src = map.getSource('h3-source')
  if (src) src.setData(geojson)
}

export function clearH3Data(map) {
  const src = map.getSource('h3-source')
  if (src) src.setData({ type: 'FeatureCollection', features: [] })
}

export function fitToCities(map, commCodes, cityGeoJSON) {
  if (!cityGeoJSON || !commCodes?.length) return
  const features = cityGeoJSON.features.filter(f =>
    commCodes.includes(f.properties?.UGRCODE)
  )
  if (!features.length) return
  const bounds = new maplibregl.LngLatBounds()
  features.forEach(f => {
    const coords = f.geometry?.coordinates
    if (!coords) return
    const flat = f.geometry.type === 'Polygon' ? coords[0] :
      f.geometry.type === 'MultiPolygon' ? coords.flatMap(p => p[0]) : []
    flat.forEach(c => bounds.extend(c))
  })
  if (!bounds.isEmpty()) {
    map.fitBounds(bounds, { padding: 40, maxZoom: 13, duration: 800 })
  }
}
