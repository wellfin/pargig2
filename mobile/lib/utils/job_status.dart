/// Job lifecycle helpers shared across screens.
library;

/// Statuses that exist before the work is finished.
const kPreCompletionStatuses = <String>[
  'open',
  'confirmed',
  'reached',
  'in_progress',
];

/// Whether a posted job still belongs in the giver's "Active Jobs".
///
/// A job is only finished for the giver once the work is done AND the
/// money has moved. Everything before completion qualifies, and a
/// `completed` job keeps its place until payment is settled — so the one
/// thing still owed stays in front of them instead of vanishing the moment
/// the worker marks the job done.
///
/// `paymentReleasedAt` is the settle stamp written by the backend's
/// settleJob(), which both the online and cash-on-delivery paths run
/// through — so COD clears from this list exactly like a card payment.
///
/// `cancelled` never shows. `disputed` is excluded too: nothing stamps
/// `paymentReleasedAt` on such a job, so it would sit in Active Jobs
/// permanently.
bool isActiveForGiver(Map<String, dynamic> job) {
  final status = (job['status'] ?? '').toString();
  if (kPreCompletionStatuses.contains(status)) return true;
  if (status != 'completed') return false;
  return !isPaymentSettled(job);
}

/// True once the money for [job] has been released to the worker.
bool isPaymentSettled(Map<String, dynamic> job) =>
    (job['paymentReleasedAt'] ?? '').toString().trim().isNotEmpty;

/// Whether [job] is the work this [userId] is currently engaged on.
///
/// The mirror of [isActiveForGiver] for the worker's side. Two extra
/// conditions: they must be the *selected* worker — merely having applied
/// is not being on the job — and the same "not done until paid" rule
/// applies, because a completed job they have not been paid for is very
/// much still their business.
bool isActiveForWorker(Map<String, dynamic> job, String? userId) {
  if (userId == null || userId.isEmpty) return false;
  final selected = job['selectedJobtaker'];
  final selectedId = selected is Map
      ? (selected['_id'] ?? '').toString()
      : (selected ?? '').toString();
  if (selectedId != userId) return false;
  return isActiveForGiver(job);
}

/// Human label for where a job has got to, from the worker's point of
/// view. Kept beside the predicates so the wording cannot drift from the
/// statuses they test.
String workerStatusLabel(Map<String, dynamic> job) {
  final status = (job['status'] ?? '').toString();
  switch (status) {
    case 'confirmed':
      return 'Accepted — head to the location';
    case 'reached':
      return 'You have arrived';
    case 'in_progress':
      return 'Work in progress';
    case 'completed':
      return isPaymentSettled(job) ? 'Paid' : 'Awaiting payment';
    default:
      return status;
  }
}
