import { useEffect, useState } from 'react'
import { api } from '../api'

const Stat = ({ label, value }) => (
  <div className="card stat">
    <div className="label">{label}</div>
    <div className="value">{value ?? '—'}</div>
  </div>
)

export default function Reports() {
  const [data, setData] = useState(null)
  useEffect(() => {
    const load = () =>
      api.get('/admin/reports').then((r) => setData(r.data)).catch(() => {})
    load()
    const id = setInterval(load, 5000)
    return () => clearInterval(id)
  }, [])
  return (
    <div className="grid-stats">
      <Stat label="Total Users" value={data?.totalUsers} />
      <Stat label="Total Jobs" value={data?.totalJobs} />
      <Stat label="Completed" value={data?.completedJobs} />
      <Stat label="Cancelled" value={data?.cancelledJobs} />
      <Stat label="Platform Revenue (₹)" value={data?.platformRevenue?.toFixed?.(2)} />
      <Stat label="Funds in Escrow (₹)" value={data?.inEscrow?.toFixed?.(2)} />
    </div>
  )
}
