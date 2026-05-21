<template>
  <div id="map-controls-bar">
    <!-- LEFT: action buttons -->
    <button
      class="btn btn-outline-primary btn-sm"
      :class="{ disabled: !hasData }"
      :disabled="!hasData"
      @click="$emit('download')"
    >
      <i class="fa-solid fa-download"></i> Download Data
    </button>
    <button
      class="btn btn-outline-secondary btn-sm"
      :class="{ disabled: !hasData }"
      :disabled="!hasData"
      @click="$emit('screenshot')"
    >
      <i class="fa-solid fa-camera"></i> Download Map
    </button>

    <div style="flex:1"></div>

    <!-- RIGHT: Z-SCALE + 3D + Pin -->
    <div class="ctrl-group">
      <label class="ctrl-label" for="z-mult">Z-Scale:</label>
      <input
        id="z-mult"
        type="number"
        :value="zMult"
        min="0.5"
        max="20"
        step="0.5"
        :disabled="!is3D"
        @input="$emit('update:zMult', parseFloat($event.target.value) || 1)"
      />
    </div>

    <div class="switch-wrap">
      <label class="toggle-switch">
        <input type="checkbox" :checked="is3D" @change="$emit('update:is3D', $event.target.checked)" />
        <span class="toggle-slider"></span>
      </label>
      <span>3D View</span>
    </div>

    <div class="switch-wrap">
      <label class="toggle-switch">
        <input type="checkbox" :checked="pinnedTooltip" @change="$emit('update:pinnedTooltip', $event.target.checked)" />
        <span class="toggle-slider"></span>
      </label>
      <span>Pin Tooltip</span>
    </div>
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
