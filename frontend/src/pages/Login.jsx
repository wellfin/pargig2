import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { api } from '../api'

export default function Login() {
  const [email, setEmail] = useState('admin@pargig.com')
  const [password, setPassword] = useState('admin@123')
  const [err, setErr] = useState('')
  const [loading, setLoading] = useState(false)
  const nav = useNavigate()

  const submit = async (e) => {
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

  return (
    <div className="login-wrap">
      <form className="login-card" onSubmit={submit}>
        <h1>Pargig Admin</h1>
        <p style={{ color: '#707684', marginTop: 0 }}>Sign in to the admin panel</p>
        <input
          className="input"
          type="email"
          placeholder="admin@pargig.com"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          autoFocus
        />
        <input
          className="input"
          type="password"
          placeholder="Password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
        />
        {err && <div className="error">{err}</div>}
        <button className="btn" disabled={loading}>{loading ? 'Signing in…' : 'Sign in'}</button>
      </form>
    </div>
  )
}
