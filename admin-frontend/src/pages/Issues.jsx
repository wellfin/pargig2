import { useCallback, useEffect, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { api } from '../api'
import Pagination from '../components/Pagination.jsx'
import {
  ISSUE_TYPES,
  GIVER_ISSUE_TYPES,
  TAKER_ISSUE_TYPES,
  statusBadge,
  roleBadge,
} from '../issueMeta.jsx'

const PAGE_SIZE = 20

export default function Issues() {
  const [issues, setIssues] = useState([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  // The URL owns the filters, so a dashboard tile linking to
  // ?status=open lands already filtered, and any filtered view is
  // shareable and survives a refresh.
  const [params, setParams] = useSearchParams()
  const status = params.get('status') || ''
  const issueType = params.get('issueType') || ''
  const role = params.get('role') || ''

  const load = useCallback(async () => {
    const { data } = await api.get('/admin/issues', {
      params: {
        status: status || undefined,
        issueType: issueType || undefined,
        role: role || undefined,
        page,
        limit: PAGE_SIZE,
      },
    })
    const nextTotal = data.total ?? 0
    // Resolving an issue drops it out of an "open" filter, so the page
    // count can shrink under the cursor.
    const pages = Math.max(1, Math.ceil(nextTotal / PAGE_SIZE))
    if (page > pages) {
      setPage(pages)
      return
    }
    setIssues(data.issues || [])
    setTotal(nextTotal)
  }, [status, issueType, role, page])

  const setFilter = (key, value) => {
    const next = { status, issueType, role, [key]: value }
    const clean = Object.fromEntries(
      Object.entries(next).filter(([, v]) => v)
    )
    setParams(clean, { replace: true })
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

  return (
    <div>
      <div className="row" style={{ marginBottom: 16, gap: 10 }}>
        <select
          className="input"
          value={status}
          onChange={(e) => setFilter('status', e.target.value)}
        >
          <option value="">All statuses</option>
          {['open', 'under_review', 'resolved', 'rejected'].map((s) => (
            <option key={s} value={s}>{s.replace(/_/g, ' ')}</option>
          ))}
        </select>
        <select
          className="input"
          value={role}
          onChange={(e) => setFilter('role', e.target.value)}
        >
          <option value="">Both sides</option>
          <option value="jobgiver">Raised by job giver</option>
          <option value="jobtaker">Raised by job taker</option>
        </select>
        {/* Grouped by side: the two catalogues share only "Other", and a
            flat list of thirteen gives no clue which is which. */}
        <select
          className="input"
          value={issueType}
          onChange={(e) => setFilter('issueType', e.target.value)}
        >
          <option value="">All types</option>
          <optgroup label="From job givers">
            {Object.entries(GIVER_ISSUE_TYPES).map(([k, label]) => (
              <option key={k} value={k}>{label}</option>
            ))}
          </optgroup>
          <optgroup label="From job takers">
            {Object.entries(TAKER_ISSUE_TYPES).map(([k, label]) => (
              <option key={k} value={k}>{label}</option>
            ))}
          </optgroup>
          <option value="other">Other</option>
        </select>
      </div>

      <div className="card" style={{ padding: 0 }}>
        <table>
          <thead>
            <tr>
              <th>Ref</th>
              <th>Job</th>
              <th>Raised By</th>
              <th>Side</th>
              <th>Against</th>
              <th>Type</th>
              <th>What happened</th>
              <th>Photos</th>
              <th>Status</th>
              <th>Raised</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {issues.map((i) => (
              <tr key={i._id}>
                <td style={{ fontFamily: 'monospace', fontSize: 12 }}>
                  <Link to={`/issues/${i._id}`}>#{i.code || i._id.slice(-6)}</Link>
                </td>
                <td>{i.job?.title || '—'}</td>
                <td>{i.raisedBy?.name || i.raisedBy?.mobile || '—'}</td>
                <td>{roleBadge(i.raisedByRole)}</td>
                <td>{i.against?.name || i.against?.mobile || '—'}</td>
                <td>{ISSUE_TYPES[i.issueType] || i.issueType}</td>
                <td style={{ maxWidth: 280 }}>
                  {i.subIssues?.length > 0 && (
                    <div style={{ fontSize: 11, color: 'var(--muted)' }}>
                      {i.subIssues.join(', ')}
                    </div>
                  )}
                  <div
                    style={{
                      overflow: 'hidden',
                      textOverflow: 'ellipsis',
                      whiteSpace: 'nowrap',
                    }}
                  >
                    {i.description}
                  </div>
                </td>
                <td>{i.photos?.length || 0}</td>
                <td>{statusBadge(i.status)}</td>
                <td>{new Date(i.createdAt).toLocaleDateString()}</td>
                <td>
                  <Link to={`/issues/${i._id}`}>
                    <button className="btn">
                      {['open', 'under_review'].includes(i.status) ? 'Review' : 'View'}
                    </button>
                  </Link>
                </td>
              </tr>
            ))}
            {issues.length === 0 && (
              <tr>
                <td colSpan={11} style={{ padding: 24, color: 'var(--muted)' }}>
                  No issues match this filter.
                </td>
              </tr>
            )}
          </tbody>
        </table>
        <Pagination page={page} limit={PAGE_SIZE} total={total} onPage={setPage} />
      </div>
    </div>
  )
}
