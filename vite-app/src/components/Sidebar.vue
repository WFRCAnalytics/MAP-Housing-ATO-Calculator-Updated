<template>
  <div id="sidebar">
    <div id="sidebar-top">
      <span class="step-header" style="margin-top:0">Step 1: Select Cities</span>
      <Multiselect
        v-model="selectedCities"
        :options="props.cities"
        mode="multiple"
        :searchable="true"
        label="label"
        value-prop="value"
        placeholder="Search communities..."
        :close-on-select="false"
        :can-clear="true"
        no-results-text="No cities found"
        no-options-text="Loading cities..."
        @change="val => emit('update:selectedCities', val || [])"
      />
    </div>

    <div id="sidebar-body">
      <!-- Step 2: Land Use -->
      <span class="step-header">Step 2: Filter by Land Use</span>
      <select class="lu-select" v-model="localLandUse" @change="$emit('update:landUse', localLandUse)">
        <option v-for="key in luKeys" :key="key" :value="key">{{ key }}</option>
      </select>

      <!-- Wasatch Choice Centers (toggle-only) -->
      <div class="accordion">
        <div class="accordion-item">
          <button class="accordion-button" @click="centers.open = !centers.open">
            <span>Wasatch Choice Centers (Overlay)</span>
            <i :class="centers.open ? 'fa-solid fa-chevron-up' : 'fa-solid fa-chevron-down'"></i>
          </button>
          <div v-show="centers.open" class="accordion-body">
            <div v-for="def in CENTER_DEFS" :key="def.id" class="toggle-row">
              <div class="toggle-row-label">
                <span>{{ def.label }}</span>
                <i class="fa-regular fa-circle-question help-icon" v-tooltip="def.help"></i>
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
      <span class="step-header">Step 3: Customize Accessibility Priorities</span>
      <p class="step-desc">Indicate priority level for each factor.<br>Toggle layers using the icon on the right.</p>

      <div class="accordion">
        <div class="accordion-item">
          <button class="accordion-button" @click="emp.open = !emp.open">
            <span>Employment</span>
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
            <span>Transportation</span>
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
            <span>Necessities</span>
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

      <!-- Reset / Max buttons — after accordions, matching R Shiny layout -->
      <div class="btn-row">
        <button class="btn btn-outline-secondary btn-sm" @click="resetWeights">
          <i class="fa-solid fa-ban"></i> Reset All (0)
        </button>
        <button class="btn btn-outline-primary btn-sm" @click="maxWeights">
          <i class="fa-solid fa-check-double"></i> Max All (1)
        </button>
      </div>

      <hr class="sidebar-hr" />

      <!-- OZ Toggle -->
      <div class="oz-row">
        <label class="toggle-switch">
          <input type="checkbox" v-model="localOZ" @change="$emit('update:ozOnly', localOZ)" />
          <span class="toggle-slider"></span>
        </label>
        <span class="oz-label">Limit to Opportunity Zones (OZ)</span>
      </div>
    </div><!-- /#sidebar-body -->
  </div><!-- /#sidebar -->
</template>

<script setup>
import { ref, reactive, computed, inject } from 'vue'
import Multiselect from '@vueform/multiselect'
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

const selectedCities = ref([])
const localLandUse = ref(props.landUse)
const localOZ = ref(props.ozOnly)

const luKeys = Object.keys(LU_MAPPINGS)
const empSliders = computed(() => SLIDER_DEFS.filter(d => d.group === 'Employment'))
const transSliders = computed(() => SLIDER_DEFS.filter(d => d.group === 'Transportation'))
const necSliders = computed(() => SLIDER_DEFS.filter(d => d.group === 'Necessities'))

const centers = reactive({ open: false })
const emp = reactive({ open: false })
const trans = reactive({ open: false })
const nec = reactive({ open: false })

function resetWeights() { SLIDER_DEFS.forEach(d => { weights[d.col] = 0 }) }
function maxWeights()   { SLIDER_DEFS.forEach(d => { weights[d.col] = 1 }) }

function toggleCity(code) {
  const str = String(code)
  const idx = selectedCities.value.indexOf(str)
  if (idx >= 0) {
    selectedCities.value = selectedCities.value.filter(v => v !== str)
  } else {
    selectedCities.value = [...selectedCities.value, str]
  }
  emit('update:selectedCities', selectedCities.value)
}

defineExpose({ toggleCity })
</script>
