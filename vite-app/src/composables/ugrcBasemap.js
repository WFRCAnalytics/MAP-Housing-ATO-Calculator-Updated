// UGRC's "Lite" and "Hybrid" vector basemaps, each composed from AGRC's
// hosted ArcGIS vector tile services (Utah's official GIS agency). Every
// service publishes its own complete MapLibre style document (root.json)
// with one source, a relative sprite/glyphs URL, and a relative source
// `url` that itself points to a TileJSON document rather than a tile URL
// template directly — so building one combined style means fetching each
// layer's style AND its source's TileJSON, then rewriting every relative
// reference to absolute and namespacing ids so independently-authored
// layers don't collide.
const UGRC_TILES = 'https://tiles.arcgis.com/tiles/99lidPhWCzftIe9K/arcgis/rest/services'

const LITE_LAYERS = [
  { prefix: 'hillshade', styleUrl: `${UGRC_TILES}/VectorHillshade/VectorTileServer/resources/styles/root.json` },
  { prefix: 'base', styleUrl: `${UGRC_TILES}/LiteBase/VectorTileServer/resources/styles/root.json` },
  { prefix: 'labels', styleUrl: `${UGRC_TILES}/LiteLabels/VectorTileServer/resources/styles/root.json` },
]

// UGRC's "Vector Overlay" service — roads, boundaries, and labels only, no
// fills for terrain/water/parks/etc. — is the vector-tile equivalent of the
// "Overlay" cache their legacy raster Hybrid basemap draws on top of
// imagery (confirmed against UGRC's own public "Utah Hybrid Base map" web
// map, which pairs Esri World Imagery with that same overlay cache).
const HYBRID_OVERLAY_STYLE_URL = `${UGRC_TILES}/Vector_Overlay/VectorTileServer/resources/styles/root.json`

// Esri's public World Imagery basemap — the same aerial imagery UGRC's own
// Hybrid basemap uses. No API key required.
const ESRI_WORLD_IMAGERY_TILES = 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
const ESRI_WORLD_IMAGERY_ATTRIBUTION = 'Imagery © <a href="https://www.esri.com" target="_blank">Esri</a>, Maxar, Earthstar Geographics, and the GIS User Community'

// `new URL(relative, base).href` percent-encodes `{`/`}` — fine for a plain
// tile/source URL, but wrong for `glyphs`/`sprite`/`tiles` templates, which
// need their `{fontstack}`/`{range}`/`{z}`/`{x}`/`{y}` tokens verbatim.
function resolveUrl(relative, base) {
  return new URL(relative, base).href.replace(/%7B/gi, '{').replace(/%7D/gi, '}')
}

// A source's `url` field points to a TileJSON document, not a tile template
// directly — fetch it and inline its own `tiles` array (resolved against
// itself) so the merged, in-memory style never needs MapLibre to resolve a
// relative source URL against a style document that no longer has one.
async function inlineTileJsonSource(source, sourceUrl) {
  const res = await fetch(sourceUrl)
  const tilejson = await res.json()
  const { url, ...rest } = source
  return {
    ...rest,
    tiles: tilejson.tiles.map(t => resolveUrl(t, sourceUrl)),
    ...(tilejson.minzoom !== undefined ? { minzoom: tilejson.minzoom } : {}),
    ...(tilejson.maxzoom !== undefined ? { maxzoom: tilejson.maxzoom } : {}),
  }
}

