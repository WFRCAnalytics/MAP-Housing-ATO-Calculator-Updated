import { SCORE_COLS } from '../config/sliders.js'
import { METRIC_COLORS, METRIC_ICONS } from '../config/colors.js'
import { BC_MAP } from '../config/landUse.js'
import { SCORE_PALETTE } from '../config/constants.js'

export function computeScores(rows, weights) {
  const totalW = SCORE_COLS.reduce((s, c) => s + (weights[c] ?? 0), 0)

  const scores = rows.map(row => {
    if (totalW === 0) return 0
    return SCORE_COLS.reduce((s, c) => s + (row[c] ?? 0) * (weights[c] ?? 0), 0) / totalW
  })

  const minS = Math.min(...scores)
  let maxS = Math.max(...scores)
  if (maxS === minS) maxS = minS + 0.0001
  const range = maxS - minS

  rows.forEach((row, i) => {
    row.score = scores[i]
    row.norm_score = (scores[i] - minS) / range
  })

  return { rows, minScore: minS, maxScore: maxS }
}

export function buildColorExpression(weights, minS, maxS) {
  const totalW = SCORE_COLS.reduce((s, c) => s + (weights[c] ?? 0), 0) || 1
  const terms = SCORE_COLS.map(c => ['*', ['get', c], weights[c] ?? 0])
  const rawScore = ['/', ['+', ...terms], totalW]
  const range = (maxS - minS) || 0.0001
  const normScore = ['/', ['-', rawScore, minS], range]

  const stops = SCORE_PALETTE.reduce((acc, color, i) => {
    acc.push(i / (SCORE_PALETTE.length - 1), color)
    return acc
  }, [])

  return ['interpolate', ['linear'], normScore, ...stops]
}

export function buildExtrusionExpr(weights, zMult) {
  const totalW = SCORE_COLS.reduce((s, c) => s + (weights[c] ?? 0), 0) || 1
  const terms = SCORE_COLS.map(c => ['*', ['get', c], weights[c] ?? 0])
  const rawScore = ['/', ['+', ...terms], totalW]
  return ['interpolate', ['linear'], rawScore, 0, 0, 1, (zMult || 2) * 1000]
}

export function computeNormScore(props, weights, minS, maxS) {
  const totalW = SCORE_COLS.reduce((s, c) => s + (weights[c] ?? 0), 0) || 1
  const raw = SCORE_COLS.reduce((s, c) => s + (props[c] ?? 0) * (weights[c] ?? 0), 0) / totalW
  return (raw - minS) / ((maxS - minS) || 0.0001)
}

const MAX_H = 40

function bar(col, score) {
  const h = Math.round((score ?? 0) * MAX_H)
  const color = METRIC_COLORS[col]
  const icon = METRIC_ICONS[col]
  return `<div style="display:flex;flex-direction:column;align-items:center;width:18px">` +
    `<div style="width:100%;border-radius:2px 2px 0 0;background:${color};min-height:1px;height:${h}px"></div>` +
    `<div style="font-size:12px;margin-top:2px;color:${color}"><i class="fa-solid ${icon}"></i></div>` +
    `</div>`
}

export function buildTooltipHTML(props) {
  const bcName = BC_MAP[props.BC] ?? 'Unknown'
  const normScore = typeof props.norm_score === 'number' ? props.norm_score.toFixed(2) : '—'

  return `<div style="font-family:sans-serif;padding:12px;background:white;border-radius:4px;min-width:160px;">` +
    `<div style="margin-bottom:10px;border-bottom:1px solid #eee;padding-bottom:6px;">` +
    `<div style="font-weight:bold;font-size:16px;color:#233A57;">Site Index: ${normScore}</div>` +
    `<div style="font-size:12px;color:#666;margin-top:2px;">Land Use: ${bcName}</div>` +
    `</div>` +
    `<div style="font-size:8px;font-weight:bold;color:#999;display:flex;justify-content:space-between;margin-bottom:4px;">` +
    `<span>TRANSPORTATION</span><span>JOB ACCESS</span></div>` +
    `<div style="display:flex;gap:6px;height:55px;align-items:flex-end;justify-content:space-between;margin-bottom:12px;">` +
    bar('TT', props.TT) + bar('TF', props.TF) + bar('TA', props.TA) +
    `<div style="width:18px"></div>` +
    bar('AA', props.AA) + bar('AT', props.AT) +
    `</div>` +
    `<div style="font-size:8px;font-weight:bold;color:#999;margin-bottom:4px;">NECESSITIES</div>` +
    `<div style="display:flex;gap:6px;height:55px;align-items:flex-end;justify-content:space-between;">` +
    bar('AC', props.AC) + bar('AH', props.AH) + bar('AE', props.AE) +
    bar('AG', props.AG) + bar('AM', props.AM) + bar('AP', props.AP) +
    `</div></div>`
}
