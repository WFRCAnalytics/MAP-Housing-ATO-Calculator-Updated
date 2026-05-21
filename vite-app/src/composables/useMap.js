import maplibregl from 'maplibre-gl'
import { MAP_CENTER, MAP_ZOOM } from '../config/constants.js'

let mapInstance = null

export function initMap(containerId) {
  mapInstance = new maplibregl.Map({
    container: containerId,
    style: 'https://basemaps.cartocdn.com/gl/voyager-gl-style/style.json',
    center: MAP_CENTER,
    zoom: MAP_ZOOM,
    preserveDrawingBuffer: true,
  })

  mapInstance.addControl(new maplibregl.NavigationControl(), 'top-left')
  mapInstance.addControl(new maplibregl.ScaleControl({ unit: 'imperial' }), 'bottom-left')
  mapInstance.addControl(new maplibregl.GeolocateControl({ trackUserLocation: false }), 'top-left')

  return mapInstance
}

export function getMap() {
  return mapInstance
}

export function setupBaseLayers(map, citiesGeojson) {
  // City boundaries fill (bottom)
  if (citiesGeojson) {
    map.addSource('src-cities', { type: 'geojson', data: citiesGeojson })
    map.addLayer({
      id: 'lay_cities_fill',
      type: 'fill',
      source: 'src-cities',
      paint: {
        'fill-color': '#CCCCCC',
        'fill-opacity': ['interpolate', ['linear'], ['zoom'], 12, 0.5, 15, 0.0],
      },
    })
  }

  // Carto vector major roads overlay (separate, toggleable)
  // Voyager style source name: inspect map.getStyle().sources after load
  // The source containing 'transportation' layer is typically 'carto' or 'openmaptiles'
  try {
    const sources = map.getStyle().sources
    const cartoSource = Object.keys(sources).find(k => {
      const s = sources[k]
      return s.type === 'vector' && (k === 'carto' || k === 'openmaptiles' || k.includes('carto'))
    }) || 'carto'

    map.addLayer({
      id: 'roads-major',
      type: 'line',
      source: cartoSource,
      'source-layer': 'transportation',
      filter: ['in', ['get', 'class'], ['literal', ['motorway', 'trunk', 'primary', 'secondary']]],
      paint: {
        'line-color': [
          'match', ['get', 'class'],
          'motorway', '#e892a2',
          'trunk', '#f9b29c',
          '#bbbbbb',
        ],
        'line-width': ['interpolate', ['linear'], ['zoom'], 7, 0.5, 12, 1.5, 16, 4],
        'line-opacity': ['interpolate', ['linear'], ['zoom'], 13, 0.9, 14, 0.0],
      },
    })
  } catch (e) {
    console.warn('Could not add Carto roads layer:', e)
  }

  // Empty H3 GeoJSON source
  map.addSource('h3-source', {
    type: 'geojson',
    data: { type: 'FeatureCollection', features: [] },
    generateId: true,
  })

  // 2D fill layer
  map.addLayer({
    id: 'h3_layer_2d',
    type: 'fill',
    source: 'h3-source',
    paint: {
      'fill-color': '#cccccc',
      'fill-opacity': 0.8,
    },
  })

  // 3D extrusion layer (hidden initially)
  map.addLayer({
    id: 'h3_layer_3d',
    type: 'fill-extrusion',
    source: 'h3-source',
    layout: { visibility: 'none' },
    paint: {
      'fill-extrusion-color': '#cccccc',
      'fill-extrusion-height': 0,
      'fill-extrusion-opacity': 0.8,
    },
  })

  // City boundary line (top)
  if (citiesGeojson) {
    map.addLayer({
      id: 'lay_cities_line',
      type: 'line',
      source: 'src-cities',
      paint: {
        'line-color': '#999999',
        'line-width': 1.5,
        'line-opacity': 0.5,
      },
    })
  }
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
