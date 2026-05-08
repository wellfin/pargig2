import { useEffect, useState } from 'react'
import { api } from '../api'

const statusBadge = (s) => {
  const map = {
    initiated: 'gray', paid: 'blue', on_hold: 'yellow',
    released: 'green', refunded: 'red', failed: 'red'
  }
  return <span className={`badge ${map[s] || 'gray'}`}>{s}</span>
}

export default function Payments() {
  const [payments, setPayments] = useState([])
  const [status, setStatus] = useState('')

  const load = async () => {
    const { data } = await api.get('/admin/payments', { params: { status: status || undefined, limit: 50 } })
    setPayments(data.payments)
  }

  useEffect(() => { load() }, [status])

  const refund = async (id) => {
    const reason = prompt('Refund reason?')
    if (!reason) return
    await api.post(`/payments/${id}/refund`, { reason })
    load()
  }

  return (
    <div>
      <div className="row" style={{ marginBottom: 16 }}>
        <select className="input" value={status} onChange={(e) => setStatus(e.target.value)}>
          <option value="">All statuses</option>
          {['initiated', 'paid', 'on_hold', 'released', 'refunded', 'failed'].map((s) =>
            <option key={s} value={s}>{s}</option>
          )}
        </select>
      </div>
      <div className="card" style={{ padding: 0 }}>
        <table>
          <thead>
            <tr>
              <th>Job</th>
              <th>Giver</th>
              <th>Taker</th>
              <th>Amount</th>
              <th>Fee</th>
              <th>Status</th>
              <th>Date</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {payments.map((p) => (
              <tr key={p._id}>
                <td>{p.job?.title || '—'}</td>
                <td>{p.jobgiver?.name || p.jobgiver?.mobile}</td>
                <td>{p.jobtaker?.name || p.jobtaker?.mobile}</td>
                <td>₹{p.amount}</td>
                <td>₹{p.platformFee}</td>
                <td>{statusBadge(p.status)}</td>
                <td>{new Date(p.createdAt).toLocaleString()}</td>
                <td>
                  {['paid', 'on_hold'].includes(p.status) && (
                    <button className="btn danger" onClick={() => refund(p._id)}>Refund</button>
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
