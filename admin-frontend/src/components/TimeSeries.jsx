import { useEffect, useMemo, useRef, useState } from 'react'

/**
 * A multi-series line chart over time.
 *
 * Interaction is part of the chart, not an upgrade: a crosshair snaps
 * to the nearest bucket and one tooltip reads out every series at that
 * x, so the pointer never has to land on a 2px line. Arrow keys move
 * the same crosshair, so a keyboard reaches every value a pointer does.
 *
 * Nothing here is reachable only by hovering. The last point of each
 * series is labelled on the plot, and the Table button swaps in the
 * whole series as rows — which is also what satisfies the relief rule
 * for the series colours that sit under 3:1 on a white panel.
 *
 * Series colours arrive as CSS custom properties so the themes can
 * restate them for a dark panel; they were validated against both
 * surfaces rather than picked by eye.
 */

const PAD = { top: 16, bottom: 26, left: 44 }

/**
 * Room for the end labels, measured from the labels themselves.
 *
 * A fixed gutter is fine until the chart formats money: "₹1,24,500" is
 * twice the width of "18" and would run off the right edge of the
 * plot. ~6.4px per character at 11.5px semibold, plus the gap and the
 * end dot.
 */
const rightPad = (points, series, format) => {
  if (points.length === 0) return 48
  const last = points[points.length - 1]
  const widest = Math.max(
    ...series.map((s) => String(format(last[s.key] ?? 0)).length),
  )
  return Math.min(120, Math.max(40, 18 + widest * 6.4))
}

/** 0 → a clean round ceiling, so the axis reads in whole steps. */
const niceMax = (v) => {
  if (!(v > 0)) return 1
  const mag = 10 ** Math.floor(Math.log10(v))
  const step = [1, 2, 2.5, 5, 10].find((s) => v <= s * mag) ?? 10
  return step * mag
}

const fmtTick = (n) =>
  n >= 1000 ? `${(n / 1000).toFixed(n % 1000 === 0 ? 0 : 1)}K` : `${n}`

const labelFor = (iso, unit) => {
  const d = new Date(iso)
  if (unit === 'hour') {
    return d.toLocaleTimeString('en-IN', { hour: 'numeric', hour12: true })
  }
  return d.toLocaleDateString('en-IN', { day: 'numeric', month: 'short' })
}

const fullLabel = (iso, unit) => {
  const d = new Date(iso)
  if (unit === 'hour') {
    return d.toLocaleString('en-IN', {
      day: 'numeric',
      month: 'short',
      hour: 'numeric',
      hour12: true,
    })
  }
  const base = d.toLocaleDateString('en-IN', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  })
  return unit === 'week' ? `Week of ${base}` : base
}

