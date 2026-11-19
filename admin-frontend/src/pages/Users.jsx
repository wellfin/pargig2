import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { api } from '../api'
import Pagination from '../components/Pagination.jsx'
import { IconEye, IconBan, IconUnban, IconTrash, IconClose } from '../icons.jsx'

const PAGE_SIZE = 20

/** What to call someone in a confirm dialog or a button label. */
const nameOf = (u) => u.name || u.mobile || 'this user'

/**
 * First letter for the avatar. Falls back to the mobile's first digit
 * rather than to a blank circle, so every row keeps the same shape
 * whether or not the person has filled their name in.
 */
const initial = (u) => {
  const from = (u.name || u.mobile || '?').trim()
  return (from[0] || '?').toUpperCase()
}

const DASH = '\u2014'

/**
 * Join address parts, dropping any the earlier parts already contain.
 *
 * The stored address usually ends with the city, so the plain join
 * produced "Subash Nagar, Tirupati, Tirupati, Andhra Pradesh" — the
 * sort of thing that reads as a bug in the data to whoever is looking
 * at it, when it is really just the join.
 */
const addressOf = (loc) => {
  const parts = []
  for (const raw of [loc?.address, loc?.city, loc?.state, loc?.pincode]) {
    const part = String(raw ?? '').trim()
    if (!part) continue
    const seen = parts.join(', ').toLowerCase()
    if (seen.includes(part.toLowerCase())) continue
    parts.push(part)
  }
  return parts.join(', ') || DASH
}

/** "lat, lng", or null when the point was never set. */
const coordsOf = (geo) => {
  const c = geo?.coordinates
  if (!Array.isArray(c) || c.length < 2) return null
  if (c[0] === 0 && c[1] === 0) return null
  return `${c[1]}, ${c[0]}`
}

/**
 * A place, as one or two lines.
 *
 * A saved place may have a readable label, a point, both or neither.
 * Rendering the label and the point as fixed lines left an empty
 * first line whenever the label was missing, which reads as broken
 * rather than as absent — so the point is promoted to the main line
 * when there is nothing else to put there.
 */
const Place = ({ label, geo, suffix }) => {
  const coords = coordsOf(geo)
  if (!label && !coords) return DASH
  return (
    <>
      {label || coords}
      {label && coords && <span className="sub mono">{coords}{suffix}</span>}
      {!label && coords && suffix && <span className="sub">{suffix}</span>}
    </>
  )
}

/** One labelled value in the dialog's grid. */
const Field = ({ label, wide, children }) => (
  <div className={`field${wide ? ' wide' : ''}`}>
    <span className="field-label">{label}</span>
    <div className="field-value">{children}</div>
  </div>
)

