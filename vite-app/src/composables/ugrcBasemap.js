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

// Fetches one UGRC vector tile service's style and returns its
// sources/layers/sprite/glyphs, namespaced `${prefix}__...` (e.g.
// "base__esri", "base__Base/Roads - white version/...") so callers can
// target UGRC's own road/building layers by source-layer name — see
// App.vue's setupMapLayers. Returns a plain object rather than mutating a
// shared style in place, so sibling services can be fetched concurrently
// (via Promise.all) without their network responses racing each other into
// the merged layer array in the wrong order.
async function fetchVectorService(prefix, styleUrl, { skipFillLayers = false } = {}) {
  const raw = await (await fetch(styleUrl)).json()

  const sourceEntries = await Promise.all(
    Object.entries(raw.sources ?? {}).map(async ([sourceId, source]) => {
      const key = `${prefix}__${sourceId}`
      const absoluteUrl = resolveUrl(source.url, styleUrl)
      const inlined = await inlineTileJsonSource(source, absoluteUrl)
      // Neither service's TileJSON declares its own attribution.
      inlined.attribution = 'Basemap © <a href="https://gis.utah.gov" target="_blank">UGRC</a>'
      return [key, inlined]
    })
  )

  const layers = []
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
      rewritten.layout = { ...rewritten.layout, 'icon-image': `${prefix}:${iconImage}` }
    }
    layers.push(rewritten)
  }

  return {
    prefix,
    sources: Object.fromEntries(sourceEntries),
    layers,
    sprite: raw.sprite ? { id: prefix, url: resolveUrl(raw.sprite, styleUrl) } : null,
    glyphs: raw.glyphs ? resolveUrl(raw.glyphs, styleUrl) : undefined,
  }
}

async function buildUgrcLiteStyleUncached() {
  // Fetched in parallel — each service is an independent network round trip
  // (its root.json plus its source's TileJSON), so awaiting them one at a
  // time in sequence (as a for-of loop would) needlessly serializes three
  // requests that don't depend on each other. Promise.all still resolves
  // `results` in LITE_LAYERS' order regardless of which finishes first, so
  // the merge below stays deterministic (layer z-order intact).
  const results = await Promise.all(LITE_LAYERS.map(({ prefix, styleUrl }) => fetchVectorService(prefix, styleUrl)))

  const style = {
    version: 8,
    sources: {},
    // MapLibre blends semi-transparent tile edges toward black without an
    // opaque background layer underneath — always add one.
    layers: [{ id: 'background', type: 'background', paint: { 'background-color': '#ffffff' } }],
  }
  const spriteEntries = []

  for (const { prefix, sources, layers, sprite, glyphs } of results) {
    Object.assign(style.sources, sources)
    style.layers.push(...layers)
    if (sprite) spriteEntries.push(sprite)
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

async function buildUgrcHybridStyleUncached() {
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

  const { sources, layers, sprite, glyphs } = await fetchVectorService('overlay', HYBRID_OVERLAY_STYLE_URL, { skipFillLayers: true })
  Object.assign(style.sources, sources)
  style.layers.push(...layers)
  if (glyphs) style.glyphs = glyphs
  if (sprite) style.sprite = [sprite]

  return style
}

// Each basemap only needs to be fetched and assembled once — the UGRC/Esri
// documents behind it don't change within a session, so switching back to
// an already-built basemap should be instant rather than re-issuing the
// same handful of network requests. Caching the in-flight PROMISE (not just
// the resolved style) also means two near-simultaneous callers share one
// fetch instead of duplicating it. The cached style object is also handed
// to `map.setStyle()` unchanged on every switch, which lets MapLibre's own
// style diffing recognize a source as unchanged (same id, same definition)
// and keep reusing its already-downloaded tiles instead of re-requesting
// them — see App.vue's switchBasemap.
const styleCache = new Map()
function cached(id, build) {
  if (!styleCache.has(id)) {
    styleCache.set(id, build().catch(e => { styleCache.delete(id); throw e }))
  }
  return styleCache.get(id)
}

export function buildUgrcLiteStyle() {
  return cached('lite', buildUgrcLiteStyleUncached)
}

export function buildUgrcHybridStyle() {
  return cached('hybrid', buildUgrcHybridStyleUncached)
}
