import { useEffect, useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import { api } from '../api'

const statusBadge = (s) => {
  const map = {
    open: 'blue', confirmed: 'yellow', reached: 'yellow', in_progress: 'yellow',
    completed: 'green', cancelled: 'gray', disputed: 'red'
  }
  return <span className={`badge ${map[s] || 'gray'}`}>{s}</span>
}

const money = (n) => (n || n === 0 ? `₹${Number(n).toLocaleString('en-IN')}` : '—')
const when = (d) => (d ? new Date(d).toLocaleString() : '—')

const Field = ({ label, children }) => (
  <div style={{ marginBottom: 12 }}>
    <div style={{ fontSize: 12, color: '#707684', marginBottom: 2 }}>{label}</div>
    <div>{children ?? '—'}</div>
  </div>
)

// Uploads are served relative to the API host, so a bare /uploads/... path
// resolves correctly whether the panel is served from the backend or a dev
// server proxying /api.
const fileUrl = (u) => (!u ? null : /^https?:\/\//.test(u) ? u : u)

export default function JobDetail() {
  const { id } = useParams()
  const [data, setData] = useState(null)
  const [error, setError] = useState('')

  useEffect(() => {
    let alive = true
    api.get(`/admin/jobs/${id}`)
      .then((r) => alive && setData(r.data))
      .catch((e) => alive && setError(e?.response?.data?.message || 'Could not load job'))
    return () => { alive = false }
  }, [id])

  if (error) return <div className="card">{error}</div>
  if (!data) return <div className="card">Loading…</div>

  const { job, payments = [], ratings = [] } = data
  const location = [job.location?.address, job.location?.city, job.location?.pincode]
    .filter((s) => s && String(s).trim()).join(', ')
  const applicants = (job.interested || []).filter((i) => i.jobtaker)

  return (
    <div>
      <div className="row" style={{ marginBottom: 16, gap: 12, alignItems: 'center' }}>
        <Link className="btn secondary" to="/jobs">← Jobs</Link>
        <h2 style={{ margin: 0 }}>{job.title}</h2>
        {statusBadge(job.status)}
        {job.isUrgent && <span className="badge red">urgent</span>}
        {job.isBoosted && <span className="badge yellow">boosted</span>}
      </div>

      <div className="grid-stats" style={{ marginBottom: 16 }}>
        <div className="card stat">
          <div className="label">Price</div>
          <div className="value">{money(job.finalPrice || job.proposedBudget)}</div>
        </div>
        <div className="card stat">
          <div className="label">Tip</div>
          <div className="value">{money(job.tip || 0)}</div>
        </div>
        <div className="card stat">
          <div className="label">Category</div>
          <div className="value" style={{ fontSize: 18 }}>{job.category || '—'}</div>
        </div>
        <div className="card stat">
          <div className="label">Payment</div>
          <div className="value" style={{ fontSize: 18 }}>
            {job.paymentReleasedAt ? 'Released' : 'Pending'}
          </div>
        </div>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Details</h3>
        <Field label="Description">{job.description || '—'}</Field>

        {/* The giver may describe the job by voice instead of typing — the
            list view gives no hint that a recording even exists. */}
        {job.voiceNoteUrl && (
          <Field label="Voice description (recorded by the job giver)">
            <audio controls src={fileUrl(job.voiceNoteUrl)} style={{ width: '100%', maxWidth: 420 }} />
          </Field>
        )}

        <Field label="Location">{location || '—'}</Field>
        <Field label="Scheduled">{job.isUrgent ? 'Immediate' : when(job.scheduledAt)}</Field>
        <Field label="Preference">{job.preference || '—'}</Field>
        <Field label="Price mode">{job.priceMode || '—'}</Field>
        <Field label="Created">{when(job.createdAt)}</Field>

        {!!(job.photos || []).length && (
          <Field label="Photos">
            <div className="row" style={{ flexWrap: 'wrap', gap: 8 }}>
              {job.photos.map((p) => (
                <a key={p} href={fileUrl(p)} target="_blank" rel="noreferrer">
                  <img src={fileUrl(p)} alt="" style={{ width: 110, height: 110, objectFit: 'cover', borderRadius: 8 }} />
                </a>
              ))}
            </div>
          </Field>
        )}
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>People</h3>
        <Field label="Job giver">
          {job.jobgiver
            ? <Link to={`/users/${job.jobgiver._id}`}>{job.jobgiver.name || job.jobgiver.mobile}</Link>
            : '—'}
        </Field>
        <Field label="Worker">
          {job.selectedJobtaker
            ? <Link to={`/users/${job.selectedJobtaker._id}`}>
                {job.selectedJobtaker.name || job.selectedJobtaker.mobile}
              </Link>
            : 'Not assigned'}
        </Field>
        <Field label={`Applicants (${applicants.length})`}>
          {applicants.length === 0 ? '—' : (
            <table>
              <thead>
                <tr><th>Name</th><th>Mobile</th><th>Proposed</th><th>Jobs done</th><th>Applied</th></tr>
              </thead>
              <tbody>
                {applicants.map((a) => (
                  <tr key={a._id || a.jobtaker._id}>
                    <td><Link to={`/users/${a.jobtaker._id}`}>{a.jobtaker.name || '—'}</Link></td>
                    <td>{a.jobtaker.mobile || '—'}</td>
                    <td>{money(a.proposedPrice)}</td>
                    <td>{a.jobtaker.jobsCompleted ?? 0}</td>
                    <td>{when(a.at || a.createdAt)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </Field>
      </div>

      {/* Proof the worker uploaded before the job could be marked done —
          the evidence a complaint usually turns on. */}
      {(job.completionPhotos?.length || job.completionNote) && (
        <div className="card">
          <h3 style={{ marginTop: 0 }}>Completion proof</h3>
          {job.completionNote && <Field label="Worker's note">{job.completionNote}</Field>}
          {!!(job.completionPhotos || []).length && (
            <div className="row" style={{ flexWrap: 'wrap', gap: 8 }}>
              {job.completionPhotos.map((p) => (
                <a key={p} href={fileUrl(p)} target="_blank" rel="noreferrer">
                  <img src={fileUrl(p)} alt="" style={{ width: 140, height: 140, objectFit: 'cover', borderRadius: 8 }} />
                </a>
              ))}
            </div>
          )}
          <Field label="Completed at">{when(job.completedAt)}</Field>
        </div>
      )}

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Timeline</h3>
        <Field label="Started (PIN verified)">{when(job.startedAt)}</Field>
        <Field label="Payout requested">{when(job.payoutRequestedAt)}</Field>
        <Field label="Payment released">{when(job.paymentReleasedAt)}</Field>
        {job.cancellation?.at && (
          <Field label="Cancelled">
            {when(job.cancellation.at)} by {job.cancellation.by || '—'}
            {job.cancellation.reason ? ` — ${job.cancellation.reason}` : ''}
          </Field>
        )}
      </div>

      <div className="card" style={{ padding: 0 }}>
        <h3 style={{ margin: 16 }}>Payments</h3>
        <table>
          <thead>
            <tr>
              <th>Amount</th><th>Fee</th><th>Payout</th><th>Method</th>
              <th>Transaction ID</th><th>Status</th><th>Released</th>
            </tr>
          </thead>
          <tbody>
            {payments.length === 0 && (
              <tr><td colSpan={7} style={{ color: '#707684' }}>No payment records</td></tr>
            )}
            {payments.map((p) => (
              <tr key={p._id}>
                <td>{money(p.amount)}</td>
                <td>{money(p.platformFee)}</td>
                <td>{money(p.payoutAmount)}</td>
                <td>{p.isCod ? 'Cash on Delivery' : (p.method || '—')}</td>
                <td style={{ fontFamily: 'monospace', fontSize: 12 }}>{p.transactionId || '—'}</td>
                <td><span className="badge gray">{p.status}</span></td>
                <td>{when(p.releasedAt)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {ratings.length > 0 && (
        <div className="card" style={{ padding: 0 }}>
          <h3 style={{ margin: 16 }}>Ratings</h3>
          <table>
            <thead>
              <tr><th>From</th><th>To</th><th>Stars</th><th>Review</th><th>When</th></tr>
            </thead>
            <tbody>
              {ratings.map((r) => (
                <tr key={r._id}>
                  <td>{r.rater?.name || '—'}</td>
                  <td>{r.ratee?.name || '—'}</td>
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
