import { useEffect, useState } from 'react'
import { api } from '../../api'
import PasswordInput from '../../components/PasswordInput.jsx'

/**
 * Payment Gateway settings — the first tab of Settings.
 *
 * After registering with Razorpay you are given a Key ID and a Key
 * Secret, and — once you add a webhook in their dashboard — a webhook
 * secret. This page is where those go. Saving them switches the whole
 * platform from the built-in stand-in to real payments; nothing has to
 * be deployed.
 *
 * The secrets are stored encrypted and are never sent back here, which
 * is why the fields show a mask and sit empty: leaving one blank keeps
 * what is already saved.
 */

const fmtDate = (v) =>
  v ? new Date(v).toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short' }) : '—'

export default function PaymentGateway() {
  const [cfg, setCfg] = useState(null)
  const [provider, setProvider] = useState('dummy')
  const [enabled, setEnabled] = useState(true)
  const [keyId, setKeyId] = useState('')
  const [keySecret, setKeySecret] = useState('')
  const [webhookSecret, setWebhookSecret] = useState('')
  const [saving, setSaving] = useState(false)
  const [testing, setTesting] = useState(false)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')

  const apply = (data) => {
    setCfg(data)
    setProvider(data.provider || 'dummy')
    setEnabled(data.enabled !== false)
    setKeyId(data.keyId || '')
  }

  const describe = (err) =>
    err?.response?.status === 403
      ? 'Your admin account does not have access to payment settings.'
      : err?.response?.data?.message || 'Could not load payment settings'

  const load = () =>
    api
      .get('/admin/settings/payment')
      .then((r) => apply(r.data))
      .catch((err) => setError(describe(err)))

  useEffect(() => {
    let cancelled = false
    api
      .get('/admin/settings/payment')
      .then((r) => {
        if (!cancelled) apply(r.data)
      })
      .catch((err) => {
        if (!cancelled) setError(describe(err))
      })
    return () => {
      cancelled = true
    }
  }, [])

  const save = async (e) => {
    e.preventDefault()
    setSaving(true)
    setError('')
    setNotice('')
    try {
      const { data } = await api.put('/admin/settings/payment', {
        provider,
        enabled,
        keyId: keyId.trim(),
        // Empty means "keep the saved one" — the server reads it that
        // way, and this page has no way to show what is already there.
        keySecret: keySecret.trim(),
        webhookSecret: webhookSecret.trim(),
      })
      setCfg({ ...data, webhookEvents: cfg?.webhookEvents })
      setKeySecret('')
      setWebhookSecret('')
      setNotice(
        data.provider === 'razorpay'
          ? 'Saved. Use Test Connection to confirm Razorpay accepts these keys.'
          : 'Saved. Payments are running on the built-in stand-in gateway.'
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
      const { data } = await api.post('/admin/settings/payment/test')
      setNotice(data.message || 'Credentials verified')
      load()
    } catch (err) {
      setError(err?.response?.data?.message || 'Razorpay rejected these credentials')
    } finally {
      setTesting(false)
    }
  }

  const copyWebhook = () => {
    if (!cfg?.webhookUrl) return
    navigator.clipboard?.writeText(cfg.webhookUrl)
    setNotice('Webhook URL copied')
  }

  const live = cfg?.provider === 'razorpay' && cfg?.mode === 'live'
  const dirtyKeyId = cfg?.keyId && keyId.trim() !== cfg.keyId

  return (
    <div>
      {/* No heading: the tab above already says Payment Gateway, and
          repeating it put the same words twice within 40 pixels. */}
      <div className="panel-intro">
        <p>
          The Razorpay credentials this install runs on. Saving them switches
          the platform between the built-in stand-in and real card payments,
          with no deploy in between.
        </p>
        {cfg && (
          <div className="panel-intro-actions">
            <span className={`badge ${live ? 'green' : cfg.provider === 'razorpay' ? 'blue' : 'gray'}`}>
              {cfg.provider === 'razorpay'
                ? live
                  ? 'Live — real money'
                  : 'Razorpay test mode'
                : 'Stand-in gateway'}
            </span>
          </div>
        )}
      </div>

      {error && <div className="error" style={{ marginBottom: 14 }}>{error}</div>}
      {notice && (
        <div className="card" style={{ marginBottom: 14, borderColor: '#86efac', background: '#f0fdf4' }}>
          {notice}
        </div>
      )}

      {cfg && !cfg.canStoreSecrets && (
        <div className="card" style={{ marginBottom: 14, borderColor: '#fca5a5', background: '#fef2f2' }}>
          This server has no encryption key, so secrets cannot be stored. Set
          <code> SETTINGS_ENCRYPTION_KEY</code> (or <code>JWT_SECRET</code>) in the
          backend environment and restart.
        </div>
      )}

      <form className="card form-narrow" onSubmit={save}>
        <label style={{ display: 'block', marginBottom: 16 }}>
          <div style={{ fontSize: 13, color: '#666', marginBottom: 6 }}>Provider</div>
          <select
            className="input"
            value={provider}
            onChange={(e) => setProvider(e.target.value)}
            style={{ width: '100%' }}
          >
            <option value="dummy">Stand-in (no real money moves)</option>
            <option value="razorpay">Razorpay</option>
          </select>
        </label>

        {provider === 'razorpay' && (
          <>
            <label style={{ display: 'block', marginBottom: 16 }}>
              <div style={{ fontSize: 13, color: '#666', marginBottom: 6 }}>
                Key ID
                <span style={{ color: '#999' }}> — from Razorpay Dashboard → Account &amp; Settings → API Keys</span>
              </div>
              <input
                className="input"
                style={{ width: '100%' }}
                value={keyId}
                onChange={(e) => setKeyId(e.target.value)}
                placeholder="rzp_test_xxxxxxxxxxxxxx"
                autoComplete="off"
              />
              {keyId.startsWith('rzp_live_') && (
                <div style={{ fontSize: 13, color: '#b45309', marginTop: 6 }}>
                  This is a live key. Saving it means the next payment charges a real card.
                </div>
              )}
            </label>

            <label style={{ display: 'block', marginBottom: 16 }}>
              <div style={{ fontSize: 13, color: '#666', marginBottom: 6 }}>
                Key Secret
                {cfg?.hasKeySecret && !dirtyKeyId && (
                  <span style={{ color: '#999' }}>
                    {' '}— saved ({cfg.keySecretMasked}). Leave blank to keep it.
                  </span>
                )}
              </div>
              <PasswordInput
                value={keySecret}
                onChange={(e) => setKeySecret(e.target.value)}
                placeholder={cfg?.hasKeySecret ? '••••••••••••' : 'Paste the key secret'}
                autoComplete="new-password"
              />
              <div style={{ fontSize: 13, color: '#999', marginTop: 6 }}>
                Razorpay shows the secret once, when the key is created. If it was
                lost, generate a new key pair there and paste both fields here.
              </div>
            </label>

            <label style={{ display: 'block', marginBottom: 16 }}>
              <div style={{ fontSize: 13, color: '#666', marginBottom: 6 }}>
                Webhook Secret
                {cfg?.hasWebhookSecret && (
                  <span style={{ color: '#999' }}>
                    {' '}— saved ({cfg.webhookSecretMasked}). Leave blank to keep it.
                  </span>
                )}
              </div>
              <PasswordInput
                value={webhookSecret}
                onChange={(e) => setWebhookSecret(e.target.value)}
                placeholder={cfg?.hasWebhookSecret ? '••••••••••••' : 'The secret you typed when adding the webhook'}
                autoComplete="new-password"
              />
            </label>

            <div
              className="card"
              style={{ background: '#f8fafc', marginBottom: 16, padding: '14px 16px' }}
            >
              <div style={{ fontSize: 13, color: '#666', marginBottom: 6 }}>
                Add this URL as a webhook in the Razorpay dashboard
              </div>
              <div className="row">
                <code style={{ flex: 1, fontSize: 13, wordBreak: 'break-all' }}>
                  {cfg?.webhookUrl || '—'}
                </code>
                <button type="button" className="btn secondary" onClick={copyWebhook}>
                  Copy
                </button>
              </div>
              <div style={{ fontSize: 13, color: '#666', marginTop: 10 }}>
                Subscribe to: {(cfg?.webhookEvents || []).join(', ') || 'payment.captured, payment.failed, refund.processed'}
              </div>
              <div style={{ fontSize: 13, color: '#999', marginTop: 6 }}>
                Without a webhook, a payment still works — but if the app is closed
                before it confirms, nobody is told the money arrived.
              </div>
            </div>
          </>
        )}

        <label className="row" style={{ marginBottom: 18, cursor: 'pointer' }}>
          <input
            type="checkbox"
            checked={enabled}
            onChange={(e) => setEnabled(e.target.checked)}
          />
          <span>
            Enabled
            <span style={{ color: '#999' }}>
              {' '}— unticking falls back to the stand-in gateway, so payments keep working
            </span>
          </span>
        </label>

        <div className="row">
          <button className="btn" type="submit" disabled={saving}>
            {saving ? 'Saving…' : 'Save'}
          </button>
          {cfg?.provider === 'razorpay' && (
            <button
              type="button"
              className="btn secondary"
              onClick={test}
              disabled={testing}
            >
              {testing ? 'Checking…' : 'Test Connection'}
            </button>
          )}
        </div>
      </form>

      {cfg && (
        <div className="card" style={{ marginTop: 18 }}>
          <h4 style={{ marginTop: 0 }}>Current status</h4>
          <Row label="Gateway in use" value={cfg.provider === 'razorpay' ? 'Razorpay' : 'Stand-in'} />
          <Row label="Mode" value={cfg.mode === 'live' ? 'Live' : 'Test'} />
          <Row
            label="Credentials from"
            value={
              { admin: 'This panel', env: 'Server environment', default: 'Built-in default', disabled: 'Switched off here' }[
                cfg.source
              ] || cfg.source
            }
          />
          <Row label="Key ID" value={cfg.keyId || '—'} />
          <Row label="Key Secret" value={cfg.hasKeySecret ? cfg.keySecretMasked : 'Not set'} />
          <Row
            label="Webhook Secret"
            value={cfg.hasWebhookSecret ? cfg.webhookSecretMasked : 'Not set'}
          />
          <Row label="Last verified" value={fmtDate(cfg.lastVerifiedAt)} />
          <Row
            label="Last changed"
            value={`${fmtDate(cfg.updatedAt)}${cfg.updatedByName ? ` by ${cfg.updatedByName}` : ''}`}
          />
        </div>
      )}
    </div>
  )
}

const Row = ({ label, value }) => (
  <div
    className="row"
    style={{ justifyContent: 'space-between', padding: '8px 0', borderBottom: '1px solid #f1f5f9' }}
  >
    <span style={{ color: '#666', fontSize: 14 }}>{label}</span>
    <span style={{ fontSize: 14, wordBreak: 'break-all', textAlign: 'right' }}>{value}</span>
  </div>
)
