import { useEffect, useState } from 'react'
import { api } from '../../api'

/**
 * Where road distances come from.
 *
 * There is no API key here, which is the first thing to say because
 * it is the usual assumption. Distances come from OSRM, which is open
 * and needs no account. What is configurable is WHICH OSRM: the
 * public demo server by default, or your own, which is the answer
 * when the demo server starts rate-limiting.
 *
 * When it cannot be reached, distance falls back to the straight line
 * multiplied by a detour factor, so a card always shows a plausible
 * road distance rather than an obviously short crow-flies one. That
 * factor is editable because the right number for a dense city is not
 * the right number for a district.
 */
export default function DistanceSettings() {
  const [cfg, setCfg] = useState(null)
  const [enabled, setEnabled] = useState(true)
  const [baseUrl, setBaseUrl] = useState('')
  const [factor, setFactor] = useState('1.35')
  const [saving, setSaving] = useState(false)
  const [testing, setTesting] = useState(false)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')

  const apply = (d) => {
    setCfg(d)
    setEnabled(d.enabled !== false)
    setBaseUrl(d.baseUrl || '')
    setFactor(String(d.detourFactor ?? 1.35))
  }

  useEffect(() => {
    let off = false
    api
      .get('/admin/settings/routing')
      .then((r) => { if (!off) apply(r.data) })
      .catch((e) => {
        if (!off) setError(e?.response?.data?.message || 'Could not load distance settings')
      })
    return () => { off = true }
  }, [])

  const save = async (e) => {
    e.preventDefault()
    setSaving(true)
    setError('')
    setNotice('')
    try {
      const { data } = await api.put('/admin/settings/routing', {
        enabled,
        baseUrl: baseUrl.trim(),
        detourFactor: Number(factor),
      })
      apply(data)
      setNotice('Saved. It applies to the next distance that is worked out.')
    } catch (err) {
      setError(err?.response?.data?.message || 'Could not save')
    } finally {
      setSaving(false)
    }
  }

  const test = async () => {
    setTesting(true)
    setError('')
    setNotice('')
    try {
      const { data } = await api.post('/admin/settings/routing/test')
      setNotice(data.message || 'Answered')
    } catch (err) {
      setError(err?.response?.data?.message || 'No route came back')
    } finally {
      setTesting(false)
    }
  }

  if (!cfg) return <p className="muted">Loading…</p>

  const onPublic = baseUrl.includes('router.project-osrm.org')

  return (
    <section className="card form-narrow">
      <div className="panel-intro" style={{ marginBottom: 14 }}>
        <div>
          <h4 style={{ margin: 0 }}>Distance — OSRM</h4>
          <p style={{ margin: '4px 0 0' }}>
            Measures the road distance shown on worker and job cards.
            No API key: OSRM is open.
          </p>
        </div>
        <div className="panel-intro-actions">
          <span className={`badge ${enabled ? (onPublic ? 'yellow' : 'green') : 'gray'}`}>
            {!enabled ? 'Off — estimates only' : onPublic ? 'Public demo server' : 'Self-hosted'}
          </span>
        </div>
      </div>

      {error && <div className="error" style={{ marginBottom: 14 }}>{error}</div>}
      {notice && (
        <div
          className="card"
          style={{ marginBottom: 14, borderColor: '#86efac', background: '#f0fdf4' }}
        >
          {notice}
        </div>
      )}

      <form onSubmit={save}>
        <label className="row" style={{ marginBottom: 16, cursor: 'pointer' }}>
          <input
            type="checkbox"
            checked={enabled}
            onChange={(e) => setEnabled(e.target.checked)}
          />
          <span style={{ fontSize: 13.5 }}>
            Ask OSRM for real road distances. Unticking skips the request
            entirely and uses the estimate below.
          </span>
        </label>

        <div className="form-field" style={{ marginBottom: 14 }}>
          <label className="field-label" htmlFor="osrm-url">OSRM server</label>
          <input
            id="osrm-url"
            className="input"
            value={baseUrl}
            placeholder={cfg.defaultBaseUrl}
            onChange={(e) => setBaseUrl(e.target.value)}
          />
          <span className="form-hint">
            {onPublic
              ? 'The public demo server. Free and fine to start on, but it '
                + 'rate-limits and carries no promise of being up — move to '
                + 'your own before it matters.'
              : 'Your own server. Nothing leaves for a third party.'}
          </span>
        </div>

        <div className="form-field" style={{ marginBottom: 14 }}>
          <label className="field-label" htmlFor="osrm-factor">
            Fallback detour factor
          </label>
          <input
            id="osrm-factor"
            className="input"
            type="number"
            step="0.05"
            min="1"
            max="3"
            style={{ maxWidth: 160 }}
            value={factor}
            onChange={(e) => setFactor(e.target.value)}
          />
          <span className="form-hint">
            Used only when OSRM cannot be reached: straight-line distance is
            multiplied by this. {cfg.defaultDetourFactor} suits a mixed city.
            Raise it where roads wind, lower it on a grid. A card never shows a
            crow-flies number, because that reads as nearer than anyone is.
          </span>
        </div>

        <div className="row" style={{ gap: 8 }}>
          <button className="btn" disabled={saving}>
            {saving ? 'Saving…' : 'Save'}
          </button>
          <button
            type="button"
            className="btn secondary"
            onClick={test}
            disabled={testing}
          >
            {testing ? 'Asking…' : 'Test the server'}
          </button>
        </div>
        <p className="muted" style={{ marginTop: 10, marginBottom: 0, fontSize: 12.5 }}>
          The test asks for one real route between two known points and reports
          how long it took. A server that answers slowly is worth knowing about
          before it is measuring every card.
        </p>
      </form>
    </section>
  )
}
