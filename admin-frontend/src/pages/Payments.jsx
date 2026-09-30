import { useCallback, useEffect, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { api } from '../api'
import Pagination from '../components/Pagination.jsx'

const PAGE_SIZE = 20

const statusBadge = (s) => {
  const map = {
    initiated: 'gray', paid: 'blue', on_hold: 'yellow',
    released: 'green', refunded: 'red', failed: 'red'
  }
  return <span className={`badge ${map[s] || 'gray'}`}>{s}</span>
}

const MODE_LABELS = {
  upi: 'UPI',
  card: 'Card',
  netbanking: 'Net Banking',
  wallet: 'Wallet',
  cash: 'Cash',
  other: 'Other',
}

export default function Payments() {
  const [payments, setPayments] = useState([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  // The URL owns the filter, so a dashboard tile linking to
  // ?status=open lands already filtered, and any filtered view is
  // shareable and survives a refresh.
  const [params, setParams] = useSearchParams()
  const status = params.get('status') || ''

  const load = useCallback(async () => {
    const { data } = await api.get('/admin/payments', {
      params: { status: status || undefined, page, limit: PAGE_SIZE },
    })
    const nextTotal = data.total ?? 0
    // A refund moves a row between status filters, which can shrink the
    // list under the current page. Step back instead of showing nothing.
    const pages = Math.max(1, Math.ceil(nextTotal / PAGE_SIZE))
    if (page > pages) {
      setPage(pages)
      return
    }
    setPayments(data.payments)
    setTotal(nextTotal)
  }, [status, page])

  const filter = (value) => {
    setParams(value ? { status: value } : {}, { replace: true })
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

  const refund = async (id) => {
    const reason = prompt('Refund reason?')
    if (!reason) return
    await api.post(`/payments/${id}/refund`, { reason })
    load()
  }

  return (
    <div>
      <div className="row" style={{ marginBottom: 16 }}>
        <select className="input" value={status} onChange={(e) => filter(e.target.value)}>
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
              <th>Mode</th>
              <th>Method</th>
              <th>Transaction ID</th>
              <th>Status</th>
              <th>Settlement</th>
              <th>Refunded</th>
              <th>Date</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {payments.map((p) => (
              <tr key={p._id}>
                <td>{p.job?._id ? <Link to={`/jobs/${p.job._id}`}>{p.job?.title || '—'}</Link> : (p.job?.title || '—')}</td>
                <td>{p.jobgiver?.name || p.jobgiver?.mobile}</td>
                <td>{p.jobtaker?.name || p.jobtaker?.mobile}</td>
                <td>₹{p.amount}</td>
                <td>₹{p.platformFee}</td>
                <td>
                  <span className="badge gray">
                    {MODE_LABELS[p.mode] || (p.isCod ? 'Cash' : 'Other')}
                  </span>
                </td>
                <td>{p.isCod ? 'Cash on Delivery' : (p.method || '—')}</td>
                <td style={{ fontFamily: 'monospace', fontSize: 12 }}>{p.transactionId || '—'}</td>
                <td>{statusBadge(p.status)}</td>
                <td>
                  <span
                    className={`badge ${
                      p.settlementStatus === 'refunded' ? 'green'
                        : p.settlementStatus === 'partially_refunded' ? 'yellow'
                        : p.settlementStatus === 'refund_failed' ? 'red'
                        : 'gray'
                    }`}
                  >
                    {(p.settlementStatus || 'pending').replace(/_/g, ' ')}
                  </span>
                </td>
                <td>
                  {p.refundedAmount > 0 ? `₹${Number(p.refundedAmount).toFixed(0)}` : '—'}
                  {p.refunds?.length > 0 && (
                    <div style={{ fontSize: 11, color: 'var(--muted)', fontFamily: 'monospace' }}>
                      {p.refunds[p.refunds.length - 1].refundId || 'wallet'}
                    </div>
                  )}
                </td>
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
        <Pagination
          page={page}
          limit={PAGE_SIZE}
          total={total}
          onPage={setPage}
        />
      </div>
    </div>
  )
}
