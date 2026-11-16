import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { api } from '../api'

/**
 * The queue — everything that wants a human to look at it.
 *
 * Each group shows a count and the handful of rows you would open
 * first. A count on its own says there is a problem without saying
 * which one, so the rows come with it; the count says how deep the
 * pile goes behind them.
 *
 * The thresholds come from the server and are printed under the list.
 * "Stale" is an opinion; "open more than 7 days with nobody on it" is
 * a rule somebody can disagree with, which is the point.
 */

const money = (n) =>
  `₹${Number(n || 0).toLocaleString('en-IN', { maximumFractionDigits: 0 })}`

const ago = (iso) => {
  if (!iso) return ''
  const mins = Math.max(0, Math.round((Date.now() - new Date(iso)) / 60000))
  if (mins < 60) return `${mins}m ago`
  const hrs = Math.round(mins / 60)
  if (hrs < 48) return `${hrs}h ago`
  return `${Math.round(hrs / 24)}d ago`
}

const valueOf = (j) =>
  (j.value ?? (j.finalPrice ?? j.proposedBudget ?? 0) + (j.tip ?? 0)) || 0

export default function AttentionPanel() {
  const [data, setData] = useState(null)
  const [picked, setPicked] = useState(null)

  useEffect(() => {
    let cancelled = false
    const load = () => {
      if (cancelled) return
      api
        .get('/admin/alerts')
        .then((r) => setData(r.data))
        .catch(() => {})
    }
    load()
    const id = setInterval(load, 60000)
    return () => {
      cancelled = true
      clearInterval(id)
    }
  }, [])

  // Memoised so the fallback [] is not a fresh array on every render,
  // which would re-run the lookup below for nothing.
  const groups = useMemo(() => data?.groups || [], [data])
  const total = groups.reduce((a, g) => a + g.count, 0)

  // Open on the first group that actually has something in it, so the
  // panel lands on work rather than on an empty list the reader then
  // has to click past.
  const active = useMemo(() => {
    if (picked && groups.some((g) => g.id === picked)) return picked
    return (groups.find((g) => g.count > 0) || groups[0])?.id
  }, [picked, groups])

  const group = groups.find((g) => g.id === active)

  return (
    <section className="panel">
      <div className="panel-head">
        <h3>Needs attention</h3>
        <span className="panel-note">
          {data ? (total === 0 ? 'all clear' : `${total} items`) : ''}
        </span>
      </div>
      <div className="panel-body">
        {!data ? (
          <div className="muted">Loading…</div>
        ) : total === 0 ? (
          <div className="chart-empty">
            Nothing is waiting. No disputes, nothing stalled, no job sitting
            unassigned.
          </div>
        ) : (
          <>
            <div className="alert-tabs">
              {groups.map((g) => (
                <button
                  key={g.id}
                  type="button"
                  className={`alert-tab tone-${g.tone}${g.id === active ? ' on' : ''}${
                    g.count === 0 ? ' empty' : ''
                  }`}
                  onClick={() => setPicked(g.id)}
                  aria-pressed={g.id === active}
                >
                  <span className="alert-dot" aria-hidden="true" />
                  {g.label}
                  <span className="alert-count num">{g.count}</span>
                </button>
              ))}
            </div>

            {group && (
              <>
                {group.count === 0 ? (
                  <div className="chart-empty">Nothing here right now.</div>
                ) : group.kind === 'user' ? (
                  <UserRows rows={group.rows} />
                ) : (
                  <JobRows rows={group.rows} id={group.id} />
                )}
                <div className="chart-caption">
                  {group.hint}
                  {group.count > group.rows.length &&
                    ` · showing ${group.rows.length} of ${group.count}`}
                </div>
              </>
            )}
          </>
        )}
      </div>
    </section>
  )
}

const JobRows = ({ rows, id }) => (
  <div className="table-scroll" style={{ maxHeight: 290 }}>
    <table>
      <thead>
        <tr>
          <th>Job</th>
          <th>Job giver</th>
          <th className="num">Value</th>
          <th className="num">
            {/* Each group is waiting on a different clock, so the
                column says which one it is showing. */}
            {id === 'stuck' ? 'PIN issued' : 'Posted'}
          </th>
        </tr>
      </thead>
      <tbody>
        {rows.map((j) => (
          <tr key={j._id}>
            <td>
              <Link to={`/jobs/${j._id}`}>{j.title || 'Untitled'}</Link>
              <div className="sub">
                {j.status}
                {(j.city || j.location?.city) && ` · ${j.city || j.location.city}`}
              </div>
            </td>
            <td>
              {j.jobgiver ? (
                <Link to={`/users/${j.jobgiver._id}`}>
                  {j.jobgiver.name || j.jobgiver.mobile}
                </Link>
              ) : (
                <span className="sub">—</span>
              )}
            </td>
            <td className="num">{money(valueOf(j))}</td>
            <td className="num">
              {ago(id === 'stuck' ? j.startOtp?.issuedAt : j.createdAt)}
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  </div>
)

const UserRows = ({ rows }) => (
  <div className="table-scroll" style={{ maxHeight: 290 }}>
    <table>
      <thead>
        <tr>
          <th>Account</th>
          <th>Cancelled as</th>
          <th className="num">Count</th>
          <th className="num">Last one</th>
        </tr>
      </thead>
      <tbody>
        {rows.map((u) => (
          <tr key={`${u.userId}-${u.side}`}>
            <td>
              <Link to={`/users/${u.userId}`}>{u.name || 'Unnamed'}</Link>
              <div className="sub">{u.mobile}</div>
            </td>
            <td>{u.side === 'jobgiver' ? 'Job giver' : 'Job taker'}</td>
            <td className="num">{u.n}</td>
            <td className="num">{ago(u.lastAt)}</td>
          </tr>
        ))}
      </tbody>
    </table>
  </div>
)
