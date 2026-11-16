import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { api } from '../api'

/**
 * Where the work is, and how it ends up there.
 *
 * One row per city: the split as a thin bar, the figures beside it.
 * The bar carries no text of its own — the columns next to it already
 * give every number, and printing them on the segments would say the
 * same thing twice in a smaller font. One legend serves the table.
 *
 * Those figures are also what makes the bar legal: two of the four
 * segment colours sit under 3:1 on a white panel, and a reader who
 * cannot separate them still has the counts in the columns.
 *
 * Scoped to the range chosen above it, like everything else on this
 * page — a filter that some panels ignored would be worse than none.
 */

const SEGMENTS = [
  { key: 'open', label: 'Open or in progress', color: 'var(--viz-1)' },
  { key: 'completed', label: 'Completed', color: 'var(--viz-2)' },
  { key: 'cancelled', label: 'Cancelled', color: 'var(--viz-3)' },
  { key: 'disputed', label: 'Disputed', color: 'var(--viz-4)' },
]

const money = (n) =>
  `₹${Number(n || 0).toLocaleString('en-IN', { maximumFractionDigits: 0 })}`

const num = (n) => Number(n || 0).toLocaleString('en-IN')

export default function GeoPanel({ range }) {
  const [data, setData] = useState(null)

  useEffect(() => {
    let cancelled = false
    api
      .get('/admin/insights/geography', { params: range })
      .then((r) => {
        if (!cancelled) setData(r.data)
      })
      .catch(() => {})
    return () => {
      cancelled = true
    }
  }, [range])

  const rows = data?.rows || []
  const t = data?.totals

  return (
    <section className="panel">
      <div className="panel-head">
        <h3>Jobs by location</h3>
        <span className="panel-note">
          {data
            ? data.cities > data.shown
              ? `top ${data.shown} of ${data.cities} cities`
              : `${data.cities} ${data.cities === 1 ? 'city' : 'cities'}`
            : ''}
        </span>
      </div>
      <div className="panel-body">
        {!data ? (
          <div className="muted">Loading…</div>
        ) : rows.length === 0 ? (
          <div className="chart-empty">No jobs were posted in this period.</div>
        ) : (
          <>
            <div className="chart-legend" style={{ marginBottom: 14 }}>
              {SEGMENTS.map((s) => (
                <span className="chart-legend-item" key={s.key}>
                  <span
                    className="chart-legend-swatch"
                    style={{ background: s.color }}
                  />
                  {s.label}
                </span>
              ))}
            </div>

            <div className="table-scroll" style={{ maxHeight: 420 }}>
              <table>
                <thead>
                  <tr>
                    <th>City</th>
                    <th>Split</th>
                    <th className="num">Jobs</th>
                    <th className="num">Open</th>
                    <th className="num">Done</th>
                    <th className="num">Cancelled</th>
                    <th className="num">Disputed</th>
                    <th className="num">Value</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((r) => (
                    <tr key={r.city}>
                      <td>
                        <Link to={`/jobs?city=${encodeURIComponent(r.city)}`}>
                          {r.city}
                        </Link>
                      </td>
                      <td style={{ minWidth: 150 }}>
                        <Split row={r} />
                      </td>
                      <td className="num">{num(r.total)}</td>
                      <td className="num">{num(r.open)}</td>
                      <td className="num">{num(r.completed)}</td>
                      <td className="num">{num(r.cancelled)}</td>
                      <td className="num">{num(r.disputed)}</td>
                      <td className="num">{money(r.value)}</td>
                    </tr>
                  ))}
                </tbody>
                {t && (
                  <tfoot>
                    <tr>
                      <td colSpan={2}>All cities</td>
                      <td className="num">{num(t.total)}</td>
                      <td className="num">{num(t.open)}</td>
                      <td className="num">{num(t.completed)}</td>
                      <td className="num">{num(t.cancelled)}</td>
                      <td className="num">{num(t.disputed)}</td>
                      <td className="num">{money(t.value)}</td>
                    </tr>
                  </tfoot>
                )}
              </table>
            </div>
            <div className="chart-caption">
              Open folds in confirmed, reached and in progress — from here they
              are the same thing: started, not finished. A city name is a link
              into the jobs list filtered to it.
            </div>
          </>
        )}
      </div>
    </section>
  )
}

const Split = ({ row }) => {
  const total = row.total || 1
  return (
    <span
      className="split"
      role="img"
      aria-label={SEGMENTS.map((s) => `${row[s.key]} ${s.label}`).join(', ')}
    >
      {SEGMENTS.map((s) =>
        row[s.key] > 0 ? (
          <span
            key={s.key}
            style={{
              background: s.color,
              // Percentages of the row's own total, so every bar fills
              // its track: the row is a split, not a comparison
              // between cities. The Jobs column carries that.
              flexGrow: (row[s.key] / total) * 100,
            }}
          />
        ) : null,
      )}
    </span>
  )
}
