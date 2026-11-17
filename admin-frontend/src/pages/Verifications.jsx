import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { api } from '../api'
import Pagination from '../components/Pagination.jsx'

const PAGE_SIZE = 20

/**
 * The identity queue.
 *
 * Approving a document is what puts a Verified badge on someone's
 * profile, so the reviewer has to SEE the file before deciding — the
 * document is shown here, full size on click, rather than being a row
 * with an Approve button and no evidence.
 *
 * Ordered oldest-wait-first by the server. That ordering is the whole
 * point of the page: a queue sorted newest-first starves the person who
 * has been waiting longest, and they are the one most likely to have
 * given up on us already.
 */

const DOC_LABELS = {
  aadhaar: 'Aadhaar card',
  pan: 'PAN card',
  license: 'Driving licence',
  certification: 'Skill certificate',
  other: 'Other document',
}

// Document URLs are used exactly as the server stored them, the way
// UserDetail already does: absolute on S3, and host-relative on disk
// storage, where the panel and the files share an origin.

const waitedFor = (iso) => {
  const then = new Date(iso)
  if (Number.isNaN(then.getTime())) return ''
  const days = Math.floor((Date.now() - then.getTime()) / 86400000)
  if (days >= 1) return `${days} day${days === 1 ? '' : 's'}`
  const hours = Math.floor((Date.now() - then.getTime()) / 3600000)
  if (hours >= 1) return `${hours} hour${hours === 1 ? '' : 's'}`
  return 'under an hour'
}

