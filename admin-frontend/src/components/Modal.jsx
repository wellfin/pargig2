import { useEffect } from 'react'
import { IconClose } from '../icons.jsx'

/**
 * A dialog with a pinned header and footer.
 *
 * Only the body scrolls. A dialog whose Close button scrolls away
 * with the content makes the way out something you have to go looking
 * for, which is how people learn not to open things.
 *
 * Escape closes, and so does the backdrop. Both are expected, and a
 * dialog that traps you until you find the right button is the same
 * mistake in a different shape.
 */
export default function Modal({
  title,
  subtitle,
  titleId = 'modal-title',
  head,
  footer,
  onClose,
  width,
  children,
}) {
  useEffect(() => {
    const onKey = (e) => {
      if (e.key === 'Escape') onClose()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div
        className="modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        style={width ? { width: `min(${width}px, 100%)` } : undefined}
        onClick={(e) => e.stopPropagation()}
      >
        <header className="modal-head">
          <div className="modal-title">
            <h3 id={titleId}>{title}</h3>
            {subtitle && <span className="sub">{subtitle}</span>}
          </div>
          {head}
          <button
            type="button"
            className="modal-x"
            onClick={onClose}
            aria-label="Close"
            title="Close (Esc)"
          >
            <IconClose size={18} />
          </button>
        </header>

        <div className="modal-body">{children}</div>

        {footer && <footer className="modal-foot">{footer}</footer>}
      </div>
    </div>
  )
}
