/**
 * CSV export for the admin reports.
 *
 * CSV rather than a real .xlsx on purpose: Excel opens it natively, and a
 * true xlsx writer (SheetJS) is ~1 MB of JavaScript shipped to every admin
 * on every page load, to produce a file that opens identically. If cell
 * formatting or multiple sheets are ever needed, that trade flips.
 */

/** Escapes one cell. */
function cell(value) {
  if (value === null || value === undefined) return ''
  let s = String(value)
  // A leading =, +, - or @ makes Excel treat the cell as a formula, which
  // is both wrong (a name like "-Rahul" vanishes) and a known injection
  // vector when the data came from users. Prefix with a quote to force
  // it to stay text.
  if (/^[=+\-@]/.test(s)) s = `'${s}`
  // Quote anything containing a delimiter, quote or newline; double up
  // internal quotes per RFC 4180.
  if (/[",\n\r]/.test(s)) s = `"${s.replace(/"/g, '""')}"`
  return s
}

/** Reads a possibly-nested path like 'job.title' off a row. */
function pick(row, path) {
  return path.split('.').reduce((acc, k) => (acc == null ? acc : acc[k]), row)
}

/**
 * Turns rows into CSV text.
 * @param {Array<object>} rows
 * @param {Array<{key: string, label: string, format?: (v:any, row:object)=>any}>} columns
 */
export function toCsv(rows, columns) {
  const head = columns.map((c) => cell(c.label)).join(',')
  const body = rows.map((row) =>
    columns
      .map((c) => {
        const raw = pick(row, c.key)
        return cell(c.format ? c.format(raw, row) : raw)
      })
      .join(',')
  )
  return [head, ...body].join('\r\n')
}

/**
 * Triggers a download of [rows] as `<filename>-YYYY-MM-DD.csv`.
 *
 * The BOM matters: without it Excel on Windows reads the file as the
 * local codepage, so ₹ and non-Latin names come out as mojibake.
 */
export function downloadCsv(filename, rows, columns) {
  const csv = toCsv(rows, columns)
  const blob = new Blob(['﻿' + csv], {
    type: 'text/csv;charset=utf-8;',
  })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `${filename}-${new Date().toISOString().slice(0, 10)}.csv`
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  // Revoking immediately can cancel the download in some browsers; give
  // the click a moment to start.
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}

/** Formats an ISO date for a spreadsheet cell. */
export const fmtDate = (v) => (v ? new Date(v).toLocaleString() : '')

/** Renders a populated ref as a readable name, not "[object Object]". */
export const fmtUser = (v) =>
  !v ? '' : typeof v === 'string' ? v : v.name || v.mobile || ''
