import { useRef, useState } from 'react'
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
 *
 * A segmented control rather than an underlined row. The row sits
 * directly beneath the topbar, which already draws a full-width rule,
 * and an underlined tab bar put a second horizontal line a few pixels
 * under the first. A group that reads as one object does not compete
 * with it.
 *
 * The tab is the panel's heading, wired through aria-labelledby. Each
 * panel used to repeat its own name immediately below the tab that
 * had just said it, which is noise on screen and a duplicate heading
 * to a screen reader.
 */

const TABS = [
  {
    key: 'payment',
    label: 'Payment Gateway',
    perm: 'payment_settings',
    Panel: PaymentGateway,
  },
  { key: 'admins', label: 'Admin Users', perm: 'admins', Panel: AdminUsers },
  {
    key: 'roles',
    label: 'Role Permissions',
    perm: 'admins',
    Panel: RolePermissions,
  },
]

export default function Settings() {
  const { permissions, loading } = useAdmin()
  const allowed = TABS.filter((t) => permissions.includes(t.perm))
  const [active, setActive] = useState(null)
  const tabsRef = useRef(null)

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

  // Arrow keys move between tabs and take focus with them, which is
  // what a role="tablist" promises. Without it, Tab lands on the first
  // tab and then leaves the group entirely.
  const onKeyDown = (e) => {
    const step = e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : 0
    if (!step) return
    e.preventDefault()
    const at = allowed.findIndex((t) => t.key === current.key)
    const next = allowed[(at + step + allowed.length) % allowed.length]
    setActive(next.key)
    tabsRef.current?.querySelector(`#tab-${next.key}`)?.focus()
  }

  return (
    <div>
      {allowed.length > 1 && (
        <div
          className="tabs"
          role="tablist"
          aria-label="Settings sections"
          ref={tabsRef}
          onKeyDown={onKeyDown}
        >
          {allowed.map((t) => {
            const on = t.key === current.key
            return (
              <button
                key={t.key}
                id={`tab-${t.key}`}
                type="button"
                role="tab"
                aria-selected={on}
                aria-controls={`panel-${t.key}`}
                // Only the selected tab is in the tab order; the arrow
                // keys reach the others. Four stops for one control is
                // how a keyboard user ends up avoiding the group.
                tabIndex={on ? 0 : -1}
                className={`tab${on ? ' is-on' : ''}`}
                onClick={() => setActive(t.key)}
              >
                {t.label}
              </button>
            )
          })}
        </div>
      )}
      <div
        id={`panel-${current.key}`}
        role="tabpanel"
        aria-labelledby={`tab-${current.key}`}
      >
        <Panel />
      </div>
    </div>
  )
}
