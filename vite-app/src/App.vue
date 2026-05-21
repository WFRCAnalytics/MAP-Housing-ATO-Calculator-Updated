<template>
  <nav id="navbar">
    <img src="https://wfrc.org/wp-content/uploads/2021/02/WFRC_logo_white.png" alt="WFRC" />
    <span>Housing Site Evaluator</span>
  </nav>

  <div id="app-layout">
    <Sidebar
      ref="sidebarRef"
      :cities="cities"
      :landUse="landUse"
      :ozOnly="ozOnly"
      :layerVisible="layerVisible"
      @update:selectedCities="onCitiesChange"
      @update:landUse="onLandUseChange"
      @update:ozOnly="onOzOnlyChange"
      @toggle-layer="onToggleLayer"
    />

    <div id="map-area">
      <MapControls
        :is3D="is3D"
        :zMult="zMult"
        :pinnedTooltip="pinnedTooltip"
        :hasData="hasData"
        @update:is3D="on3DChange"
        @update:zMult="onZMultChange"
        @update:pinnedTooltip="pinnedTooltip = $event"
        @download="onDownload"
        @screenshot="onScreenshot"
      />
      <div id="map"></div>
      <Tooltip v-if="mapReady" :map="mapInstance" :pinned="pinnedTooltip" />
      <LayerControl :layerVisible="layerVisible" @toggle-layer="onToggleLayer" />
      <div id="loading-overlay" v-if="isLoading">
        <div class="loading-spinner"></div>
        <div class="loading-text">{{ loadingText }}</div>
      </div>
    </div>
  </div>

  <SplashModal v-if="showSplash" @close="showSplash = false" />
  <DownloadModal v-if="showDownload" @close="showDownload = false" />
</template>

<script setup>
import { ref, reactive, provide, watch, onMounted } from 'vue'
import Sidebar from './components/Sidebar.vue'
import MapControls from './components/MapControls.vue'
import LayerControl from './components/LayerControl.vue'
import Tooltip from './components/Tooltip.vue'
import SplashModal from './components/SplashModal.vue'
import DownloadModal from './components/DownloadModal.vue'
import { initMap } from './composables/useMap.js'
import { loadCities, loadMunicipalBoundaries } from './composables/useData.js'
import { computeScores, buildColorExpression, buildExtrusionExpr } from './composables/useScoring.js'
import { toggleLayer } from './composables/useLayers.js'
import { SLIDER_DEFS, SCORE_COLS } from './config/sliders.js'
import { LU_MAPPINGS } from './config/landUse.js'

// ── State ──────────────────────────────────────────────
const weights = reactive(
  Object.fromEntries(SLIDER_DEFS.map(d => [d.col, 0.5]))
)
const layerVisible = reactive({
  'roads-major': true,
  'h3-heatmap': true,
  'city-bounds': true,
  w_CM: false, w_CU: false, w_CC: false, w_CN: false,
  w_AA: false, w_AT: false, w_TT: false, w_TF: false, w_TA: false,
  w_AC: false, w_AH: false, w_AE: false, w_AG: false, w_AM: false, w_AP: false,
})

const cities = ref([])
const landUse = ref('All Land Uses')
const ozOnly = ref(false)
const is3D = ref(false)
const zMult = ref(2)
const pinnedTooltip = ref(false)
const showSplash = ref(true)
const showDownload = ref(false)
const isLoading = ref(false)
const loadingText = ref('Loading...')
const mapReady = ref(false)
const hasData = ref(false)

// ── Provide to children ────────────────────────────────
const minScore = ref(0)
const maxScore = ref(1)
provide('weights', weights)
provide('minScore', minScore)
provide('maxScore', maxScore)

// ── Internal state ─────────────────────────────────────
const sidebarRef = ref(null)
let mapInstance = null
let cachedRows = []
let colorTimer = null

// ── Map init ───────────────────────────────────────────
onMounted(async () => {
  mapInstance = initMap('map')
  mapInstance.on('style.load', async () => {
    setupMapLayers()
    mapReady.value = true
    await fetchCities()
  })
})

