<template>
  <nav id="navbar">
    <img :src="logoUrl" alt="WFRC" />
    <span>Wasatch Front Housing Site Evaluator</span>
    <div id="navbar-links">
      <a
        href="https://github.com/WFRCAnalytics/MAP-Housing-ATO-Calculator-Updated/blob/main/README.md"
        target="_blank"
        rel="noopener noreferrer"
        title="Documentation"
      >
        <i class="fa-regular fa-file-lines"></i> Documentation
      </a>
      <a
        class="icon-only"
        href="https://github.com/WFRCAnalytics/MAP-Housing-ATO-Calculator-Updated"
        target="_blank"
        rel="noopener noreferrer"
        title="GitHub Repository"
        aria-label="GitHub Repository"
      >
        <i class="fa-brands fa-github"></i>
      </a>
    </div>
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
      <Legend :hasData="hasData" />
      <LayerControl :layerVisible="layerVisible" @toggle-layer="onToggleLayer" />
      <div id="loading-overlay" v-if="isLoading">
        <div class="loading-spinner"></div>
        <div class="loading-text">{{ loadingText }}</div>
      </div>
    </div>
  </div>

  <SplashModal v-if="showSplash" @close="showSplash = false" />
  <DownloadModal v-if="showDownload" @close="showDownload = false" />
  <div id="global-tooltip"></div>
</template>

<script setup>
import { ref, reactive, provide, watch, onMounted } from 'vue'
const logoUrl = `${import.meta.env.BASE_URL}logo.png`
import Sidebar from './components/Sidebar.vue'
import MapControls from './components/MapControls.vue'
import LayerControl from './components/LayerControl.vue'
import Tooltip from './components/Tooltip.vue'
import SplashModal from './components/SplashModal.vue'
import DownloadModal from './components/DownloadModal.vue'
import Legend from './components/Legend.vue'
import { initMap, setExtentBounds } from './composables/useMap.js'
import { loadCities, loadMunicipalData } from './composables/useData.js'
import { computeScores, buildColorExpression, buildExtrusionExpr } from './composables/useScoring.js'
import { toggleLayer } from './composables/useLayers.js'
import { SLIDER_DEFS, SCORE_COLS } from './config/sliders.js'
import { LU_MAPPINGS } from './config/landUse.js'

// ── State ──────────────────────────────────────────────
const weights = reactive(
  Object.fromEntries(SLIDER_DEFS.map(d => [d.col, 0.5]))
)
const layerVisible = reactive({
  'roads-major': false,
  'h3-heatmap': true,
  'city-bounds': true,
  w_CM: false, w_CU: false, w_CC: false, w_CN: false,
  w_AA: false, w_AT: false, w_TT: false, w_TF: false, w_TA: false,
  w_AC: false, w_AH: false, w_AE: false, w_AG: false, w_AM: false, w_AP: false,
})

const cities = ref([])
const selectedCommCodes = ref([])
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
let allMunicipalities = null // { cities, geojson } from parquet — R Shiny's cities_sf
let roadsMajorLayerIds = []

// Both LiteBase's roads/buildings AND LiteLabels' roads/buildings vector tiles
// share these source-layer names (LiteLabels' road *labels* use a "…/label"
// suffixed variant instead, so they never match here — see setRoadsOnTop).
const ROAD_SOURCE_LAYERS = ['Roads - white version', 'Roads - Interstates and Ramps - white version']

// Where our custom overlays (hexagons, boundaries, the Major Roads redraw)
// must stop, layer-order-wise: above UGRC's actual map geometry (roads,
// buildings, water, parks, …) but below every label/sprite — not just
// LiteLabels' text, but LiteBase's own POI/transit icons too, which render
// (within LiteBase's own style) AFTER its roads/buildings but BEFORE
// LiteLabels starts. A plain "first labels__ layer" boundary (LiteLabels
// only) misses that LiteBase icon band entirely, letting our overlays cover
// things like TRAX station markers — see git history/PR discussion for the
// screenshot that caught it.
function firstOverlayCeilingId(style) {
  const layers = style.layers
  const lastRoadOrBuildingIdx = layers.reduce((max, l, i) => {
    const matches = ROAD_SOURCE_LAYERS.includes(l['source-layer']) || l['source-layer'] === 'Buildings'
    return matches ? i : max
  }, -1)
  // Every label/sprite layer (LiteBase's or LiteLabels') is styled as
  // MapLibre type "symbol" — real map features (fill/line/circle) aren't —
  // so the first symbol layer after the roads/buildings band is the top of
  // that band, regardless of which service authored it or how UGRC reorders
  // its own style in the future.
  return layers.find((l, i) => i > lastRoadOrBuildingIdx && l.type === 'symbol')?.id
}