export default function Users() {
  const [users, setUsers] = useState([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [q, setQ] = useState('')
  const [selected, setSelected] = useState(null)

  const load = useCallback(async () => {
    const { data } = await api.get('/admin/users', {
      params: { q, page, limit: PAGE_SIZE },
    })
    const nextTotal = data.total ?? 0
    // Deleting the last row of the final page leaves the cursor past the
    // end. Step back and let the refetch land somewhere with rows, rather
    // than showing an empty table under a pager.
    const pages = Math.max(1, Math.ceil(nextTotal / PAGE_SIZE))
    if (page > pages) {
      setPage(pages)
      return
    }
    setUsers(data.users)
    setTotal(nextTotal)
  }, [q, page])

  // A new search starts from the top — staying on page 7 of the old
  // result set would show an empty table for a query with 3 matches.
  const search = (value) => {
    setQ(value)
    setPage(1)
  }

  useEffect(() => {
    let cancelled = false
    const tick = () => {
      if (cancelled) return
      load()
    }
    tick()
    const id = setInterval(tick, 5000)
    return () => {
      cancelled = true
      clearInterval(id)
    }
  }, [load])

  // Escape closes it. A dialog that can only be dismissed by finding
  // and hitting a specific button is one people learn to avoid opening.
  useEffect(() => {
    if (!selected) return undefined
    const onKey = (e) => {
      if (e.key === 'Escape') setSelected(null)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [selected])

  const toggleBlock = async (u) => {
    await api.put(`/admin/users/${u._id}/status`, {
      isBlocked: !u.isBlocked,
      blockReason: !u.isBlocked ? prompt('Reason for blocking?') || 'Blocked by admin' : ''
    })
    load()
  }

  const deleteUser = async (u) => {
    const ok = window.confirm(
      `Delete ${nameOf(u)}? This permanently removes the user. ` +
      `Their past jobs and payments stay in the database for audit, ` +
      `but show as "—" instead of a name.`
    )
    if (!ok) return
    try {
      await api.delete(`/admin/users/${u._id}`)
      if (selected && selected._id === u._id) setSelected(null)
      load()
    } catch (err) {
      const msg =
        err?.response?.data?.message || err?.message || 'Could not delete user'
      alert(msg)
    }
  }

  const verifyDoc = async (userId, docId, status) => {
    const remark = status === 'rejected' ? prompt('Reason for rejection?') || '' : ''
    await api.post('/admin/users/document/verify', { userId, docId, status, remark })
    load()
    setSelected(null)
  }

  return (
    <div>
      <div className="row" style={{ marginBottom: 16 }}>
        <input
          className="input"
          style={{ minWidth: 280 }}
          placeholder="Search by name / mobile"
          value={q}
          onChange={(e) => search(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && load()}
        />
        <button className="btn" onClick={load}>Search</button>
        <span className="muted" style={{ marginLeft: 'auto' }}>
          {total} {total === 1 ? 'user' : 'users'}
        </span>
      </div>
      <div className="card" style={{ padding: 0 }}>
        <div className="table-scroll">
        <table>
          <thead>
            <tr>
              <th>Name</th>
              <th>Mobile</th>
              <th>Role</th>
              <th>Status</th>
              <th style={{ textAlign: 'right' }}>Actions</th>
            </tr>
          </thead>
          <tbody>
            {users.length === 0 && (
              <tr>
                <td colSpan={5} className="muted" style={{ padding: 28, textAlign: 'center' }}>
                  {q ? `No user matches “${q}”.` : 'No users yet.'}
                </td>
              </tr>
            )}
            {users.map((u) => (
              <tr key={u._id}>
                <td>
                  <span className="who">
                    <span className="avatar" aria-hidden="true">{initial(u)}</span>
                    <Link to={`/users/${u._id}`}>{u.name || u.mobile || '—'}</Link>
                  </span>
                </td>
                <td className="mono">{u.mobile || '—'}</td>
                <td>
                  {(u.roles || []).length
                    ? (u.roles || []).map((r) => (
                        <span key={r} className="badge gray plain" style={{ marginRight: 4 }}>
                          {r}
                        </span>
                      ))
                    : '—'}
                </td>
                <td>
                  {u.isBlocked
                    ? <span className="badge red">blocked</span>
                    : <span className="badge green">active</span>}
                </td>
                <td>
                  {/* Icons, not words. Each carries a title AND an
                      aria-label naming the person: "Delete" with no
                      subject is the kind of button that gets clicked
                      on the wrong row. */}
                  <div className="row-actions">
                    <button
                      type="button"
                      className="act view"
                      title="View details"
                      aria-label={`View ${nameOf(u)}`}
                      onClick={() => setSelected(u)}
                    >
                      <IconEye size={16} />
                    </button>
                    <button
                      type="button"
                      className={`act ${u.isBlocked ? 'good' : 'warn'}`}
                      title={u.isBlocked ? 'Unblock this user' : 'Block this user'}
                      aria-label={`${u.isBlocked ? 'Unblock' : 'Block'} ${nameOf(u)}`}
                      onClick={() => toggleBlock(u)}
                    >
                      {u.isBlocked ? <IconUnban size={16} /> : <IconBan size={16} />}
                    </button>
                    <button
                      type="button"
                      className="act danger sep"
                      title="Delete this user"
                      aria-label={`Delete ${nameOf(u)}`}
                      onClick={() => deleteUser(u)}
                    >
                      <IconTrash size={16} />
                    </button>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        </div>
        <Pagination
          page={page}
          limit={PAGE_SIZE}
          total={total}
          onPage={setPage}
        />
      </div>

      {selected && (
        <div
          className="modal-backdrop"
          onClick={() => setSelected(null)}
        >
          <div
            className="modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="user-dialog-title"
            onClick={(e) => e.stopPropagation()}
          >
            {/* Pinned, so the way out is always on screen. */}
            <header className="modal-head">
              <span className="avatar" aria-hidden="true">{initial(selected)}</span>
              <div className="modal-title">
                <h3 id="user-dialog-title">{selected.name || selected.mobile || DASH}</h3>
                <span className="sub mono">{selected.mobile || DASH}</span>
              </div>
              {selected.isBlocked
                ? <span className="badge red">blocked</span>
                : <span className="badge green">active</span>}
              <button
                type="button"
                className="modal-x"
                onClick={() => setSelected(null)}
                aria-label="Close"
                title="Close (Esc)"
                autoFocus
              >
                <IconClose size={18} />
              </button>
            </header>

            <div className="modal-body">
              <div className="modal-section">Account</div>
              <div className="fields">
                <Field label="Email">{selected.email || DASH}</Field>
                <Field label="Roles">
                  {(selected.roles || []).length
                    ? (selected.roles || []).map((r) => (
                        <span key={r} className="badge gray plain" style={{ marginRight: 4 }}>
                          {r}
                        </span>
                      ))
                    : DASH}
                </Field>
                <Field label="Verified">
                  {selected.isVerifiedProfessional
                    ? <span className="badge green">verified</span>
                    : <span className="badge gray">not verified</span>}
                </Field>
                <Field label="Rating">
                  {selected.rating?.average?.toFixed?.(1) || 0}{' '}
                  <span className="muted">
                    ({selected.rating?.count || 0} review
                    {selected.rating?.count === 1 ? '' : 's'})
                  </span>
                </Field>
                <Field label="Wallet">₹{selected.walletBalance || 0}</Field>
                <Field label="Experience">{selected.yearsOfExperience || DASH}</Field>
                <Field label="Profession / skills" wide>
                  {Array.isArray(selected.skills) && selected.skills.length
                    ? selected.skills.map((sk) => (
                        <span
                          key={sk}
                          className="badge"
                          style={{
                            background: '#FFEDD4',
                            color: '#F54900',
                            marginRight: 4,
                          }}
                        >
                          {sk}
                        </span>
                      ))
                    : DASH}
                </Field>
                {selected.isBlocked && selected.blockReason && (
                  <Field label="Block reason" wide>{selected.blockReason}</Field>
                )}
              </div>

              <div className="modal-section">Location</div>
              <div className="fields">
                <Field label="Address" wide>
                  {addressOf(selected.location)}
                  {coordsOf(selected.location) && (
                    <span className="sub mono">{coordsOf(selected.location)}</span>
                  )}
                </Field>
                <Field label="Work area">
                  <Place label={selected.workAreaLabel} geo={selected.workArea} />
                </Field>
                <Field label="Search radius">
                  {selected.searchRadiusLabel ||
                    (selected.searchRadiusKm ? `${selected.searchRadiusKm} km` : DASH)}
                </Field>
                <Field label="Last seen" wide>
                  <Place
                    label={selected.currentLocationLabel}
                    geo={selected.currentLocation}
                    suffix={
                      selected.currentLocationUpdatedAt
                        ? ` · ${new Date(selected.currentLocationUpdatedAt).toLocaleString('en-IN')}`
                        : ''
                    }
                  />
                </Field>
              </div>

              <div className="modal-section">
                Documents
                {(selected.documents || []).length > 0 &&
                  ` (${selected.documents.length})`}
              </div>
              {(selected.documents || []).length === 0 ? (
                <p className="muted" style={{ margin: 0 }}>No documents uploaded.</p>
              ) : (
                selected.documents.map((d) => (
                  <div key={d._id} className="doc-row">
                    <a
                      className="doc-name truncate"
                      href={d.url}
                      target="_blank"
                      rel="noreferrer"
                      title={`Open the ${d.type} in a new tab`}
                    >
                      {d.type}
                    </a>
                    <span
                      className={`badge ${
                        d.status === 'approved'
                          ? 'green'
                          : d.status === 'rejected'
                            ? 'red'
                            : 'yellow'
                      }`}
                    >
                      {d.status}
                    </span>
                    {d.status === 'pending' && (
                      <>
                        <button
                          className="btn success sm"
                          onClick={() => verifyDoc(selected._id, d._id, 'approved')}
                        >
                          Approve
                        </button>
                        <button
                          className="btn danger sm"
                          onClick={() => verifyDoc(selected._id, d._id, 'rejected')}
                        >
                          Reject
                        </button>
                      </>
                    )}
                  </div>
                ))
              )}
            </div>

            {/* Delete is pushed to the far edge, away from Close. They
                were side by side, which put a permanent deletion one
                slip away from dismissing a dialog. */}
            <footer className="modal-foot">
              <Link className="btn secondary sm" to={`/users/${selected._id}`}>
                Open full profile
              </Link>
              <button
                className="btn secondary"
                style={{ marginLeft: 'auto' }}
                onClick={() => setSelected(null)}
              >
                Close
              </button>
              <button
                className="btn danger"
                style={{ marginLeft: 8 }}
                onClick={() => deleteUser(selected)}
              >
                Delete user
              </button>
            </footer>
          </div>
        </div>
      )}
    </div>
  )
}
