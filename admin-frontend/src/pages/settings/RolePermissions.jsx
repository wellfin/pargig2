import { useCallback, useEffect, useMemo, useState } from 'react'
import { api } from '../../api'
import { useAdmin } from '../../auth.js'
import Modal from '../../components/Modal.jsx'
import { IconEdit, IconTrash } from '../../icons.jsx'

/**
 * What each role may open — and which roles exist.
 *
 * Roles are data, not source. The ones that ship are a starting
 * point: they can be renamed, re-permissioned or deleted here, and
 * new ones added beside them, without a deploy. Which is the point —
 * "we need someone who only does verifications" should not be a
 * commit.
 *
 * A grid rather than per-account checkboxes, because with a handful
 * of admins per-account rules cost more than they buy: you end up
 * unable to answer "what can a support admin do?", since the answer
 * is different for each of them. A role is a job title, and a job
 * title is the thing an owner has an opinion about.
 *
 * Superadmin is not data and cannot be edited or deleted. A grid that
 * can take permissions away from superadmin can take away this page,
 * and then nobody can give it back.
 *
 * This page can be delegated — `admins` is a grantable permission —
 * so whoever is looking at it is not necessarily the owner. A
 * delegated admin may only tick what they hold themselves, because
 * otherwise managing roles would be a way to climb: grant a role
 * everything, create an account in it, set its password, sign in.
 * Boxes outside their own set are locked HERE, and left exactly as
 * they were by the server, which is what actually enforces it.
 *
 * Everything is one Save. Adding, renaming, re-permissioning and
 * deleting travel together, because the guards are the same for all
 * four and a half-applied set of changes should not be possible.
 */

const slug = (v) =>
  String(v || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 32)