// Fetches one UGRC vector tile service's style and merges its sources/layers
// into `style` in place, namespaced `${prefix}__...` (e.g. "base__esri",
// "base__Base/Roads - white version/...") so callers can target UGRC's own
// road/building layers by source-layer name — see useMap.js's
// setupMapLayers. Returns the service's own (still-relative-resolved)
// glyphs URL, if any, so the caller can decide which service's glyphs to
// use when merging more than one.
async function mergeVectorService(style, spriteEntries, prefix, styleUrl, { skipFillLayers = false } = {}) {
  const raw = await (await fetch(styleUrl)).json()

  for (const [sourceId, source] of Object.entries(raw.sources ?? {})) {
    const key = `${prefix}__${sourceId}`
    const absoluteUrl = resolveUrl(source.url, styleUrl)
    style.sources[key] = await inlineTileJsonSource(source, absoluteUrl)
    // Neither service's TileJSON declares its own attribution.
    style.sources[key].attribution = 'Basemap © <a href="https://gis.utah.gov" target="_blank">UGRC</a>'
  }

  const spriteId = prefix
  for (const layer of raw.layers ?? []) {
    // The Hybrid overlay's only two fill layers exist to paint solid white
    // over everything outside Utah when the overlay is used standalone —
    // drawn over imagery instead, they'd blot it out, so skip them.
    if (skipFillLayers && layer.type === 'fill') continue
    const rewritten = {
      ...layer,
      id: `${prefix}__${layer.id}`,
      source: layer.source ? `${prefix}__${layer.source}` : undefined,
    }
    // A symbol layer's icon-image is only resolvable against its OWN
    // layer's sprite — prefix it so it survives merging multiple sprites
    // (MapLibre's array-form `sprite` resolves "id:icon" against the
    // matching entry). Without this, e.g. LiteLabels' highway shield
    // icons silently fail to render because LiteBase's sprite "wins".
    const iconImage = rewritten.layout?.['icon-image']
    if (typeof iconImage === 'string') {
      rewritten.layout = { ...rewritten.layout, 'icon-image': `${spriteId}:${iconImage}` }
    }
    style.layers.push(rewritten)
  }

  if (raw.sprite) spriteEntries.push({ id: spriteId, url: resolveUrl(raw.sprite, styleUrl) })
  return raw.glyphs ? resolveUrl(raw.glyphs, styleUrl) : undefined
}

export async function buildUgrcLiteStyle() {
  const style = {
    version: 8,
    sources: {},
    // MapLibre blends semi-transparent tile edges toward black without an
    // opaque background layer underneath — always add one.
    layers: [{ id: 'background', type: 'background', paint: { 'background-color': '#ffffff' } }],
  }
  const spriteEntries = []

  for (const { prefix, styleUrl } of LITE_LAYERS) {
    const glyphs = await mergeVectorService(style, spriteEntries, prefix, styleUrl)
    // Each service hosts its own copy of the font glyph PBFs — VectorHillshade's
    // copy triggers a real maplibre-gl pbf-parser bug ("Unimplemented type: 3")
    // even though LiteBase's/LiteLabels' copies parse fine, so always use
    // LiteBase's regardless of layer order (confirmed: VectorHillshade's own
    // vector TILE data parses fine — only its glyphs endpoint is affected).
    if ((prefix === 'base' || !style.glyphs) && glyphs) style.glyphs = glyphs
  }

  if (spriteEntries.length) style.sprite = spriteEntries
  return style
}

export async function buildUgrcHybridStyle() {
  const style = {
    version: 8,
    sources: {
      'esri-world-imagery': {
        type: 'raster',
        tiles: [ESRI_WORLD_IMAGERY_TILES],
        tileSize: 256,
        maxzoom: 19,
        attribution: ESRI_WORLD_IMAGERY_ATTRIBUTION,
      },
    },
    layers: [
      { id: 'background', type: 'background', paint: { 'background-color': '#000000' } },
      { id: 'esri-world-imagery', type: 'raster', source: 'esri-world-imagery' },
    ],
  }
  const spriteEntries = []

  const glyphs = await mergeVectorService(style, spriteEntries, 'overlay', HYBRID_OVERLAY_STYLE_URL, { skipFillLayers: true })
  if (glyphs) style.glyphs = glyphs
  if (spriteEntries.length) style.sprite = spriteEntries

  return style
}
