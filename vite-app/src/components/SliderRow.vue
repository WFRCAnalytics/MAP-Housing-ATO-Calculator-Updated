<template>
  <div class="slider-row">
    <div class="slider-label-row">
      <div class="slider-label">
        <i :class="`fa-solid ${def.icon}`"></i>
        <span>{{ def.label }}</span>
        <i class="fa-regular fa-circle-question help-icon" :data-tip="def.help"></i>
      </div>
      <button
        class="layer-toggle-btn"
        :class="{ active: layerVisible }"
        :title="`Toggle ${def.label} layer`"
        @click="$emit('toggle-layer', def.id)"
      >
        <i :class="layerVisible ? 'fa-solid fa-eye' : 'fa-solid fa-eye-slash'"></i>
      </button>
    </div>
    <input
      type="range"
      :id="def.id"
      min="0" max="1" step="0.1"
      :value="modelValue"
      @input="$emit('update:modelValue', parseFloat($event.target.value))"
    />
  </div>
</template>

<script setup>
defineProps({
  def: { type: Object, required: true },
  modelValue: { type: Number, default: 0.5 },
  layerVisible: { type: Boolean, default: false },
})
defineEmits(['update:modelValue', 'toggle-layer'])
</script>
