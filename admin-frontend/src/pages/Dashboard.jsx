import { useEffect, useState } from 'react'
import { api } from '../api'

const Stat = ({ label, value }) => (
  <div className="card stat">
    <div className="label">{label}</div>
    <div className="value">{value ?? '—'}</div>
  </div>
)

export default function Dashboard() {
  const [data, setData] = useState(null)
  useEffect(() => {
    api.get('/admin/dashboard').then((r) => setData(r.data)).catch(() => {})
  }, [])

  return (
    <div>
      <div className="grid-stats">
        <Stat label="Total Users" value={data?.users} />
        <Stat label="Total Jobs" value={data?.jobs} />
        <Stat label="Completed Jobs" value={data?.completedJobs} />
        <Stat label="Payments" value={data?.payments} />
        <Stat label="Disputes" value={data?.disputes} />
        <Stat label="Open Disputes" value={data?.openDisputes} />
        <Stat label="Platform Revenue (₹)" value={data?.platformRevenue?.toFixed?.(2)} />
      </div>
      <div className="card">
        <h3 style={{ marginTop: 0 }}>Quick links</h3>
        <p style={{ color: '#707684' }}>
          Use the sidebar to manage users (block / unblock, verify documents),
          monitor jobs across all statuses, oversee payments and escrow,
          resolve disputes, and view financial reports.
        </p>
      </div>
    </div>
  )
}
