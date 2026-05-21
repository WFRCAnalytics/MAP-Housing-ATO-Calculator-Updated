<template>
  <Teleport to="#map-area">
    <div id="pinned-tooltip-container" v-if="pinned">
      <div id="pinned-tooltip-header">
        <i class="fa-solid fa-thumbtack"></i> Site Details
      </div>
      <div id="pinned-tooltip-content" v-html="pinnedContent || placeholder"></div>
    </div>
  </Teleport>
</template>

<script setup>
import { ref, watch, onMounted, onUnmounted, inject } from 'vue'
import maplibregl from 'maplibre-gl'
import { buildTooltipHTML, computeNormScore } from '../composables/useScoring.js'

const props = defineProps({
  map: { type: Object, required: true },
  pinned: { type: Boolean, default: false },
})

const weights = inject('weights')
const minScore = inject('minScore')
const maxScore = inject('maxScore')

const pinnedContent = ref('')
const placeholder = `<div style="padding:20px;text-align:center;color:#999;font-size:0.9rem;"><i class="fa-solid fa-hand-pointer"></i><br>Hover over a hexagon</div>`

let popup = null
let hoverHandler = null
let leaveHandler = null
let hoveredId = null

const H3_LAYERS = ['h3_layer_2d', 'h3_layer_3d']

function buildHTML(featureProps) {
  const norm = computeNormScore(featureProps, weights, minScore.value, maxScore.value)
  return buildTooltipHTML({ ...featureProps, norm_score: norm })
}

function setHover(id, on) {
  if (id == null) return
  props.map.setFeatureState({ source: 'h3-source', id }, { hover: on })
}

onMounted(() => {
  popup = new maplibregl.Popup({
    closeButton: false,
    closeOnClick: false,
    maxWidth: '300px',
    offset: [0, -5],
  })

  hoverHandler = (e) => {
    if (!e.features?.length) return
    props.map.getCanvas().style.cursor = 'pointer'

    const id = e.features[0].id
    if (id !== hoveredId) {
      setHover(hoveredId, false)
      hoveredId = id
      setHover(hoveredId, true)
    }

    const html = buildHTML(e.features[0].properties)
    if (props.pinned) {
      pinnedContent.value = html
    } else {
      popup.setLngLat(e.lngLat).setHTML(html).addTo(props.map)
    }
  }

  leaveHandler = () => {
    props.map.getCanvas().style.cursor = ''
    setHover(hoveredId, false)
    hoveredId = null
    if (props.pinned) {
      pinnedContent.value = ''
    } else {
      popup.remove()
    }
  }

  for (const layer of H3_LAYERS) {
    props.map.on('mousemove', layer, hoverHandler)
    props.map.on('mouseleave', layer, leaveHandler)
  }
})

onUnmounted(() => {
  if (popup) popup.remove()
  if (props.map && hoverHandler) {
    for (const layer of H3_LAYERS) {
      props.map.off('mousemove', layer, hoverHandler)
      props.map.off('mouseleave', layer, leaveHandler)
    }
  }
})

watch(() => props.pinned, (pinned) => {
  if (!pinned) {
    pinnedContent.value = ''
    popup?.remove()
  }
})
</script>