// ── Map init ───────────────────────────────────────────
onMounted(async () => {
  mapInstance = await initMap('map')
  mapInstance.on('style.load', async () => {
    setupMapLayers()
    mapReady.value = true
    await fetchCities()
  })
})

function setupMapLayers() {
  const map = mapInstance
  const style = map.getStyle()

  // Insert all our data layers below every label/sprite (see
  // firstOverlayCeilingId) so they always render on top of hexagons/roads.
  // LiteBase's own roads stay exactly as UGRC authored them (labels already
  // on top natively) — see setRoadsOnTop() below for the toggleable "redraw
  // above the hexagons" duplicate.
  const firstLabelId = firstOverlayCeilingId(style)

  // ── Municipality background (clickable for city selection) ──────────────
  map.addSource('src-all-municipalities', { type: 'geojson', data: { type: 'FeatureCollection', features: [] } })
  map.addLayer({
    id: 'all-mun-fill', type: 'fill', source: 'src-all-municipalities',
    paint: { 'fill-color': '#88aacc', 'fill-opacity': 0.06 },
  }, firstLabelId)
  map.addLayer({
    id: 'all-mun-line', type: 'line', source: 'src-all-municipalities',
    paint: { 'line-color': '#233A57', 'line-width': 1, 'line-opacity': 0.6 },
  }, firstLabelId)

  map.on('mouseenter', 'all-mun-fill', () => { map.getCanvas().style.cursor = 'pointer' })
  map.on('mouseleave', 'all-mun-fill', () => { map.getCanvas().style.cursor = '' })
  map.on('click', (e) => {
    const munHits = map.queryRenderedFeatures(e.point, { layers: ['all-mun-fill'] })
    if (munHits.length) sidebarRef.value?.toggleCity(String(munHits[0].properties.UGRCODE))
  })

  // ── Selected city boundaries ────────────────────────────────────────────
  map.addSource('src-cities', { type: 'geojson', data: { type: 'FeatureCollection', features: [] } })
  map.addLayer({
    id: 'lay_cities_fill', type: 'fill', source: 'src-cities',
    paint: {
      'fill-color': '#CCCCCC',
      'fill-opacity': ['interpolate', ['linear'], ['zoom'], 12, 0.3, 15, 0.0],
    },
  }, firstLabelId)

  // ── H3 hexagons ─────────────────────────────────────────────────────────
  map.addSource('h3-source', {
    type: 'geojson',
    data: { type: 'FeatureCollection', features: [] },
    generateId: true,
  })
  map.addLayer({
    id: 'h3_layer_2d', type: 'fill', source: 'h3-source',
    paint: { 'fill-color': '#cccccc', 'fill-opacity': 0.8 },
  }, firstLabelId)
  map.addLayer({
    id: 'h3_layer_3d', type: 'fill-extrusion', source: 'h3-source',
    layout: { visibility: 'none' },
    paint: { 'fill-extrusion-color': '#cccccc', 'fill-extrusion-height': 0, 'fill-extrusion-opacity': 0.8 },
  }, firstLabelId)

  // ── Selected city border line (above hexagons, below roads) ────────────
  // A white halo underneath keeps the outline crisp against both the
  // colorful heatmap and UGRC's lighter basemap — the plain line alone
  // read as washed-out ("dimmed") against it.
  map.addLayer({
    id: 'lay_cities_line_halo', type: 'line', source: 'src-cities',
    paint: { 'line-color': '#ffffff', 'line-width': 6, 'line-opacity': 0.85 },
  }, firstLabelId)
  map.addLayer({
    id: 'lay_cities_line', type: 'line', source: 'src-cities',
    paint: { 'line-color': '#233A57', 'line-width': 3, 'line-opacity': 1 },
  }, firstLabelId)

  // Move UGRC building layers below our bottommost custom layer so they
  // render under municipal boundaries and H3 hexagons.
  style.layers
    .filter(l => l['source-layer'] === 'Buildings')
    .forEach(l => {
      try { map.moveLayer(l.id, 'all-mun-fill') } catch {}
    })

  // Match the "Major Roads" toggle's default (see layerVisible) — roads
  // stay in their normal authored position otherwise.
  setRoadsOnTop(layerVisible['roads-major'])
}

