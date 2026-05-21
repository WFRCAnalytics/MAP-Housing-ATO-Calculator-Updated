<template>
  <div class="modal-backdrop" @click.self="$emit('close')">
    <div class="modal-box">
      <div class="modal-header-grad">
        <div class="modal-title">
          <h2>Download Data</h2>
          <p>Your filtered H3 data is ready to download.</p>
        </div>
        <button class="modal-close-btn" @click="$emit('close')"><i class="fa-solid fa-xmark"></i></button>
      </div>
      <div class="modal-body">
        <div class="info-box">
          <i class="fa-solid fa-circle-info"></i>
          This file contains <strong>H3 Hexagon Indices</strong> rather than standard coordinates. Select your preferred tool below to visualize this data.
        </div>
        <div class="tab-nav">
          <button v-for="t in tabs" :key="t.id" class="tab-btn" :class="{ active: activeTab === t.id }" @click="activeTab = t.id" v-html="t.label"></button>
        </div>
        <div v-if="activeTab === 'r'">
          <pre><code class="language-r" ref="rCode">{{ rScript }}</code></pre>
        </div>
        <div v-if="activeTab === 'python'">
          <pre><code class="language-python" ref="pyCode">{{ pyScript }}</code></pre>
        </div>
        <div v-if="activeTab === 'gis'">
          <p style="font-size:0.88rem;margin-bottom:10px;"><i class="fa-solid fa-triangle-exclamation" style="color:#f39c12;"></i> To visualize this data, load the reference geometry service below, then join your downloaded CSV.</p>
          <div class="url-box">https://services1.arcgis.com/taguadKoI1XFwivx/ArcGIS/rest/services/HousingSuitability_Centers202512_gdb/FeatureServer/0</div>
          <hr style="margin:12px 0;" />
          <h5 style="font-family:'Oswald';color:#233A57;margin-bottom:6px;">Option A: QGIS</h5>
          <ul style="font-size:0.88rem;color:#444;line-height:1.7;padding-left:18px;">
            <li>Go to <strong>Layer</strong> &gt; <strong>Add Layer</strong> &gt; <strong>Add ArcGIS REST Service Layer...</strong></li>
            <li>Click 'New', paste the URL above, and click 'Connect' to add the layer.</li>
            <li>Import your downloaded CSV and perform a <strong>Table Join</strong> using the H3 Index column.</li>
          </ul>
          <h5 style="font-family:'Oswald';color:#233A57;margin-top:12px;margin-bottom:6px;">Option B: ArcGIS Pro</h5>
          <ul style="font-size:0.88rem;color:#444;line-height:1.7;padding-left:18px;">
            <li>Go to the <strong>Map</strong> tab &gt; <strong>Add Data</strong> &gt; <strong>Data From Path</strong></li>
            <li>Paste the URL above and click 'Add'.</li>
            <li>Import your CSV and use the <strong>Add Join</strong> tool to append your data using the H3 Index.</li>
          </ul>
        </div>
      </div>
      <div class="modal-footer">
        <span class="modal-footer-note">Need help? Contact <a href="mailto:analytics@wfrc.utah.gov" style="color:inherit;text-decoration:underline;">analytics@wfrc.utah.gov</a></span>
        <button class="btn-brand" @click="$emit('close')"><i class="fa-solid fa-check"></i> Done</button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, watch, nextTick } from 'vue'

defineEmits(['close'])

const activeTab = ref('r')
const rCode = ref(null)
const pyCode = ref(null)

const tabs = [
  { id: 'r', label: '<i class="fa-brands fa-r-project"></i> R Script' },
  { id: 'python', label: '<i class="fa-brands fa-python"></i> Python Script' },
  { id: 'gis', label: '<i class="fa-solid fa-map"></i> QGIS / ArcGIS' },
]

const rScript = `# Install packages if missing
# install.packages(c("sf", "h3o", "readr", "dplyr"))

library(sf)
library(h3o)
library(readr)
library(dplyr)

folder_path <- "path/to/folder"
df <- read_csv(file.path(folder_path, "HousingSiteEvaluator_Filtered_Data.csv"))

sf_data <- df |>
  mutate(
    h3_obj  = h3_from_strings(tolower(h3_index)),
    geometry = h3_to_vertexes(h3_obj) |> st_cast("POLYGON")
  ) |>
  st_as_sf()

write_sf(sf_data, file.path(folder_path, "HousingSiteEvaluator_Filtered_Data.geojson"))`

const pyScript = `# pip install h3 pandas geopandas shapely

import h3
import pandas as pd
import geopandas as gpd
from shapely.geometry import shape
import os

folder_path = "path/to/folder"
df = pd.read_csv(os.path.join(folder_path, "HousingSiteEvaluator_Filtered_Data.csv"))
df["geometry"] = df["h3_index"].apply(lambda x: shape(h3.cells_to_geo([x])))
gdf = gpd.GeoDataFrame(df, geometry="geometry", crs="EPSG:4326")
gdf.to_file(os.path.join(folder_path, "HousingSiteEvaluator_Filtered_Data.geojson"), driver="GeoJSON")`

watch(activeTab, async () => {
  await nextTick()
  if (typeof window.hljs !== 'undefined') {
    document.querySelectorAll('pre code').forEach(el => window.hljs.highlightElement(el))
  }
})
</script>
