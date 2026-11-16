import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { api } from '../api'
import Pagination from '../components/Pagination.jsx'
import { downloadCsv, fmtDate, fmtUser } from '../utils/exportCsv'

const PAGE_SIZE = 20
const EXPORT_LIMIT = 5000

const STATUSES = [
  'open', 'confirmed', 'reached', 'in_progress',
  'completed', 'cancelled', 'disputed',
]

const statusBadge = (s) => {
  const map = {
    open: 'blue', confirmed: 'yellow', reached: 'yellow', in_progress: 'yellow',
    completed: 'green', cancelled: 'gray', disputed: 'red'
  }
  return <span className={`badge ${map[s] || 'gray'}`}>{s}</span>
}

const money = (n) =>
  Number(n) > 0 ? `₹${Number(n).toLocaleString('en-IN')}` : '—'

/** The columns the CSV carries — more than the table shows, because a
 *  spreadsheet is where someone goes to ask a question the table does
 *  not answer. */
const CSV_COLUMNS = [
  { key: '_id', label: 'Job ID' },
  { key: 'title', label: 'Title' },
  { key: 'status', label: 'Status' },
  { key: 'category', label: 'Category' },
  { key: 'jobgiver', label: 'Job giver', format: fmtUser },
  { key: 'selectedJobtaker', label: 'Job taker', format: fmtUser },
  { key: 'location.address', label: 'Address' },
  { key: 'location.city', label: 'City' },
  { key: 'location.pincode', label: 'Pincode' },
  { key: 'value', label: 'Price (₹)' },
  { key: 'tip', label: 'Tip (₹)' },
  { key: 'isUrgent', label: 'Urgent' },
  { key: 'createdAt', label: 'Posted', format: fmtDate },
  { key: 'completedAt', label: 'Completed', format: fmtDate },
]