// ── Roads — toggleable duplicate above the H3 hexagons, below labels ────
// LiteBase's roads render in their normal, correctly-authored position
// (under labels, under our hexagon overlay) unless this is on. Rather than
// permanently hiding + duplicating every road (which fought LiteBase's own
// label ordering — see git history for the mess that caused), the
// duplicate now only exists while toggled on: cloned from UGRC's OWN
// road-casing layers (real colors/widths/zoom bands) for MAJOR roads only
// — everything else (ramps/collectors, local roads) is left untouched, in
// its normal position. Toggling off removes the clones and restores the
// originals.
function setRoadsOnTop(visible) {
  const map = mapInstance
  if (!map) return
  // Every road class is distinguished by a numeric `_symbol` code
  // (confirmed against the real LiteBase style.json): 0 Interstates,
  // 1 Ramps/Collectors, 2 US Highways, 3 State Highways, 4 Major Local
  // Roads Paved (UGRC's nearest equivalent to "arterial"), 5 Major Local
  // Roads Not Paved, 6 Other Federal Aid Roads, 7 Local Roads. Interstate/
  // US/state highway/arterial count as "major," plus ramps/collectors —
  // excluding those would leave a visible gap in the highlight at every
  // interchange, since a ramp is a separate `_symbol` from the mainline
  // it connects to.
  const MAJOR_ROAD_SYMBOLS = [0, 1, 2, 3, 4]

  if (visible) {
    if (roadsMajorLayerIds.length) return // already shown
    const style = map.getStyle()
    const firstLabelId = firstOverlayCeilingId(style)
    // Both source-layers are included — "Roads - Interstates and Ramps -
    // white version" is an extra-wide highlight UGRC draws underneath the
    // standard casing/fill from "Roads - white version" specifically for
    // Interstates; cloning only the latter (a prior bug) left interstates
    // visibly thinner than UGRC's own combined styling.
    const majors = style.layers.filter(
      l => ROAD_SOURCE_LAYERS.includes(l['source-layer']) && MAJOR_ROAD_SYMBOLS.includes(l.filter?.[2])
    )
    majors.forEach(l => {
      try { map.setLayoutProperty(l.id, 'visibility', 'none') } catch {}
    })
    try {
      majors.forEach(l => {
        const id = `redraw__${l.id}`
        map.addLayer({ ...l, id }, firstLabelId)
        roadsMajorLayerIds.push(id)
      })
    } catch (e) {
      console.warn('UGRC road redraw layers unavailable:', e)
    }
  } else {
    roadsMajorLayerIds.forEach(id => {
      if (map.getLayer(id)) map.removeLayer(id)
    })
    roadsMajorLayerIds = []
    // Re-fetch now that the clones are gone — filtering the pre-removal
    // snapshot here would also match the (now-removed) clones, since they
    // carry the same original `source-layer` value, and MapLibre errors
    // trying to restyle a layer id that no longer exists.
    map.getStyle().layers
      .filter(l => ROAD_SOURCE_LAYERS.includes(l['source-layer']) && MAJOR_ROAD_SYMBOLS.includes(l.filter?.[2]))
      .forEach(l => {
        try { map.setLayoutProperty(l.id, 'visibility', 'visible') } catch {}
      })
  }
}

// ── City picker + background boundary layer ────────────
// Mirrors R Shiny: cities_sf loaded once from UtahMunicipalBoundaries.parquet,
// used for both the community dropdown and the clickable boundary layer.
async function fetchCities() {
  try {
    isLoading.value = true
    loadingText.value = 'Loading communities...'
    allMunicipalities = await loadMunicipalData()
    cities.value = allMunicipalities.cities
    mapInstance?.getSource('src-all-municipalities')?.setData(allMunicipalities.geojson)
  } catch (e) {
    console.error('Failed to load municipalities:', e)
  } finally {
    isLoading.value = false
  }
}

