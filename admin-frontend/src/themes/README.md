# Admin panel themes

## Switching

Edit one line in [`src/theme.js`](../theme.js):

```js
export const THEME = 'midnight';
```

Then rebuild and upload:

```
cd admin-frontend && npm run build
```

Copy the contents of `dist/` into `backend/dist/` on the server and
hard-refresh. No `pm2 restart` — Express serves those files from disk
on every request.

| Value | What it looks like |
|---|---|
| `studio` | navy sidebar, coloured headline cards |
| `pargig` | the original: dark brown sidebar, bright orange accent |
| `slate` | white sidebar, indigo accent, cool neutrals |
| `midnight` | dark sidebar, light content, orange accent |
| `clay` | cream ground, terracotta, softer corners |
| `dusk` | full dark |

Every theme also sets the four `--kpi-N-bg` fills behind the headline
cards on the Dashboard. They are the one place the panel uses colour
to separate things rather than to mean something, so a theme is free
to make them quiet (`midnight`, `dusk`) or bright (`studio`).

`pargig` lives in `App.css`'s `:root` rather than in a file here, so it
needs no `data-theme` attribute — which also makes it what you get if
the value is ever misspelt. A typo shows the original panel, not an
unstyled one.

## How it works

`App.css` holds the structure and reads every colour, radius and font
from a custom property. Each file here overrides those properties
under its own `[data-theme='…']` selector. All four are bundled —
a few hundred bytes each — and only the selected one matches, which is
what lets the choice be one line instead of a changed import.

A theme overrides only the properties it names. Anything it leaves out
falls back to the `:root` value, so a half-written theme degrades to
the original rather than to black-on-black.

## The one rule that bites

Theme selectors must start with `:root`, as in
`:root[data-theme='slate']`, never a bare `[data-theme='slate']`.

A bare attribute selector has exactly the same specificity as the
`:root` block in `App.css`, and `App.css` is bundled last — so the
defaults would quietly win and the theme would do nothing at all. No
error, no warning, just a panel that ignores the setting. Prefixing
`:root` raises the specificity above the defaults and makes the file
order irrelevant.

## Writing another one

Copy `slate.css`, rename the selector, change the values, add it to the
table above and to the list in `theme.js`. The properties worth knowing
about, beyond the obvious `--bg` / `--text` / `--primary`:

- `--on-primary` — text that sits **on** a `--primary` fill. White for
  most themes; near-black when the accent is bright. Getting this wrong
  is what makes buttons unreadable.
- `--sidebar-*` — a separate set, because the sidebar is the one region
  that may be dark while the rest of the panel is light.
- `--sidebar-active-accent` — drawn as an inset shadow rather than a
  border, so the active nav item's text does not shift sideways.
- `--row-border` — table row rules. Usually lighter than `--border`.
- `color-scheme: dark` — set it on any dark theme, or native `<select>`
  menus and scrollbars render white.

## Contrast

Check any accent you pick against the text that sits on it. The brand
orange `#ff6b1a` with white text is about **2.6:1**, well under the 4.5:1
that body text needs — which is why `midnight.css` uses `#c2410c`
instead. It reads as the same colour and passes.
