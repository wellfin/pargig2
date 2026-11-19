import { useState } from 'react'
import Modal from './Modal.jsx'
import RoleChoice from './RoleChoice.jsx'

/**
 * Change an admin's name and role.
 *
 * The role used to be a dropdown sitting in the table row, applying
 * the moment it changed. That is a privilege change with no
 * confirmation step and no undo: a mis-click, or a scroll wheel over
 * a focused select, silently moved somebody between "can read
 * disputes" and "can read nothing", or the other way. Nothing in the
 * row said it had happened except the row itself changing.
 *
 * So the row now SHOWS the role, and changing it is a deliberate act
 * with a Save button and every option on screen saying what it
 * grants — the same control the New admin form uses.
 *
 * Your own role is not offered at all, because the server refuses it —
 * see the lockout guards in adminAccountController. Offering a
 * control whose only outcome is an error is worse than not offering
 * it.
 */

export default function AdminEditDialog({
  admin,
  roles,
  roleHint,
  countFor,
  isSelf,
  busy,
  error,
  onClose,
  onSave,
}) {
  const [name, setName] = useState(admin.name || '')
  const [role, setRole] = useState(admin.role)

  const trimmed = name.trim()
  const changed = trimmed !== (admin.name || '') || role !== admin.role
  const valid = trimmed.length > 0 && changed

  const submit = (e) => {
    e.preventDefault()
    if (!valid || busy) return
    const body = {}
    if (trimmed !== admin.name) body.name = trimmed
    if (role !== admin.role) body.role = role
    onSave(body, role)
  }

  return (
    <Modal
      title="Edit admin"
      subtitle={admin.email}
      titleId="admin-edit-title"
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
            form="admin-edit-form"
            className="btn"
            style={{ marginLeft: 8 }}
            disabled={!valid || busy}
          >
            {busy ? 'Saving…' : 'Save'}
          </button>
        </>
      }
    >
      <form id="admin-edit-form" onSubmit={submit}>
        <label className="field-label" htmlFor="admin-name">Name</label>
        <input
          id="admin-name"
          className="input"
          style={{ width: '100%', marginBottom: 14 }}
          value={name}
          autoFocus
          onChange={(e) => setName(e.target.value)}
        />

        {isSelf ? (
          <>
            <span className="field-label">Role</span>
            <div className="input is-readonly">{admin.role}</div>
            <p className="muted" style={{ marginTop: 8, lineHeight: 1.6 }}>
              You cannot change your own role. Demoting yourself by accident
              is one click from a panel nobody can administer, so it is
              refused by the server — ask another superadmin, or use{' '}
              <code>npm run admin:create</code> over SSH.
            </p>
          </>
        ) : (
          <>
            <RoleChoice
              name="edit-admin-role"
              roles={roles}
              hints={roleHint}
              value={role}
              onChange={setRole}
            />
            <p className="muted" style={{ marginTop: 10, lineHeight: 1.6 }}>
              {role === 'superadmin'
                ? 'A superadmin can change anyone else’s role, including yours.'
                : `${role} currently reaches ${countFor(role)}.`}
              {role !== admin.role && (
                <>
                  {' '}The change applies on their next click — they do not
                  have to sign in again.
                </>
              )}
            </p>
          </>
        )}

        {error && <div className="error" style={{ marginTop: 12 }}>{error}</div>}
      </form>
    </Modal>
  )
}
