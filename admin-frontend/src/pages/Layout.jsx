import { useCallback, useEffect, useState } from 'react'
import { NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom'
import { api } from '../api'
import { AdminContext } from '../auth.js'
import {
  IconBell,
  IconDashboard,
  IconDisputes,
  IconJobs,
  IconLogout,
  IconPayments,
  IconReports,
  IconTrend,
  IconSettings,
  IconUsers,
  IconVerify,
  IconChat,
} from '../icons.jsx'

/**
 * The sidebar is grouped rather than one flat list: with seven
 * destinations a flat list is fine, but the groups say what each page
 * is FOR, which is what someone new to the panel is actually missing.
 *
 * `end` on Dashboard only — without it "/" matches every route and
 * two items light up at once.
 *
 * `perm` is the permission the item needs. Items a role cannot open
 * are not rendered at all, and a group whose items all drop out takes
 * its heading with it — a section label over nothing reads as a
 * broken page. Hiding is courtesy, not security: the server refuses
 * the endpoint whether or not the link was drawn.
 */
const SECTIONS = [
  {
    label: 'Menu',
    items: [
      { to: '/', label: 'Dashboard', Icon: IconDashboard, end: true, perm: 'dashboard' },
    ],
  },
  {
    label: 'Operations',
    items: [
      { to: '/users', label: 'Users', Icon: IconUsers, perm: 'users' },
      {
        to: '/verifications',
        label: 'Verifications',
        Icon: IconVerify,
        badge: 'pendingVerifications',
        perm: 'verifications',
      },
      { to: '/jobs', label: 'Jobs', Icon: IconJobs, perm: 'jobs' },
      { to: '/payments', label: 'Payments', Icon: IconPayments, perm: 'payments' },
      // The route and the API stay /issues; only the label the admin
      // reads is "Disputes".
      {
        to: '/issues',
        label: 'Disputes',
        Icon: IconDisputes,
        badge: 'openIssues',
        perm: 'disputes',
      },
      // Live chat from the Help Center. Separate from Disputes on
      // purpose: a dispute is filed against a job and carries the
      // money with it, while most of what arrives here is a question.
      {
        to: '/support',
        label: 'Support Chat',
        Icon: IconChat,
        badge: 'openSupportChats',
        perm: 'support',
      },
    ],
  },
  {
    label: 'More',
    items: [
      { to: '/analytics', label: 'Analytics', Icon: IconTrend, perm: 'analytics' },
      { to: '/reports', label: 'Reports', Icon: IconReports, perm: 'reports' },
      // Settings holds the payment keys, the admin accounts and the
      // permission grid. Either permission is reason to show it; the
      // page itself only draws the tabs the role can use.
      {
        to: '/settings',
        label: 'Settings',
        Icon: IconSettings,
        perm: ['payment_settings', 'admins'],
      },
    ],
  },
]

/** Page title shown in the topbar, keyed by the first path segment. */
const TITLES = {
  '': 'Dashboard',
  users: 'Users',
  verifications: 'Verifications',
  jobs: 'Jobs',
  payments: 'Payments',
  issues: 'Disputes',
  support: 'Support Chat',
  analytics: 'Analytics',
  reports: 'Reports',
  settings: 'Settings',
}

export default function Layout() {
  const nav = useNavigate()
  const { pathname } = useLocation()

  // Seeded from what login stored so the name and avatar paint at
  // once, then replaced by the server's answer. Permissions are NOT
  // seeded: a role can be edited while someone is signed in, and a
  // stale copy would show doors the server has already locked.
  const stored = JSON.parse(localStorage.getItem('pargig_admin') || '{}')
  const [me, setMe] = useState(null)
  const [loadingMe, setLoadingMe] = useState(true)

  const loadMe = useCallback(
    () =>
      api
        .get('/admin/me')
        .then((r) => {
          setMe(r.data)
          localStorage.setItem('pargig_admin', JSON.stringify(r.data))
          return r.data
        })
        .catch(() => null)
        .finally(() => setLoadingMe(false)),
    [],
  )

  useEffect(() => {
    loadMe()
  }, [loadMe])

  const admin = me || stored
  const permissions = me?.permissions || []

  // Counts for the sidebar badge and the bell. A badge that is always
  // there, or always a fixed number, trains people to ignore it — so
  // it is the real open-dispute count or nothing at all.
  const [counts, setCounts] = useState(null)

  // Only fetched by someone who may read it. Without this an admin
  // with no dashboard permission would poll a 403 every thirty
  // seconds for as long as the panel stayed open.
  const mayCount = permissions.includes('dashboard') || permissions.includes('analytics')

  const refreshCounts = useCallback(
    () =>
      api
        .get('/admin/dashboard')
        .then((r) => setCounts(r.data))
        .catch(() => {}),
    [],
  )

  useEffect(() => {
    if (!mayCount) return undefined
    let cancelled = false
    const load = () =>
      api
        .get('/admin/dashboard')
        .then((r) => {
          if (!cancelled) setCounts(r.data)
        })
        .catch(() => {})
    load()
    const id = setInterval(load, 30000)
    return () => {
      cancelled = true
      clearInterval(id)
    }
  }, [mayCount])

  const logout = () => {
    localStorage.removeItem('pargig_admin_token')
    localStorage.removeItem('pargig_admin')
    nav('/login', { replace: true })
  }

  const segment = pathname.split('/')[1] || ''
  const title = TITLES[segment] || 'Dashboard'
  // Badges read their own count out of the dashboard payload, so a
  // new badged item needs a key here and nothing else.
  const badgeCount = (key) => (key ? counts?.[key] || 0 : 0)

  // What the bell counts: open disputes THIS admin has not opened —
  // exactly what the dots in the list mark, and nothing else.
  //
  // It is not the open count, which stays true until someone decides
  // each dispute and so sat on the same number forever; that is the
  // sidebar's job. Nor is it "arrived since I last looked", which
  // zeroed the bell the moment the page loaded and left three dotted
  // rows under a bell reading nothing. Two marks disagreeing on one
  // screen teaches people to believe neither.
  //
  // (It never showed at all before any of that: `open` was never
  // declared, so it resolved to window.open, the browser global, and
  // `open > 0` compared a function to a number and got NaN. eslint
  // saw nothing wrong because window.open is a legitimate global.)
  const open = badgeCount('unreadIssues')

  const allows = (perm) =>
    !perm ||
    (Array.isArray(perm)
      ? perm.some((k) => permissions.includes(k))
      : permissions.includes(perm))

  // Built before render so an emptied group drops its heading too.
  const sections = SECTIONS
    .map((s) => ({ ...s, items: s.items.filter((i) => allows(i.perm)) }))
    .filter((s) => s.items.length > 0)
  const initial = (admin.name || 'A').trim().charAt(0).toUpperCase()

  return (
    <AdminContext.Provider
      value={{
        admin,
        permissions,
        loading: loadingMe,
        reload: loadMe,
        refreshCounts,
      }}
    >
    <div className="layout">
      <aside className="sidebar">
        <div className="brand">
          <span className="brand-mark" aria-hidden="true">P</span>
          <span className="brand-name">PARGIG</span>
        </div>

        <nav className="nav">
          {sections.map((section) => (
            <div className="nav-section" key={section.label}>
              <div className="nav-section-label">{section.label}</div>
              {section.items.map(({ to, label, Icon, end, badge }) => (
                <NavLink to={to} end={end} key={to}>
                  <Icon />
                  <span className="nav-label">{label}</span>
                  {badgeCount(badge) > 0 && (
                    <span className="nav-badge">{badgeCount(badge)}</span>
                  )}
                </NavLink>
              ))}
            </div>
          ))}
        </nav>

        <div className="sidebar-foot">
          <div className="avatar" aria-hidden="true">{initial}</div>
          <div className="sidebar-foot-text">
            <div className="sidebar-foot-name">{admin.name || 'Admin'}</div>
            <div className="sidebar-foot-role">{admin.role || 'admin'}</div>
          </div>
        </div>
      </aside>

      <main className="main">
        <header className="topbar">
          <div>
            <h2>{title}</h2>
            <div className="crumbs">
              Pargig <span aria-hidden="true">/</span> {title}
            </div>
          </div>

          <div className="topbar-actions">
            {/* The bell goes to the dispute queue, so it is only drawn
                for a role that can open it. */}
            {permissions.includes('disputes') && (
            <button
              type="button"
              className="icon-btn"
              onClick={() => nav('/issues?status=open,under_review')}
              aria-label={
                open > 0
                  ? `${open} dispute${open === 1 ? '' : 's'} you have not read`
                  : 'You have read every open dispute'
              }
              title={
                open > 0
                  ? `${open} you have not read yet`
                  : 'You have read every open dispute'
              }
            >
              <IconBell />
              {open > 0 && <span className="icon-btn-dot">{open}</span>}
            </button>
            )}

            <div className="who">
              <div className="avatar" aria-hidden="true">{initial}</div>
              <span className="who-name">{admin.name || 'Admin'}</span>
            </div>

            <button className="btn secondary btn-icon" onClick={logout}>
              <IconLogout size={16} />
              Logout
            </button>
          </div>
        </header>

        <Outlet />
      </main>
    </div>
    </AdminContext.Provider>
  )
}
