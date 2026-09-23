import { cellToBoundary } from 'h3-js'

// Echoes `id` back so the main thread can tell which request a response
// belongs to — this worker is a shared singleton (see getH3Worker in
// useData.js), and overlapping requests (e.g. selecting a second city
// before the first one's response arrives) would otherwise all resolve off
// of whichever response happens to arrive first.
self.addEventListener('message', ({ data: { rows, id } }) => {
  const features = rows.map(row => ({
    type: 'Feature',
    geometry: {
      type: 'Polygon',
      coordinates: [cellToBoundary(row.h3_index, true)],
    },
    properties: {
      h3_index: row.h3_index,
      CommCode: row.CommCode,
      BC: row.BC,
      OZ: row.OZ,
      AA: row.AA,
      AT: row.AT,
      TT: row.TT,
      TF: row.TF,
      TA: row.TA,
      AC: row.AC,
      AH: row.AH,
      AE: row.AE,
      AG: row.AG,
      AM: row.AM,
      AP: row.AP,
    },
  }))
  self.postMessage({ id, features })
})
