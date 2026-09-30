import { useCallback, useEffect, useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import { api } from '../api'

const money = (n) => (n || n === 0 ? `₹${Number(n).toLocaleString('en-IN')}` : '—')
const when = (d) => (d ? new Date(d).toLocaleString() : '—')

const txnBadge = (t) => {
  const map = {
    payout: 'green', wallet_topup: 'blue', refund: 'blue',
    fee: 'red', payment: 'yellow'
  }
  return <span className={`badge ${map[t] || 'gray'}`}>{t}</span>
}

const Field = ({ label, children }) => (
  <div style={{ marginBottom: 12 }}>
    <div style={{ fontSize: 12, color: '#707684', marginBottom: 2 }}>{label}</div>
    <div>{children ?? '—'}</div>
  </div>
)

export default function UserDetail() {
  const { id } = useParams()
  const [data, setData] = useState(null)
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  const load = useCallback(
    () =>
      api.get(`/admin/users/${id}`)
        .then((r) => setData(r.data))
        .catch((e) => setError(e?.response?.data?.message || 'Could not load user')),
    [id],
  )

  useEffect(() => { load() }, [load])

  const toggleBlock = async () => {
    if (!data) return
    const next = !data.user.isBlocked
    const reason = next
      ? window.prompt('Reason for blocking this user?') ?? ''
      : ''
    if (next && reason === '') return
    setBusy(true)
    try {
      await api.put(`/admin/users/${id}/status`, { isBlocked: next, blockReason: reason })
      await load()
    } finally {
      setBusy(false)
    }
  }

  // Approving a document is what flips a worker to "verified" in the app,
  // so the reviewer needs to see the file itself before deciding.
  const decideDoc = async (docId, status) => {
    const remark = status === 'rejected'
      ? window.prompt('Reason for rejecting?') ?? ''
      : ''
    if (status === 'rejected' && remark === '') return
    setBusy(true)
    try {
      await api.post('/admin/users/document/verify', {
        userId: id, docId, status, remark,
      })
      await load()
    } finally {
      setBusy(false)
    }
  }

  if (error) return <div className="card">{error}</div>
  if (!data) return <div className="card">Loading…</div>

  const { user, transactions = [], stats = {}, ratings = [] } = data
  const location = [user.location?.address, user.location?.city, user.location?.pincode]
    .filter((s) => s && String(s).trim()).join(', ')

  return (
    <div>
      <div className="row" style={{ marginBottom: 16, gap: 12, alignItems: 'center' }}>
        <Link className="btn secondary" to="/users">← Users</Link>
        <h2 style={{ margin: 0 }}>{user.name || user.mobile}</h2>
        {user.isBlocked && <span className="badge red">blocked</span>}
        {user.isVerifiedProfessional && <span className="badge green">verified</span>}
        <div style={{ marginLeft: 'auto' }}>
          <button className="btn secondary" disabled={busy} onClick={toggleBlock}>
            {user.isBlocked ? 'Unblock' : 'Block'}
          </button>
        </div>
      </div>

      <div className="grid-stats" style={{ marginBottom: 16 }}>
        <div className="card stat">
          <div className="label">Wallet balance</div>
          <div className="value">{money(user.walletBalance || 0)}</div>
        </div>
        <div className="card stat">
          <div className="label">Jobs posted</div>
          <div className="value">{stats.postedJobs ?? 0}</div>
        </div>
        <div className="card stat">
          <div className="label">Jobs worked</div>
          <div className="value">{stats.workedJobs ?? 0}</div>
        </div>
        <div className="card stat">
          <div className="label">Rating</div>
          <div className="value">
            {user.rating?.average ? `${user.rating.average} ★` : '—'}
          </div>
        </div>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Profile</h3>
        <Field label="Mobile">{user.mobile}</Field>
        <Field label="Email">{user.email}</Field>
        <Field label="Roles">{(user.roles || []).join(', ') || '—'}</Field>
        <Field label="Active role">{user.activeRole || '—'}</Field>
        <Field label="Location">{location || '—'}</Field>
        <Field label="Skills">{(user.skills || []).join(', ') || '—'}</Field>
        <Field label="Jobs completed">{user.jobsCompleted ?? 0}</Field>
        <Field label="Jobs cancelled">{user.jobsCancelled ?? 0}</Field>
        <Field label="Free jobs remaining">{user.freeJobsRemaining ?? 0}</Field>
        <Field label="Joined">{when(user.createdAt)}</Field>
        {user.isBlocked && <Field label="Block reason">{user.blockReason || '—'}</Field>}
      </div>

      {/* KYC review. The verify endpoint already existed but there was no
          way to actually look at the document being approved. */}
      <div className="card">
        <h3 style={{ marginTop: 0 }}>Documents (KYC)</h3>
        {(user.documents || []).length === 0 && (
          <div style={{ color: '#707684' }}>No documents uploaded</div>
        )}
        {(user.documents || []).map((d) => (
          <div key={d._id} style={{ borderTop: '1px solid #e6e8ee', paddingTop: 12, marginTop: 12 }}>
            <div className="row" style={{ gap: 12, alignItems: 'center', marginBottom: 8 }}>
              <strong>{d.type || 'Document'}</strong>
              <span className={`badge ${d.status === 'approved' ? 'green' : d.status === 'rejected' ? 'red' : 'yellow'}`}>
                {d.status || 'pending'}
              </span>
              {d.status !== 'approved' && (
                <button className="btn" disabled={busy} onClick={() => decideDoc(d._id, 'approved')}>
                  Approve
                </button>
              )}
              {d.status !== 'rejected' && (
                <button className="btn secondary" disabled={busy} onClick={() => decideDoc(d._id, 'rejected')}>
                  Reject
                </button>
              )}
            </div>
            {d.remark && <Field label="Remark">{d.remark}</Field>}
            {d.url && (
              <a href={d.url} target="_blank" rel="noreferrer">
                <img
                  src={d.url}
                  alt={d.type || 'document'}
                  style={{ maxWidth: 320, borderRadius: 8, border: '1px solid #e6e8ee' }}
                />
              </a>
            )}
          </div>
        ))}
      </div>

      {/* The ledger behind the balance — every credit and debit, so a
          "where did my money go" query can be answered directly. */}
      <div className="card" style={{ padding: 0 }}>
        <h3 style={{ margin: 16 }}>Wallet transactions</h3>
        <table>
          <thead>
            <tr><th>Type</th><th>Amount</th><th>Balance after</th><th>Note</th><th>When</th></tr>
          </thead>
          <tbody>
            {transactions.length === 0 && (
              <tr><td colSpan={5} style={{ color: '#707684' }}>No transactions</td></tr>
            )}
            {transactions.map((t) => (
              <tr key={t._id}>
                <td>{txnBadge(t.type)}</td>
                <td style={{ color: t.amount < 0 ? '#c0392b' : '#1e8e4e' }}>
                  {t.amount < 0 ? '-' : '+'}{money(Math.abs(t.amount))}
                </td>
                <td>{t.balanceAfter != null ? money(t.balanceAfter) : '—'}</td>
                <td>{t.note || '—'}</td>
                <td>{when(t.createdAt)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {ratings.length > 0 && (
        <div className="card" style={{ padding: 0 }}>
          <h3 style={{ margin: 16 }}>Ratings received</h3>
          <table>
            <thead>
              <tr><th>From</th><th>Stars</th><th>Review</th><th>When</th></tr>
            </thead>
            <tbody>
              {ratings.map((r) => (
                <tr key={r._id}>
                  <td>{r.rater?.name || '—'}</td>
                  <td>{'★'.repeat(r.stars || 0)}</td>
                  <td>{r.review || '—'}</td>
                  <td>{when(r.createdAt)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