// ── City selection ─────────────────────────────────────
async function onCitiesChange(commCodes) {
  selectedCommCodes.value = commCodes ?? []
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

function fetchCityBoundaries(commCodes) {
  if (!allMunicipalities) return
  const codeSet = new Set(commCodes.map(String))
  const features = allMunicipalities.geojson.features.filter(
    f => codeSet.has(String(f.properties.UGRCODE))
  )
  mapInstance?.getSource('src-cities')?.setData({ type: 'FeatureCollection', features })
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
  const bounds = [[minLng, minLat], [maxLng, maxLat]]
  setExtentBounds(bounds)
  mapInstance.fitBounds(bounds, { padding: 40, maxZoom: 13, duration: 800 })
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
    setRoadsOnTop(newVis)
  } else if (id === 'h3-heatmap') {
    const activeLayer = is3D.value ? 'h3_layer_3d' : 'h3_layer_2d'
    if (map.getLayer(activeLayer)) {
      map.setLayoutProperty(activeLayer, 'visibility', newVis ? 'visible' : 'none')
    }
  } else if (id === 'city-bounds') {
    const vis = newVis ? 'visible' : 'none'
    if (map.getLayer('all-mun-fill')) map.setLayoutProperty('all-mun-fill', 'visibility', vis)
    if (map.getLayer('all-mun-line')) map.setLayoutProperty('all-mun-line', 'visibility', vis)
    if (map.getLayer('lay_cities_fill')) map.setLayoutProperty('lay_cities_fill', 'visibility', vis)
    if (map.getLayer('lay_cities_line_halo')) map.setLayoutProperty('lay_cities_line_halo', 'visibility', vis)
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
  mapInstance.once('render', () => {
    const mapCanvas = mapInstance.getCanvas()
    const W = mapCanvas.width
    const H = mapCanvas.height
    const dpr = window.devicePixelRatio || 1
    const hdrH = Math.round(75 * dpr)

    const out = document.createElement('canvas')
    out.width = W
    out.height = H + hdrH
    const ctx = out.getContext('2d')

    // ── Header ───────────────────────────────────────
    ctx.fillStyle = '#233A57'
    ctx.fillRect(0, 0, W, hdrH)

    const pad = Math.round(14 * dpr)
    ctx.fillStyle = '#ffffff'
    ctx.font = `bold ${Math.round(24 * dpr)}px Oswald, Arial, sans-serif`
    ctx.textBaseline = 'alphabetic'
    ctx.fillText('Wasatch Front Housing Site Evaluator', pad, Math.round(34 * dpr))

    const cityNames = selectedCommCodes.value
      .map(c => allMunicipalities?.cities.find(x => x.value === c)?.label ?? c)
      .join(', ')
    if (cityNames) {
      ctx.font = `${Math.round(18 * dpr)}px Arial, sans-serif`
      ctx.fillStyle = 'rgba(255,255,255,0.75)'
      // Truncate if too wide
      let label = cityNames
      while (label.length > 4 && ctx.measureText(label).width > W - pad * 2) {
        label = label.slice(0, -4) + '…'
      }
      ctx.fillText(label, pad, Math.round(62 * dpr))
    }

    // ── Map ──────────────────────────────────────────
    ctx.drawImage(mapCanvas, 0, hdrH)

    // ── Legend ───────────────────────────────────────
    if (hasData.value) {
      const PALETTE = ['#EDF8B1', '#C7E9B4', '#7FCDBB', '#41B6C4', '#1D91C0', '#225EA8']
      const LABELS  = ['0.00', '0.20', '0.40', '0.60', '0.80', '1.00']
      const s   = Math.round(20 * dpr)
      const gap = Math.round(5 * dpr)
      const lp  = Math.round(12 * dpr)
      const titleH = Math.round(21 * dpr)
      const boxW = lp + s + Math.round(45 * dpr) + lp
      const boxH = lp + titleH + PALETTE.length * (s + gap) - gap + lp
      const bx = Math.round(10 * dpr)
      const by = H + hdrH - boxH - Math.round(10 * dpr)

      ctx.fillStyle = 'rgba(255,255,255,0.92)'
      ctx.beginPath()
      if (ctx.roundRect) {
        ctx.roundRect(bx, by, boxW, boxH, Math.round(4 * dpr))
      } else {
        ctx.rect(bx, by, boxW, boxH)
      }
      ctx.fill()

      ctx.fillStyle = '#233A57'
      ctx.font = `bold ${Math.round(14 * dpr)}px Oswald, Arial, sans-serif`
      ctx.textBaseline = 'top'
      ctx.fillText('SITE INDEX', bx + lp, by + lp)

      PALETTE.forEach((color, i) => {
        const iy = by + lp + titleH + i * (s + gap)
        ctx.fillStyle = color
        ctx.fillRect(bx + lp, iy, s, s)
        ctx.fillStyle = '#333333'
        ctx.font = `${Math.round(14 * dpr)}px Arial, sans-serif`
        ctx.textBaseline = 'middle'
        ctx.fillText(LABELS[i], bx + lp + s + Math.round(4 * dpr), iy + s / 2)
      })
    }

    // ── Download ─────────────────────────────────────
    const link = document.createElement('a')
    link.href = out.toDataURL('image/png')
    link.download = 'HousingSiteEvaluator_Map.png'
    link.click()
  })
  mapInstance.triggerRepaint()
}
</script>
