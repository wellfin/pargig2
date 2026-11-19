import { useState } from 'react'
import { useAdmin } from '../auth.js'
import PaymentGateway from './settings/PaymentGateway.jsx'
import AdminUsers from './settings/AdminUsers.jsx'
import RolePermissions from './settings/RolePermissions.jsx'

/**
 * Settings, as tabs.
 *
 * The page has no Guard of its own because its tabs sit behind two
 * different permissions: finance reaches the gateway keys and nothing
 * else here, superadmin reaches all three. So the page draws only the
 * tabs the role can use, and says so plainly when that is none —
 * rather than showing an empty shell or bouncing somebody who
 * followed a link.
 */

const TABS = [
  { key: 'payment', label: 'Payment Gateway', perm: 'payment_settings', Panel: PaymentGateway },
  { key: 'admins', label: 'Admin Users', perm: 'admins', Panel: AdminUsers },
  { key: 'roles', label: 'Role Permissions', perm: 'admins', Panel: RolePermissions },
]

export default function Settings() {
  const { permissions, loading } = useAdmin()
  const allowed = TABS.filter((t) => permissions.includes(t.perm))
  const [active, setActive] = useState(null)

  if (loading) return null

  if (allowed.length === 0) {
    return (
      <div className="card" style={{ maxWidth: 520 }}>
        <h3 style={{ marginTop: 0 }}>Nothing here for your role</h3>
        <p className="muted" style={{ lineHeight: 1.6 }}>
          Settings holds the payment gateway keys and the admin accounts.
          Your role has neither. A superadmin can change that in Settings
          &rarr; Role Permissions.
        </p>
      </div>
    )
  }

  // Falls back to the first allowed tab rather than storing a default,
  // so a role that loses a permission does not land on a blank panel.
  const current = allowed.find((t) => t.key === active) || allowed[0]
  const { Panel } = current

  return (
    <div>
      {allowed.length > 1 && (
        <div className="tabs" role="tablist">
          {allowed.map((t) => (
            <button
              key={t.key}
              type="button"
              role="tab"
              aria-selected={t.key === current.key}
              className={`tab${t.key === current.key ? ' is-on' : ''}`}
              onClick={() => setActive(t.key)}
            >
              {t.label}
            </button>
          ))}
        </div>
      )}
      <Panel />
    </div>
  )
}
