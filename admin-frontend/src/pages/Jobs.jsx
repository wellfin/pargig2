import { useCallback, useEffect, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { api } from '../api'
import Pagination from '../components/Pagination.jsx'

const PAGE_SIZE = 20

const statusBadge = (s) => {
  const map = {
    open: 'blue', confirmed: 'yellow', reached: 'yellow', in_progress: 'yellow',
    completed: 'green', cancelled: 'gray', disputed: 'red'
  }
  return <span className={`badge ${map[s] || 'gray'}`}>{s}</span>
}

export default function Jobs() {
  const [jobs, setJobs] = useState([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  // The URL owns the filter, so a dashboard tile linking to
  // ?status=open lands already filtered, and any filtered view is
  // shareable and survives a refresh.
  const [params, setParams] = useSearchParams()
  const status = params.get('status') || ''

  const load = useCallback(async () => {
    const { data } = await api.get('/admin/jobs', {
      params: { status: status || undefined, page, limit: PAGE_SIZE },
    })
    const nextTotal = data.total ?? 0
    // The list can shrink under the cursor as jobs change status; step
    // back rather than showing an empty table under a pager.
    const pages = Math.max(1, Math.ceil(nextTotal / PAGE_SIZE))
    if (page > pages) {
      setPage(pages)
      return
    }
    setJobs(data.jobs)
    setTotal(nextTotal)
  }, [status, page])

  // Changing the filter restarts at page 1 — the old page number means
  // nothing against a different result set.
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

  return (
    <div>
      <div className="row" style={{ marginBottom: 16 }}>
        <select className="input" value={status} onChange={(e) => filter(e.target.value)}>
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
                  <td><Link to={`/jobs/${j._id}`}>{j.title}</Link></td>
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
