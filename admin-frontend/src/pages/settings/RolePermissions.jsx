import { useCallback, useEffect, useMemo, useState } from 'react'
import { api } from '../../api'
import { useAdmin } from '../../auth.js'

/**
 * What each role may open.
 *
 * A grid rather than per-account checkboxes, because with a handful
 * of admins per-account rules cost more than they buy: you end up
 * unable to answer "what can a support admin do?", since the answer
 * is different for each of them. A role is a job title, and a job
 * title is the thing an owner has an opinion about.
 *
 * Two columns are deliberately not editable, and both are lockout
 * protection rather than policy:
 *
 *   superadmin holds everything, always. A grid that can take
 *   permissions away from superadmin can take away this page, and
 *   then nobody can grant it back.
 *
 *   "Admin accounts & permissions" cannot be given to another role.
 *   Whoever holds it can create a superadmin and sign in as one, so
 *   granting it is promotion, not delegation. If that is what is
 *   meant, make the person a superadmin and mean it.
 */

export default function RolePermissions() {
  const { reload: reloadMe } = useAdmin()
  const [data, setData] = useState(null)
  const [draft, setDraft] = useState(null)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [saving, setSaving] = useState(false)

  const load = useCallback(
    () =>
      api
        .get('/admin/permissions')
        .then((r) => {
          setData(r.data)
          setDraft(structuredClone(r.data.rolePermissions))
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

  const editableRoles = useMemo(
    () => (data?.roles || []).filter((r) => r !== 'superadmin'),
    [data],
  )

  const dirty = useMemo(() => {
    if (!data || !draft) return false
    return editableRoles.some((role) => {
      const a = [...(data.rolePermissions[role] || [])].sort().join(',')
      const b = [...(draft[role] || [])].sort().join(',')
      return a !== b
    })
  }, [data, draft, editableRoles])

  const toggle = (role, key) => {
    setDraft((d) => {
      const has = d[role].includes(key)
      return {
        ...d,
        [role]: has ? d[role].filter((k) => k !== key) : [...d[role], key],
      }
    })
    setNotice('')
  }

  const save = async () => {
    setSaving(true)
    try {
      const { data: res } = await api.put('/admin/permissions', {
        rolePermissions: draft,
      })
      setData((d) => ({ ...d, rolePermissions: res.rolePermissions }))
      setDraft(structuredClone(res.rolePermissions))
      setNotice('Saved. It applies to their next request — nobody has to sign in again.')
      setError('')
      // Your own role's grid may have changed under you.
      reloadMe()
    } catch (e) {
      setError(e?.response?.data?.message || 'Could not save')
      setNotice('')
    } finally {
      setSaving(false)
    }
  }

  const reset = () => {
    setDraft(structuredClone(data.defaults))
    setNotice('')
  }

  if (error && !data) return <div className="error">{error}</div>
  if (!data || !draft) return <p className="muted">Loading…</p>

  return (
    <div style={{ maxWidth: 980 }}>
      <div className="row" style={{ justifyContent: 'space-between', marginBottom: 18 }}>
        <div>
          <h3 style={{ margin: 0 }}>Role Permissions</h3>
          <p className="muted" style={{ margin: '4px 0 0' }}>
            What each role can open. Changes apply to everyone holding that role.
          </p>
        </div>
        <div className="row" style={{ gap: 8 }}>
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
        <table className="table-fit">
          <colgroup>
            <col style={{ width: '46%' }} />
            {data.roles.map((r) => (
              <col key={r} style={{ width: `${54 / data.roles.length}%` }} />
            ))}
          </colgroup>
          <thead>
            <tr>
              <th>Page or capability</th>
              {data.roles.map((r) => (
                <th key={r} style={{ textAlign: 'center' }}>{r}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {data.permissions.map((p) => (
              <tr key={p.key}>
                <td className="cell-2">
                  <div style={{ fontWeight: 600 }}>{p.label}</div>
                  <span className="sub" title={p.hint}>{p.hint}</span>
                </td>
                {data.roles.map((role) => {
                  const locked = role === 'superadmin' || p.superadminOnly
                  const on = locked
                    ? role === 'superadmin'
                    : draft[role].includes(p.key)
                  const why = p.superadminOnly && role !== 'superadmin'
                    ? 'Superadmin only — whoever holds this can create a superadmin'
                    : role === 'superadmin'
                      ? 'Superadmin always holds everything, or nobody could grant it back'
                      : undefined
                  return (
                    <td key={role} style={{ textAlign: 'center' }}>
                      <input
                        type="checkbox"
                        checked={on}
                        disabled={locked}
                        title={why}
                        aria-label={`${p.label} for ${role}`}
                        onChange={() => toggle(role, p.key)}
                        style={{ width: 16, height: 16, cursor: locked ? 'not-allowed' : 'pointer' }}
                      />
                    </td>
                  )
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <p className="muted" style={{ marginTop: 14, lineHeight: 1.7 }}>
        The greyed boxes are not a limitation of the editor. Superadmin keeps
        everything because a grid that could take this page away from
        superadmin would have no way to give it back, and{' '}
        <strong>Admin accounts &amp; permissions</strong> stays superadmin-only
        because whoever holds it can create a superadmin and sign in as one —
        that is promotion, not delegation.
      </p>
      <p className="muted" style={{ lineHeight: 1.7 }}>
        Taking a page away also closes the API behind it, not just the menu
        item. Someone already signed in loses it on their next click; they do
        not need to sign in again.
      </p>
    </div>
  )
}
