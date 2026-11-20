import { createContext, useContext } from 'react'

/**
 * Who is signed in, and what their role may open.
 *
 * The permission list comes from GET /api/admin/me and nowhere else.
 * It is deliberately NOT read from the token or from localStorage: a
 * role's permissions can be edited while someone is signed in, and a
 * panel that trusts a copy saved at login keeps showing pages the
 * server has already started refusing.
 *
 * Everything here is convenience, not security. Hiding a nav item
 * stops nobody from typing the URL, and hiding a button stops nobody
 * from calling the endpoint — which is why every admin route names
 * the permission it needs on the server side. This exists so the
 * panel does not offer people doors that are locked.
 *
 * No JSX in this file on purpose: a module that exports both
 * components and plain values breaks Vite's fast refresh. The Guard
 * component lives in components/Guard.jsx.
 */

export const AdminContext = createContext({
  admin: null,
  permissions: [],
  loading: true,
  reload: () => {},
  // Re-reads the sidebar and bell counts. A page that changes one of
  // them calls this instead of waiting out the thirty-second poll,
  // which is long enough to read as "the button did nothing".
  refreshCounts: () => {},
})

export const useAdmin = () => useContext(AdminContext)

/** True when the signed-in admin holds ANY of these permissions. */
export function useCan(...keys) {
  const { permissions } = useAdmin()
  return keys.some((k) => permissions.includes(k))
}

/**
 * Where to send someone who has no access to where they asked for,
 * best first. The server's catalogue is the real one and is what the
 * permission grid renders; this is only the landing order.
 */
export const LANDING_ORDER = [
  { perm: 'dashboard', to: '/' },
  { perm: 'disputes', to: '/issues' },
  { perm: 'support', to: '/support' },
  { perm: 'verifications', to: '/verifications' },
  { perm: 'users', to: '/users' },
  { perm: 'jobs', to: '/jobs' },
  { perm: 'payments', to: '/payments' },
  { perm: 'analytics', to: '/analytics' },
  { perm: 'reports', to: '/reports' },
  { perm: 'integrations', to: '/settings' },
  { perm: 'admins', to: '/settings' },
]

/** The first page this admin can actually open, or null. */
export function firstAllowed(permissions) {
  const hit = LANDING_ORDER.find((p) => permissions.includes(p.perm))
  return hit ? hit.to : null
}
