import { useEffect, useState } from 'react'
import { api } from '../api'

const statusBadge = (s) => {
  const map = {
    open: 'blue', confirmed: 'yellow', reached: 'yellow', in_progress: 'yellow',
    completed: 'green', cancelled: 'gray', disputed: 'red'
  }
  return <span className={`badge ${map[s] || 'gray'}`}>{s}</span>
}

export default function Jobs() {
  const [jobs, setJobs] = useState([])
  const [status, setStatus] = useState('')

  useEffect(() => {
    let isActive = true
    const fetchJobs = async () => {
      const { data } = await api.get('/admin/jobs', { params: { status: status || undefined, limit: 50 } })
      if (!isActive) return
      setJobs(data.jobs)
    }
    fetchJobs()
    const id = setInterval(fetchJobs, 5000)
    return () => {
      isActive = false
      clearInterval(id)
    }
  }, [status])

  return (
    <div>
      <div className="row" style={{ marginBottom: 16 }}>
        <select className="input" value={status} onChange={(e) => setStatus(e.target.value)}>
          <option value="">All statuses</option>
          {['open', 'confirmed', 'reached', 'in_progress', 'completed', 'cancelled', 'disputed'].map((s) =>
            <option key={s} value={s}>{s}</option>
          )}
        </select>
      </div>
      <div className="card" style={{ padding: 0 }}>
        <table>
          <thead>
            <tr>
              <th>Title</th>
              <th>Job Giver</th>
              <th>Job Taker</th>
              <th>Location</th>
              <th>Price</th>
              <th>Status</th>
              <th>Created</th>
            </tr>
          </thead>
          <tbody>
            {jobs.map((j) => {
              const parts = [j.location?.address, j.location?.city, j.location?.pincode]
                .filter((s) => s && String(s).trim())
              const locationText = parts.length ? parts.join(', ') : '—'
              return (
                <tr key={j._id}>
                  <td>{j.title}</td>
                  <td>{j.jobgiver?.name || j.jobgiver?.mobile}</td>
                  <td>{j.selectedJobtaker?.name || '—'}</td>
                  <td title={locationText} style={{ maxWidth: 220, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                    {locationText}
                  </td>
                  <td>₹{j.finalPrice || j.proposedBudget || '—'}</td>
                  <td>{statusBadge(j.status)}</td>
                  <td>{new Date(j.createdAt).toLocaleString()}</td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>
    </div>
  )
}
