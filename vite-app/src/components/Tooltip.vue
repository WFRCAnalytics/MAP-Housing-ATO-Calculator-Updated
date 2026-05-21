<template>
  <Teleport to="#map-area">
    <div id="pinned-tooltip-container" v-if="pinned">
      <div id="pinned-tooltip-header">
        <i class="fa-solid fa-thumbtack"></i> Selected Site
      </div>
      <div
        id="pinned-tooltip-content"
        v-html="pinnedContent || '<div class=\'tooltip-placeholder\'>Click a hexagon to pin its data</div>'"
      ></div>
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
let popup = null
let hoverHandler = null
let leaveHandler = null
let clickHandler = null

function buildHTML(featureProps) {
  const p = featureProps
  const norm = computeNormScore(p, weights, minScore.value, maxScore.value)
  return buildTooltipHTML({ ...p, norm_score: norm })
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
    if (!props.pinned) {
      const html = buildHTML(e.features[0].properties)
      popup.setLngLat(e.lngLat).setHTML(html).addTo(props.map)
    }
  }

  leaveHandler = () => {
    props.map.getCanvas().style.cursor = ''
    if (!props.pinned) popup.remove()
  }

  clickHandler = (e) => {
    if (!props.pinned || !e.features?.length) return
    pinnedContent.value = buildHTML(e.features[0].properties)
  }

  props.map.on('mousemove', 'h3_layer_2d', hoverHandler)
  props.map.on('mouseleave', 'h3_layer_2d', leaveHandler)
  props.map.on('click', 'h3_layer_2d', clickHandler)
})

onUnmounted(() => {
  if (popup) popup.remove()
  if (props.map && hoverHandler) {
    props.map.off('mousemove', 'h3_layer_2d', hoverHandler)
    props.map.off('mouseleave', 'h3_layer_2d', leaveHandler)
    props.map.off('click', 'h3_layer_2d', clickHandler)
  }
})

watch(() => props.pinned, (pinned) => {
  if (!pinned) {
    pinnedContent.value = ''
    popup?.remove()
  }
})
</script>
