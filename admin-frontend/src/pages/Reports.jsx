import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { api } from '../api'
import { downloadCsv, fmtDate, fmtUser } from '../utils/exportCsv'

// One page holds every row of an export. The list endpoints paginate, so
// without an explicit high limit an export would silently contain only
// the first 30 rows — a report that looks complete and isn't.
const EXPORT_LIMIT = 5000

const Stat = ({ label, value, to }) => (
  <Link to={to} className="card stat stat-link" title={`View ${label}`}>
    <div className="label">{label}</div>
    <div className="value">{value ?? '—'}</div>
    <div className="stat-go">View →</div>
  </Link>
)

const DATASETS = [
  {
    id: 'users',
    label: 'Users',
    path: '/admin/users',
    pick: (d) => d.users,
    columns: [
      { key: 'name', label: 'Name' },
      { key: 'mobile', label: 'Mobile' },
      { key: 'email', label: 'Email' },
      { key: 'roles', label: 'Roles', format: (v) => (v || []).join(' | ') },
      { key: 'isVerifiedProfessional', label: 'Verified' },
      { key: 'isBlocked', label: 'Blocked' },
      { key: 'blockReason', label: 'Block reason' },
      { key: 'rating.average', label: 'Rating' },
      { key: 'rating.count', label: 'Reviews' },
      { key: 'jobsCompleted', label: 'Jobs completed' },
      { key: 'walletBalance', label: 'Wallet (₹)' },
      { key: 'location.city', label: 'City' },
      { key: 'createdAt', label: 'Joined', format: fmtDate },
    ],
  },
  {
    id: 'jobs',
    label: 'Jobs',
    path: '/admin/jobs',
    pick: (d) => d.jobs,
    columns: [
      { key: 'title', label: 'Title' },
      { key: 'category', label: 'Category' },
      { key: 'status', label: 'Status' },
      { key: 'jobgiver', label: 'Job giver', format: fmtUser },
      { key: 'selectedJobtaker', label: 'Worker', format: fmtUser },
      { key: 'proposedBudget', label: 'Budget (₹)' },
      { key: 'finalPrice', label: 'Final price (₹)' },
      { key: 'tip', label: 'Tip (₹)' },
      { key: 'isUrgent', label: 'Urgent' },
      { key: 'location.city', label: 'City' },
      { key: 'location.pincode', label: 'Pincode' },
      { key: 'scheduledAt', label: 'Scheduled', format: fmtDate },
      { key: 'createdAt', label: 'Posted', format: fmtDate },
    ],
  },
  {
    id: 'payments',
    label: 'Payments',
    path: '/admin/payments',
    pick: (d) => d.payments,
    columns: [
      { key: 'transactionId', label: 'Transaction ID' },
      { key: 'job.title', label: 'Job' },
      { key: 'jobgiver', label: 'Paid by', format: fmtUser },
      { key: 'jobtaker', label: 'Paid to', format: fmtUser },
      { key: 'amount', label: 'Amount (₹)' },
      { key: 'platformFee', label: 'Platform fee (₹)' },
      { key: 'tipAmount', label: 'Tip (₹)' },
      { key: 'payoutAmount', label: 'Payout (₹)' },
      { key: 'status', label: 'Status' },
      { key: 'isCod', label: 'Cash on delivery' },
      { key: 'gateway', label: 'Gateway' },
      { key: 'refundReason', label: 'Refund reason' },
      { key: 'createdAt', label: 'Date', format: fmtDate },
    ],
  },
]

export default function Reports() {
  const [data, setData] = useState(null)
  const [busy, setBusy] = useState('')
  const [error, setError] = useState('')

  useEffect(() => {
    let cancelled = false
    const load = () => {
      if (cancelled) return
      api
        .get('/admin/reports')
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

  const exportDataset = async (ds) => {
    setBusy(ds.id)
    setError('')
    try {
      const { data: res } = await api.get(ds.path, {
        params: { page: 1, limit: EXPORT_LIMIT },
      })
      const rows = ds.pick(res) || []
      if (!rows.length) {
        setError(`No ${ds.label.toLowerCase()} to export.`)
        return
      }
      downloadCsv(`pargig-${ds.id}`, rows, ds.columns)
      // Tell the admin when the export was capped, rather than handing
      // them a truncated file that looks whole.
      if ((res.total ?? rows.length) > rows.length) {
        setError(
          `Exported the first ${rows.length} of ${res.total} ${ds.label.toLowerCase()}.`
        )
      }
    } catch (err) {
      setError(err?.response?.data?.message || `Could not export ${ds.label}`)
    } finally {
      setBusy('')
    }
  }

  const exportSummary = () => {
    if (!data) return
    const rows = [
      { metric: 'Total users', value: data.totalUsers },
      { metric: 'Total jobs', value: data.totalJobs },
      { metric: 'Completed jobs', value: data.completedJobs },
      { metric: 'Cancelled jobs', value: data.cancelledJobs },
      { metric: 'Platform revenue (₹)', value: data.platformRevenue },
      { metric: 'Funds in escrow (₹)', value: data.inEscrow },
      { metric: 'Generated', value: new Date().toLocaleString() },
    ]
    downloadCsv('pargig-summary', rows, [
      { key: 'metric', label: 'Metric' },
      { key: 'value', label: 'Value' },
    ])
  }

  return (
    <div>
      <div className="grid-stats">
        <Stat label="Total Users" value={data?.totalUsers} to="/users" />
        <Stat label="Total Jobs" value={data?.totalJobs} to="/jobs" />
        <Stat
          label="Completed"
          value={data?.completedJobs}
          to="/jobs?status=completed"
        />
        <Stat
          label="Cancelled"
          value={data?.cancelledJobs}
          to="/jobs?status=cancelled"
        />
        <Stat
          label="Platform Revenue (₹)"
          value={data?.platformRevenue?.toFixed?.(2)}
          to="/payments?status=released"
        />
        <Stat
          label="Funds in Escrow (₹)"
          value={data?.inEscrow?.toFixed?.(2)}
          to="/payments?status=on_hold"
        />
      </div>

      <div className="card">
        <div className="row" style={{ justifyContent: 'space-between' }}>
          <h3 style={{ margin: 0 }}>Export to Excel</h3>
          <button
            className="btn secondary"
            onClick={exportSummary}
            disabled={!data}
          >
            ⬇ Summary
          </button>
        </div>
        <p style={{ color: 'var(--muted)', fontSize: 13, marginTop: 8 }}>
          Downloads a CSV that opens directly in Excel. Exports the full
          dataset, not just the page you are viewing.
        </p>
        <div className="quick-links">
          {DATASETS.map((ds) => (
            <button
              key={ds.id}
              className="quick-link"
              style={{ textAlign: 'left', cursor: 'pointer', font: 'inherit' }}
              onClick={() => exportDataset(ds)}
              disabled={busy === ds.id}
            >
              <div className="quick-link-title">
                {busy === ds.id ? `Exporting ${ds.label}…` : `Export ${ds.label}`}
              </div>
              <div className="quick-link-body">
                {ds.columns.length} columns · CSV for Excel
              </div>
            </button>
          ))}
        </div>
        {error && (
          <p style={{ color: 'var(--red)', fontSize: 13, marginBottom: 0 }}>
            {error}
          </p>
        )}
      </div>
    </div>
  )
}
