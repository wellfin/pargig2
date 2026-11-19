import { useState } from 'react'
import { IconEye, IconEyeOff } from '../icons.jsx'

/**
 * A password field with a show/hide toggle.
 *
 * Hidden by default and revealed only on purpose. The reason to offer
 * it at all is that a password field gives no feedback except
 * failure: you cannot see a caps-lock slip, a stray space, or the
 * wrong character on a phone keyboard until the whole attempt is
 * rejected — and on a login screen a few of those in a row end with
 * someone resetting a password that was never wrong.
 *
 * The toggle is a type="button". Inside a form, a button without that
 * submits it, so the eye would sign you in rather than show you what
 * you typed.
 *
 * autoComplete stays on the input and is passed through, because
 * password managers key off it. Swapping the input's `type` does not
 * disturb them.
 */
export default function PasswordInput({ className = 'input', ...props }) {
  const [shown, setShown] = useState(false)

  return (
    <div className="pw-field">
      <input
        {...props}
        className={className}
        type={shown ? 'text' : 'password'}
      />
      <button
        type="button"
        className="pw-eye"
        onClick={() => setShown((v) => !v)}
        // The label says what pressing it DOES, not what the state
        // is — "Password shown" read out on a button is a riddle.
        aria-label={shown ? 'Hide the password' : 'Show the password'}
        title={shown ? 'Hide' : 'Show'}
        // Skipped by Tab: it sits between the password field and the
        // submit button, and a keyboard user heading for Sign in
        // should not land on it. Still reachable by click or by
        // screen reader.
        tabIndex={-1}
      >
        {shown ? <IconEyeOff size={16} /> : <IconEye size={16} />}
      </button>
    </div>
  )
}
