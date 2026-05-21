import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  base: '/MAP-Housing-ATO-Calculator-Updated/',
  build: {
    outDir: 'dist',
    assetsInlineLimit: 0,
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (id.includes('maplibre-gl')) return 'maplibre'
          if (id.includes('@duckdb/duckdb-wasm')) return 'duckdb'
          if (id.includes('h3-js')) return 'h3'
        }
      }
    }
  },
  optimizeDeps: {
    exclude: ['@duckdb/duckdb-wasm']
  }
})
