<template>
  <div class="modal-backdrop" @click.self="$emit('close')">
    <div class="modal-box">
      <div class="splash-header">
        <img :src="logoUrl" alt="WFRC Logo" />
        <h2>Housing Site Evaluator</h2>
      </div>
      <div class="splash-body">
        <p>The Housing Site Evaluator is designed to assist housing and land use planning efforts across the Wasatch Front.</p>
        <div class="feature-grid">
          <div class="feature-item">
            <div class="feature-icon"><i class="fa-solid fa-comments"></i></div>
            <div class="feature-title">Conversation Starter</div>
            <div class="feature-text">Facilitate discussions about housing needs.</div>
          </div>
          <div class="feature-item">
            <div class="feature-icon"><i class="fa-solid fa-map-location-dot"></i></div>
            <div class="feature-title">Visualization Tool</div>
            <div class="feature-text">Explore spatial data interactively.</div>
          </div>
          <div class="feature-item">
            <div class="feature-icon"><i class="fa-solid fa-chart-pie"></i></div>
            <div class="feature-title">Data-Informed Guide</div>
            <div class="feature-text">Plan based on access metrics.</div>
          </div>
        </div>
        <div class="instruction-box">
          <i class="fa-solid fa-circle-info"></i> <strong> How it works:</strong><br/>
          1. Start by selecting your <strong>community</strong> (one or more) from the sidebar.<br/>
          2. Optionally, filter the map by specific <strong>land use</strong> types.<br/>
          3. Adjust the sliders to <strong>prioritize the accessibility factors</strong> that matter most to you.
          <p style="margin-top:8px;margin-bottom:0;">The tool will generate a heat map highlighting locations ranging from <strong>most accessible</strong> to <strong>least accessible</strong> based on your inputs.</p>
        </div>
      </div>
      <div class="splash-footer">
        <button class="btn-get-started" @click="$emit('close')">GET STARTED</button>
        <div class="splash-footer-note">
          <strong>Questions or Comments?</strong><br/>
          <a href="mailto:christy.dahlberg@wfrc.utah.gov"><i class="fa-solid fa-envelope"></i> Christy Dahlberg</a>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
defineEmits(['close'])
const logoUrl = `${import.meta.env.BASE_URL}logo.png`
</script>
