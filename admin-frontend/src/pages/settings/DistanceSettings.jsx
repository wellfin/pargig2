import { useEffect, useState } from 'react'
import { api } from '../../api'
import PasswordInput from '../../components/PasswordInput.jsx'

/**
 * Where road distances come from.
 *
 * Two providers, and choosing one switches the other off — there is
 * no fallback from a paid service to a free one, because a bill and a
 * set of numbers changing with nothing saying so is worse than a
 * missing distance.
 *
 * The cost difference is stated on the form rather than left to be
 * discovered. Google is billed per element, and a Hire-mode feed is
 * one element per worker shown, every time it loads — which is a real
 * number per day, not a rounding error.
 *
 * Whichever is in force, a provider that cannot answer falls back to
 * the straight line times a detour factor, so a card never shows a
 * crow-flies number. That factor is editable because the right value
 * for a dense city is not the right value for a district.
 */
export default function DistanceSettings() {
  const [cfg, setCfg] = useState(null)
  const [enabled, setEnabled] = useState(true)
  const [provider, setProvider] = useState('osrm')
  const [googleKey, setGoogleKey] = useState('')
  const [baseUrl, setBaseUrl] = useState('')
  const [factor, setFactor] = useState('1.35')
  const [saving, setSaving] = useState(false)
  const [testing, setTesting] = useState(false)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')

  const apply = (d) => {
    setCfg(d)
    setEnabled(d.enabled !== false)
    // wantedProvider, not provider: if Google was chosen but has no
    // key the server runs OSRM, and the form has to keep showing what
    // was asked for or the radio jumps back under the cursor.
    setProvider(d.wantedProvider || d.provider || 'osrm')
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
        provider,
        googleKey: googleKey.trim(),
        baseUrl: baseUrl.trim(),
        detourFactor: Number(factor),
      })
      apply(data)
      setGoogleKey('')
      setNotice(
        data.provider === 'google'
          ? 'Saved. Google is measuring distances now, and OSRM is no longer '
            + 'called.'
          : 'Saved. OSRM is measuring distances.',
      )
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
  const live = cfg.provider === 'google' ? 'Google' : 'OSRM'

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
          <span
            className={`badge ${
              !enabled
                ? 'gray'
                : cfg.provider === 'google'
                  ? 'blue'
                  : onPublic
                    ? 'yellow'
                    : 'green'
            }`}
          >
            {!enabled
              ? 'Off — estimates only'
              : cfg.provider === 'google'
                ? 'Google — billed per lookup'
                : onPublic
                  ? 'OSRM public demo server'
                  : 'OSRM self-hosted'}
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
            Ask {live} for real road distances. Unticking skips the request
            entirely and uses the estimate below.
          </span>
        </label>

        <fieldset className="choices" style={{ marginBottom: 18 }}>
          <legend className="field-label">Provider</legend>
          <label className={`choice${provider === 'osrm' ? ' is-on' : ''}`}>
            <input
              type="radio"
              name="distance-provider"
              value="osrm"
              checked={provider === 'osrm'}
              onChange={() => setProvider('osrm')}
            />
            <span className="choice-body">
              <span className="choice-name">OSRM</span>
              <span className="choice-hint">
                Open and free, no account. About 95 points per request, so a
                whole screen costs one call.
              </span>
            </span>
          </label>
          <label className={`choice${provider === 'google' ? ' is-on' : ''}`}>
            <input
              type="radio"
              name="distance-provider"
              value="google"
              checked={provider === 'google'}
              onChange={() => setProvider('google')}
            />
            <span className="choice-body">
              <span className="choice-name">Google Distance Matrix</span>
              <span className="choice-hint">
                More accurate, knows one-way streets and traffic. Billed per
                lookup, {cfg.googleMaxDests} destinations per request.
              </span>
            </span>
          </label>
        </fieldset>

        {provider === 'google' && (
          <div className="form-field" style={{ marginBottom: 14 }}>
            <label className="field-label" htmlFor="google-key">
              Google API key
            </label>
            <PasswordInput
              id="google-key"
              value={googleKey}
              autoComplete="off"
              placeholder={
                cfg.hasGoogleKey ? cfg.googleKeyMasked || '••••••••' : 'From the Google Cloud console'
              }
              onChange={(e) => setGoogleKey(e.target.value)}
            />
            <span className="form-hint">
              {cfg.hasGoogleKey
                ? 'Saved. Leave blank to keep it.'
                : 'Stored encrypted and never shown again.'}{' '}
              The key needs the Distance Matrix API enabled and billing on —
              a key that looks right but has neither is the usual reason this
              fails.
            </span>
            <span className="form-hint">
              <strong>What this costs:</strong> one lookup per worker shown,
              every time a Hire-mode feed loads. Twenty workers on screen is
              twenty lookups. Restrict the key to the Distance Matrix API in
              the console so a leak cannot be spent on anything else.
            </span>
          </div>
        )}

        {cfg.googleNeedsKey && (
          <div className="error" style={{ marginBottom: 14 }}>
            Google is selected but has no key saved, so OSRM is being used.
            Add a key and save.
          </div>
        )}

        <div
          className="form-field"
          style={{ marginBottom: 14, display: provider === 'osrm' ? undefined : 'none' }}
        >
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
          The test asks {live} for one real route between two known points and
          reports how long it took. On Google that spends one lookup, which is
          the point — a test that costs nothing would not prove billing is on,
          and billing is the usual reason a key that looks right still fails.
        </p>
      </form>
    </section>
  )
}
