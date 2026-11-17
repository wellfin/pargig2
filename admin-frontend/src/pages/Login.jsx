import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { api } from '../api'

/**
 * Sign in, and the way back in when the password is gone.
 *
 * The email and password fields used to arrive pre-filled with the
 * seeded account and its password. That put a working admin login on
 * screen for anyone who opened the page — including anyone who found
 * the panel without being told where it was. They start empty now.
 *
 * Three views in one component rather than three routes: the reset is
 * two steps of one short conversation, and routing it would put the
 * email address in the URL, which is the one part of the login worth
 * not writing down.
 */
export default function Login() {
  const [view, setView] = useState('signin') // signin | ask | code
  const nav = useNavigate()

  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [otp, setOtp] = useState('')
  const [newPassword, setNewPassword] = useState('')
  const [confirm, setConfirm] = useState('')

  const [err, setErr] = useState('')
  const [note, setNote] = useState('')
  const [loading, setLoading] = useState(false)

  const go = (next) => {
    setErr('')
    setNote('')
    setView(next)
  }

  const signIn = async (e) => {
    e.preventDefault()
    setErr('')
    setLoading(true)
    try {
      const { data } = await api.post('/auth/admin/login', { email, password })
      localStorage.setItem('pargig_admin_token', data.token)
      localStorage.setItem('pargig_admin', JSON.stringify(data.admin))
      nav('/', { replace: true })
    } catch (e) {
      setErr(e?.response?.data?.message || 'Login failed')
    } finally {
      setLoading(false)
    }
  }

  const askForCode = async (e) => {
    e.preventDefault()
    setErr('')
    setLoading(true)
    try {
      const { data } = await api.post('/auth/admin/forgot-password', { email })
      // The server answers the same way whether or not this address is
      // an admin, so this message is not a confirmation that it is.
      setNote(data?.message || 'If that address is an admin, a code is on its way.')
      // devCode only ever comes back from a non-production server with
      // no mail configured. Filling it in there saves a trip to the logs.
      if (data?.devCode) setOtp(String(data.devCode))
      setView('code')
    } catch (e) {
      setErr(e?.response?.data?.message || 'Could not send a code')
    } finally {
      setLoading(false)
    }
  }

  const setNew = async (e) => {
    e.preventDefault()
    setErr('')
    if (newPassword !== confirm) {
      setErr('The two passwords do not match')
      return
    }
    if (newPassword.length < 10) {
      setErr('Use at least 10 characters')
      return
    }
    setLoading(true)
    try {
      await api.post('/auth/admin/reset-password', {
        email,
        otp: otp.trim(),
        password: newPassword,
      })
      setPassword('')
      setOtp('')
      setNewPassword('')
      setConfirm('')
      setView('signin')
      setNote('Password changed. Sign in with the new one.')
    } catch (e) {
      setErr(e?.response?.data?.message || 'Could not change the password')
    } finally {
      setLoading(false)
    }
  }

  const linkStyle = {
    background: 'none',
    border: 0,
    padding: 0,
    font: 'inherit',
    fontSize: 13,
    color: '#ff6b1a',
    cursor: 'pointer',
    textDecoration: 'underline',
  }

  // ------------------------------------------------------------ views

  if (view === 'ask') {
    return (
      <div className="login-wrap">
        <form className="login-card" onSubmit={askForCode}>
          <h1>Forgot password</h1>
          <p style={{ color: '#707684', marginTop: 0 }}>
            We will email a code to your admin address.
          </p>
          <input
            className="input"
            type="email"
            placeholder="Your admin email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            autoFocus
            required
          />
          {err && <div className="error">{err}</div>}
          <button className="btn" disabled={loading || !email.trim()}>
            {loading ? 'Sending…' : 'Send code'}
          </button>
          <div style={{ marginTop: 14, textAlign: 'center' }}>
            <button type="button" style={linkStyle} onClick={() => go('signin')}>
              Back to sign in
            </button>
          </div>
        </form>
      </div>
    )
  }

  if (view === 'code') {
    return (
      <div className="login-wrap">
        <form className="login-card" onSubmit={setNew}>
          <h1>Set a new password</h1>
          <p style={{ color: '#707684', marginTop: 0 }}>
            {note || 'Enter the code we emailed you, then choose a password.'}
          </p>
          <input
            className="input"
            inputMode="numeric"
            autoComplete="one-time-code"
            placeholder="6-digit code"
            value={otp}
            onChange={(e) => setOtp(e.target.value.replace(/\D/g, '').slice(0, 6))}
            autoFocus
            required
          />
          <input
            className="input"
            type="password"
            autoComplete="new-password"
            placeholder="New password (at least 10 characters)"
            value={newPassword}
            onChange={(e) => setNewPassword(e.target.value)}
            required
          />
          <input
            className="input"
            type="password"
            autoComplete="new-password"
            placeholder="Type it again"
            value={confirm}
            onChange={(e) => setConfirm(e.target.value)}
            required
          />
          {err && <div className="error">{err}</div>}
          <button className="btn" disabled={loading}>
            {loading ? 'Saving…' : 'Change password'}
          </button>
          <p style={{ color: '#707684', fontSize: 12, marginBottom: 0 }}>
            The code expires in 10 minutes and works once. Five wrong
            tries and you will need a new one.
          </p>
          <div style={{ marginTop: 10, textAlign: 'center' }}>
            <button type="button" style={linkStyle} onClick={() => go('ask')}>
              Send a new code
            </button>
          </div>
        </form>
      </div>
    )
  }

  return (
    <div className="login-wrap">
      <form className="login-card" onSubmit={signIn}>
        <h1>Pargig Admin</h1>
        <p style={{ color: '#707684', marginTop: 0 }}>
          Sign in to the admin panel
        </p>
        <input
          className="input"
          type="email"
          autoComplete="username"
          placeholder="Email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          autoFocus
        />
        <input
          className="input"
          type="password"
          autoComplete="current-password"
          placeholder="Password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
        />
        {err && <div className="error">{err}</div>}
        {note && (
          <div style={{ color: '#16a34a', fontSize: 13 }}>{note}</div>
        )}
        <button className="btn" disabled={loading}>
          {loading ? 'Signing in…' : 'Sign in'}
        </button>
        <div style={{ marginTop: 14, textAlign: 'center' }}>
          <button type="button" style={linkStyle} onClick={() => go('ask')}>
            Forgot password?
          </button>
        </div>
      </form>
    </div>
  )
}
