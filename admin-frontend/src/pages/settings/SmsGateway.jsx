import { useEffect, useState } from 'react'
import { api } from '../../api'
import PasswordInput from '../../components/PasswordInput.jsx'

/**
 * MSG91 — the gateway that carries login OTPs.
 *
 * Two providers, picked here, the same shape as the distance panel:
 * the development code, which sends nothing and returns the code in
 * the sign-in response, or MSG91, which sends a real message.
 *
 * Choosing MSG91 is what stops the dev code — the server only echoes
 * a code when nothing was delivered, so the two can never both be
 * true. Going back to the dev code keeps the credentials, which is
 * what to reach for on a bad day at MSG91 rather than deleting a key
 * you will want again.
 *
 * The auth key is stored encrypted and never sent back — only a mask.
 * Blank on save means "leave it alone", so editing the sender id does
 * not demand the key again.
 */
export default function SmsGateway() {
  const [cfg, setCfg] = useState(null)
  const [provider, setProvider] = useState('dev')
  const [authKey, setAuthKey] = useState('')
  const [templateId, setTemplateId] = useState('')
  const [senderId, setSenderId] = useState('')
  const [countryCode, setCountryCode] = useState('91')
  const [testTo, setTestTo] = useState('')
  const [saving, setSaving] = useState(false)
  const [testing, setTesting] = useState(false)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')

  const apply = (d) => {
    setCfg(d)
    setProvider(d.provider || 'dev')
    setTemplateId(d.templateId || '')
    setSenderId(d.senderId || '')
    setCountryCode(d.countryCode || '91')
  }

  useEffect(() => {
    let off = false
    api
      .get('/admin/settings/sms')
      .then((r) => { if (!off) apply(r.data) })
      .catch((e) => {
        if (!off) setError(e?.response?.data?.message || 'Could not load SMS settings')
      })
    return () => { off = true }
  }, [])

  const save = async (e) => {
    e.preventDefault()
    setSaving(true)
    setError('')
    setNotice('')
    try {
      const { data } = await api.put('/admin/settings/sms', {
        provider,
        authKey: authKey.trim(),
        templateId: templateId.trim(),
        senderId: senderId.trim(),
        countryCode: countryCode.trim(),
      })
      apply(data)
      setAuthKey('')
      setNotice(
        data.configured
          ? 'Saved. Real SMS is on, and the development code is no longer '
            + 'returned at sign-in.'
          : 'Saved. Nothing is being sent yet, so the development code still '
            + 'comes back at sign-in.',
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
      const { data } = await api.post('/admin/settings/sms/test', {
        mobile: testTo.trim(),
      })
      setNotice(data.message || 'Sent')
    } catch (err) {
      setError(err?.response?.data?.message || 'The test message was refused')
    } finally {
      setTesting(false)
    }
  }

  if (!cfg) return <p className="muted">Loading…</p>

  return (
    <section className="card form-narrow" style={{ marginBottom: 18 }}>
      <div className="panel-intro" style={{ marginBottom: 14 }}>
        <div>
          <h4 style={{ margin: 0 }}>SMS — MSG91</h4>
          <p style={{ margin: '4px 0 0' }}>
            Carries the six-digit code people sign in with.
          </p>
        </div>
        <div className="panel-intro-actions">
          <span className={`badge ${cfg.configured ? 'green' : 'yellow'}`}>
            {cfg.configured ? 'Live — real SMS' : 'Not configured'}
          </span>
        </div>
      </div>

      {/* Stated before the fields, not after saving. Somebody needs to
          know what pressing Save will change. */}
      <div
        className="card"
        style={{ background: 'var(--panel-sunk)', marginBottom: 16, padding: '12px 14px' }}
      >
        <p className="muted" style={{ margin: 0, fontSize: 13, lineHeight: 1.6 }}>
          {cfg.devCodeInUse ? (
            <>
              Running on the development code: nothing is sent and the code
              comes back in the sign-in response.{' '}
              <strong>Choosing MSG91 below ends that</strong> — from then on
              the code only reaches the handset.
            </>
          ) : (
            <>
              MSG91 is sending real messages, and the development code is no
              longer returned at sign-in. Switching back to the development
              code keeps the key saved, which is how to keep working if MSG91
              has a bad day.
            </>
          )}
        </p>
      </div>

      {error && <div className="error" style={{ marginBottom: 14 }}>{error}</div>}
      {notice && (
        <div
          className="notice ok"
        >
          {notice}
        </div>
      )}

      <form onSubmit={save}>
        <fieldset className="choices" style={{ marginBottom: 18 }}>
          <legend className="field-label">Provider</legend>
          <label className={`choice${provider === 'dev' ? ' is-on' : ''}`}>
            <input
              type="radio"
              name="sms-provider"
              value="dev"
              checked={provider === 'dev'}
              onChange={() => setProvider('dev')}
            />
            <span className="choice-body">
              <span className="choice-name">Development code</span>
              <span className="choice-hint">
                Nothing is sent. The code comes back in the sign-in response,
                so you can log in without an SMS bill. Keeps any saved key.
              </span>
            </span>
          </label>
          <label className={`choice${provider === 'msg91' ? ' is-on' : ''}`}>
            <input
              type="radio"
              name="sms-provider"
              value="msg91"
              checked={provider === 'msg91'}
              onChange={() => setProvider('msg91')}
            />
            <span className="choice-body">
              <span className="choice-name">MSG91</span>
              <span className="choice-hint">
                Real messages to real handsets. Needs an auth key and a
                DLT-approved template id.
              </span>
            </span>
          </label>
        </fieldset>

        <div className="form-grid" style={{ marginBottom: 14 }}>
          <div className="form-field">
            <label className="field-label" htmlFor="msg91-key">Auth key</label>
            <PasswordInput
              id="msg91-key"
              value={authKey}
              autoComplete="off"
              placeholder={cfg.hasAuthKey ? cfg.authKeyMasked || '••••••••' : 'From the MSG91 dashboard'}
              onChange={(e) => setAuthKey(e.target.value)}
            />
            <span className="form-hint">
              {cfg.hasAuthKey
                ? 'Saved. Leave blank to keep it.'
                : 'Stored encrypted and never shown again.'}
            </span>
          </div>
          <div className="form-field">
            <label className="field-label" htmlFor="msg91-tmpl">Template id</label>
            <input
              id="msg91-tmpl"
              className="input"
              value={templateId}
              placeholder="The DLT-approved OTP template"
              onChange={(e) => setTemplateId(e.target.value)}
            />
            <span className="form-hint">
              Required with the key — one without the other is rejected per
              message and looks like a delivery fault.
            </span>
          </div>
          <div className="form-field">
            <label className="field-label" htmlFor="msg91-sender">Sender id</label>
            <input
              id="msg91-sender"
              className="input"
              value={senderId}
              placeholder="PARGIG"
              onChange={(e) => setSenderId(e.target.value)}
            />
            <span className="form-hint">Optional. Six letters, DLT-registered.</span>
          </div>
          <div className="form-field">
            <label className="field-label" htmlFor="msg91-cc">Country code</label>
            <input
              id="msg91-cc"
              className="input"
              value={countryCode}
              onChange={(e) => setCountryCode(e.target.value)}
            />
            <span className="form-hint">Added to ten-digit numbers. 91 for India.</span>
          </div>
        </div>

        <div className="row" style={{ gap: 8 }}>
          <button className="btn" disabled={saving}>
            {saving ? 'Saving…' : 'Save'}
          </button>
          {cfg.source === 'env' && (
            <span className="badge gray plain">
              currently coming from the server environment
            </span>
          )}
        </div>
      </form>

      {cfg.configured && (
        <>
          <div className="modal-section">Send a test</div>
          <p className="muted" style={{ marginTop: 0, fontSize: 13, lineHeight: 1.6 }}>
            Sends one real message. That is the only test worth running — a
            well-formed key proves nothing about the DLT template, the sender
            id or the balance, which is where this actually goes wrong.
          </p>
          <div className="row" style={{ gap: 8 }}>
            <input
              className="input"
              style={{ maxWidth: 220 }}
              value={testTo}
              placeholder="Mobile number"
              onChange={(e) => setTestTo(e.target.value)}
            />
            <button
              type="button"
              className="btn secondary"
              onClick={test}
              disabled={testing || testTo.trim().length < 10}
            >
              {testing ? 'Sending…' : 'Send test SMS'}
            </button>
          </div>
        </>
      )}
    </section>
  )
}
