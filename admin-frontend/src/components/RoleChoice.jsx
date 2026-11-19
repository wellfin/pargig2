/**
 * Pick a role, with all the options on screen.
 *
 * Shared by the New admin form and the edit dialog, so there is one
 * answer to "what does finance mean" rather than two that drift.
 *
 * Not a dropdown: there are three options and the whole decision is
 * what each one grants, which a control that shows one value and
 * hides the rest cannot say. Not a text box either — there are
 * exactly three valid strings and the server rejects anything else,
 * so typing is a way to produce an error, not a way to make a choice.
 */
export default function RoleChoice({
  roles,
  hints,
  value,
  onChange,
  name,
  label = 'Role',
  disabled = false,
}) {
  return (
    <fieldset className="choices" disabled={disabled}>
      <legend className="field-label">{label}</legend>
      {roles.map((r) => (
        <label key={r} className={`choice${value === r ? ' is-on' : ''}`}>
          <input
            type="radio"
            name={name}
            value={r}
            checked={value === r}
            onChange={() => onChange(r)}
          />
          <span className="choice-body">
            <span className="choice-name">{r}</span>
            <span className="choice-hint">{hints[r]}</span>
          </span>
        </label>
      ))}
    </fieldset>
  )
}