function setupMapLayers() {
  const map = mapInstance

  // All municipality boundaries — clickable background layer for city selection
  map.addSource('src-all-municipalities', { type: 'geojson', data: { type: 'FeatureCollection', features: [] } })
  map.addLayer({
    id: 'all-mun-fill',
    type: 'fill',
    source: 'src-all-municipalities',
    paint: { 'fill-color': '#88aacc', 'fill-opacity': 0.06 },
  })
  map.addLayer({
    id: 'all-mun-line',
    type: 'line',
    source: 'src-all-municipalities',
    paint: { 'line-color': '#557799', 'line-width': 0.8, 'line-opacity': 0.45 },
  })

  // Cursor + click for municipality selection
  map.on('mouseenter', 'all-mun-fill', () => { map.getCanvas().style.cursor = 'pointer' })
  map.on('mouseleave', 'all-mun-fill', () => { map.getCanvas().style.cursor = '' })
  map.on('click', (e) => {
    const h3Hits = map.queryRenderedFeatures(e.point, {
      layers: ['h3_layer_2d', 'h3_layer_3d'].filter(l => map.getLayer(l)),
    })
    if (h3Hits.length) return
    const munHits = map.queryRenderedFeatures(e.point, { layers: ['all-mun-fill'] })
    if (munHits.length) {
      sidebarRef.value?.toggleCity(String(munHits[0].properties.UGRCODE))
    }
  })

  // City boundary fill + line (empty initially)
  map.addSource('src-cities', { type: 'geojson', data: { type: 'FeatureCollection', features: [] } })
  map.addLayer({
    id: 'lay_cities_fill',
    type: 'fill',
    source: 'src-cities',
    paint: {
      'fill-color': '#CCCCCC',
      'fill-opacity': ['interpolate', ['linear'], ['zoom'], 12, 0.3, 15, 0.0],
    },
  })

  // Carto major roads overlay
  try {
    const sources = map.getStyle().sources
    const cartoSrc = Object.keys(sources).find(k => {
      const s = sources[k]
      return s.type === 'vector' && (k === 'carto' || k === 'openmaptiles' || k.includes('carto'))
    }) || 'carto'
    map.addLayer({
      id: 'roads-major',
      type: 'line',
      source: cartoSrc,
      'source-layer': 'transportation',
      filter: ['in', ['get', 'class'], ['literal', ['motorway', 'trunk', 'primary', 'secondary']]],
      paint: {
        'line-color': ['match', ['get', 'class'], 'motorway', '#e892a2', 'trunk', '#f9b29c', '#bbbbbb'],
        'line-width': ['interpolate', ['linear'], ['zoom'], 7, 0.5, 12, 1.5, 16, 4],
        'line-opacity': ['interpolate', ['linear'], ['zoom'], 13, 0.9, 14, 0.0],
      },
    })
  } catch (e) {
    console.warn('Carto roads layer unavailable:', e)
  }

  // Empty H3 source
  map.addSource('h3-source', {
    type: 'geojson',
    data: { type: 'FeatureCollection', features: [] },
    generateId: true,
  })

  // 2D fill
  map.addLayer({
    id: 'h3_layer_2d',
    type: 'fill',
    source: 'h3-source',
    paint: { 'fill-color': '#cccccc', 'fill-opacity': 0.8 },
  })

  // 3D extrusion (hidden)
  map.addLayer({
    id: 'h3_layer_3d',
    type: 'fill-extrusion',
    source: 'h3-source',
    layout: { visibility: 'none' },
    paint: { 'fill-extrusion-color': '#cccccc', 'fill-extrusion-height': 0, 'fill-extrusion-opacity': 0.8 },
  })

  // City boundary line (on top)
  map.addLayer({
    id: 'lay_cities_line',
    type: 'line',
    source: 'src-cities',
    paint: { 'line-color': '#555555', 'line-width': 1.5, 'line-opacity': 0.6 },
  })
}

// ── City picker ────────────────────────────────────────
async function fetchCities() {
  try {
    isLoading.value = true
    loadingText.value = 'Loading communities...'
    const [munis] = await Promise.all([
      loadMunicipalBoundaries(),
      loadAllMunicipalBoundaries(),
    ])
    cities.value = munis
  } catch (e) {
    console.error('Failed to load municipalities:', e)
  } finally {
    isLoading.value = false
  }
}

