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
import { IconPhoto } from '../icons.jsx'

const PAGE_SIZE = 20

/** How many sub-issue tags to show before collapsing the rest. */
const CHIP_LIMIT = 2

/**
 * The sub-issue tags for one row.
 *
 * These used to be a comma-joined string inside a nowrap cell, so the
 * cell's overflow sliced it mid-word with no ellipsis: "Property
 * Damage" rendered as "Property I". Nothing marked it as cut, and
 * nothing recovered it.
 *
 * Tags are a list, so they are drawn as a list. Past CHIP_LIMIT they
 * become a +N counter rather than disappearing, which is the part
 * that makes the truncation honest — the row says how much it is not
 * showing. The full set is on the title and on the detail page.
 */
function SubIssues({ items }) {
  if (!items || items.length === 0) return null
  const shown = items.slice(0, CHIP_LIMIT)
  const hidden = items.length - shown.length
  return (
    <div className="chips">
      {shown.map((s) => (
        <span key={s} className="chip" title={s}>{s}</span>
      ))}
      {hidden > 0 && (
        <span className="chip chip-more" title={items.join(', ')}>
          +{hidden}
        </span>
      )}
    </div>
  )
}

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
        <span className="muted" style={{ marginLeft: 'auto' }}>
          {total} {total === 1 ? 'issue' : 'issues'}
        </span>
      </div>

      <div className="card" style={{ padding: 0 }}>
        {/* Eleven columns do not fit a laptop. Scrolling inside the card
            keeps the sidebar and the filters put, and the header sticks
            so column names survive the scroll. */}
        <div className="table-scroll">
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
              <th style={{ textAlign: 'right' }}>Action</th>
            </tr>
          </thead>
          <tbody>
            {issues.map((i) => (
              <tr key={i._id}>
                <td className="mono">
                  <Link to={`/issues/${i._id}`}>#{i.code || i._id.slice(-6)}</Link>
                </td>
                <td title={i.job?.title || ''}>{i.job?.title || '—'}</td>
                <td title={i.raisedBy?.name || i.raisedBy?.mobile || ''}>
                  {i.raisedBy?.name || i.raisedBy?.mobile || '—'}
                </td>
                <td>{roleBadge(i.raisedByRole)}</td>
                <td title={i.against?.name || i.against?.mobile || ''}>
                  {i.against?.name || i.against?.mobile || '—'}
                </td>
                <td>{ISSUE_TYPES[i.issueType] || i.issueType}</td>
                {/* The widest column, and the only one carrying free
                    text. Both lines are recoverable on hover; all of it
                    is on the detail page behind Review. */}
                <td style={{ maxWidth: 340 }} title={i.description || ''}>
                  <SubIssues items={i.subIssues} />
                  <div className="truncate">{i.description}</div>
                </td>
                <td>
                  {i.photos?.length ? (
                    <span className="count-ico">
                      <IconPhoto size={14} />
                      {i.photos.length}
                    </span>
                  ) : (
                    /* A dash, not a 0: a column of zeroes reads as data
                       when it is really the absence of it. */
                    <span className="dim">—</span>
                  )}
                </td>
                <td>{statusBadge(i.status)}</td>
                <td>{new Date(i.createdAt).toLocaleDateString('en-IN', {
                  day: 'numeric', month: 'short', year: 'numeric',
                })}</td>
                <td style={{ textAlign: 'right' }}>
                  <Link className="btn secondary sm" to={`/issues/${i._id}`}>
                    {['open', 'under_review'].includes(i.status) ? 'Review' : 'View'}
                  </Link>
                </td>
              </tr>
            ))}
            {issues.length === 0 && (
              <tr>
                <td colSpan={11} className="muted" style={{ padding: 28, textAlign: 'center' }}>
                  No issues match this filter.
                </td>
              </tr>
            )}
          </tbody>
        </table>
        </div>
        <Pagination page={page} limit={PAGE_SIZE} total={total} onPage={setPage} />
      </div>
    </div>
  )
}
