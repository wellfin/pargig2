import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { api } from '../api'

/**
 * A KPI tile that navigates to the rows it counts.
 *
 * Every number here is a count of something with its own list page, so a
 * tile that can't be clicked just makes the admin go and find it in the
 * sidebar and re-apply the filter by hand. `to` carries the filter in the
 * query string, which the list pages read on mount.
 */
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

export default function Dashboard() {
  const [data, setData] = useState(null)

  useEffect(() => {
    let cancelled = false
    const load = () => {
      if (cancelled) return
      api
        .get('/admin/dashboard')
        .then((r) => setData(r.data))
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
    <div>
      <div className="grid-stats">
        <Stat label="Total Users" value={data?.users} to="/users" />
        <Stat label="Total Jobs" value={data?.jobs} to="/jobs" />
        <Stat
          label="Completed Jobs"
          value={data?.completedJobs}
          to="/jobs?status=completed"
        />
        <Stat label="Payments" value={data?.payments} to="/payments" />
        <Stat label="Issues" value={data?.issues} to="/issues" />
        <Stat
          label="Open Issues"
          value={data?.openIssues}
          // Matches how the count is computed server-side, so the
          // number on the tile equals the rows you land on.
          to="/issues?status=open,under_review"
          hint="Need Help reports awaiting review"
        />
        <Stat
          label="Platform Revenue (₹)"
          value={data?.platformRevenue?.toFixed?.(2)}
          to="/reports"
        />
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Quick links</h3>
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
    </div>
  )
}
