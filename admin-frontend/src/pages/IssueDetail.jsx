import { useCallback, useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { api } from '../api'
import { ISSUE_TYPES, statusBadge, roleBadge } from '../issueMeta.jsx'

// Moving to "under review" only tells the user we are looking. The two
// closing decisions are what they are shown, so both demand a note.
const ACTIONS = [
  {
    value: 'under_review',
    label: 'Mark under review',
    hint: 'Tells the user we are looking into it. Stays open.',
    closes: false,
  },
  {
    value: 'resolved',
    label: 'Resolve',
    hint: 'Closes the issue. Your note is shown to the user.',
    closes: true,
  },
  {
    value: 'rejected',
    label: 'Reject',
    hint: 'Closes the issue without action. Your note is shown to the user.',
    closes: true,
  },
]

export default function IssueDetail() {
  const { id } = useParams()
  const nav = useNavigate()

  const [data, setData] = useState(null)
  const [error, setError] = useState('')
  const [action, setAction] = useState('')
  const [note, setNote] = useState('')
  const [saving, setSaving] = useState(false)

  const load = useCallback(async () => {
    try {
      const res = await api.get(`/admin/issues/${id}`)
      setData(res.data)
    } catch (err) {
      setError(err?.response?.data?.message || 'Could not load this issue')
    }
  }, [id])

  // Polled rather than loaded once: two admins can be looking at the
  // same issue, and the guard keeps a reply that lands after unmount
  // from setting state on a gone component.
  useEffect(() => {
    let cancelled = false
    const tick = () => {
      if (cancelled) return
      load()
    }
    tick()
    const timer = setInterval(tick, 5000)
    return () => {
      cancelled = true
      clearInterval(timer)
    }
  }, [load])

  if (error && !data) return <div className="card">{error}</div>
  if (!data) return <div className="card">Loading…</div>

  const { issue: i, otherIssuesByUser, issuesAgainstWorker } = data
  const decided = ['resolved', 'rejected'].includes(i.status)
  const chosen = ACTIONS.find((a) => a.value === action)
  const needsNote = chosen?.closes && !note.trim()
  const canSubmit = action && !needsNote && !saving

  const submit = async () => {
    if (chosen?.closes) {
      const ok = window.confirm(
        `${chosen.label} ${i.code}?\n\nThe user is notified and sees your note. This cannot be undone.`
      )
      if (!ok) return
    }
    setSaving(true)
    setError('')
    try {
      await api.put(`/admin/issues/${i._id}`, { status: action, note })
      await load()
      setAction('')
      setNote('')
    } catch (err) {
      setError(err?.response?.data?.message || 'Could not update this issue')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div>
      <div className="row" style={{ marginBottom: 16 }}>
        <button className="btn secondary" onClick={() => nav('/issues')}>
          ← Back
        </button>
      </div>

      <div className="card" style={{ marginBottom: 16 }}>
        <div className="row" style={{ justifyContent: 'space-between' }}>
          <h2 style={{ margin: 0 }}>
            <span style={{ fontFamily: 'monospace' }}>#{i.code}</span>{' '}
            {ISSUE_TYPES[i.issueType] || i.issueType}
          </h2>
          <div className="row" style={{ gap: 8 }}>
            {roleBadge(i.raisedByRole)}
            {statusBadge(i.status)}
          </div>
        </div>
        <div style={{ color: 'var(--muted)', fontSize: 13, marginTop: 6 }}>
          Raised {new Date(i.createdAt).toLocaleString()}
        </div>
      </div>

      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'minmax(0, 2fr) minmax(280px, 1fr)',
          gap: 16,
          alignItems: 'start',
        }}
      >
        <div>
          <div className="card" style={{ marginBottom: 16 }}>
            <h3 style={{ marginTop: 0 }}>What happened</h3>
            {i.subIssues?.length > 0 && (
              <div style={{ marginBottom: 10 }}>
                {i.subIssues.map((s) => (
                  <span key={s} className="badge gray" style={{ marginRight: 6 }}>
                    {s}
                  </span>
                ))}
              </div>
            )}
            <p style={{ whiteSpace: 'pre-wrap', margin: 0, lineHeight: 1.6 }}>
              {i.description}
            </p>
          </div>

          <div className="card" style={{ marginBottom: 16 }}>
            <h3 style={{ marginTop: 0 }}>
              Evidence ({i.photos?.length || 0})
            </h3>
            {i.photos?.length > 0 ? (
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10 }}>
                {i.photos.map((url) => (
                  <a key={url} href={url} target="_blank" rel="noreferrer">
                    <img
                      src={url}
                      alt="evidence"
                      style={{
                        width: 120,
                        height: 120,
                        objectFit: 'cover',
                        borderRadius: 8,
                        border: '1px solid var(--border)',
                      }}
                    />
                  </a>
                ))}
              </div>
            ) : (
              <div style={{ color: 'var(--muted)', fontSize: 13 }}>
                No photos were attached.
              </div>
            )}
          </div>

          <div className="card">
            <h3 style={{ marginTop: 0 }}>Job</h3>
            <Field label="Title">
              {i.job?._id
                ? <Link to={`/jobs/${i.job._id}`}>{i.job?.title || '—'}</Link>
                : (i.job?.title || '—')}
            </Field>
            <Field label="Category">{i.job?.category || '—'}</Field>
            <Field label="Amount">
              {i.job?.finalPrice ? `₹${Number(i.job.finalPrice).toFixed(0)}` : '—'}
            </Field>
            <Field label="Job status">{i.job?.status || '—'}</Field>
          </div>
        </div>

        <div>
          <div className="card" style={{ marginBottom: 16 }}>
            <h3 style={{ marginTop: 0 }}>People</h3>
            <Field label={
              i.raisedByRole === 'jobtaker'
                ? 'Raised by (worker)'
                : 'Raised by (client)'
            }>
              {i.raisedBy?.name || '—'}
              <div style={{ fontSize: 12, color: 'var(--muted)' }}>
                {i.raisedBy?.mobile}
                {otherIssuesByUser > 0 && ` · ${otherIssuesByUser} other issue(s) raised`}
              </div>
            </Field>
            <Field label={
              i.raisedByRole === 'jobtaker' ? 'Against (client)' : 'Against (worker)'
            }>
              {i.against?.name || '—'}
              <div style={{ fontSize: 12, color: 'var(--muted)' }}>
                {i.against?.mobile}
                {issuesAgainstWorker > 1 && ` · ${issuesAgainstWorker} issues against them`}
              </div>
            </Field>
            {issuesAgainstWorker > 2 && (
              <p style={{ color: 'var(--red)', fontSize: 12, marginBottom: 0 }}>
                Several issues have been filed against this person — worth a
                look at their record before deciding.
              </p>
            )}
          </div>

          {decided ? (
            <div className="card">
              <h3 style={{ marginTop: 0 }}>Decision</h3>
              <Field label="Outcome">{i.status}</Field>
              <Field label="Note">{i.resolution?.note || '—'}</Field>
              <Field label="Decided">
                {i.resolution?.decidedAt
                  ? new Date(i.resolution.decidedAt).toLocaleString()
                  : '—'}
              </Field>
              <p style={{ color: 'var(--muted)', fontSize: 12, marginBottom: 0 }}>
                Already closed, so the form is shut. The user can raise a new
                issue on this job if something else comes up.
              </p>
            </div>
          ) : (
            <div className="card">
              <h3 style={{ marginTop: 0 }}>Action</h3>
              {ACTIONS.map((a) => (
                <label
                  key={a.value}
                  style={{
                    display: 'block',
                    padding: '9px 0',
                    borderTop: '1px solid var(--border)',
                    cursor: 'pointer',
                  }}
                >
                  <input
                    type="radio"
                    name="action"
                    value={a.value}
                    checked={action === a.value}
                    onChange={(e) => setAction(e.target.value)}
                    style={{ marginRight: 8 }}
                  />
                  <strong style={{ fontSize: 13 }}>{a.label}</strong>
                  <div style={{ color: 'var(--muted)', fontSize: 12, marginLeft: 22 }}>
                    {a.hint}
                  </div>
                </label>
              ))}

              <div style={{ marginTop: 12 }}>
                <label style={{ fontSize: 13, fontWeight: 600 }}>
                  Note {chosen?.closes ? '(required)' : '(optional)'}
                </label>
                <textarea
                  className="input"
                  rows={4}
                  value={note}
                  onChange={(e) => setNote(e.target.value)}
                  placeholder="What did you decide, and why?"
                  style={{ width: '100%', marginTop: 6 }}
                />
                {needsNote && (
                  <div style={{ color: 'var(--red)', fontSize: 12 }}>
                    A closing note is shown to the user, so it cannot be empty.
                  </div>
                )}
              </div>

              {error && (
                <div style={{ color: 'var(--red)', fontSize: 12, marginTop: 8 }}>
                  {error}
                </div>
              )}

              <button
                className="btn"
                disabled={!canSubmit}
                onClick={submit}
                style={{ marginTop: 12, width: '100%' }}
              >
                {saving ? 'Saving…' : 'Apply'}
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

function Field({ label, children }) {
  return (
    <div style={{ marginBottom: 10 }}>
      <div style={{ fontSize: 12, color: 'var(--muted)' }}>{label}</div>
      <div style={{ fontSize: 14 }}>{children}</div>
    </div>
  )
}
