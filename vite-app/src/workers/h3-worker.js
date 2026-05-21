import { cellToBoundary } from 'h3-js'

self.addEventListener('message', ({ data: { rows } }) => {
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
  self.postMessage({ features })
})
