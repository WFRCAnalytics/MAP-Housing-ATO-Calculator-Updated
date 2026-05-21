<template>
  <div id="map-controls-bar">
    <span class="ctrl-label">Z-Scale:</span>
    <input
      id="z-mult"
      type="number"
      :value="zMult"
      min="0.1"
      max="20"
      step="0.1"
      :disabled="!is3D"
      @input="$emit('update:zMult', parseFloat($event.target.value) || 1)"
    />

    <div class="switch-wrap">
      <input
        type="checkbox"
        :checked="is3D"
        @change="$emit('update:is3D', $event.target.checked)"
      />
      <span>3D View</span>
    </div>

    <div class="switch-wrap">
      <input
        type="checkbox"
        :checked="pinnedTooltip"
        @change="$emit('update:pinnedTooltip', $event.target.checked)"
      />
      <span>Pin Tooltip</span>
    </div>

    <div style="flex:1"></div>

    <button
      class="btn btn-outline-secondary btn-sm"
      :disabled="!hasData"
      @click="$emit('screenshot')"
      title="Download map screenshot"
    >
      <i class="fa-solid fa-camera"></i> Screenshot
    </button>

    <button
      class="btn btn-outline-primary btn-sm"
      :disabled="!hasData"
      @click="$emit('download')"
      title="Download filtered data as CSV"
    >
      <i class="fa-solid fa-download"></i> Download Data
    </button>
  </div>
</template>

<script setup>
defineProps({
  is3D: { type: Boolean, default: false },
  zMult: { type: Number, default: 2 },
  pinnedTooltip: { type: Boolean, default: false },
  hasData: { type: Boolean, default: false },
})
defineEmits(['update:is3D', 'update:zMult', 'update:pinnedTooltip', 'download', 'screenshot'])
</script>
