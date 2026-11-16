import { useEffect, useMemo, useState } from 'react'
import { api } from '../api'
import TimeSeries from '../components/TimeSeries.jsx'
import GeoPanel from '../components/GeoPanel.jsx'

const PRESETS = [
  { id: 'today', label: 'Today', days: 0 },
  { id: '7', label: '7 days', days: 6 },
  { id: '30', label: '30 days', days: 29 },
  { id: '90', label: '90 days', days: 89 },
]

const iso = (d) => d.toISOString()
const dayInput = (d) => d.toISOString().slice(0, 10)

/** Midnight IST for a yyyy-mm-dd the operator typed, as an instant. */
const startOfDay = (ymd) => new Date(`${ymd}T00:00:00+05:30`)
const endOfDay = (ymd) => new Date(`${ymd}T23:59:59+05:30`)

const rangeFor = (preset) => {
  const now = new Date()
  const p = PRESETS.find((x) => x.id === preset)
  if (!p) return null
  const from = new Date(now)
  from.setHours(0, 0, 0, 0)
  from.setDate(from.getDate() - p.days)
  return { from: iso(from), to: iso(now) }
}

const money = (n) =>
  `₹${Number(n || 0).toLocaleString('en-IN', { maximumFractionDigits: 0 })}`

const count = (n) => Number(n || 0).toLocaleString('en-IN')

export default function Analytics() {
  const [preset, setPreset] = useState('30')
  const [custom, setCustom] = useState(() => {
    const to = new Date()
    const from = new Date()
    from.setDate(from.getDate() - 29)
    return { from: dayInput(from), to: dayInput(to) }
  })
  // One piece of state, stamped with the range it answers. "Loading"
  // is then a comparison rather than a flag the effect has to set
  // before it starts, and the previous slice stays on screen while the
  // next one is on its way.
  const [result, setResult] = useState({ data: null, error: '', forRange: null })

  const range = useMemo(() => {
    if (preset === 'custom') {
      return { from: iso(startOfDay(custom.from)), to: iso(endOfDay(custom.to)) }
    }
    return rangeFor(preset)
  }, [preset, custom])

  const { data, error } = result
  const loading = result.forRange !== range

  useEffect(() => {
    let cancelled = false
    api
      .get('/admin/insights/timeline', { params: range })
      .then((r) => {
        if (!cancelled) setResult({ data: r.data, error: '', forRange: range })
      })
      .catch((e) => {
        if (cancelled) return
        // Keep whatever is already drawn: a failed refresh should not
        // wipe the figures the reader was looking at.
        setResult((prev) => ({
          ...prev,
          error: e?.response?.data?.message || 'Could not load the figures',
          forRange: range,
        }))
      })
    return () => {
      cancelled = true
    }
  }, [range])

  const points = data?.points || []
  const unit = data?.unit || 'day'
  const t = data?.totals

  // Completed out of created inside the same window is a ratio across
  // two different cohorts — jobs posted before it finish inside it. It
  // is a throughput reading, not a success rate, and the caption says so.
  const throughput =
    t && t.created > 0 ? Math.round((t.completed / t.created) * 100) : null

  return (
    // Held at reduced opacity rather than blanked while a new range
    // loads: the frame stays, so nothing jumps and the reader keeps
    // their place.
    <div className={`dash${loading && data ? ' is-loading' : ''}`}>
      <div className="filter-row">
        {PRESETS.map((p) => (
          <button
            key={p.id}
            type="button"
            className={`seg${preset === p.id ? ' on' : ''}`}
            onClick={() => setPreset(p.id)}
          >
            {p.label}
          </button>
        ))}
        <button
          type="button"
          className={`seg${preset === 'custom' ? ' on' : ''}`}
          onClick={() => setPreset('custom')}
        >
          Custom
        </button>

        {preset === 'custom' && (
          <span className="filter-dates">
            <input
              type="date"
              className="input"
              value={custom.from}
              max={custom.to}
              onChange={(e) => setCustom((c) => ({ ...c, from: e.target.value }))}
              aria-label="From date"
            />
            <span className="filter-sep">to</span>
            <input
              type="date"
              className="input"
              value={custom.to}
              min={custom.from}
              max={dayInput(new Date())}
              onChange={(e) => setCustom((c) => ({ ...c, to: e.target.value }))}
              aria-label="To date"
            />
          </span>
        )}
      </div>

      {error && <div className="panel panel-error">{error}</div>}

      <div className="figures">
        <Fig label="Jobs created" value={count(t?.created)} />
        <Fig
          label="Jobs completed"
          value={count(t?.completed)}
          note={throughput === null ? null : `${throughput}% of created, same window`}
        />
        <Fig label="Cancelled" value={count(t?.cancelled)} />
        <Fig label="Disputes raised" value={count(t?.disputed)} />
        <Fig label="Value completed" value={money(t?.value)} />
      </div>

      <section className="panel">
        <div className="panel-head">
          <h3>Jobs created vs completed</h3>
          <span className="panel-note">per {unit}</span>
        </div>
        <div className="panel-body">
          <TimeSeries
            points={points}
            unit={unit}
            format={count}
            series={[
              { key: 'created', label: 'Created', color: 'var(--viz-1)' },
              { key: 'completed', label: 'Completed', color: 'var(--viz-2)' },
            ]}
            caption="Each job counts on its own date — posted in one bucket, finished in another — so the gap between the lines is the work still in flight."
          />
        </div>
      </section>

      <section className="panel">
        <div className="panel-head">
          <h3>Cancellations and disputes</h3>
          <span className="panel-note">per {unit}</span>
        </div>
        <div className="panel-body">
          <TimeSeries
            points={points}
            unit={unit}
            format={count}
            series={[
              { key: 'cancelled', label: 'Cancelled', color: 'var(--viz-3)' },
              { key: 'disputed', label: 'Disputes raised', color: 'var(--viz-4)' },
            ]}
            caption="Cancellations count on the day the job was cancelled; disputes on the day the report was filed."
          />
        </div>
      </section>

      <GeoPanel range={range} />

      <section className="panel">
        <div className="panel-head">
          <h3>Value of work completed</h3>
          <span className="panel-note">per {unit}</span>
        </div>
        <div className="panel-body">
          <TimeSeries
            points={points}
            unit={unit}
            height={200}
            format={money}
            series={[{ key: 'value', label: 'Value completed', color: 'var(--viz-1)' }]}
            caption="Agreed price where one was settled, the asking price until then, plus the tip."
          />
        </div>
      </section>
    </div>
  )
}

const Fig = ({ label, value, note }) => (
  <div className="figure">
    <div className="figure-label">{label}</div>
    <div className="figure-value num">{value}</div>
    {note && <div className="figure-note">{note}</div>}
  </div>
)
