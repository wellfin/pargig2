import { useCallback, useEffect, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { api } from '../api'
import Pagination from '../components/Pagination.jsx'

const PAGE_SIZE = 20

const STATUS_TONE = {
  initiated: 'gray',
  paid: 'blue',
  on_hold: 'yellow',
  released: 'green',
  refunded: 'red',
  failed: 'red',
}

const SETTLEMENT_TONE = {
  refunded: 'green',
  partially_refunded: 'yellow',
  refund_failed: 'red',
}

const MODE_LABELS = {
  upi: 'UPI',
  card: 'Card',
  netbanking: 'Net Banking',
  wallet: 'Wallet',
  cash: 'Cash',
  other: 'Other',
}

const label = (s) => String(s || '').replace(/_/g, ' ')

/**
 * "2 Nov, 5:05 pm" rather than "2/11/2026, 5:05:14 pm".
 *
 * The old format wrapped onto two lines in its column, which set the
 * height of every row in the table. The seconds were never useful and
 * the year is only useful when it is not this one — both are still
 * one hover away in the tooltip.
 */
const when = (iso) => {
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return '—'
  const sameYear = d.getFullYear() === new Date().getFullYear()
  const date = d.toLocaleDateString('en-IN', {
    day: 'numeric',
    month: 'short',
    ...(sameYear ? {} : { year: '2-digit' }),
  })
  const time = d
    .toLocaleTimeString('en-IN', { hour: 'numeric', minute: '2-digit' })
    .toLowerCase()
  return `${date}, ${time}`
}

const money = (n) =>
  `₹${Number(n || 0).toLocaleString('en-IN', { maximumFractionDigits: 0 })}`

/** A zero fee is not a number worth reading; it is the absence of one. */
const fee = (n) =>
  Number(n) > 0 ? money(n) : <span className="dim">—</span>

/**
 * Transaction ids are 20-odd characters of noise with about six that
 * matter. Showing the tail keeps the column narrow and still lets a
 * row be matched against a gateway dashboard; the whole id is in the
 * tooltip and survives a copy.
 */
const txn = (id) =>
  id ? (
    <span className="mono" title={id}>
      …{String(id).slice(-8)}
    </span>
  ) : (
    <span className="dim">—</span>
  )

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
      <section className="panel">
        <div className="panel-head">
          <h3>
            Payments{' '}
            <span style={{ color: 'var(--faint)', fontWeight: 500 }}>
              {total.toLocaleString('en-IN')}
            </span>
          </h3>
          <select
            className="input"
            value={status}
            onChange={(e) => filter(e.target.value)}
            aria-label="Filter by status"
          >
            <option value="">All statuses</option>
            {Object.keys(STATUS_TONE).map((s) => (
              <option key={s} value={s}>
                {label(s)}
              </option>
            ))}
          </select>
        </div>

        <div className="table-scroll">
          <table>
            <thead>
              <tr>
                <th>Job</th>
                <th>Giver</th>
                <th>Taker</th>
                <th className="num">Amount</th>
                <th className="num">Fee</th>
                {/* Mode and method were two columns saying one thing —
                    "Wallet" / "Pargig Wallet", "Cash" / "Cash on
                    Delivery". One cell, method as the sub-line. */}
                <th>Method</th>
                <th>Txn</th>
                <th>Status</th>
                {/* Settlement carried the refunded amount's context, so
                    the amount moved in under it. */}
                <th>Settlement</th>
                <th className="num">Date</th>
                <th aria-label="Actions"></th>
              </tr>
            </thead>
            <tbody>
              {payments.map((p) => {
                const mode = MODE_LABELS[p.mode] || (p.isCod ? 'Cash' : 'Other')
                const method = p.isCod ? 'Cash on Delivery' : p.method || ''
                const settlement = p.settlementStatus || 'pending'
                const lastRefund = p.refunds?.[p.refunds.length - 1]
                return (
                  <tr key={p._id}>
                    <td title={p.job?.title || ''}>
                      {p.job?._id ? (
                        <Link to={`/jobs/${p.job._id}`}>{p.job?.title || '—'}</Link>
                      ) : (
                        p.job?.title || <span className="dim">—</span>
                      )}
                    </td>
                    <td title={p.jobgiver?.name || p.jobgiver?.mobile || ''}>
                      {p.jobgiver?.name || p.jobgiver?.mobile || <span className="dim">—</span>}
                    </td>
                    <td title={p.jobtaker?.name || p.jobtaker?.mobile || ''}>
                      {p.jobtaker?.name || p.jobtaker?.mobile || <span className="dim">—</span>}
                    </td>
                    <td className="num" style={{ fontWeight: 600 }}>{money(p.amount)}</td>
                    <td className="num">{fee(p.platformFee)}</td>
                    <td>
                      {mode}
                      {method && <span className="sub" title={method}>{method}</span>}
                    </td>
                    <td>{txn(p.transactionId)}</td>
                    <td>
                      <span className={`badge ${STATUS_TONE[p.status] || 'gray'}`}>
                        {label(p.status)}
                      </span>
                    </td>
                    <td>
                      <span className={`badge ${SETTLEMENT_TONE[settlement] || 'gray'}`}>
                        {label(settlement)}
                      </span>
                      {p.refundedAmount > 0 && (
                        <span className="sub">
                          {money(p.refundedAmount)} back
                          {lastRefund ? ` · ${lastRefund.refundId || 'wallet'}` : ''}
                        </span>
                      )}
                    </td>
                    <td className="num" title={new Date(p.createdAt).toLocaleString()}>
                      {when(p.createdAt)}
                    </td>
                    <td>
                      {['paid', 'on_hold'].includes(p.status) && (
                        <button className="btn danger sm" onClick={() => refund(p._id)}>
                          Refund
                        </button>
                      )}
                    </td>
                  </tr>
                )
              })}
              {payments.length === 0 && (
                <tr>
                  <td colSpan={11} style={{ padding: '36px 14px', textAlign: 'center' }}>
                    <span className="dim">
                      {status ? `No ${label(status)} payments.` : 'No payments yet.'}
                    </span>
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>

        <Pagination page={page} limit={PAGE_SIZE} total={total} onPage={setPage} />
      </section>
    </div>
  )
}
