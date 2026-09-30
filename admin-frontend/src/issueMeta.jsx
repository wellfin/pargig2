// Shared between the Issues list and the Issue detail page.
//
// In its own module because a file that exports both a component and
// constants breaks Vite's fast refresh — the whole module reloads on
// every edit instead of just the component.

// Both catalogues in one map. The two sides share only 'other', so a
// single lookup is enough to label any issue whoever raised it.
export const GIVER_ISSUE_TYPES = {
  service_quality: 'Service Quality',
  payment: 'Payment',
  worker_behavior: 'Worker Behavior',
  wrong_service: 'Wrong Service',
  safety: 'Safety Concern',
}

export const TAKER_ISSUE_TYPES = {
  payment_not_received: 'Payment Not Received',
  requirement_changed: 'Requirement Changed',
  additional_work: 'Additional Work Requested',
  access_not_provided: 'Material/Access Not Provided',
  giver_unavailable: 'Job Giver Unavailable',
  giver_behaviour: 'Behaviour/Safety Concern',
}

export const ISSUE_TYPES = {
  ...GIVER_ISSUE_TYPES,
  ...TAKER_ISSUE_TYPES,
  other: 'Other',
}

export const ROLE_LABELS = {
  jobgiver: 'Job Giver',
  jobtaker: 'Job Taker',
}

export const roleBadge = (role) => (
  <span className={`badge ${role === 'jobtaker' ? 'yellow' : 'gray'}`}>
    {ROLE_LABELS[role] || 'Job Giver'}
  </span>
)

export const statusBadge = (s) => {
  const map = {
    open: 'red',
    under_review: 'yellow',
    resolved: 'green',
    rejected: 'gray',
  }
  return (
    <span className={`badge ${map[s] || 'gray'}`}>
      {(s || '').replace(/_/g, ' ')}
    </span>
  )
}
