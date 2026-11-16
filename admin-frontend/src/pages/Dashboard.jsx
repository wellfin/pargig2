import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { api } from '../api'
import { IconDisputes, IconJobs, IconRupee, IconUsers } from '../icons.jsx'

/**
 * A headline figure that navigates to the rows it counts.
 *
 * The card is white and only the icon tile and the meter carry the
 * colour. Four saturated colour blocks is what every admin template
 * ships with, and it makes four unrelated numbers shout at the same
 * volume — the eye has nowhere to land.
 *
 * `ratio` draws the meter. It is only passed where a genuine
 * proportion exists — completed out of all jobs, open out of all
 * disputes. The cards without one show a caption instead, rather than
 * a bar filled to a number that means nothing.
 */
const Kpi = ({ tone, Icon, label, chip, value, caption, ratio, to }) => {
  const pct = typeof ratio === 'number' ? Math.round(ratio * 100) : null
  return (
    <Link to={to} className={`kpi kpi-${tone}`} title={`View ${label}`}>
      <div className="kpi-top">
        <span className="kpi-icon">
          <Icon size={17} />
        </span>
        {chip && <span className="kpi-chip">{chip}</span>}
      </div>
      <div className="kpi-label">{label}</div>
      <div className="kpi-value">{value ?? '—'}</div>
      {pct === null ? (
        <div className="kpi-caption">{caption}</div>
      ) : (
        <>
          <div className="kpi-bar" role="img" aria-label={`${pct} percent ${caption}`}>
            <span style={{ width: `${Math.min(100, Math.max(0, pct))}%` }} />
          </div>
          <div className="kpi-caption">
            <b>{pct}%</b> {caption}
          </div>
        </>
      )}
    </Link>
  )
}

const Stat = ({ label, value, to, hint }) => (
  <Link to={to} className="card stat stat-link" title={hint || `View ${label}`}>
    <div className="label">{label}</div>
    <div className="value">{value ?? '—'}</div>
    <div className="stat-go">View →</div>
  </Link>
)

const QuickLink = ({ to, title, body }) => (
  <Link to={to} className="quick-link">
    <div className="quick-link-title">{title}</div>
    <div className="quick-link-body">{body}</div>
  </Link>
)

/** Guards against 0/0 — a NaN width silently collapses the bar. */
const share = (part, whole) =>
  typeof part === 'number' && typeof whole === 'number' && whole > 0
    ? part / whole
    : undefined

const money = (n) =>
  typeof n === 'number'
    ? `₹${n.toLocaleString('en-IN', { maximumFractionDigits: 2 })}`
    : undefined

const STATUS_TONE = {
  open: 'blue',
  confirmed: 'yellow',
  reached: 'yellow',
  in_progress: 'yellow',
  completed: 'green',
  cancelled: 'gray',
  disputed: 'red',
}

const prettyStatus = (s) => s.replace(/_/g, ' ')

/**
 * Where every job stands right now, as a count and a share of the whole.
 *
 * Each row is a link into the jobs list filtered to that status, so the
 * number you read is one click from the rows behind it. A status with
 * no jobs still gets a row — "disputed: 0" is the answer somebody came
 * here for, and a missing row looks like a bug.
 */
const StatusOverview = ({ total, rows }) => (
  <section className="panel">
    <div className="panel-head">
      <h3>Job status overview</h3>
      <span className="panel-note">
        {typeof total === 'number' ? `${total.toLocaleString('en-IN')} jobs` : ''}
      </span>
    </div>
    <div className="panel-body">
      {!rows ? (
        <div className="muted">Loading…</div>
      ) : total === 0 ? (
        <div className="muted">No jobs posted yet.</div>
      ) : (
        <div className="statbars">
          {rows.map((r) => (
            <Link
              key={r.status}
              to={`/jobs?status=${r.status}`}
              className="statbar"
              title={`View ${prettyStatus(r.status)} jobs`}
            >
              <span className={`badge ${STATUS_TONE[r.status] || 'gray'}`}>
                {prettyStatus(r.status)}
              </span>
              <span className="statbar-meter" aria-hidden="true">
                <span
                  className={`fill ${STATUS_TONE[r.status] || 'gray'}`}
                  style={{ width: `${Math.min(100, r.percent)}%` }}
                />
              </span>
              <span className="statbar-count num">
                {r.count.toLocaleString('en-IN')}
              </span>
              <span className="statbar-pct num">{r.percent}%</span>
            </Link>
          ))}
        </div>
      )}
    </div>
  </section>
)

/**
 * How far jobs get, start to finish.
 *
 * Built from the marks each stage leaves behind — an applicant, a hire,
 * an issued start PIN, a completion stamp — not from the current
 * status, which only ever names the last step reached. That is why
 * these steps never go up, and why the drop between two of them is a
 * real loss rather than a counting artefact.
 */
