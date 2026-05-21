<template>
  <div id="sidebar">
    <div id="sidebar-inner">
      <!-- Step 1: Community -->
      <span class="step-header"><i class="fa-solid fa-city"></i> 1. Select Community</span>
      <p class="step-desc">Choose one or more communities to evaluate.</p>
      <select ref="citySelectEl" multiple></select>

      <!-- Step 2: Land Use -->
      <span class="step-header"><i class="fa-solid fa-layer-group"></i> 2. Filter Land Use</span>
      <p class="step-desc">Optionally filter the map by land use type.</p>
      <div class="lu-group">
        <label v-for="opt in luOptions" :key="opt.value" class="lu-option">
          <input type="radio" :value="opt.value" v-model="localLandUse" @change="$emit('update:landUse', opt.value)" />
          <span>{{ opt.label }}</span>
        </label>
      </div>

      <!-- Wasatch Choice Centers (toggle-only) -->
      <div class="accordion">
        <div class="accordion-item">
          <button class="accordion-button" @click="centers.open = !centers.open">
            <span><i class="fa-solid fa-bullseye"></i> Wasatch Choice Centers</span>
            <i :class="centers.open ? 'fa-solid fa-chevron-up' : 'fa-solid fa-chevron-down'"></i>
          </button>
          <div v-show="centers.open" class="accordion-body">
            <div v-for="def in CENTER_DEFS" :key="def.id" class="toggle-row">
              <div class="toggle-row-label">
                <span>{{ def.label }}</span>
                <i class="fa-regular fa-circle-question help-icon" :data-tip="def.help"></i>
              </div>
              <button
                class="layer-toggle-btn"
                :class="{ active: layerVisible[def.id] }"
                @click="$emit('toggle-layer', def.id)"
              >
                <i :class="layerVisible[def.id] ? 'fa-solid fa-eye' : 'fa-solid fa-eye-slash'"></i>
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- Step 3: Weights -->
      <span class="step-header"><i class="fa-solid fa-sliders"></i> 3. Prioritize Factors</span>
      <p class="step-desc">Adjust sliders to weight accessibility factors.</p>

      <div class="btn-row">
        <button class="btn btn-outline-secondary btn-sm" @click="resetWeights">
          <i class="fa-solid fa-rotate-left"></i> Reset All
        </button>
        <button class="btn btn-outline-primary btn-sm" @click="maxWeights">
          <i class="fa-solid fa-arrow-up-wide-short"></i> Max All
        </button>
      </div>

      <div class="accordion">
        <div class="accordion-item">
          <button class="accordion-button" @click="emp.open = !emp.open">
            <span><i class="fa-solid fa-briefcase"></i> Employment Access</span>
            <i :class="emp.open ? 'fa-solid fa-chevron-up' : 'fa-solid fa-chevron-down'"></i>
          </button>
          <div v-show="emp.open" class="accordion-body">
            <SliderRow
              v-for="def in empSliders"
              :key="def.id"
              :def="def"
              v-model="weights[def.col]"
              :layerVisible="layerVisible[def.id]"
              @toggle-layer="$emit('toggle-layer', def.id)"
            />
          </div>
        </div>
      </div>

      <div class="accordion">
        <div class="accordion-item">
          <button class="accordion-button" @click="trans.open = !trans.open">
            <span><i class="fa-solid fa-car-on"></i> Transportation</span>
            <i :class="trans.open ? 'fa-solid fa-chevron-up' : 'fa-solid fa-chevron-down'"></i>
          </button>
          <div v-show="trans.open" class="accordion-body">
            <SliderRow
              v-for="def in transSliders"
              :key="def.id"
              :def="def"
              v-model="weights[def.col]"
              :layerVisible="layerVisible[def.id]"
              @toggle-layer="$emit('toggle-layer', def.id)"
            />
          </div>
        </div>
      </div>

      <div class="accordion">
        <div class="accordion-item">
          <button class="accordion-button" @click="nec.open = !nec.open">
            <span><i class="fa-solid fa-store"></i> Necessities</span>
            <i :class="nec.open ? 'fa-solid fa-chevron-up' : 'fa-solid fa-chevron-down'"></i>
          </button>
          <div v-show="nec.open" class="accordion-body">
            <SliderRow
              v-for="def in necSliders"
              :key="def.id"
              :def="def"
              v-model="weights[def.col]"
              :layerVisible="layerVisible[def.id]"
              @toggle-layer="$emit('toggle-layer', def.id)"
            />
          </div>
        </div>
      </div>

      <!-- OZ Toggle -->
      <div class="oz-row">
        <input
          type="checkbox"
          class="oz-check"
          id="oz-check"
          v-model="localOZ"
          @change="$emit('update:ozOnly', localOZ)"
        />
        <label for="oz-check" class="oz-label">
          <i class="fa-solid fa-star"></i> Opportunity Zones Only
        </label>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted, inject, watch } from 'vue'
import TomSelect from 'tom-select'
import SliderRow from './SliderRow.vue'
import { SLIDER_DEFS, CENTER_DEFS } from '../config/sliders.js'
import { LU_MAPPINGS } from '../config/landUse.js'

const props = defineProps({
  cities: { type: Array, default: () => [] },
  landUse: { type: String, default: 'All Land Uses' },
  ozOnly: { type: Boolean, default: false },
  layerVisible: { type: Object, required: true },
})

const emit = defineEmits(['update:selectedCities', 'update:landUse', 'update:ozOnly', 'toggle-layer'])

const weights = inject('weights')

const localLandUse = ref(props.landUse)
const localOZ = ref(props.ozOnly)
const citySelectEl = ref(null)
let tomSelect = null

const empSliders = computed(() => SLIDER_DEFS.filter(d => d.group === 'Employment'))
const transSliders = computed(() => SLIDER_DEFS.filter(d => d.group === 'Transportation'))
const necSliders = computed(() => SLIDER_DEFS.filter(d => d.group === 'Necessities'))

const luOptions = Object.keys(LU_MAPPINGS).map(k => ({ value: k, label: k }))

const centers = reactive({ open: false })
const emp = reactive({ open: true })
const trans = reactive({ open: true })
const nec = reactive({ open: true })

function resetWeights() {
  SLIDER_DEFS.forEach(d => { weights[d.col] = 0.5 })
}

function maxWeights() {
  SLIDER_DEFS.forEach(d => { weights[d.col] = 1 })
}

watch(() => props.cities, (cities) => {
  if (!tomSelect || !cities.length) return
  cities.forEach(c => tomSelect.addOption({ value: c.value, text: c.label }))
  tomSelect.refreshOptions(false)
}, { deep: true })

function toggleCity(code) {
  if (!tomSelect) return
  if (tomSelect.items.includes(String(code))) {
    tomSelect.removeItem(String(code))
  } else {
    tomSelect.addItem(String(code))
  }
}

defineExpose({ toggleCity })

onMounted(() => {
  tomSelect = new TomSelect(citySelectEl.value, {
    plugins: ['remove_button'],
    placeholder: 'Search communities...',
    maxOptions: 200,
    onChange(vals) {
      emit('update:selectedCities', Array.isArray(vals) ? vals : vals ? [vals] : [])
    },
  })
  if (props.cities.length) {
    props.cities.forEach(c => tomSelect.addOption({ value: c.value, text: c.label }))
    tomSelect.refreshOptions(false)
  }
})
</script>
