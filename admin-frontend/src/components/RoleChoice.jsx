/**
 * Pick a role, with all the options on screen.
 *
 * Shared by the New admin form and the edit dialog, so there is one
 * answer to "what does finance mean" rather than two that drift. The
 * label and that one-line answer come from the server, because roles
 * are editable now and a copy written into the panel would be stale
 * the first time somebody renamed one.
 *
 * Not a dropdown: the whole decision is what each role grants, which
 * a control that shows one value and hides the rest cannot say. Not a
 * text box either — a role is a key the server knows about, and
 * typing one is a way to produce an error rather than a way to make a
 * choice.
 */
export default function RoleChoice({
  roles,
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
        <label key={r.key} className={`choice${value === r.key ? ' is-on' : ''}`}>
          <input
            type="radio"
            name={name}
            value={r.key}
            checked={value === r.key}
            onChange={() => onChange(r.key)}
          />
          <span className="choice-body">
            <span className="choice-name">{r.label}</span>
            <span className="choice-hint">{r.hint}</span>
          </span>
        </label>
      ))}
    </fieldset>
  )
}
