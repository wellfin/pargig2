import { useMemo, useState } from 'react'
import Modal from './Modal.jsx'
import { IconEye, IconEyeOff, IconCopy, IconRefresh } from '../icons.jsx'

/**
 * Set a new password for someone else's admin account.
 *
 * This replaced window.prompt, which is the worst available control
 * for a password: it echoes every character in plain text, it cannot
 * confirm the entry, it cannot say why something was rejected until
 * after the request fails, and some browsers refuse to show it at
 * all.
 *
 * Two entries, because a typo here does not fail — it succeeds, and
 * locks out the person whose password it was. They find out at their
 * next sign-in, and whoever set it has no copy to compare against.
 *
 * Generate exists for the same reason. An admin setting someone
 * else's password has to transmit it to them anyway, so inventing one
 * by hand buys nothing and tends to produce something guessable.
 */

const MIN = 10

// No 0/O/1/l/I: this password gets read aloud or copied out of a
// message, and those four are where that goes wrong.
const ALPHABET = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'

/**
 * crypto.getRandomValues, not Math.random.
 *
 * Math.random is seeded predictably enough that generated passwords
 * are correlated with each other. The modulo below is very slightly
 * biased toward the start of the alphabet, which does not matter at
 * 56 symbols and 18 characters — about 104 bits either way.
 */
function generate(length = 18) {
  const bytes = new Uint32Array(length)
  crypto.getRandomValues(bytes)
  let out = ''
  for (let i = 0; i < length; i += 1) out += ALPHABET[bytes[i] % ALPHABET.length]
  return out
}

const Rule = ({ ok, children }) => (
  <li className={ok ? 'rule is-ok' : 'rule'}>
    <span className="rule-mark" aria-hidden="true">{ok ? '✓' : '○'}</span>
    {children}
  </li>
)

export default function PasswordDialog({ admin, onClose, onSave, busy, error }) {
  const [pw, setPw] = useState('')
  const [again, setAgain] = useState('')
  const [shown, setShown] = useState(false)
  const [copied, setCopied] = useState(false)

  const longEnough = pw.trim().length >= MIN
  const matches = pw.length > 0 && pw === again
  const valid = longEnough && matches

  const strength = useMemo(() => {
    const classes = [/[a-z]/, /[A-Z]/, /[0-9]/, /[^A-Za-z0-9]/]
      .filter((r) => r.test(pw)).length
    if (!pw) return null
    if (pw.length >= 16 && classes >= 3) return { label: 'strong', tone: 'green' }
    if (pw.length >= 12 && classes >= 2) return { label: 'decent', tone: 'yellow' }
    return { label: 'weak', tone: 'red' }
  }, [pw])

  const roll = () => {
    const next = generate()
    setPw(next)
    setAgain(next)
    // Shown on purpose: a generated password nobody can read is one
    // nobody can pass on, and it was never typed so there is nothing
    // to shoulder-surf that is not already on this screen.
    setShown(true)
    setCopied(false)
  }

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(pw)
      setCopied(true)
    } catch {
      setCopied(false)
    }
  }

  const submit = (e) => {
    e.preventDefault()
    if (valid && !busy) onSave(pw)
  }

  return (
    <Modal
      title="Set a new password"
      subtitle={admin.email}
      titleId="password-dialog-title"
      onClose={onClose}
      width={460}
      footer={
        <>
          <button
            type="button"
            className="btn secondary"
            style={{ marginLeft: 'auto' }}
            onClick={onClose}
            disabled={busy}
          >
            Cancel
          </button>
          <button
            type="submit"
            form="password-form"
            className="btn"
            style={{ marginLeft: 8 }}
            disabled={!valid || busy}
          >
            {busy ? 'Saving…' : 'Set password'}
          </button>
        </>
      }
    >
      <form id="password-form" onSubmit={submit}>
        <label className="field-label" htmlFor="pw-new">New password</label>
        <div className="search" style={{ marginBottom: 10 }}>
          <input
            id="pw-new"
            className="search-input"
            type={shown ? 'text' : 'password'}
            value={pw}
            autoFocus
            autoComplete="new-password"
            onChange={(e) => { setPw(e.target.value); setCopied(false) }}
            placeholder={`At least ${MIN} characters`}
          />
          {pw && (
            <button
              type="button"
              className="search-clear"
              onClick={copy}
              title={copied ? 'Copied' : 'Copy to clipboard'}
              aria-label="Copy the password"
            >
              <IconCopy size={14} />
            </button>
          )}
          <button
            type="button"
            className="search-clear"
            onClick={() => setShown((v) => !v)}
            title={shown ? 'Hide' : 'Show'}
            aria-label={shown ? 'Hide the password' : 'Show the password'}
          >
            {shown ? <IconEyeOff size={14} /> : <IconEye size={14} />}
          </button>
        </div>

        <label className="field-label" htmlFor="pw-again">Type it again</label>
        <div className="search" style={{ marginBottom: 12 }}>
          <input
            id="pw-again"
            className="search-input"
            type={shown ? 'text' : 'password'}
            value={again}
            autoComplete="new-password"
            onChange={(e) => setAgain(e.target.value)}
            placeholder="The same thing"
          />
        </div>

        <div className="row" style={{ gap: 8, marginBottom: 14 }}>
          <button type="button" className="btn secondary sm btn-icon" onClick={roll}>
            <IconRefresh size={14} />
            Generate
          </button>
          {copied && <span className="badge green">copied</span>}
          {strength && (
            <span className={`badge ${strength.tone}`} style={{ marginLeft: 'auto' }}>
              {strength.label}
            </span>
          )}
        </div>

        <ul className="rules">
          <Rule ok={longEnough}>At least {MIN} characters</Rule>
          <Rule ok={matches}>Both entries match</Rule>
        </ul>

        {error && <div className="error" style={{ marginTop: 12 }}>{error}</div>}

        <p className="muted" style={{ marginBottom: 0, lineHeight: 1.6 }}>
          They stay signed in on the old password until their session
          expires — a password change does not end a session. Send them the
          new one over something they already trust, and have them change it.
        </p>
      </form>
    </Modal>
  )
}
