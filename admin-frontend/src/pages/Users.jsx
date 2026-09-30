import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { api } from '../api'
import Pagination from '../components/Pagination.jsx'

const PAGE_SIZE = 20

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

  const toggleBlock = async (u) => {
    await api.put(`/admin/users/${u._id}/status`, {
      isBlocked: !u.isBlocked,
      blockReason: !u.isBlocked ? prompt('Reason for blocking?') || 'Blocked by admin' : ''
    })
    load()
  }

  const deleteUser = async (u) => {
    const ok = window.confirm(
      `Delete ${u.name || u.mobile}? This permanently removes the user. ` +
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
          placeholder="Search by name / mobile"
          value={q}
          onChange={(e) => search(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && load()}
        />
        <button className="btn" onClick={load}>Search</button>
      </div>
      <div className="card" style={{ padding: 0 }}>
        <table>
          <thead>
            <tr>
              <th>Name</th>
              <th>Mobile</th>
              <th>Role</th>
              <th>Status</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {users.map((u) => (
              <tr key={u._id}>
                <td><Link to={`/users/${u._id}`}>{u.name || u.mobile || '—'}</Link></td>
                <td>{u.mobile}</td>
                <td>{(u.roles || []).join(', ') || '—'}</td>
                <td>
                  {u.isBlocked
                    ? <span className="badge red">blocked</span>
                    : <span className="badge green">active</span>}
                </td>
                <td>
                  <button
                    className="btn"
                    style={{ background: '#408ee0', color: '#fff', borderColor: '#408ee0' }}
                    onClick={() => setSelected(u)}
                  >
                    View
                  </button>{' '}
                  <button className={`btn ${u.isBlocked ? 'success' : 'danger'}`} onClick={() => toggleBlock(u)}>
                    {u.isBlocked ? 'Unblock' : 'Block'}
                  </button>{' '}
                  <button className="btn danger" onClick={() => deleteUser(u)}>
                    Delete
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        <Pagination
          page={page}
          limit={PAGE_SIZE}
          total={total}
          onPage={setPage}
        />
      </div>

      {selected && (
        <div style={{
          position: 'fixed', inset: 0, background: 'rgba(0,0,0,.5)',
          display: 'grid', placeItems: 'center', zIndex: 50
        }} onClick={() => setSelected(null)}>
          <div className="card" style={{ width: 600, maxHeight: '80vh', overflow: 'auto' }} onClick={(e) => e.stopPropagation()}>
            <h3>{selected.name || selected.mobile}</h3>
            <p>Mobile: {selected.mobile}</p>
            <p>Email: {selected.email || '—'}</p>
            <p>Roles: {(selected.roles || []).join(', ') || '—'}</p>
            <p>
              Verified:{' '}
              {selected.isVerifiedProfessional
                ? <span className="badge green">verified</span>
                : <span className="badge gray">not verified</span>}
            </p>
            <p>
              Rating: {selected.rating?.average?.toFixed?.(1) || 0}{' '}
              <span style={{ color: 'var(--muted, #6a7282)' }}>
                ({selected.rating?.count || 0} reviews)
              </span>
            </p>
            <p>Wallet: ₹{selected.walletBalance || 0}</p>
            <p>
              Status:{' '}
              {selected.isBlocked
                ? <span className="badge red">blocked</span>
                : <span className="badge green">active</span>}
              {selected.isBlocked && selected.blockReason && (
                <span style={{ marginLeft: 8, color: 'var(--muted, #6a7282)' }}>
                  — {selected.blockReason}
                </span>
              )}
            </p>
            <p>
              Address:{' '}
              {[
                selected.location?.address,
                selected.location?.city,
                selected.location?.state,
                selected.location?.pincode,
              ]
                .filter((s) => s && String(s).trim())
                .join(', ') || '—'}
            </p>
            <p>
              Coordinates:{' '}
              {Array.isArray(selected.location?.coordinates) &&
              (selected.location.coordinates[0] !== 0 ||
                selected.location.coordinates[1] !== 0)
                ? `${selected.location.coordinates[1]}, ${selected.location.coordinates[0]}`
                : '—'}
            </p>
            <p>
              Work Location:{' '}
              {selected.workAreaLabel ? (
                <span>{selected.workAreaLabel} </span>
              ) : null}
              {Array.isArray(selected.workArea?.coordinates) &&
              (selected.workArea.coordinates[0] !== 0 ||
                selected.workArea.coordinates[1] !== 0)
                ? `(${selected.workArea.coordinates[1]}, ${selected.workArea.coordinates[0]})`
                : (selected.workAreaLabel ? '' : '—')}
            </p>
            <p>
              Search Radius:{' '}
              {selected.searchRadiusLabel
                ? selected.searchRadiusLabel
                : selected.searchRadiusKm
                  ? `${selected.searchRadiusKm} km`
                  : '—'}
            </p>
            <p>
              Current Location:{' '}
              {selected.currentLocationLabel ? (
                <span>{selected.currentLocationLabel} </span>
              ) : null}
              {Array.isArray(selected.currentLocation?.coordinates) &&
              (selected.currentLocation.coordinates[0] !== 0 ||
                selected.currentLocation.coordinates[1] !== 0)
                ? `${selected.currentLocation.coordinates[1]}, ${selected.currentLocation.coordinates[0]}`
                : '—'}
              {selected.currentLocationUpdatedAt && (
                <span style={{ marginLeft: 8, color: 'var(--muted, #6a7282)' }}>
                  (updated {new Date(selected.currentLocationUpdatedAt).toLocaleString()})
                </span>
              )}
            </p>
            <p>
              Profession / Skills:{' '}
              {Array.isArray(selected.skills) && selected.skills.length
                ? selected.skills.map((s) => (
                    <span
                      key={s}
                      className="badge"
                      style={{
                        background: '#FFEDD4',
                        color: '#F54900',
                        marginRight: 4,
                      }}
                    >
                      {s}
                    </span>
                  ))
                : '—'}
            </p>
            <p>
              Experience: {selected.yearsOfExperience || '—'}
            </p>
            <h4>Documents</h4>
            {(selected.documents || []).length === 0 && <p>No documents uploaded</p>}
            {(selected.documents || []).map((d) => (
              <div key={d._id} className="row" style={{ borderTop: '1px solid var(--border)', padding: '10px 0' }}>
                <a href={d.url} target="_blank" rel="noreferrer">{d.type}</a>
                <span className={`badge ${d.status === 'approved' ? 'green' : d.status === 'rejected' ? 'red' : 'yellow'}`}>{d.status}</span>
                {d.status === 'pending' && (
                  <>
                    <button className="btn success" onClick={() => verifyDoc(selected._id, d._id, 'approved')}>Approve</button>
                    <button className="btn danger" onClick={() => verifyDoc(selected._id, d._id, 'rejected')}>Reject</button>
                  </>
                )}
              </div>
            ))}
            <div className="row" style={{ marginTop: 16, gap: 8 }}>
              <button className="btn secondary" onClick={() => setSelected(null)}>Close</button>
              <button className="btn danger" onClick={() => deleteUser(selected)}>Delete user</button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
