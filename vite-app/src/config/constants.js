// Full absolute URL required — DuckDB read_parquet() needs http(s):// not a relative path
export const DATA_BASE_URL = `${window.location.origin}${import.meta.env.BASE_URL}data`

export const MAP_CENTER = [-111.891, 40.7608]
export const MAP_ZOOM = 8
export const BRAND_BLUE = '#233A57'
export const SCORE_PALETTE = ['#EDF8B1', '#C7E9B4', '#7FCDBB', '#41B6C4', '#1D91C0', '#225EA8']
