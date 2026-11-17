import { useEffect, useState } from 'react'
import { api } from '../api'

const statusBadge = (s) => {
  const map = { open: 'red', under_review: 'yellow', resolved: 'green', rejected: 'gray' }
  return <span className={`badge ${map[s] || 'gray'}`}>{s}</span>
}

export default function Disputes() {
  const [disputes, setDisputes] = useState([])
  const [status, setStatus] = useState('')

  const load = async () => {
    const { data } = await api.get('/admin/disputes', { params: { status: status || undefined, limit: 50 } })
    setDisputes(data.disputes)
  }

  useEffect(() => {
    let isActive = true
    const fetchDisputes = async () => {
      const { data } = await api.get('/admin/disputes', { params: { status: status || undefined, limit: 50 } })
      if (!isActive) return
      setDisputes(data.disputes)
    }
    fetchDisputes()
    const id = setInterval(fetchDisputes, 5000)
    return () => {
      isActive = false
      clearInterval(id)
    }
  }, [status])

  const resolve = async (id) => {
    const outcome = prompt('Outcome (refund_giver | release_taker | split | no_action)?')
    if (!outcome) return
    const note = prompt('Resolution note?') || ''
    await api.put(`/admin/disputes/${id}/resolve`, { outcome, note, status: 'resolved' })
    load()
  }

  return (
    <div>
      <div className="row" style={{ marginBottom: 16 }}>
        <select className="input" value={status} onChange={(e) => setStatus(e.target.value)}>
          <option value="">All statuses</option>
          {['open', 'under_review', 'resolved', 'rejected'].map((s) =>
            <option key={s} value={s}>{s}</option>
          )}
        </select>
      </div>
      <div className="card" style={{ padding: 0 }}>
        <table>
          <thead>
            <tr>
              <th>Job</th>
              <th>Raised By</th>
              <th>Against</th>
              <th>Reason</th>
              <th>Status</th>
              <th>Outcome</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {disputes.map((d) => (
              <tr key={d._id}>
                <td>{d.job?.title || '—'}</td>
                <td>{d.raisedBy?.name || d.raisedBy?.mobile}</td>
                <td>{d.against?.name || d.against?.mobile}</td>
                <td>{d.reason}</td>
                <td>{statusBadge(d.status)}</td>
                <td>{d.resolution?.outcome || '—'}</td>
                <td>
                  {['open', 'under_review'].includes(d.status) && (
                    <button className="btn" onClick={() => resolve(d._id)}>Resolve</button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}