export default function RolePermissions() {
  const { reload: reloadMe } = useAdmin()
  const [data, setData] = useState(null)
  const [draft, setDraft] = useState(null)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [saving, setSaving] = useState(false)
  // The role being added or renamed, or null.
  const [editing, setEditing] = useState(null)

  const load = useCallback(
    () =>
      api
        .get('/admin/permissions')
        .then((r) => {
          setData(r.data)
          setDraft(structuredClone(r.data.roles))
          setError('')
        })
        .catch((e) =>
          setError(e?.response?.data?.message || 'Could not load permissions'),
        ),
    [],
  )

  useEffect(() => {
    load()
  }, [load])

  const editable = useMemo(() => (draft || []).filter((r) => !r.builtIn), [draft])

  const dirty = useMemo(() => {
    if (!data || !draft) return false
    const shape = (rs) =>
      JSON.stringify(
        rs
          .filter((r) => !r.builtIn)
          .map((r) => [r.key, r.label, r.hint, [...r.permissions].sort()]),
      )
    return shape(data.roles) !== shape(draft)
  }, [data, draft])

  const toggle = (key, perm) => {
    setDraft((rs) =>
      rs.map((r) => {
        if (r.key !== key) return r
        const has = r.permissions.includes(perm)
        return {
          ...r,
          permissions: has
            ? r.permissions.filter((k) => k !== perm)
            : [...r.permissions, perm],
        }
      }),
    )
    setNotice('')
  }

  const upsertRole = ({ key, label, hint }) => {
    setDraft((rs) => {
      const at = rs.findIndex((r) => r.key === editing?.key)
      if (at >= 0) {
        const next = [...rs]
        next[at] = { ...next[at], key, label, hint }
        return next
      }
      return [...rs, { key, label, hint, permissions: [] }]
    })
    setEditing(null)
    setNotice('')
  }

  const removeRole = (role) => {
    const held = data.inUse?.[role.key] || 0
    if (held > 0) return
    const ok = window.confirm(
      `Delete the role "${role.label}"?\n\n` +
      'Nobody holds it, so nothing is signed out. It disappears when you ' +
      'press Save.',
    )
    if (!ok) return
    setDraft((rs) => rs.filter((r) => r.key !== role.key))
    setNotice('')
  }

  const save = async () => {
    setSaving(true)
    try {
      const { data: res } = await api.put('/admin/permissions', {
        roles: draft.filter((r) => !r.builtIn),
      })
      setData((d) => ({ ...d, roles: res.roles, inUse: res.inUse }))
      setDraft(structuredClone(res.roles))
      setNotice('Saved. It applies on their next request — nobody has to sign in again.')
      setError('')
      reloadMe()
    } catch (e) {
      setError(e?.response?.data?.message || 'Could not save')
      setNotice('')
    } finally {
      setSaving(false)
    }
  }

  const reset = () => {
    setDraft([
      draft.find((r) => r.builtIn),
      ...structuredClone(data.defaults),
    ])
    setNotice('')
  }

  if (error && !data) return <div className="error">{error}</div>
  if (!data || !draft) return <p className="muted">Loading…</p>

  const canGrant = data.canGrant || []
  const limited = !data.isOwner

  return (
    <div>
      <div className="panel-intro">
        <p>
          What each role can open, and which roles exist. A change applies to
          everyone holding that role, and takes effect on their next click —
          nobody has to sign in again.
        </p>
        <div className="panel-intro-actions">
          <button
            className="btn secondary"
            onClick={() => setEditing({ key: '', label: '', hint: '' })}
            disabled={saving}
          >
            Add role
          </button>
          <button className="btn secondary" onClick={reset} disabled={saving}>
            Reset to defaults
          </button>
          <button className="btn" onClick={save} disabled={saving || !dirty}>
            {saving ? 'Saving…' : dirty ? 'Save changes' : 'Saved'}
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

      <div className="card" style={{ padding: 0 }}>
        {/* Scrolls sideways once there are enough roles. A fixed
            layout would squeeze every column instead, and the first
            thing to become unreadable would be the permission names
            down the left. */}
        <div className="table-scroll">
          <table className="perm-grid">
            <thead>
              <tr>
                <th>Page or capability</th>
                {draft.map((r) => {
                  const held = data.inUse?.[r.key] || 0
                  return (
                    <th key={r.key} className="perm-col">
                      <span className="perm-col-name">{r.label}</span>
                      <span className="sub">
                        {held === 0
                          ? 'nobody'
                          : `${held} admin${held === 1 ? '' : 's'}`}
                      </span>
                      {!r.builtIn && (
                        <span className="perm-col-tools">
                          <button
                            type="button"
                            className="act view"
                            title={`Rename ${r.label}`}
                            aria-label={`Rename ${r.label}`}
                            onClick={() => setEditing(r)}
                          >
                            <IconEdit size={14} />
                          </button>
                          <button
                            type="button"
                            className="act danger"
                            disabled={held > 0}
                            title={
                              held > 0
                                ? `${held} admin${held === 1 ? '' : 's'} still hold this role — move them first`
                                : `Delete ${r.label}`
                            }
                            aria-label={`Delete ${r.label}`}
                            onClick={() => removeRole(r)}
                          >
                            <IconTrash size={14} />
                          </button>
                        </span>
                      )}
                    </th>
                  )
                })}
              </tr>
            </thead>
            <tbody>
              {data.permissions.map((p) => (
                <tr key={p.key}>
                  <td className="cell-2">
                    <div style={{ fontWeight: 600 }}>{p.label}</div>
                    <span className="sub" title={p.hint}>{p.hint}</span>
                  </td>
                  {draft.map((role) => {
                    const beyondMe = !canGrant.includes(p.key)
                    const locked =
                      role.builtIn || p.superadminOnly || beyondMe
                    const on = locked && role.builtIn
                      ? true
                      : role.permissions.includes(p.key)
                    const why = role.builtIn
                      ? 'Superadmin always holds everything, or nobody could grant it back'
                      : p.superadminOnly
                        ? `Superadmin only. ${p.lockNote || ''}`.trim()
                        : beyondMe
                          ? 'You do not have this yourself, so you cannot give it away'
                          : undefined
                    return (
                      <td key={role.key} style={{ textAlign: 'center' }}>
                        <input
                          type="checkbox"
                          checked={on}
                          disabled={locked}
                          title={why}
                          aria-label={`${p.label} for ${role.label}`}
                          onChange={() => toggle(role.key, p.key)}
                          style={{
                            width: 16,
                            height: 16,
                            cursor: locked ? 'not-allowed' : 'pointer',
                          }}
                        />
                      </td>
                    )
                  })}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {editing && (
        <RoleDialog
          role={editing}
          taken={editable.filter((r) => r.key !== editing.key).map((r) => r.key)}
          inUse={data.inUse?.[editing.key] || 0}
          onClose={() => setEditing(null)}
          onSave={upsertRole}
        />
      )}

      <div className="muted" style={{ marginTop: 14, lineHeight: 1.7 }}>
        <p style={{ marginTop: 0 }}>
          The greyed boxes are not a limitation of the editor. Superadmin
          keeps everything, because a grid that could take this page away
          from superadmin would have no way to give it back. These stay
          superadmin-only for reasons of their own:
        </p>
        <ul style={{ margin: '0 0 10px 2px', paddingLeft: 18 }}>
          {data.permissions
            .filter((p) => p.superadminOnly)
            .map((p) => (
              <li key={p.key} style={{ marginBottom: 4 }}>
                <strong>{p.label}</strong> — {p.lockNote}
              </li>
            ))}
        </ul>
        <p>
          A role people still hold cannot be deleted — move them to another
          role first. Otherwise they would stay signed in holding a role that
          grants nothing, with no page and no explanation.
        </p>
        {limited && (
          <p style={{ marginBottom: 0 }}>
            You are not a superadmin, so you can only tick what your own role
            holds. Anything beyond it is locked and left exactly as it is —
            saving will neither grant it nor take it away. Otherwise this
            page would be a way to climb: give a role everything, create an
            account in it, and sign in as that account.
          </p>
        )}
        {!limited && <p style={{ marginBottom: 0 }} />}
      </div>
    </div>
  )
}

/**
 * Name a role.
 *
 * The stored key is derived from the name rather than typed, and is
 * fixed once the role exists. It is what every admin record points
 * at, so a free rename of the key would silently orphan each account
 * holding it. Renaming therefore changes the label only; the key is
 * shown so nobody is surprised by it later.
 */
function RoleDialog({ role, taken, inUse, onClose, onSave }) {
  const isNew = !role.key
  const [label, setLabel] = useState(role.label || '')
  const [hint, setHint] = useState(role.hint || '')

  const key = isNew ? slug(label) : role.key
  const clash = isNew && key && taken.includes(key)
  const valid = label.trim().length > 0 && key.length > 0 && !clash

  const submit = (e) => {
    e.preventDefault()
    if (!valid) return
    onSave({ key, label: label.trim(), hint: hint.trim() })
  }

  return (
    <Modal
      title={isNew ? 'Add a role' : `Rename ${role.label}`}
      subtitle={isNew ? 'It starts with no permissions' : key}
      titleId="role-dialog-title"
      onClose={onClose}
      width={440}
      footer={
        <>
          <button
            type="button"
            className="btn secondary"
            style={{ marginLeft: 'auto' }}
            onClick={onClose}
          >
            Cancel
          </button>
          <button
            type="submit"
            form="role-form"
            className="btn"
            style={{ marginLeft: 8 }}
            disabled={!valid}
          >
            {isNew ? 'Add' : 'Rename'}
          </button>
        </>
      }
    >
      <form id="role-form" onSubmit={submit}>
        <label className="field-label" htmlFor="role-label">Name</label>
        <input
          id="role-label"
          className="input"
          style={{ width: '100%' }}
          value={label}
          autoFocus
          placeholder="Operations"
          onChange={(e) => setLabel(e.target.value)}
        />
        {isNew ? (
          <span className="form-hint">
            Stored as <code>{key || '…'}</code>. That is what admin accounts
            point at, so it is fixed once the role exists — the name can be
            changed later, the stored key cannot.
          </span>
        ) : (
          <span className="form-hint">
            Stored as <code>{key}</code>, which does not change
            {inUse > 0 && ` — ${inUse} admin${inUse === 1 ? '' : 's'} point at it`}.
          </span>
        )}
        {clash && (
          <div className="error" style={{ marginTop: 8 }}>
            There is already a role stored as <code>{key}</code>.
          </div>
        )}

        <label className="field-label" htmlFor="role-hint" style={{ marginTop: 14 }}>
          What it means
        </label>
        <input
          id="role-hint"
          className="input"
          style={{ width: '100%' }}
          value={hint}
          placeholder="Jobs and verifications, nothing financial"
          onChange={(e) => setHint(e.target.value)}
        />
        <span className="form-hint">
          Shown wherever this role is offered, so whoever assigns it can see
          what they are handing over without coming back to this page.
        </span>

        <p className="muted" style={{ marginTop: 16, marginBottom: 0, lineHeight: 1.6 }}>
          {isNew
            ? 'Nothing is granted yet — tick its column in the grid, then Save.'
            : 'Its permissions are unchanged; adjust them in the grid.'}
        </p>
      </form>
    </Modal>
  )
}
