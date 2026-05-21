<template>
  <div v-if="hasData" id="map-legend">
    <div class="legend-title">Site Index</div>
    <div class="legend-items">
      <div v-for="item in legendItems" :key="item.label" class="legend-item">
        <span class="legend-swatch" :style="{ background: item.color }"></span>
        <span class="legend-label">{{ item.label }}</span>
      </div>
    </div>
  </div>
</template>

<script setup>
import { SCORE_PALETTE } from '../config/constants.js'

defineProps({ hasData: { type: Boolean, default: false } })

const labels = ['0.00', '0.20', '0.40', '0.60', '0.80', '1.00']
const legendItems = SCORE_PALETTE.map((color, i) => ({ color, label: labels[i] }))
</script>