export default function Jobs() {
  const [jobs, setJobs] = useState([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [exporting, setExporting] = useState(false)
  const [more, setMore] = useState(false)

  // The URL owns every filter, so a dashboard tile linking to
  // ?status=open lands already filtered, and any filtered view is
  // shareable and survives a refresh.
  const [params, setParams] = useSearchParams()
  // Keyed on the query string, not on the params object. Whether that
  // object keeps its identity across renders is the router's business;
  // the string changes only when the URL does, so `query` — and the
  // loader that depends on it — is stable while the filters are.
  const paramsKey = params.toString()
  const query = useMemo(() => {
    const p = new URLSearchParams(paramsKey)
    const get = (k) => p.get(k) || ''
    return {
      q: get('q'),
      status: get('status'),
      city: get('city'),
      from: get('from'),
      to: get('to'),
      minPrice: get('minPrice'),
      maxPrice: get('maxPrice'),
      sort: get('sort') || 'newest',
    }
  }, [paramsKey])

  const active = Object.entries(query).filter(
    ([k, v]) => v && !(k === 'sort' && v === 'newest'),
  ).length

  const setFilter = useCallback(
    (patch) => {
      const next = { ...query, ...patch }
      const clean = Object.fromEntries(
        Object.entries(next).filter(([k, v]) => v && !(k === 'sort' && v === 'newest')),
      )
      setParams(clean, { replace: true })
      // The old page number means nothing against a different result
      // set, so every filter change restarts at the first page.
      setPage(1)
    },
    [query, setParams],
  )

  // The search box keeps its own value so typing stays smooth, and
  // writes to the URL once the operator pauses. Without this every
  // keystroke would be a request and a history entry.
  const [term, setTerm] = useState(query.q)
  const typed = useRef(false)
  useEffect(() => {
    if (!typed.current) return
    const id = setTimeout(() => {
      typed.current = false
      setFilter({ q: term })
    }, 350)
    return () => clearTimeout(id)
  }, [term, setFilter])
  useEffect(() => {
    if (!typed.current) setTerm(query.q)
  }, [query.q])

  // Only the filters that are actually set. Sending `minPrice=` and
  // friends makes the server read a blank as a value, and an empty
  // query string in the URL of every request is noise besides.
  const sent = useMemo(
    () => Object.fromEntries(Object.entries(query).filter(([, v]) => v !== '')),
    [query],
  )

  const load = useCallback(async () => {
    const { data } = await api.get('/admin/jobs', {
      params: { ...sent, page, limit: PAGE_SIZE },
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
  }, [sent, page])

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

  // Export what is on screen, not the whole collection: the filters the
  // operator set are the question they are asking, and a CSV that
  // ignores them answers a different one.
  const exportCsv = async () => {
    setExporting(true)
    try {
      const { data } = await api.get('/admin/jobs', {
        params: { ...sent, page: 1, limit: EXPORT_LIMIT },
      })
      downloadCsv('pargig-jobs', data.jobs || [], CSV_COLUMNS)
    } finally {
      setExporting(false)
    }
  }

  const sortBy = (key) => {
    const pairs = { createdAt: ['newest', 'oldest'], value: ['value_desc', 'value_asc'] }
    if (key === 'status') return setFilter({ sort: 'status' })
    const [a, b] = pairs[key]
    setFilter({ sort: query.sort === a ? b : a })
  }

  const arrow = (key) => {
    const s = query.sort
    if (key === 'createdAt') return s === 'oldest' ? ' ↑' : s === 'newest' ? ' ↓' : ''
    if (key === 'value') return s === 'value_asc' ? ' ↑' : s === 'value_desc' ? ' ↓' : ''
    if (key === 'status') return s === 'status' ? ' ↓' : ''
    return ''
  }

  return (
    <div>
      <div className="filter-row" style={{ marginBottom: 12 }}>
        <input
          className="input"
          style={{ minWidth: 260, flexGrow: 1, maxWidth: 420 }}
          placeholder="Search job ID, title, giver or taker…"
          value={term}
          onChange={(e) => {
            typed.current = true
            setTerm(e.target.value)
          }}
          aria-label="Search jobs"
        />
        <select
          className="input"
          style={{ width: 'auto' }}
          value={query.status}
          onChange={(e) => setFilter({ status: e.target.value })}
          aria-label="Status"
        >
          <option value="">All statuses</option>
          {STATUSES.map((s) => (
            <option key={s} value={s}>{s}</option>
          ))}
        </select>
        <button
          type="button"
          className={`seg${more ? ' on' : ''}`}
          onClick={() => setMore((m) => !m)}
          aria-expanded={more}
        >
          Filters{active ? ` (${active})` : ''}
        </button>
        <button type="button" className="seg" onClick={exportCsv} disabled={exporting}>
          {exporting ? 'Preparing…' : 'Export CSV'}
        </button>
        {active > 0 && (
          <button
            type="button"
            className="chart-toggle"
            onClick={() => {
              typed.current = false
              setTerm('')
              setParams({}, { replace: true })
              setPage(1)
            }}
          >
            Clear
          </button>
        )}
      </div>

      {more && (
        <div className="filter-row" style={{ marginBottom: 16 }}>
          <input
            className="input"
            style={{ width: 160 }}
            placeholder="City"
            value={query.city}
            onChange={(e) => setFilter({ city: e.target.value })}
            aria-label="City"
          />
          <span className="filter-dates">
            <input
              type="date"
              className="input"
              value={query.from}
              onChange={(e) => setFilter({ from: e.target.value })}
              aria-label="Posted from"
            />
            <span className="filter-sep">to</span>
            <input
              type="date"
              className="input"
              value={query.to}
              onChange={(e) => setFilter({ to: e.target.value })}
              aria-label="Posted to"
            />
          </span>
          <span className="filter-dates">
            <input
              type="number"
              className="input"
              style={{ width: 110 }}
              placeholder="Min ₹"
              value={query.minPrice}
              onChange={(e) => setFilter({ minPrice: e.target.value })}
              aria-label="Minimum price"
            />
            <span className="filter-sep">to</span>
            <input
              type="number"
              className="input"
              style={{ width: 110 }}
              placeholder="Max ₹"
              value={query.maxPrice}
              onChange={(e) => setFilter({ maxPrice: e.target.value })}
              aria-label="Maximum price"
            />
          </span>
        </div>
      )}

      <div className="card" style={{ padding: 0 }}>
        <div className="table-scroll">
          <table>
            <thead>
              <tr>
                <th>Title</th>
                <th>Job Giver</th>
                <th>Job Taker</th>
                <th>Location</th>
                <th className="num">
                  <button type="button" className="th-sort" onClick={() => sortBy('value')}>
                    Price{arrow('value')}
                  </button>
                </th>
                <th>
                  <button type="button" className="th-sort" onClick={() => sortBy('status')}>
                    Status{arrow('status')}
                  </button>
                </th>
                <th>
                  <button type="button" className="th-sort" onClick={() => sortBy('createdAt')}>
                    Created{arrow('createdAt')}
                  </button>
                </th>
              </tr>
            </thead>
            <tbody>
              {jobs.length === 0 && (
                <tr>
                  <td colSpan={7} className="muted" style={{ padding: 28, textAlign: 'center' }}>
                    No job matches these filters.
                  </td>
                </tr>
              )}
              {jobs.map((j) => {
                const parts = [j.location?.address, j.location?.city, j.location?.pincode]
                  .filter((s) => s && String(s).trim())
                const locationText = parts.length ? parts.join(', ') : '—'
                return (
                  <tr key={j._id}>
                    <td><Link to={`/jobs/${j._id}`}>{j.title}</Link></td>
                    <td>{j.jobgiver?.name || j.jobgiver?.mobile || '—'}</td>
                    <td>{j.selectedJobtaker?.name || '—'}</td>
                    <td title={locationText}>{locationText}</td>
                    <td className="num">{money(j.value)}</td>
                    <td>{statusBadge(j.status)}</td>
                    <td>{new Date(j.createdAt).toLocaleDateString('en-IN', {
                      day: 'numeric', month: 'short', year: 'numeric',
                    })}</td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
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
