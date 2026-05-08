import { useEffect, useState } from 'react'
import { api } from '../api'

export default function Users() {
  const [users, setUsers] = useState([])
  const [q, setQ] = useState('')
  const [selected, setSelected] = useState(null)

  const load = async () => {
    const { data } = await api.get('/admin/users', { params: { q, limit: 50 } })
    setUsers(data.users)
  }

  useEffect(() => { load() }, [])

  const toggleBlock = async (u) => {
    await api.put(`/admin/users/${u._id}/status`, {
      isBlocked: !u.isBlocked,
      blockReason: !u.isBlocked ? prompt('Reason for blocking?') || 'Blocked by admin' : ''
    })
    load()
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
          onChange={(e) => setQ(e.target.value)}
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
              <th>Roles</th>
              <th>Verified</th>
              <th>Rating</th>
              <th>Wallet</th>
              <th>Status</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {users.map((u) => (
              <tr key={u._id}>
                <td>{u.name || '—'}</td>
                <td>{u.mobile}</td>
                <td>{(u.roles || []).join(', ')}</td>
                <td>
                  {u.isVerifiedProfessional
                    ? <span className="badge green">verified</span>
                    : <span className="badge gray">no</span>}
                </td>
                <td>{u.rating?.average?.toFixed?.(1) || 0} ({u.rating?.count || 0})</td>
                <td>₹{u.walletBalance || 0}</td>
                <td>
                  {u.isBlocked
                    ? <span className="badge red">blocked</span>
                    : <span className="badge green">active</span>}
                </td>
                <td>
                  <button className="btn secondary" onClick={() => setSelected(u)}>View</button>{' '}
                  <button className={`btn ${u.isBlocked ? 'success' : 'danger'}`} onClick={() => toggleBlock(u)}>
                    {u.isBlocked ? 'Unblock' : 'Block'}
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
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
            <p>Address: {selected.location?.address || '—'}, {selected.location?.city}</p>
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
            <button className="btn secondary" onClick={() => setSelected(null)}>Close</button>
          </div>
        </div>
      )}
    </div>
  )
}
