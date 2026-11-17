import { useCallback, useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { api } from '../api'

/**
 * The support desk.
 *
 * One shared inbox, not a per-admin one: whoever is in the panel can
 * answer. That is a deliberate choice for a team this size — assigning
 * threads to people only helps once there are enough people for a
 * thread to be assigned to the wrong one.
 *
 * Ordered by most recent activity. The verification queue next door is
 * sorted the opposite way, oldest-wait-first, and the difference is the
 * point: a document can be judged whenever, but someone typing right
 * now is still holding their phone. Threads nobody has answered are
 * counted in the sidebar badge so newest-first cannot bury them.
 *
 * Opening a thread marks it read for the whole desk — which is honest
 * only because nothing here opens a thread on its own.
 */

const LIST_POLL = 15000
const THREAD_POLL = 8000

const whenLabel = (iso) => {
  const then = new Date(iso)
  if (Number.isNaN(then.getTime())) return ''
  const mins = Math.floor((Date.now() - then.getTime()) / 60000)
  if (mins < 1) return 'just now'
  if (mins < 60) return `${mins}m ago`
  const hours = Math.floor(mins / 60)
  if (hours < 24) return `${hours}h ago`
  const days = Math.floor(hours / 24)
  if (days < 7) return `${days}d ago`
  return then.toLocaleDateString()
}

const clock = (iso) => {
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return ''
  return d.toLocaleString([], {
    day: 'numeric',
    month: 'short',
    hour: 'numeric',
    minute: '2-digit',
  })
}

export default function SupportChat() {
  const [chats, setChats] = useState(null)
  const [onlyUnread, setOnlyUnread] = useState(false)
  const [openId, setOpenId] = useState(null)
  const [thread, setThread] = useState(null)
  const [draft, setDraft] = useState('')
  const [sending, setSending] = useState(false)
  const [error, setError] = useState('')
  const endRef = useRef(null)

  const loadList = useCallback(async () => {
    try {
      const { data } = await api.get('/admin/support/chats', {
        params: onlyUnread ? { unread: '1' } : {},
      })
      setChats(data?.chats || [])
      setError('')
    } catch (e) {
      setError(e?.response?.data?.message || 'Could not load conversations')
    }
  }, [onlyUnread])

  useEffect(() => {
    let cancelled = false
    const tick = () => {
      if (cancelled) return
      loadList()
    }
    tick()
    const id = setInterval(tick, LIST_POLL)
    return () => {
      cancelled = true
      clearInterval(id)
    }
  }, [loadList])

  const loadThread = useCallback(async (roomId) => {
    if (!roomId) return
    try {
      const { data } = await api.get(`/admin/support/chats/${roomId}`)
      setThread(data)
    } catch (e) {
      setError(e?.response?.data?.message || 'Could not open that conversation')
    }
  }, [])

  useEffect(() => {
    if (!openId) return undefined
    let cancelled = false
    const tick = () => {
      if (cancelled) return
      loadThread(openId)
    }
    tick()
    const id = setInterval(tick, THREAD_POLL)
    return () => {
      cancelled = true
      clearInterval(id)
    }
  }, [openId, loadThread])

  // Keep the newest message in view as replies arrive.
  useEffect(() => {
    endRef.current?.scrollIntoView({ block: 'end' })
  }, [thread])

  const pick = (roomId) => {
    setOpenId(roomId)
    setThread(null)
    setDraft('')
    // The row's unread pip is cleared by the server the moment the
    // thread is fetched; re-read the list shortly after so the sidebar
    // badge and this list agree.
    setTimeout(loadList, 600)
  }

  const send = async (e) => {
    e.preventDefault()
    const body = draft.trim()
    if (!body || sending || !openId) return
    setSending(true)
    try {
      await api.post(`/admin/support/chats/${openId}/messages`, { body })
      setDraft('')
      await loadThread(openId)
      loadList()
    } catch (err) {
      setError(err?.response?.data?.message || 'That reply did not send')
    } finally {
      setSending(false)
    }
  }

  const rows = chats || []
  const user = thread?.participants?.[0]

  return (
    <div>
      {error && <div className="panel panel-error">{error}</div>}

      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'minmax(260px, 340px) 1fr',
          gap: 16,
          alignItems: 'start',
        }}
      >
        {/* -------------------------------------------- conversations */}
        <div className="card" style={{ padding: 0 }}>
          <div className="panel-head" style={{ padding: '14px 16px' }}>
            <h3>Conversations</h3>
            <button
              type="button"
              className="seg"
              onClick={() => setOnlyUnread((v) => !v)}
            >
              {onlyUnread ? 'Showing unanswered' : 'All'}
            </button>
          </div>

          {!chats ? (
            <div className="muted" style={{ padding: 24 }}>Loading…</div>
          ) : rows.length === 0 ? (
            <div className="muted" style={{ padding: 28, fontSize: 13 }}>
              {onlyUnread
                ? 'Nothing unanswered.'
                : 'Nobody has started a chat yet.'}
            </div>
          ) : (
            <div style={{ maxHeight: '68vh', overflowY: 'auto' }}>
              {rows.map((c) => (
                <button
                  key={c._id}
                  type="button"
                  onClick={() => pick(c._id)}
                  style={{
                    display: 'block',
                    width: '100%',
                    textAlign: 'left',
                    padding: '12px 16px',
                    border: 0,
                    borderBottom: '1px solid var(--line, #e5e7eb)',
                    borderLeft:
                      c._id === openId
                        ? '3px solid #ff6b1a'
                        : '3px solid transparent',
                    background:
                      c._id === openId ? 'rgba(255,107,26,.07)' : 'transparent',
                    cursor: 'pointer',
                    font: 'inherit',
                    color: 'inherit',
                  }}
                >
                  <div
                    style={{
                      display: 'flex',
                      justifyContent: 'space-between',
                      gap: 8,
                    }}
                  >
                    <strong style={{ fontSize: 13.5 }}>
                      {c.user?.name || c.user?.mobile || '(unknown user)'}
                    </strong>
                    <span className="muted" style={{ fontSize: 11 }}>
                      {whenLabel(c.lastMessageAt)}
                    </span>
                  </div>
                  <div
                    className="muted truncate"
                    style={{ fontSize: 12.5, marginTop: 3 }}
                  >
                    {c.lastFromUser ? '' : 'You: '}
                    {c.lastMessage || 'No messages yet'}
                  </div>
                  {c.unread > 0 && (
                    <span
                      className="badge"
                      style={{ marginTop: 6, display: 'inline-block' }}
                    >
                      {c.unread} new
                    </span>
                  )}
                </button>
              ))}
            </div>
          )}
        </div>

        {/* --------------------------------------------------- thread */}
        <div className="card" style={{ padding: 0, minHeight: 420 }}>
          {!openId ? (
            <div
              className="muted"
              style={{ padding: 60, textAlign: 'center', fontSize: 13.5 }}
            >
              Pick a conversation to read it and reply.
            </div>
          ) : !thread ? (
            <div className="muted" style={{ padding: 40 }}>Loading…</div>
          ) : (
            <>
              <div className="panel-head" style={{ padding: '14px 18px' }}>
                <div>
                  <h3 style={{ margin: 0 }}>
                    {user?._id ? (
                      <Link to={`/users/${user._id}`}>
                        {user.name || '(no name)'}
                      </Link>
                    ) : (
                      '(unknown user)'
                    )}
                  </h3>
                  <div className="muted" style={{ fontSize: 12 }}>
                    {user?.mobile}
                    {user?.isBlocked ? ' · blocked' : ''}
                  </div>
                </div>
              </div>

              <div
                style={{
                  padding: '16px 18px',
                  maxHeight: '52vh',
                  overflowY: 'auto',
                }}
              >
                {(thread.messages || []).length === 0 && (
                  <div className="muted" style={{ fontSize: 13 }}>
                    They opened the chat but have not written yet.
                  </div>
                )}
                {(thread.messages || []).map((m) => {
                  const fromDesk = !!m.senderAdmin
                  return (
                    <div
                      key={m._id}
                      style={{
                        display: 'flex',
                        justifyContent: fromDesk ? 'flex-end' : 'flex-start',
                        marginBottom: 10,
                      }}
                    >
                      <div
                        style={{
                          maxWidth: '72%',
                          padding: '9px 13px',
                          borderRadius: 12,
                          background: fromDesk
                            ? 'rgba(255,107,26,.12)'
                            : 'var(--surface-2, #f3f4f6)',
                          border: '1px solid var(--line, #e5e7eb)',
                        }}
                      >
                        {fromDesk && (
                          <div
                            style={{
                              fontSize: 11,
                              fontWeight: 700,
                              marginBottom: 3,
                              color: '#c2570c',
                            }}
                          >
                            {m.senderAdmin?.name || 'Support'}
                          </div>
                        )}
                        <div style={{ fontSize: 13.5, whiteSpace: 'pre-wrap' }}>
                          {m.body}
                        </div>
                        <div
                          className="muted"
                          style={{ fontSize: 10.5, marginTop: 4 }}
                        >
                          {clock(m.createdAt)}
                        </div>
                      </div>
                    </div>
                  )
                })}
                <div ref={endRef} />
              </div>

              <form
                onSubmit={send}
                style={{
                  display: 'flex',
                  gap: 8,
                  padding: '12px 18px 16px',
                  borderTop: '1px solid var(--line, #e5e7eb)',
                }}
              >
                <input
                  className="input"
                  style={{ flex: 1 }}
                  placeholder="Write a reply…"
                  value={draft}
                  maxLength={2000}
                  onChange={(e) => setDraft(e.target.value)}
                />
                <button
                  type="submit"
                  className="btn"
                  disabled={sending || !draft.trim()}
                >
                  {sending ? 'Sending…' : 'Send'}
                </button>
              </form>
            </>
          )}
        </div>
      </div>

      <p className="muted" style={{ marginTop: 12, fontSize: 13 }}>
        Replies go straight to the person&apos;s phone as a notification.
        A complaint about a specific job belongs in Disputes, where the
        job, the other party and the money are all attached to it.
      </p>
    </div>
  )
}