export default function Verifications() {
  const [data, setData] = useState(null)
  const [page, setPage] = useState(1)
  const [busy, setBusy] = useState('')
  const [error, setError] = useState('')
  const [zoom, setZoom] = useState(null)

  const load = useCallback(async () => {
    try {
      const { data } = await api.get('/admin/verifications', {
        params: { page, limit: PAGE_SIZE },
      })
      setData(data)
      setError('')
    } catch (e) {
      setError(e?.response?.data?.message || 'Could not load the queue')
    }
  }, [page])

  useEffect(() => {
    let cancelled = false
    const tick = () => {
      if (cancelled) return
      load()
    }
    tick()
    // Two admins can be working the queue at once. Re-reading keeps one
    // from spending time on a document the other has already decided.
    const id = setInterval(tick, 20000)
    return () => {
      cancelled = true
      clearInterval(id)
    }
  }, [load])

  // A rejection without a reason is the one thing the person on the
  // other end cannot act on, so it is required here rather than
  // optional — the app shows this text back to them verbatim.
  const decide = async (userId, docId, status) => {
    let remark = ''
    if (status === 'rejected') {
      remark = window.prompt(
        'Why is this being rejected? The person sees this text in the app.',
      )
      if (remark === null || remark.trim() === '') return
    }
    setBusy(docId)
    try {
      await api.post('/admin/users/document/verify', {
        userId,
        docId,
        status,
        remark: remark.trim(),
      })
      await load()
    } catch (e) {
      setError(e?.response?.data?.message || 'That did not go through')
    } finally {
      setBusy('')
    }
  }

  const users = data?.users || []
  const total = data?.total ?? 0

  return (
    <div>
      {error && <div className="panel panel-error">{error}</div>}

      <div className="card" style={{ padding: 0 }}>
        <div className="panel-head" style={{ padding: '16px 18px' }}>
          <h3>Waiting for a decision</h3>
          <span className="panel-note">
            {data ? `${total} ${total === 1 ? 'person' : 'people'}` : ''}
          </span>
        </div>

        {!data ? (
          <div className="muted" style={{ padding: 28 }}>Loading…</div>
        ) : users.length === 0 ? (
          <div
            className="muted"
            style={{ padding: 34, textAlign: 'center' }}
          >
            Nothing waiting. Every document sent in has been decided.
          </div>
        ) : (
          <div className="table-scroll">
            <table>
              <thead>
                <tr>
                  <th>Person</th>
                  <th>Document</th>
                  <th>Waiting</th>
                  <th style={{ width: 210 }}>Decision</th>
                </tr>
              </thead>
              <tbody>
                {users.map((u) =>
                  (u.documents || []).map((d, i) => (
                    <tr key={d._id}>
                      {i === 0 && (
                        <td rowSpan={u.documents.length}>
                          <Link to={`/users/${u._id}`}>
                            {u.name || '(no name)'}
                          </Link>
                          <div className="muted" style={{ fontSize: 12 }}>
                            {u.mobile}
                          </div>
                          {u.isBlocked && (
                            <span className="badge red">blocked</span>
                          )}
                        </td>
                      )}
                      <td>
                        <button
                          type="button"
                          className="th-sort"
                          onClick={() =>
                            setZoom({
                              url: d.url,
                              label: DOC_LABELS[d.type] || d.type,
                              who: u.name || u.mobile,
                            })
                          }
                          style={{ display: 'flex', gap: 10 }}
                        >
                          <img
                            src={d.url}
                            alt=""
                            style={{
                              width: 52,
                              height: 38,
                              objectFit: 'cover',
                              borderRadius: 4,
                              border: '1px solid var(--line, #e5e7eb)',
                            }}
                          />
                          <span>{DOC_LABELS[d.type] || d.type}</span>
                        </button>
                      </td>
                      <td>{waitedFor(d.uploadedAt)}</td>
                      <td>
                        <div style={{ display: 'flex', gap: 8 }}>
                          <button
                            type="button"
                            className="seg"
                            disabled={busy === d._id}
                            onClick={() => decide(u._id, d._id, 'approved')}
                          >
                            Approve
                          </button>
                          <button
                            type="button"
                            className="seg"
                            disabled={busy === d._id}
                            onClick={() => decide(u._id, d._id, 'rejected')}
                          >
                            Reject
                          </button>
                        </div>
                      </td>
                    </tr>
                  )),
                )}
              </tbody>
            </table>
          </div>
        )}

        <Pagination
          page={page}
          limit={PAGE_SIZE}
          total={total}
          onPage={setPage}
        />
      </div>

      <p className="muted" style={{ marginTop: 12, fontSize: 13 }}>
        Approving any one document marks the person verified and puts the
        badge on their profile. Rejecting shows your reason to them in the
        app, and they can send another.
      </p>

      {zoom && <Lightbox {...zoom} onClose={() => setZoom(null)} />}
    </div>
  )
}

/** The document, big enough to actually read. */
function Lightbox({ url, label, who, onClose }) {
  useEffect(() => {
    const onKey = (e) => e.key === 'Escape' && onClose()
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])

  return (
    <div
      role="presentation"
      onClick={onClose}
      style={{
        position: 'fixed',
        inset: 0,
        background: 'rgba(15,20,30,.72)',
        display: 'grid',
        placeItems: 'center',
        padding: 24,
        zIndex: 50,
      }}
    >
      <div
        role="presentation"
        onClick={(e) => e.stopPropagation()}
        style={{ maxWidth: 'min(900px, 92vw)', textAlign: 'center' }}
      >
        <img
          src={url}
          alt={`${label} sent by ${who}`}
          style={{
            maxWidth: '100%',
            maxHeight: '78vh',
            borderRadius: 10,
            background: '#fff',
          }}
        />
        <div style={{ color: '#fff', marginTop: 12, fontSize: 14 }}>
          {label} — {who}
          {'  '}
          <a
            href={url}
            target="_blank"
            rel="noreferrer"
            style={{ color: '#9ec3ff', marginLeft: 10 }}
          >
            open original
          </a>
        </div>
        <button
          type="button"
          className="seg"
          onClick={onClose}
          style={{ marginTop: 14 }}
        >
          Close
        </button>
      </div>
    </div>
  )
}
