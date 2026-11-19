import { Link, Navigate } from 'react-router-dom'
import { useAdmin, firstAllowed } from '../auth.js'

function NoAccess({ label }) {
  const { permissions } = useAdmin()
  const home = firstAllowed(permissions)
  return (
    <div className="card" style={{ maxWidth: 520 }}>
      <h3 style={{ marginTop: 0 }}>Not available to your role</h3>
      <p className="muted" style={{ lineHeight: 1.6 }}>
        {label
          ? `Your admin role does not include ${label}.`
          : 'Your admin role does not include this page.'}{' '}
        A superadmin can change that in Settings &rarr; Role Permissions.
      </p>
      {home ? (
        <Link className="btn secondary" to={home}>Go to a page you can open</Link>
      ) : (
        <p className="muted">
          Your role currently has no pages at all. Ask a superadmin to grant
          something, or sign in as a different account.
        </p>
      )}
    </div>
  )
}

/**
 * Wraps a route in the permission it needs.
 *
 * A denied deep link gets an explanation rather than a bounce —
 * someone following a shared /issues/123 deserves to know why it did
 * not open, and a silent redirect reads as a broken link. The index
 * route is the exception and redirects: landing on "no access" at /
 * when the panel has pages you CAN open is just a wrong home page.
 *
 * This hides; it does not protect. Every endpoint behind these pages
 * names its own permission on the server.
 */
export default function Guard({ perm, label, redirect = false, children }) {
  const { permissions, loading } = useAdmin()

  // Nothing renders until /admin/me answers. Children first would
  // flash a page the role cannot have; NoAccess first would flash a
  // refusal at someone who is allowed.
  if (loading) return null

  if (permissions.includes(perm)) return children

  if (redirect) {
    const home = firstAllowed(permissions)
    if (home && home !== '/') return <Navigate to={home} replace />
  }
  return <NoAccess label={label} />
}
