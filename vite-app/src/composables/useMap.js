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
