import { createApp } from 'vue'
import '@vueform/multiselect/themes/default.css'
import './style.css'
import App from './App.vue'

const app = createApp(App)

// Global tooltip directive — position:fixed avoids overflow:auto clipping in sidebar.
// Matches R Shiny's Bootstrap 5 dark tooltip: appears above the icon with a downward arrow.
let _tipEl = null
function getTipEl() {
  if (!_tipEl) _tipEl = document.getElementById('global-tooltip')
  return _tipEl
}

app.directive('tooltip', {
  mounted(el, { value }) {
    el.addEventListener('mouseenter', () => {
      const text = value
      if (!text) return
      const tip = getTipEl()
      if (!tip) return
      tip.textContent = text
      const rect = el.getBoundingClientRect()
      tip.style.left = `${rect.left + rect.width / 2}px`
      tip.style.top  = `${rect.top - 6}px`
      tip.classList.add('visible')
    })
    el.addEventListener('mouseleave', () => getTipEl()?.classList.remove('visible'))
  },
  updated(el, { value }) {
    el._ttValue = value
  },
})

app.mount('#app')

// Favicon: colored mark in light mode, white mark in dark mode.
// Done in JS (not a <link media="..."> pair) because browser support for
// theme-conditional favicon <link> tags is inconsistent — matchMedia is not.
;(function () {
  const link = document.getElementById('app-favicon')
  if (!link) return
  const base = import.meta.env.BASE_URL
  const mql = window.matchMedia('(prefers-color-scheme: dark)')
  const applyTheme = (isDark) => {
    link.href = `${base}${isDark ? 'favicon-dark.png' : 'favicon.png'}`
  }
  applyTheme(mql.matches)
  mql.addEventListener('change', (e) => applyTheme(e.matches))
})()
