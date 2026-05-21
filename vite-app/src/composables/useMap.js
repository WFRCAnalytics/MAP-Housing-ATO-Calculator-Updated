import maplibregl from 'maplibre-gl'
import MaplibreGeocoder from '@maplibre/maplibre-gl-geocoder'
import '@maplibre/maplibre-gl-geocoder/dist/maplibre-gl-geocoder.css'
import { MAP_CENTER, MAP_ZOOM } from '../config/constants.js'

let mapInstance = null
let _extentBounds = null

export function setExtentBounds(bounds) {
  _extentBounds = bounds
}

// ── Nominatim geocoder API ────────────────────────────
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


export function initMap(containerId) {
  mapInstance = new maplibregl.Map({
    container: containerId,
    style: 'https://basemaps.cartocdn.com/gl/voyager-gl-style/style.json',
    center: MAP_CENTER,
    zoom: MAP_ZOOM,
    preserveDrawingBuffer: true,
  })

  // top-left — order determines top-to-bottom stacking (first = topmost)
  // 1. Address search
  mapInstance.addControl(
    new MaplibreGeocoder(nominatimApi, {
      maplibregl,
      placeholder: 'Search address…',
      proximity: { longitude: MAP_CENTER[0], latitude: MAP_CENTER[1] },
      flyTo: { duration: 1500 },
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
