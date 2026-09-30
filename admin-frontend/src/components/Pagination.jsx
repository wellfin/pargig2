/**
 * Pager for the admin list views.
 *
 * The backend already paginates (`page` + `limit`, returning `total`) —
 * these screens were just asking for one big page and rendering all of it,
 * which turns into thousands of rows once real data lands.
 *
 * Renders nothing when everything fits on one page, so small deployments
 * don't get a control that can't do anything.
 */
export default function Pagination({ page, limit, total, onPage }) {
  const pages = Math.max(1, Math.ceil(total / limit))
  if (total === 0 || pages <= 1) return null

  const from = (page - 1) * limit + 1
  // The last page is usually short — don't claim rows that aren't there.
  const to = Math.min(page * limit, total)

  // A window of at most 5 numbers around the current page, clamped to the
  // ends. Without this, 400 pages of buttons overflow the card.
  const windowSize = 5
  let start = Math.max(1, page - Math.floor(windowSize / 2))
  const end = Math.min(pages, start + windowSize - 1)
  start = Math.max(1, end - windowSize + 1)
  const numbers = []
  for (let p = start; p <= end; p++) numbers.push(p)

  const go = (p) => {
    const next = Math.min(pages, Math.max(1, p))
    if (next !== page) onPage(next)
  }

  const numberStyle = (active) => ({
    minWidth: 34,
    padding: '7px 10px',
    borderRadius: 8,
    fontSize: 13,
    cursor: active ? 'default' : 'pointer',
    border: `1px solid ${active ? 'var(--primary)' : 'var(--border)'}`,
    background: active ? 'var(--primary)' : '#fff',
    color: active ? '#fff' : 'var(--text)',
    fontWeight: active ? 700 : 500,
  })

  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        gap: 12,
        flexWrap: 'wrap',
        padding: '14px 16px',
        borderTop: '1px solid var(--border)',
      }}
    >
      <span style={{ color: 'var(--muted)', fontSize: 13 }}>
        Showing <strong>{from}</strong>–<strong>{to}</strong> of{' '}
        <strong>{total}</strong>
      </span>

      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
        <button
          className="btn secondary"
          style={{ padding: '7px 12px', fontSize: 13 }}
          onClick={() => go(page - 1)}
          disabled={page <= 1}
        >
          Prev
        </button>

        {/* Jump to the first page when the window has scrolled away. */}
        {start > 1 && (
          <>
            <button style={numberStyle(false)} onClick={() => go(1)}>
              1
            </button>
            {start > 2 && (
              <span style={{ color: 'var(--muted)', fontSize: 13 }}>…</span>
            )}
          </>
        )}

        {numbers.map((p) => (
          <button
            key={p}
            style={numberStyle(p === page)}
            onClick={() => go(p)}
            aria-current={p === page ? 'page' : undefined}
          >
            {p}
          </button>
        ))}

        {end < pages && (
          <>
            {end < pages - 1 && (
              <span style={{ color: 'var(--muted)', fontSize: 13 }}>…</span>
            )}
            <button style={numberStyle(false)} onClick={() => go(pages)}>
              {pages}
            </button>
          </>
        )}

        <button
          className="btn secondary"
          style={{ padding: '7px 12px', fontSize: 13 }}
          onClick={() => go(page + 1)}
          disabled={page >= pages}
        >
          Next
        </button>
      </div>
    </div>
  )
}
