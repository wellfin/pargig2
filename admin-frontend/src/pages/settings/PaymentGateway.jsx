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
        <div className="notice ok">
          {notice}
        </div>
      )}

      {cfg && !cfg.canStoreSecrets && (
        <div className="notice bad">
          This server has no encryption key, so secrets cannot be stored. Set
          <code> SETTINGS_ENCRYPTION_KEY</code> (or <code>JWT_SECRET</code>) in the
          backend environment and restart.
        </div>
      )}

      <form className="card form-narrow" onSubmit={save}>
        <fieldset className="choices" style={{ marginBottom: 18 }}>
          <legend className="field-label">Provider</legend>
          <label className={`choice${provider === 'dummy' ? ' is-on' : ''}`}>
            <input
              type="radio"
              name="payment-provider"
              value="dummy"
              checked={provider === 'dummy'}
              onChange={() => setProvider('dummy')}
            />
            <span className="choice-body">
              <span className="choice-name">Stand-in gateway</span>
              <span className="choice-hint">
                No real money moves. Every Pay button still works, so the app
                is usable end to end. Keeps any saved key pair.
              </span>
            </span>
          </label>
          <label className={`choice${provider === 'razorpay' ? ' is-on' : ''}`}>
            <input
              type="radio"
              name="payment-provider"
              value="razorpay"
              checked={provider === 'razorpay'}
              onChange={() => setProvider('razorpay')}
            />
            <span className="choice-body">
              <span className="choice-name">Razorpay</span>
              <span className="choice-hint">
                Real payments. Needs a key pair; a key starting rzp_live_
                charges real cards.
              </span>
            </span>
          </label>
        </fieldset>

        <div className="form-field" style={{ marginBottom: 16 }}>
          <label className="field-label" htmlFor="rzp-key-id">Key ID</label>
          <input
            id="rzp-key-id"
            className="input"
            value={keyId}
            onChange={(e) => setKeyId(e.target.value)}
            placeholder="rzp_test_xxxxxxxxxxxxxx"
            autoComplete="off"
          />
          <span className="form-hint">
            Razorpay Dashboard → Account &amp; Settings → API Keys.
          </span>
          {/* Warnings keep their own colour rather than the hint grey:
              they are about to change what happens to real money, and
              a hint reads as something you may skip. */}
          {keyId.startsWith('rzp_live_') && (
            <span className="form-hint" style={{ color: 'var(--yellow)' }}>
              This is a live key. Saving it means the next payment charges a
              real card.
            </span>
          )}
          {!keyId.trim() && cfg?.keyId && (
            <span className="form-hint" style={{ color: 'var(--yellow)' }}>
              Saving with this empty removes the key and both secrets, and
              payments go back to the stand-in.
            </span>
          )}
        </div>

        <div className="form-field" style={{ marginBottom: 16 }}>
          <label className="field-label" htmlFor="rzp-key-secret">Key Secret</label>
          <PasswordInput
            id="rzp-key-secret"
            value={keySecret}
            onChange={(e) => setKeySecret(e.target.value)}
            placeholder={cfg?.hasKeySecret ? '••••••••••••' : 'Paste the key secret'}
            autoComplete="new-password"
          />
          <span className="form-hint">
            {cfg?.hasKeySecret && !dirtyKeyId
              ? `Saved (${cfg.keySecretMasked}). Leave blank to keep it.`
              : 'Stored encrypted and never shown again.'}{' '}
            Razorpay shows the secret once, when the key is created. If it was
            lost, generate a new key pair there and paste both fields here.
          </span>
        </div>

        <div className="form-field" style={{ marginBottom: 16 }}>
          <label className="field-label" htmlFor="rzp-webhook-secret">
            Webhook Secret
          </label>
          <PasswordInput
            id="rzp-webhook-secret"
            value={webhookSecret}
            onChange={(e) => setWebhookSecret(e.target.value)}
            placeholder={cfg?.hasWebhookSecret ? '••••••••••••' : 'The secret you typed when adding the webhook'}
            autoComplete="new-password"
          />
          <span className="form-hint">
            {cfg?.hasWebhookSecret
              ? `Saved (${cfg.webhookSecretMasked}). Leave blank to keep it.`
              : 'Optional — payments work without it, only the out-of-band '
                + 'confirmations do not.'}
          </span>
        </div>

        <div
          className="card"
          style={{ background: 'var(--panel-sunk)', marginBottom: 16, padding: '14px 16px' }}
        >
          <span className="field-label">Webhook URL</span>
          <div className="row" style={{ marginTop: 2 }}>
            <code style={{ flex: 1, fontSize: 13, wordBreak: 'break-all' }}>
              {cfg?.webhookUrl || '—'}
            </code>
            <button type="button" className="btn secondary sm" onClick={copyWebhook}>
              Copy
            </button>
          </div>
          <span className="form-hint">
            Add this in the Razorpay dashboard and subscribe to{' '}
            {(cfg?.webhookEvents || []).join(', ')
              || 'payment.captured, payment.failed, refund.processed'}.
          </span>
          <span className="form-hint">
            Without a webhook a payment still works — but if the app is closed
            before it confirms, nobody is told the money arrived.
          </span>
        </div>

        {/* The Enabled tick used to live here. It meant "keep the keys
            but run the stand-in", which is now exactly what choosing
            the stand-in above does — two controls for one decision,
            and a state where they could disagree. The radio carries
            it. */}
        <p
          className="muted"
          style={{ margin: '0 0 18px', fontSize: 12.5, lineHeight: 1.6, maxWidth: 560 }}
        >
          {provider === 'razorpay' ? (
            <>
              Switch to the stand-in if Razorpay is down or you need to stop
              taking money now. Nothing on the app breaks — the Pay button
              keeps working, it just stops being real — and{' '}
              <strong>your keys stay saved</strong>.
            </>
          ) : (
            <>
              On the stand-in, no real money moves.{' '}
              {cfg?.keyId
                ? 'A Razorpay key is still saved, so switching back takes one click.'
                : 'Choose Razorpay and paste a key pair to take real payments.'}
            </>
          )}
          <br />
          To stop using Razorpay for good, clear the Key ID above. That
          removes the stored secrets with it.
        </p>

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
    style={{
      justifyContent: 'space-between',
      padding: '8px 0',
      borderBottom: '1px solid var(--hairline)',
    }}
  >
    <span style={{ color: 'var(--muted)', fontSize: 14 }}>{label}</span>
    <span style={{ fontSize: 14, wordBreak: 'break-all', textAlign: 'right' }}>{value}</span>
  </div>
)
