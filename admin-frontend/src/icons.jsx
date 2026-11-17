/**
 * Inline stroke icons for the sidebar and topbar.
 *
 * Hand-drawn rather than an icon package: the panel needs about a
 * dozen, and a dependency that ships a thousand of them would cost
 * more download than the whole app. They inherit `currentColor`, so a
 * theme recolours them for free.
 *
 * Every one is decorative — the label beside it is what gets read —
 * so they are aria-hidden and never the only thing in a control.
 */

const Svg = ({ size = 18, children }) => (
  <svg
    width={size}
    height={size}
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth="1.8"
    strokeLinecap="round"
    strokeLinejoin="round"
    aria-hidden="true"
    focusable="false"
  >
    {children}
  </svg>
)

export const IconDashboard = (p) => (
  <Svg {...p}>
    <rect x="3" y="3" width="7" height="9" rx="1.5" />
    <rect x="14" y="3" width="7" height="5" rx="1.5" />
    <rect x="14" y="12" width="7" height="9" rx="1.5" />
    <rect x="3" y="16" width="7" height="5" rx="1.5" />
  </Svg>
)

export const IconUsers = (p) => (
  <Svg {...p}>
    <circle cx="9" cy="8" r="3.2" />
    <path d="M3 20c0-3.3 2.7-5.5 6-5.5s6 2.2 6 5.5" />
    <path d="M17 11a3 3 0 1 0 0-6" />
    <path d="M18 20c0-2.6-1-4.4-2.6-5.3" />
  </Svg>
)

export const IconJobs = (p) => (
  <Svg {...p}>
    <rect x="3" y="7" width="18" height="13" rx="2" />
    <path d="M9 7V5.5A1.5 1.5 0 0 1 10.5 4h3A1.5 1.5 0 0 1 15 5.5V7" />
    <path d="M3 12h18" />
  </Svg>
)

export const IconPayments = (p) => (
  <Svg {...p}>
    <rect x="2" y="5" width="20" height="14" rx="2" />
    <path d="M2 10h20" />
    <path d="M6 15h3" />
  </Svg>
)

export const IconDisputes = (p) => (
  <Svg {...p}>
    <path d="M12 3 2.5 19.5h19L12 3Z" />
    <path d="M12 10v4" />
    <path d="M12 17.2v.1" />
  </Svg>
)

export const IconReports = (p) => (
  <Svg {...p}>
    <path d="M4 20V10" />
    <path d="M10 20V4" />
    <path d="M16 20v-7" />
    <path d="M22 20H2" />
  </Svg>
)

export const IconTrend = (p) => (
  <Svg {...p}>
    <path d="M3 17l5.5-6 4 3.5L21 6" />
    <path d="M15 6h6v6" />
  </Svg>
)

/** A shield with a tick: identity checked, not merely "approved". */
export const IconVerify = (p) => (
  <Svg {...p}>
    <path d="M12 3l7 3v5.5c0 4.2-2.9 7.7-7 9.5-4.1-1.8-7-5.3-7-9.5V6l7-3z" />
    <path d="M9 12l2 2 4-4" />
  </Svg>
)

/** A speech bubble: a conversation, not a ticket. */
export const IconChat = (p) => (
  <Svg {...p}>
    <path d="M20 14.5a2.5 2.5 0 0 1-2.5 2.5H9l-4 3.5V6.5A2.5 2.5 0 0 1 7.5 4h10A2.5 2.5 0 0 1 20 6.5v8Z" />
    <path d="M9 9h7" />
    <path d="M9 12.5h4.5" />
  </Svg>
)

export const IconSettings = (p) => (
  <Svg {...p}>
    <circle cx="12" cy="12" r="3" />
    <path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M19.1 4.9 17 7M7 17l-2.1 2.1" />
  </Svg>
)

export const IconSearch = (p) => (
  <Svg {...p}>
    <circle cx="11" cy="11" r="7" />
    <path d="m20 20-3.5-3.5" />
  </Svg>
)

export const IconBell = (p) => (
  <Svg {...p}>
    <path d="M18 14V9a6 6 0 0 0-12 0v5l-1.5 3h15L18 14Z" />
    <path d="M10 20.5a2.2 2.2 0 0 0 4 0" />
  </Svg>
)

export const IconLogout = (p) => (
  <Svg {...p}>
    <path d="M14 4h4a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-4" />
    <path d="M10 16 6 12l4-4" />
    <path d="M6 12h10" />
  </Svg>
)

export const IconRupee = (p) => (
  <Svg {...p}>
    <path d="M7 5h10" />
    <path d="M7 9h10" />
    <path d="M13 5c2.8 0 4 1.8 4 4s-1.2 4-4 4H7l7 7" />
  </Svg>
)

export const IconChevron = (p) => (
  <Svg {...p}>
    <path d="m9 6 6 6-6 6" />
  </Svg>
)