const Funnel = ({ steps }) => (
  <section className="panel">
    <div className="panel-head">
      <h3>Job lifecycle</h3>
      <span className="panel-note">share of all jobs posted</span>
    </div>
    <div className="panel-body">
      {!steps ? (
        <div className="muted">Loading…</div>
      ) : steps[0]?.count === 0 ? (
        <div className="muted">No jobs posted yet.</div>
      ) : (
        <ol className="funnel">
          {steps.map((step, i) => {
            const prev = i > 0 ? steps[i - 1] : null
            const lost = prev ? prev.count - step.count : 0
            return (
              <li className="funnel-step" key={step.stage}>
                <div className="funnel-head">
                  <span className="funnel-label">{step.label}</span>
                  <span className="funnel-figures num">
                    {step.count.toLocaleString('en-IN')}
                    <b>{step.percent}%</b>
                  </span>
                </div>
                <div className="funnel-meter">
                  <span style={{ width: `${Math.min(100, step.percent)}%` }} />
                </div>
                {prev && (
                  <div className="funnel-drop">
                    {lost > 0
                      ? `${lost.toLocaleString('en-IN')} did not get this far`
                      : 'no drop-off'}
                  </div>
                )}
              </li>
            )
          })}
        </ol>
      )}
    </div>
  </section>
)

export default function Dashboard() {
  const [data, setData] = useState(null)
  const [jobStats, setJobStats] = useState(null)

  useEffect(() => {
    let cancelled = false
    const load = () => {
      if (cancelled) return
      api
        .get('/admin/dashboard')
        .then((r) => setData(r.data))
        .catch(() => {})
      api
        .get('/admin/jobs/stats')
        .then((r) => setJobStats(r.data))
        .catch(() => {})
    }
    load()
    const id = setInterval(load, 5000)
    return () => {
      cancelled = true
      clearInterval(id)
    }
  }, [])

  return (
    <div className="dash">
      <div className="kpi-row">
        <Kpi
          tone="1"
          Icon={IconUsers}
          label="Total users"
          chip="All time"
          value={data?.users?.toLocaleString('en-IN')}
          caption="registered accounts"
          to="/users"
        />
        <Kpi
          tone="2"
          Icon={IconJobs}
          label="Total jobs"
          chip="All time"
          value={data?.jobs?.toLocaleString('en-IN')}
          caption="completed"
          ratio={share(data?.completedJobs, data?.jobs)}
          to="/jobs"
        />
        <Kpi
          tone="3"
          Icon={IconDisputes}
          label="Disputes"
          chip="Raised"
          value={data?.issues?.toLocaleString('en-IN')}
          caption="still open"
          ratio={share(data?.openIssues, data?.issues)}
          to="/issues"
        />
        <Kpi
          tone="4"
          Icon={IconRupee}
          label="Platform revenue"
          chip="Fees"
          value={money(data?.platformRevenue)}
          caption="collected in fees"
          to="/reports"
        />
      </div>

      <div className="grid-stats">
        <Stat label="Completed Jobs" value={data?.completedJobs} to="/jobs?status=completed" />
        <Stat label="Payments" value={data?.payments} to="/payments" />
        <Stat
          label="Open Issues"
          value={data?.openIssues}
          // Matches how the count is computed server-side, so the
          // number on the tile equals the rows you land on.
          to="/issues?status=open,under_review"
          hint="Need Help reports awaiting review"
        />
      </div>

      <div className="dash-split">
        <StatusOverview total={jobStats?.total} rows={jobStats?.byStatus} />
        <Funnel steps={jobStats?.funnel} />
      </div>

      <section className="panel">
        <div className="panel-head">
          <h3>Quick links</h3>
        </div>
        <div className="panel-body">
          <div className="quick-links">
            <QuickLink
              to="/users"
              title="Manage users"
              body="Search, block or unblock accounts, and approve KYC documents."
            />
            <QuickLink
              to="/jobs"
              title="Monitor jobs"
              body="Every job across all statuses, with applicants and proof."
            />
            <QuickLink
              to="/payments?status=on_hold"
              title="Escrow on hold"
              body="Payments frozen pending completion."
            />
            <QuickLink
              to="/issues?status=open,under_review"
              title="Review issues"
              body="Need Help reports raised by job givers on completed jobs."
            />
            <QuickLink
              to="/payments"
              title="All payments"
              body="Transactions, fees, refunds and payout status."
            />
            <QuickLink
              to="/reports"
              title="Financial reports"
              body="Revenue, completed vs cancelled, and funds in escrow."
            />
          </div>
        </div>
      </section>
    </div>
  )
}
