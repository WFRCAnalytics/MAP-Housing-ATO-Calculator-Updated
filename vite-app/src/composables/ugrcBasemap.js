// UGRC's "Lite" vector basemap, composed from three of AGRC's hosted ArcGIS
// vector tile services (Utah's official GIS agency): a hillshade layer on
// the bottom, the reference/road base map, and a labels layer on top. Each
// service publishes its own complete MapLibre style document (root.json)
// with one source, a relative sprite/glyphs URL, and a relative source
// `url` that itself points to a TileJSON document rather than a tile URL
// template directly — so building one combined style means fetching each
// layer's style AND its source's TileJSON, then rewriting every relative
// reference to absolute and namespacing ids so the three
// independently-authored layers don't collide.
const UGRC_TILES = 'https://tiles.arcgis.com/tiles/99lidPhWCzftIe9K/arcgis/rest/services'

const LAYERS = [
  { prefix: 'hillshade', styleUrl: `${UGRC_TILES}/VectorHillshade/VectorTileServer/resources/styles/root.json` },
  { prefix: 'base', styleUrl: `${UGRC_TILES}/LiteBase/VectorTileServer/resources/styles/root.json` },
  { prefix: 'labels', styleUrl: `${UGRC_TILES}/LiteLabels/VectorTileServer/resources/styles/root.json` },
]

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

// Layer/source ids in the returned style are namespaced `${prefix}__...`
// (e.g. "base__esri", "base__Base/Roads - white version/..."), so callers
// can target UGRC's own road/building layers by source-layer name — see
// useMap.js's setupMapLayers.
export async function buildUgrcLiteStyle() {
  const style = {
    version: 8,
    sources: {},
    // MapLibre blends semi-transparent tile edges toward black without an
    // opaque background layer underneath — always add one.
    layers: [{ id: 'background', type: 'background', paint: { 'background-color': '#ffffff' } }],
  }
  const spriteEntries = []

  for (const { prefix, styleUrl } of LAYERS) {
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
    // Each service hosts its own copy of the font glyph PBFs — VectorHillshade's
    // copy triggers a real maplibre-gl pbf-parser bug ("Unimplemented type: 3")
    // even though LiteBase's/LiteLabels' copies parse fine, so always use
    // LiteBase's regardless of layer order (confirmed: VectorHillshade's own
    // vector TILE data parses fine — only its glyphs endpoint is affected).
    if ((prefix === 'base' || !style.glyphs) && raw.glyphs) style.glyphs = resolveUrl(raw.glyphs, styleUrl)
  }

  if (spriteEntries.length) style.sprite = spriteEntries
  return style
}