async function loadAllMunicipalBoundaries() {
  const params = new URLSearchParams({
    where: '1=1',
    outFields: 'UGRCODE,NAME',
    f: 'geojson',
    outSR: '4326',
    resultRecordCount: '300',
  })
  try {
    const resp = await fetch(
      `https://services1.arcgis.com/99lidPhWCzftIe9K/ArcGIS/rest/services/UtahMunicipalBoundaries/FeatureServer/0/query?${params}`
    )
    const geojson = await resp.json()
    mapInstance?.getSource('src-all-municipalities')?.setData(geojson)
  } catch (e) {
    console.warn('Failed to load all municipal boundaries:', e)
  }
}

// ── City selection ─────────────────────────────────────
async function onCitiesChange(commCodes) {
  if (!commCodes?.length) {
    cachedRows = []
    hasData.value = false
    minScore.value = 0
    maxScore.value = 1
    clearH3()
    clearCityBounds()
    return
  }
  try {
    isLoading.value = true
    loadingText.value = 'Loading data...'
    const { geojson, rows, minScore: min, maxScore: max } = await loadCities(commCodes, weights)
    cachedRows = rows
    hasData.value = rows.length > 0
    minScore.value = min
    maxScore.value = max
    mapInstance.getSource('h3-source').setData(geojson)
    applyColors()
    fitToH3(geojson)
    fetchCityBoundaries(commCodes)
  } catch (e) {
    console.error('Failed to load city data:', e)
  } finally {
    isLoading.value = false
  }
}

function clearH3() {
  mapInstance?.getSource('h3-source')?.setData({ type: 'FeatureCollection', features: [] })
}

function clearCityBounds() {
  mapInstance?.getSource('src-cities')?.setData({ type: 'FeatureCollection', features: [] })
}

async function fetchCityBoundaries(commCodes) {
  const codes = commCodes.map(c => `'${c}'`).join(',')
  const params = new URLSearchParams({
    where: `UGRCODE IN (${codes})`,
    outFields: 'UGRCODE,NAME',
    f: 'geojson',
    outSR: '4326',
    resultRecordCount: '500',
  })
  const url = `https://services1.arcgis.com/99lidPhWCzftIe9K/ArcGIS/rest/services/UtahMunicipalBoundaries/FeatureServer/0/query?${params}`
  try {
    const resp = await fetch(url)
    const geojson = await resp.json()
    if (geojson.features?.length) {
      mapInstance?.getSource('src-cities')?.setData(geojson)
    }
  } catch (e) {
    console.warn('City boundaries fetch failed:', e)
  }
}

function fitToH3(geojson) {
  if (!geojson.features.length) return
  let minLng = Infinity, minLat = Infinity, maxLng = -Infinity, maxLat = -Infinity
  geojson.features.forEach(f => {
    f.geometry.coordinates[0].forEach(([lng, lat]) => {
      if (lng < minLng) minLng = lng
      if (lat < minLat) minLat = lat
      if (lng > maxLng) maxLng = lng
      if (lat > maxLat) maxLat = lat
    })
  })
  mapInstance.fitBounds([[minLng, minLat], [maxLng, maxLat]], { padding: 40, maxZoom: 13, duration: 800 })
}

// ── Colors ─────────────────────────────────────────────
function applyColors() {
  const map = mapInstance
  if (!map || !cachedRows.length) return
  const { rows, minScore: min, maxScore: max } = computeScores(cachedRows, weights)
  cachedRows = rows
  minScore.value = min
  maxScore.value = max
  const colorExpr = buildColorExpression(weights, min, max)
  if (map.getLayer('h3_layer_2d')) map.setPaintProperty('h3_layer_2d', 'fill-color', colorExpr)
  if (map.getLayer('h3_layer_3d')) {
    map.setPaintProperty('h3_layer_3d', 'fill-extrusion-color', colorExpr)
    map.setPaintProperty('h3_layer_3d', 'fill-extrusion-height', buildExtrusionExpr(weights, zMult.value))
  }
}

function scheduleColorUpdate() {
  if (colorTimer) clearTimeout(colorTimer)
  colorTimer = setTimeout(applyColors, 50)
}

watch(weights, scheduleColorUpdate, { deep: true })

// ── Filters ────────────────────────────────────────────
function applyFilter() {
  const map = mapInstance
  if (!map) return
  const filters = []
  if (landUse.value !== 'All Land Uses') {
    filters.push(['in', ['get', 'BC'], ['literal', LU_MAPPINGS[landUse.value]]])
  }
  if (ozOnly.value) {
    filters.push(['==', ['get', 'OZ'], 1])
  }
  const filter = filters.length === 0 ? null : filters.length === 1 ? filters[0] : ['all', ...filters]
  if (map.getLayer('h3_layer_2d')) map.setFilter('h3_layer_2d', filter)
  if (map.getLayer('h3_layer_3d')) map.setFilter('h3_layer_3d', filter)
}

