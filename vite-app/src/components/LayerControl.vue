<template>
  <div id="layer-control-panel">
    <button class="lc-header" @click="open = !open">
      <i class="fa-solid fa-layer-group"></i>
      <span>Layers</span>
      <i :class="open ? 'fa-solid fa-chevron-up' : 'fa-solid fa-chevron-down'" style="margin-left:auto;font-size:0.7rem;"></i>
    </button>
    <div v-show="open" class="lc-body">
      <div class="lc-section-label">Map Layers</div>
      <div class="lc-row" v-for="item in mapItems" :key="item.id">
        <span>{{ item.label }}</span>
        <button
          class="layer-toggle-btn"
          :class="{ active: layerVisible[item.id] }"
          @click="$emit('toggle-layer', item.id)"
        >
          <i :class="layerVisible[item.id] ? 'fa-solid fa-eye' : 'fa-solid fa-eye-slash'"></i>
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'

defineProps({
  layerVisible: { type: Object, required: true },
})
defineEmits(['toggle-layer'])

const open = ref(true)

const mapItems = [
  { id: 'roads-major', label: 'Major Roads' },
  { id: 'h3-heatmap', label: 'Heatmap' },
  { id: 'city-bounds', label: 'City Boundaries' },
]
</script>