export default function TimeSeries({
  points,
  series,
  unit = 'day',
  height = 220,
  format = (n) => n.toLocaleString('en-IN'),
  caption,
}) {
  const wrapRef = useRef(null)
  const [width, setWidth] = useState(640)
  const [hover, setHover] = useState(null)
  const [asTable, setAsTable] = useState(false)

  useEffect(() => {
    const el = wrapRef.current
    if (!el || typeof ResizeObserver === 'undefined') return
    const ro = new ResizeObserver(([entry]) => {
      const w = entry.contentRect.width
      if (w > 0) setWidth(w)
    })
    ro.observe(el)
    return () => ro.disconnect()
  }, [])

  const padRight = useMemo(
    () => rightPad(points, series, format),
    [points, series, format],
  )

  const geom = useMemo(() => {
    const n = points.length
    const innerW = Math.max(60, width - PAD.left - padRight)
    const innerH = Math.max(40, height - PAD.top - PAD.bottom)
    const peak = Math.max(
      0,
      ...points.flatMap((p) => series.map((s) => p[s.key] ?? 0)),
    )
    const max = niceMax(peak)
    const x = (i) => PAD.left + (n <= 1 ? innerW / 2 : (i / (n - 1)) * innerW)
    const y = (v) => PAD.top + innerH - (v / max) * innerH
    return { n, innerW, innerH, max, x, y }
  }, [points, series, width, height, padRight])

  const empty =
    points.length === 0 ||
    points.every((p) => series.every((s) => !p[s.key]))

  // End labels, pushed apart where two series finish close together.
  // Nudging them is honest here because each one sits beside its own
  // end dot — the dot keeps the label attached to its line.
  const endLabels = useMemo(() => {
    const last = points.length - 1
    if (last < 0) return []
    const rows = series
      .map((s) => ({
        key: s.key,
        value: points[last][s.key] ?? 0,
        y: geom.y(points[last][s.key] ?? 0),
      }))
      .sort((a, b) => a.y - b.y)
    // Walk down the list carrying the last placed y forward, so three
    // labels at the same value step apart instead of stacking on one.
    for (let i = 1; i < rows.length; i++) {
      if (rows[i].y - rows[i - 1].y < 14) rows[i].y = rows[i - 1].y + 14
    }
    return rows
  }, [points, series, geom])

  // Five x labels at most, always including the first and the last —
  // a reader checks the ends of a range before anything between them.
  const tickIndexes = useMemo(() => {
    const n = points.length
    if (n <= 1) return [0]
    const want = Math.min(5, n)
    const out = new Set()
    for (let i = 0; i < want; i++) {
      out.add(Math.round((i / (want - 1)) * (n - 1)))
    }
    return [...out].sort((a, b) => a - b)
  }, [points.length])

  const pick = (clientX) => {
    const el = wrapRef.current
    if (!el || points.length === 0) return
    const box = el.getBoundingClientRect()
    const rel = clientX - box.left - PAD.left
    const i = Math.round((rel / geom.innerW) * (points.length - 1))
    setHover(Math.min(points.length - 1, Math.max(0, i)))
  }

  const onKeyDown = (e) => {
    if (points.length === 0) return
    const at = hover ?? points.length - 1
    if (e.key === 'ArrowRight') {
      e.preventDefault()
      setHover(Math.min(points.length - 1, at + 1))
    } else if (e.key === 'ArrowLeft') {
      e.preventDefault()
      setHover(Math.max(0, at - 1))
    } else if (e.key === 'Escape') {
      setHover(null)
    }
  }

  if (asTable || empty) {
    return (
      <div className="chart">
        <div className="chart-tools">
          <Legend series={series} />
          {!empty && (
            <button type="button" className="chart-toggle" onClick={() => setAsTable(false)}>
              Chart
            </button>
          )}
        </div>
        {empty ? (
          <div className="chart-empty">Nothing happened in this period.</div>
        ) : (
          <div className="table-scroll" style={{ maxHeight: 260 }}>
            <table>
              <thead>
                <tr>
                  <th>When</th>
                  {series.map((s) => (
                    <th key={s.key} className="num">
                      {s.label}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {points.map((p) => (
                  <tr key={p.t}>
                    <td>{fullLabel(p.t, unit)}</td>
                    {series.map((s) => (
                      <td key={s.key} className="num">
                        {format(p[s.key] ?? 0)}
                      </td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {caption && <div className="chart-caption">{caption}</div>}
      </div>
    )
  }

  const at = hover
  const gridValues = [0, 0.25, 0.5, 0.75, 1].map((f) => geom.max * f)

  return (
    <div className="chart">
      <div className="chart-tools">
        <Legend series={series} />
        <button type="button" className="chart-toggle" onClick={() => setAsTable(true)}>
          Table
        </button>
      </div>

      <div className="chart-plot" ref={wrapRef}>
        <svg
          width={width}
          height={height}
          role="img"
          tabIndex={0}
          aria-label={`${series.map((s) => s.label).join(' and ')} over time. Use the Table button for the figures.`}
          onPointerMove={(e) => pick(e.clientX)}
          onPointerLeave={() => setHover(null)}
          onKeyDown={onKeyDown}
          onFocus={() => setHover((h) => h ?? points.length - 1)}
          onBlur={() => setHover(null)}
        >
          {gridValues.map((v) => (
            <g key={v}>
              <line
                x1={PAD.left}
                x2={width - padRight}
                y1={geom.y(v)}
                y2={geom.y(v)}
                className="chart-grid"
              />
              <text x={PAD.left - 8} y={geom.y(v) + 4} className="chart-axis" textAnchor="end">
                {fmtTick(Math.round(v))}
              </text>
            </g>
          ))}

          {tickIndexes.map((i) => (
            <text
              key={i}
              x={geom.x(i)}
              y={height - 8}
              className="chart-axis"
              textAnchor={i === 0 ? 'start' : i === points.length - 1 ? 'end' : 'middle'}
            >
              {labelFor(points[i].t, unit)}
            </text>
          ))}

          {at != null && (
            <line
              x1={geom.x(at)}
              x2={geom.x(at)}
              y1={PAD.top}
              y2={PAD.top + geom.innerH}
              className="chart-crosshair"
            />
          )}

          {series.map((s) => {
            const d = points
              .map((p, i) => `${i === 0 ? 'M' : 'L'}${geom.x(i)},${geom.y(p[s.key] ?? 0)}`)
              .join(' ')
            const last = points.length - 1
            return (
              <g key={s.key}>
                <path d={d} fill="none" stroke={s.color} strokeWidth="2"
                  strokeLinejoin="round" strokeLinecap="round" />
                {/* End marker with a surface ring, so two lines that
                    finish at the same value stay countable. */}
                <circle cx={geom.x(last)} cy={geom.y(points[last][s.key] ?? 0)} r="4"
                  fill={s.color} className="chart-dot" />
                {at != null && (
                  <circle cx={geom.x(at)} cy={geom.y(points[at][s.key] ?? 0)} r="4"
                    fill={s.color} className="chart-dot" />
                )}
              </g>
            )
          })}

          {/* The last value of each series, on the plot. The figure
              wears text ink; the dot beside it carries the identity. */}
          {endLabels.map((l) => (
            <text
              key={l.key}
              x={width - padRight + 9}
              y={l.y + 4}
              className="chart-endlabel"
            >
              {format(l.value)}
            </text>
          ))}
        </svg>

        {at != null && (
          <div
            className="chart-tip"
            style={{
              left: Math.min(Math.max(geom.x(at), 70), width - 70),
              top: PAD.top,
            }}
          >
            <div className="chart-tip-when">{fullLabel(points[at].t, unit)}</div>
            {series.map((s) => (
              <div className="chart-tip-row" key={s.key}>
                <span className="chart-tip-key" style={{ background: s.color }} />
                <b>{format(points[at][s.key] ?? 0)}</b>
                <span>{s.label}</span>
              </div>
            ))}
          </div>
        )}
      </div>

      {caption && <div className="chart-caption">{caption}</div>}
    </div>
  )
}

const Legend = ({ series }) => (
  <div className="chart-legend">
    {series.map((s) => (
      <span className="chart-legend-item" key={s.key}>
        <span className="chart-legend-key" style={{ background: s.color }} />
        {s.label}
      </span>
    ))}
  </div>
)
