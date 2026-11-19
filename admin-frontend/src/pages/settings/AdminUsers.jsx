import { useCallback, useEffect, useState } from 'react'
import { api } from '../../api'
import { useAdmin } from '../../auth.js'
import { IconTrash, IconBan, IconUnban, IconEdit } from '../../icons.jsx'
import PasswordDialog from '../../components/PasswordDialog.jsx'
import AdminEditDialog from '../../components/AdminEditDialog.jsx'
import RoleChoice from '../../components/RoleChoice.jsx'

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

// Roles are editable from Settings -> Role Permissions, so their
// names and meanings come from the server. A copy here would be wrong
// the first time one was renamed, and absent the first time one was
// added.

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
  // The admin being edited, or null.
  const [editFor, setEditFor] = useState(null)
  const [editError, setEditError] = useState('')
  // The role is filled in from the server's list once it arrives —
  // there is no longer a role name this file can assume exists.
  const [form, setForm] = useState({ name: '', email: '', password: '', role: '' })

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
        role: newRole,
        email: form.email.trim().toLowerCase(),
      })
      say(`${form.email.trim().toLowerCase()} can now sign in.`)
      setForm({ name: '', email: '', password: '', role: '' })
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
   * Save the name and role typed in the edit dialog.
   *
   * Errors stay inside the dialog, for the same reason they do in the
   * password one: the only useful answer to a refusal is to change
   * what you asked for, which a closed dialog makes impossible. The
   * last superadmin guard lands here.
   */
  const saveEdit = async (body, nextRole) => {
    const a = editFor
    setBusy(a._id)
    setEditError('')
    try {
      await api.put(`/admin/admins/${a._id}`, body)
      setEditFor(null)
      say(
        nextRole !== a.role
          ? `${a.email} is now ${nextRole}.`
          : `Saved ${a.email}.`,
      )
      await load()
      if (String(a._id) === String(self?._id)) reloadMe()
    } catch (err) {
      setEditError(
        err?.response?.data?.message || 'Could not save the change',
      )
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

  const { admins, roles } = data
  const byKey = Object.fromEntries(roles.map((r) => [r.key, r]))
  // A delegated admin — someone given `admins` without being a
  // superadmin — may not create or touch a superadmin. The server
  // refuses either way; this is so the panel does not offer buttons
  // whose only outcome is a 403.
  const isOwner = Boolean(data.isOwner)
  const assignable = isOwner ? roles : roles.filter((r) => !r.builtIn)
  const untouchable = (a) => !isOwner && byKey[a.role]?.builtIn
  // Offered when creating: superadmin included, since the first thing
  // an owner often wants is a second one of themselves.
  const newRole = form.role || roles.find((r) => !r.builtIn)?.key || roles[0]?.key

  const countFor = (key) => {
    const r = byKey[key]
    if (!r) return 'an unknown role'
    if (r.builtIn) return 'everything'
    return `${r.permissions.length} page${r.permissions.length === 1 ? '' : 's'}`
  }

  return (
    <div style={{ maxWidth: 980 }}>
      <div className="panel-intro">
        <p>
          Who can sign in to this panel, and as what. The first account had to
          be made over SSH — on an empty database there is nobody to sign in
          as — but every one after it belongs here.
        </p>
        <div className="panel-intro-actions">
          <button className="btn" onClick={() => setAdding((v) => !v)}>
            {adding ? 'Cancel' : 'Add admin'}
          </button>
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

      {adding && (
        /* Labels above the fields, not placeholders inside them: a
           placeholder disappears the moment you type, so a filled-in
           form has nothing left saying what each box was for. The
           role had neither — it was a bare dropdown showing one value
           with no indication it was even the role. */
        <form className="card" style={{ marginBottom: 18 }} onSubmit={create}>
          <h4 style={{ marginTop: 0, marginBottom: 16 }}>New admin</h4>

          <div className="form-grid">
            <div className="form-field">
              <label className="field-label" htmlFor="new-name">Name</label>
              <input
                id="new-name"
                className="input"
                required
                autoFocus
                value={form.name}
                onChange={(e) => setForm({ ...form, name: e.target.value })}
              />
            </div>
            <div className="form-field">
              <label className="field-label" htmlFor="new-email">Email</label>
              <input
                id="new-email"
                className="input"
                type="email"
                required
                value={form.email}
                onChange={(e) => setForm({ ...form, email: e.target.value })}
              />
              <span className="form-hint">
                The login, and the only place a forgotten password can be
                sent — so it has to be a mailbox they can open.
              </span>
            </div>
            <div className="form-field">
              <label className="field-label" htmlFor="new-password">
                Password
              </label>
              <input
                id="new-password"
                className="input"
                type="password"
                required
                minLength={MIN_PASSWORD}
                value={form.password}
                onChange={(e) => setForm({ ...form, password: e.target.value })}
              />
              <span className="form-hint">
                At least {MIN_PASSWORD} characters.
              </span>
            </div>
          </div>

          <RoleChoice
            name="new-admin-role"
            roles={assignable}
            value={newRole}
            onChange={(r) => setForm({ ...form, role: r })}
          />

          <div className="row" style={{ gap: 8, marginTop: 18 }}>
            <button className="btn" disabled={busy === 'new'}>
              {busy === 'new' ? 'Creating…' : 'Create admin'}
            </button>
            <button
              type="button"
              className="btn secondary"
              onClick={() => setAdding(false)}
              disabled={busy === 'new'}
            >
              Cancel
            </button>
          </div>
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
              // Shown, never actionable: hiding the row would make the
              // list lie about who can sign in.
              const senior = untouchable(a)
              const seniorWhy = 'Only a superadmin can change another superadmin'
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
                  <td className="cell-2">
                    {/* Shown, not edited. A select here applied the
                        moment it changed, so one mis-click — or a
                        scroll wheel over a focused select — moved
                        somebody between roles with no confirmation and
                        no undo. Editing is behind the pencil. */}
                    <div>
                      <span
                        className={`badge ${
                          byKey[a.role]?.builtIn ? 'blue' : 'gray'
                        } plain`}
                        title={byKey[a.role]?.hint || undefined}
                      >
                        {byKey[a.role]?.label || a.role}
                      </span>
                    </div>
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
                        disabled={working || senior}
                        onClick={() => { setPwError(''); setPwFor(a) }}
                        title={senior ? seniorWhy : `Set a new password for ${a.email}`}
                      >
                        Password
                      </button>
                      <button
                        type="button"
                        className="act view"
                        disabled={working || senior}
                        onClick={() => { setEditError(''); setEditFor(a) }}
                        title={senior ? seniorWhy : `Edit ${a.email}`}
                        aria-label={`Edit ${a.email}`}
                      >
                        <IconEdit size={16} />
                      </button>
                      <button
                        type="button"
                        className={`act ${a.isActive ? 'warn' : 'good'}`}
                        disabled={working || isSelf || senior}
                        title={
                          senior
                            ? seniorWhy
                            : isSelf
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
                        disabled={working || isSelf || senior}
                        title={
                          senior
                            ? seniorWhy
                            : isSelf
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

      {editFor && (
        <AdminEditDialog
          admin={editFor}
          roles={assignable}
          countFor={countFor}
          isSelf={String(editFor._id) === String(self?._id)}
          busy={busy === editFor._id}
          error={editError}
          onClose={() => setEditFor(null)}
          onSave={saveEdit}
        />
      )}

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
