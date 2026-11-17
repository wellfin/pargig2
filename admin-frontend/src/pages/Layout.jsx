import { useEffect, useState } from 'react'
import { NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom'
import { api } from '../api'
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
} from '../icons.jsx'

/**
 * The sidebar is grouped rather than one flat list: with seven
 * destinations a flat list is fine, but the groups say what each page
 * is FOR, which is what someone new to the panel is actually missing.
 *
 * `end` on Dashboard only — without it "/" matches every route and
 * two items light up at once.
 */
const SECTIONS = [
  {
    label: 'Menu',
    items: [{ to: '/', label: 'Dashboard', Icon: IconDashboard, end: true }],
  },
  {
    label: 'Operations',
    items: [
      { to: '/users', label: 'Users', Icon: IconUsers },
      {
        to: '/verifications',
        label: 'Verifications',
        Icon: IconVerify,
        badge: 'pendingVerifications',
      },
      { to: '/jobs', label: 'Jobs', Icon: IconJobs },
      { to: '/payments', label: 'Payments', Icon: IconPayments },
      // The route and the API stay /issues; only the label the admin
      // reads is "Disputes".
      { to: '/issues', label: 'Disputes', Icon: IconDisputes, badge: 'openIssues' },
    ],
  },
  {
    label: 'More',
    items: [
      { to: '/analytics', label: 'Analytics', Icon: IconTrend },
      { to: '/reports', label: 'Reports', Icon: IconReports },
      { to: '/settings', label: 'Settings', Icon: IconSettings },
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
  analytics: 'Analytics',
  reports: 'Reports',
  settings: 'Settings',
}

export default function Layout() {
  const nav = useNavigate()
  const { pathname } = useLocation()
  const admin = JSON.parse(localStorage.getItem('pargig_admin') || '{}')

  // Counts for the sidebar badge and the bell. A badge that is always
  // there, or always a fixed number, trains people to ignore it — so
  // it is the real open-dispute count or nothing at all.
  const [counts, setCounts] = useState(null)

  useEffect(() => {
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
  }, [])

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
  const initial = (admin.name || 'A').trim().charAt(0).toUpperCase()

  return (
    <div className="layout">
      <aside className="sidebar">
        <div className="brand">
          <span className="brand-mark" aria-hidden="true">P</span>
          <span className="brand-name">PARGIG</span>
        </div>

        <nav className="nav">
          {SECTIONS.map((section) => (
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
            <button
              type="button"
              className="icon-btn"
              onClick={() => nav('/issues?status=open,under_review')}
              aria-label={
                open > 0 ? `${open} disputes need review` : 'No disputes need review'
              }
              title={open > 0 ? `${open} disputes need review` : 'Nothing waiting'}
            >
              <IconBell />
              {open > 0 && <span className="icon-btn-dot">{open}</span>}
            </button>

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
  )
}
