import { useCallback, useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { api } from '../api'
import { IconChat } from '../icons.jsx'

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

  const initial = (c) =>
    ((c.user?.name || c.user?.mobile || '?').trim()[0] || '?').toUpperCase()

  return (
    <div>
      {error && <div className="panel panel-error">{error}</div>}

      <div className="chat">
        {/* -------------------------------------------- conversations */}
        <div className="card">
          <div className="panel-head" style={{ padding: '13px 14px' }}>
            <h3>
              Conversations{' '}
              {rows.length > 0 && (
                <span style={{ color: 'var(--faint)', fontWeight: 500 }}>
                  {rows.length}
                </span>
              )}
            </h3>
            {/* Two states, both named. A lone button reading "All" does
                not say what the other state is, so nobody presses it. */}
            <div className="tabs" style={{ margin: 0 }}>
              <button
                type="button"
                className={`tab${onlyUnread ? '' : ' is-on'}`}
                onClick={() => setOnlyUnread(false)}
              >
                All
              </button>
              <button
                type="button"
                className={`tab${onlyUnread ? ' is-on' : ''}`}
                onClick={() => setOnlyUnread(true)}
              >
                Unanswered
              </button>
            </div>
          </div>

          {!chats ? (
            <div className="muted" style={{ padding: 24 }}>Loading…</div>
          ) : rows.length === 0 ? (
            <div className="chat-empty">
              <span className="chat-empty-icon" aria-hidden="true">
                <IconChat size={24} />
              </span>
              <h4>{onlyUnread ? 'Nothing unanswered' : 'No chats yet'}</h4>
              <p>
                {onlyUnread
                  ? 'Every conversation has been replied to.'
                  : 'When somebody opens a chat from the Help Center, it '
                    + 'arrives here.'}
              </p>
            </div>
          ) : (
            <div className="chat-scroll">
              {rows.map((c) => (
                <button
                  key={c._id}
                  type="button"
                  onClick={() => pick(c._id)}
                  className={
                    'chat-row'
                    + (c._id === openId ? ' is-on' : '')
                    + (c.unread > 0 ? ' is-new' : '')
                  }
                >
                  <span className="avatar" aria-hidden="true">{initial(c)}</span>
                  <span className="chat-row-main">
                    <span className="chat-row-top">
                      <span className="chat-row-name">
                        {c.user?.name || c.user?.mobile || '(unknown user)'}
                      </span>
                      <span className="chat-row-when">
                        {whenLabel(c.lastMessageAt)}
                      </span>
                    </span>
                    {/* "You:" only when there is something of ours to
                        prefix. It used to read "You: No messages yet",
                        which credits us with the silence. */}
                    <span className="chat-row-last">
                      {c.lastMessage
                        ? `${c.lastFromUser ? '' : 'You: '}${c.lastMessage}`
                        : 'No messages yet'}
                    </span>
                  </span>
                  {c.unread > 0 && (
                    <span className="chat-count" title={`${c.unread} unanswered`}>
                      {c.unread}
                    </span>
                  )}
                </button>
              ))}
            </div>
          )}
        </div>

        {/* --------------------------------------------------- thread */}
        <div className="card">
          {!openId ? (
            <div className="chat-empty">
              <span className="chat-empty-icon" aria-hidden="true">
                <IconChat size={24} />
              </span>
              <h4>Pick a conversation</h4>
              <p>
                Replies go straight to the person’s phone as a
                notification. A complaint about a specific job belongs in
                Disputes instead, where the job, the other party and the
                money are all attached to it.
              </p>
            </div>
          ) : !thread ? (
            <div className="muted" style={{ padding: 40 }}>Loading…</div>
          ) : (
            <>
              <div className="panel-head" style={{ padding: '13px 18px' }}>
                <div className="who">
                  <span className="avatar" aria-hidden="true">
                    {((user?.name || user?.mobile || '?').trim()[0] || '?')
                      .toUpperCase()}
                  </span>
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
                    <span className="sub mono">{user?.mobile || '—'}</span>
                  </div>
                </div>
                {user?.isBlocked && <span className="badge red">blocked</span>}
              </div>

              <div className="chat-scroll" style={{ padding: '16px 18px' }}>
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
                      className={`bubble-row${fromDesk ? ' from-desk' : ''}`}
                    >
                      <div className={`bubble${fromDesk ? ' from-desk' : ''}`}>
                        {fromDesk && (
                          <div className="bubble-who">
                            {m.senderAdmin?.name || 'Support'}
                          </div>
                        )}
                        <div className="bubble-body">{m.body}</div>
                        <div className="bubble-time">{clock(m.createdAt)}</div>
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
                  padding: '12px 18px',
                  borderTop: '1px solid var(--border)',
                  background: 'var(--panel-sunk)',
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
    </div>
  )
}
