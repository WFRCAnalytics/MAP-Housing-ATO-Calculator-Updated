import { LAYER_DEFS, WFRC_BBOX } from '../config/layers.js'

const layerCache = new Map()

async function fetchArcGISLayer(def) {
  const urls = def.urls ?? [def.url]
  const limit = def.limit ?? 2000
  const chunkSize = 2000
  const allFeatures = []

  const bboxParam = `&geometry=${WFRC_BBOX}&geometryType=esriGeometryEnvelope&spatialRel=esriSpatialRelIntersects&inSR=4326`

  for (const url of urls) {
    for (let offset = 0; offset < limit; offset += chunkSize) {
      const q = encodeURIComponent(def.query)
      const fullUrl = `${url}/query?where=${q}&outFields=*&f=geojson&outSR=4326&resultOffset=${offset}&resultRecordCount=${chunkSize}${bboxParam}`
      try {
        const r = await fetch(fullUrl)
        const json = await r.json()
        if (json.features?.length) allFeatures.push(...json.features)
        if (!json.features?.length || json.features.length < chunkSize) break
      } catch (e) {
        console.warn(`Failed fetching layer chunk: ${url}`, e)
        break
      }
    }
  }

  return { type: 'FeatureCollection', features: allFeatures }
}

async function getLayerData(layerId) {
  if (layerCache.has(layerId)) return layerCache.get(layerId)
  const data = await fetchArcGISLayer(LAYER_DEFS[layerId])
  layerCache.set(layerId, data)
  return data
}

function addLayerToMap(map, layerId, data) {
  const def = LAYER_DEFS[layerId]
  const srcId = `src_${layerId}`
  const layId = `lay_${layerId}`

  if (!map.getSource(srcId)) {
    map.addSource(srcId, { type: 'geojson', data })
  } else {
    map.getSource(srcId).setData(data)
  }

  if (map.getLayer(layId)) return // already added

  const paint = {}
  if (def.type === 'polygon') {
    const color = def.colorExpr ?? def.color
    map.addLayer({ id: layId, type: 'fill', source: srcId, paint: {
      'fill-color': color,
      'fill-opacity': def.colorExpr ? 0.7 : 0.5,
      'fill-outline-color': 'rgba(0,0,0,0.2)',
    }})
  } else if (def.type === 'line') {
    map.addLayer({ id: layId, type: 'line', source: srcId, paint: {
      'line-color': def.color,
      'line-width': 2,
      'line-opacity': 0.8,
    }})
  } else { // point / circle
    map.addLayer({ id: layId, type: 'circle', source: srcId, paint: {
      'circle-color': def.color,
      'circle-radius': ['interpolate', ['linear'], ['zoom'], 9, 3, 14, 6],
      'circle-opacity': 0.8,
      'circle-stroke-color': 'white',
      'circle-stroke-width': 0.5,
    }})
  }
}

export async function toggleLayer(map, layerId, visible) {
  const layId = `lay_${layerId}`
  if (!visible) {
    if (map.getLayer(layId)) map.removeLayer(layId)
    return
  }
  const data = await getLayerData(layerId)
  addLayerToMap(map, layerId, data)
}

export { LAYER_DEFS }
