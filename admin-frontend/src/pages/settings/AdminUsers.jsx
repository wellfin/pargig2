import { useCallback, useEffect, useState } from 'react'
import { api } from '../../api'
import { useAdmin } from '../../auth.js'
import { IconTrash, IconBan, IconUnban } from '../../icons.jsx'
import PasswordDialog from '../../components/PasswordDialog.jsx'

/**
 * Admin accounts.
 *
 * Creating the FIRST admin still belongs to SSH — on an empty
 * database there is nobody to sign in as, so no page can do it. Every
 * one after that is easier here, which is the point: the alternative
 * was handing out one shared login, and a shared login means nothing
 * in the audit trail is attributable to a person.
 *
 * Three edits are refused by the server and are therefore not offered
 * here either: changing your own role, switching yourself off, and
 * deleting yourself. Each is one click from locking the panel with no
 * way back except a terminal.
 */

const MIN_PASSWORD = 10

const ROLE_HINT = {
  superadmin: 'Everything, including this page.',
  support: 'The queues: users, verifications, disputes and chat.',
  finance: 'The money: payments, reports and the gateway keys.',
}

const fmt = (v) =>
  v ? new Date(v).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' }) : '—'

export default function AdminUsers() {
  const { admin: self, reload: reloadMe } = useAdmin()
  const [data, setData] = useState(null)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [busy, setBusy] = useState('')
  const [adding, setAdding] = useState(false)
  // The admin whose password is being set, or null.
  const [pwFor, setPwFor] = useState(null)
  const [pwError, setPwError] = useState('')
  const [form, setForm] = useState({ name: '', email: '', password: '', role: 'support' })

  const load = useCallback(
    () =>
      api
        .get('/admin/admins')
        .then((r) => {
          setData(r.data)
          setError('')
        })
        .catch((e) =>
          setError(e?.response?.data?.message || 'Could not load admin accounts'),
        ),
    [],
  )

  useEffect(() => {
    load()
  }, [load])

  const say = (msg) => {
    setNotice(msg)
    setError('')
  }
  const fail = (e, fallback) => {
    setError(e?.response?.data?.message || fallback)
    setNotice('')
  }

  const create = async (e) => {
    e.preventDefault()
    setBusy('new')
    try {
      await api.post('/admin/admins', {
        ...form,
        email: form.email.trim().toLowerCase(),
      })
      say(`${form.email.trim().toLowerCase()} can now sign in.`)
      setForm({ name: '', email: '', password: '', role: 'support' })
      setAdding(false)
      load()
    } catch (err) {
      fail(err, 'Could not create the account')
    } finally {
      setBusy('')
    }
  }

  const patch = async (a, body, msg) => {
    setBusy(a._id)
    try {
      await api.put(`/admin/admins/${a._id}`, body)
      say(msg)
      await load()
      // Your own row can change what the sidebar should show.
      if (String(a._id) === String(self?._id)) reloadMe()
    } catch (err) {
      fail(err, 'Could not save the change')
    } finally {
      setBusy('')
    }
  }

  /**
   * Save the password typed in the dialog.
   *
   * Errors stay INSIDE the dialog rather than closing it and showing
   * a banner behind: the only useful response to "that was refused"
   * is to type a different one, and that is impossible from a closed
   * dialog.
   */
  const savePassword = async (pw) => {
    const a = pwFor
    setBusy(a._id)
    setPwError('')
    try {
      const { data: res } = await api.put(`/admin/admins/${a._id}/password`, {
        password: pw,
      })
      setPwFor(null)
      say(res.message || `Password changed for ${a.email}.`)
    } catch (err) {
      setPwError(
        err?.response?.data?.message || 'Could not change the password',
      )
    } finally {
      setBusy('')
    }
  }

  const remove = async (a) => {
    const ok = window.confirm(
      `Delete the admin account ${a.email}?\n\n` +
      `They lose access immediately. Anything they already decided — a ` +
      `dispute, a verification — keeps their name on it.`,
    )
    if (!ok) return
    setBusy(a._id)
    try {
      await api.delete(`/admin/admins/${a._id}`)
      say(`${a.email} deleted.`)
      load()
    } catch (err) {
      fail(err, 'Could not delete the account')
    } finally {
      setBusy('')
    }
  }

  if (error && !data) return <div className="error">{error}</div>
  if (!data) return <p className="muted">Loading…</p>

  const { admins, roles, rolePermissions } = data
  const countFor = (role) =>
    role === 'superadmin' ? 'everything' : `${rolePermissions?.[role]?.length || 0} pages`

  return (
    <div style={{ maxWidth: 980 }}>
      <div className="row" style={{ justifyContent: 'space-between', marginBottom: 18 }}>
        <div>
          <h3 style={{ margin: 0 }}>Admin Users</h3>
          <p className="muted" style={{ margin: '4px 0 0' }}>
            Who can sign in to this panel, and as what.
          </p>
        </div>
        <button className="btn" onClick={() => setAdding((v) => !v)}>
          {adding ? 'Cancel' : 'Add admin'}
        </button>
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

      {adding && (
        <form className="card" style={{ marginBottom: 18 }} onSubmit={create}>
          <h4 style={{ marginTop: 0 }}>New admin</h4>
          <div className="row" style={{ gap: 10, flexWrap: 'wrap' }}>
            <input
              className="input"
              placeholder="Name"
              required
              value={form.name}
              onChange={(e) => setForm({ ...form, name: e.target.value })}
            />
            <input
              className="input"
              type="email"
              placeholder="Email"
              required
              style={{ minWidth: 240 }}
              value={form.email}
              onChange={(e) => setForm({ ...form, email: e.target.value })}
            />
            <select
              className="input"
              value={form.role}
              onChange={(e) => setForm({ ...form, role: e.target.value })}
            >
              {roles.map((r) => (
                <option key={r} value={r}>{r}</option>
              ))}
            </select>
          </div>
          <div className="row" style={{ gap: 10, marginTop: 10 }}>
            <input
              className="input"
              type="password"
              placeholder={`Password (min ${MIN_PASSWORD})`}
              required
              minLength={MIN_PASSWORD}
              style={{ minWidth: 240 }}
              value={form.password}
              onChange={(e) => setForm({ ...form, password: e.target.value })}
            />
            <button className="btn" disabled={busy === 'new'}>
              {busy === 'new' ? 'Creating…' : 'Create'}
            </button>
          </div>
          <p className="muted" style={{ marginBottom: 0, lineHeight: 1.6 }}>
            The email is the login <em>and</em> the only place a forgotten
            password can be sent, so it has to be a mailbox they can open.{' '}
            <strong>{ROLE_HINT[form.role]}</strong>
          </p>
        </form>
      )}

      <div className="card" style={{ padding: 0 }}>
        <table>
          <thead>
            <tr>
              <th>Name</th>
              <th>Email</th>
              <th>Role</th>
              <th>Status</th>
              <th>Added</th>
              <th style={{ textAlign: 'right' }}>Actions</th>
            </tr>
          </thead>
          <tbody>
            {admins.map((a) => {
              const isSelf = String(a._id) === String(self?._id)
              const working = busy === a._id
              return (
                <tr key={a._id}>
                  <td>
                    {a.name}
                    {isSelf && (
                      <span className="badge blue plain" style={{ marginLeft: 6 }}>
                        you
                      </span>
                    )}
                  </td>
                  <td title={a.email}>{a.email}</td>
                  <td>
                    {/* Your own role is text, not a dropdown: the server
                        refuses the change, so offering it would only be
                        a way to get an error. */}
                    {isSelf ? (
                      <span title="You cannot change your own role">{a.role}</span>
                    ) : (
                      <select
                        className="input"
                        style={{ height: 30, fontSize: 12.5 }}
                        value={a.role}
                        disabled={working}
                        onChange={(e) =>
                          patch(a, { role: e.target.value },
                            `${a.email} is now ${e.target.value}.`)
                        }
                      >
                        {roles.map((r) => (
                          <option key={r} value={r}>{r}</option>
                        ))}
                      </select>
                    )}
                    <span className="sub">{countFor(a.role)}</span>
                  </td>
                  <td>
                    {a.isActive
                      ? <span className="badge green">active</span>
                      : <span className="badge gray">off</span>}
                  </td>
                  <td className="muted">{fmt(a.createdAt)}</td>
                  <td>
                    <div className="row-actions">
                      <button
                        type="button"
                        className="btn secondary sm"
                        disabled={working}
                        onClick={() => { setPwError(''); setPwFor(a) }}
                        title={`Set a new password for ${a.email}`}
                      >
                        Password
                      </button>
                      <button
                        type="button"
                        className={`act ${a.isActive ? 'warn' : 'good'}`}
                        disabled={working || isSelf}
                        title={
                          isSelf
                            ? 'You cannot switch your own account off'
                            : a.isActive
                              ? 'Switch this account off — they are signed out at once'
                              : 'Switch this account back on'
                        }
                        aria-label={`${a.isActive ? 'Deactivate' : 'Activate'} ${a.email}`}
                        onClick={() =>
                          patch(a, { isActive: !a.isActive },
                            a.isActive
                              ? `${a.email} is switched off and signed out.`
                              : `${a.email} can sign in again.`)
                        }
                      >
                        {a.isActive ? <IconBan size={16} /> : <IconUnban size={16} />}
                      </button>
                      <button
                        type="button"
                        className="act danger sep"
                        disabled={working || isSelf}
                        title={
                          isSelf
                            ? 'You cannot delete your own account'
                            : 'Delete this admin account'
                        }
                        aria-label={`Delete ${a.email}`}
                        onClick={() => remove(a)}
                      >
                        <IconTrash size={16} />
                      </button>
                    </div>
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>

      {pwFor && (
        <PasswordDialog
          admin={pwFor}
          busy={busy === pwFor._id}
          error={pwError}
          onClose={() => setPwFor(null)}
          onSave={savePassword}
        />
      )}

      <p className="muted" style={{ marginTop: 14, lineHeight: 1.7 }}>
        Switching an account off takes effect on the next request, not when
        their session expires — they are signed out immediately. Deleting one
        is permanent, but it leaves their name on the decisions they already
        made. If every superadmin is ever locked out, the way back is SSH:{' '}
        <code>npm run admin:create</code>.
      </p>
    </div>
  )
}