function onLandUseChange(val) {
  landUse.value = val
  applyFilter()
}

function onOzOnlyChange(val) {
  ozOnly.value = val
  applyFilter()
}

// ── 3D ─────────────────────────────────────────────────
function on3DChange(val) {
  is3D.value = val
  const map = mapInstance
  if (!map) return
  const show = layerVisible['h3-heatmap'] ? 'visible' : 'none'
  if (val) {
    if (map.getLayer('h3_layer_2d')) map.setLayoutProperty('h3_layer_2d', 'visibility', 'none')
    if (map.getLayer('h3_layer_3d')) {
      map.setLayoutProperty('h3_layer_3d', 'visibility', show)
      map.setPaintProperty('h3_layer_3d', 'fill-extrusion-height', buildExtrusionExpr(weights, zMult.value))
    }
    map.easeTo({ pitch: 45, duration: 500 })
  } else {
    if (map.getLayer('h3_layer_3d')) map.setLayoutProperty('h3_layer_3d', 'visibility', 'none')
    if (map.getLayer('h3_layer_2d')) map.setLayoutProperty('h3_layer_2d', 'visibility', show)
    map.easeTo({ pitch: 0, duration: 500 })
  }
}

function onZMultChange(val) {
  zMult.value = val
  if (!is3D.value) return
  const map = mapInstance
  if (map?.getLayer('h3_layer_3d')) {
    map.setPaintProperty('h3_layer_3d', 'fill-extrusion-height', buildExtrusionExpr(weights, val))
  }
}

// ── Layer toggling ─────────────────────────────────────
async function onToggleLayer(id) {
  const newVis = !layerVisible[id]
  layerVisible[id] = newVis
  const map = mapInstance
  if (!map) return

  if (id === 'roads-major') {
    if (map.getLayer('roads-major')) {
      map.setLayoutProperty('roads-major', 'visibility', newVis ? 'visible' : 'none')
    }
  } else if (id === 'h3-heatmap') {
    const activeLayer = is3D.value ? 'h3_layer_3d' : 'h3_layer_2d'
    if (map.getLayer(activeLayer)) {
      map.setLayoutProperty(activeLayer, 'visibility', newVis ? 'visible' : 'none')
    }
  } else if (id === 'city-bounds') {
    const vis = newVis ? 'visible' : 'none'
    if (map.getLayer('lay_cities_fill')) map.setLayoutProperty('lay_cities_fill', 'visibility', vis)
    if (map.getLayer('lay_cities_line')) map.setLayoutProperty('lay_cities_line', 'visibility', vis)
  } else {
    // Reference layers from LAYER_DEFS (centers + metrics)
    try {
      isLoading.value = newVis
      loadingText.value = 'Loading layer...'
      await toggleLayer(map, id, newVis)
    } catch (e) {
      console.error(`Failed to toggle layer ${id}:`, e)
    } finally {
      isLoading.value = false
    }
  }
}

// ── Download ───────────────────────────────────────────
function onDownload() {
  let rows = cachedRows
  if (landUse.value !== 'All Land Uses') {
    rows = rows.filter(r => LU_MAPPINGS[landUse.value].includes(r.BC))
  }
  if (ozOnly.value) {
    rows = rows.filter(r => r.OZ === 1)
  }
  const cols = ['h3_index', 'CommCode', 'BC', 'OZ', ...SCORE_COLS, 'norm_score']
  const header = cols.join(',')
  const body = rows.map(r => cols.map(c => r[c] ?? '').join(',')).join('\n')
  const blob = new Blob([header + '\n' + body], { type: 'text/csv' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = 'HousingSiteEvaluator_Filtered_Data.csv'
  a.click()
  URL.revokeObjectURL(url)
  showDownload.value = true
}

// ── Screenshot ─────────────────────────────────────────
function onScreenshot() {
  if (!mapInstance) return
  const canvas = mapInstance.getCanvas()
  const link = document.createElement('a')
  link.href = canvas.toDataURL('image/png')
  link.download = 'HousingSiteEvaluator_Map.png'
  link.click()
}
</script>
