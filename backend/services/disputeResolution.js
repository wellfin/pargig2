const refundService = require('./refundService');
const { pushToUser } = require('../utils/notify');

/**
 * Carries out an admin's decision on a dispute.
 *
 * Three decisions, in the business's own vocabulary:
 *
 *   full_refund    - the whole of what the giver paid goes back
 *   partial_refund - an approved part goes back; the rest stays settled
 *   no_refund      - the original payment stands
 *
 * Whatever is decided, the same facts are written down: payment mode,
 * payment status, the decision, the approved amount, the gateway
 * reference and the settlement status. That set is what reconciliation
 * and any audit needs, and recording it is not optional on any path —
 * including the paths where the gateway says no.
 *
 * Split across possibly several payments for one job (a retry, a
 * separate tip), oldest first, so a partial refund comes off the oldest
 * money first and the arithmetic still adds up when there is more than
 * one.
 */

const DECISIONS = ['full_refund', 'partial_refund', 'no_refund'];

// The older money-movement vocabulary, still written so existing admin
// screens and records keep reading correctly.
const OUTCOME_FOR = {
  full_refund: 'refund_giver',
  partial_refund: 'split',
  no_refund: 'no_action',
};

/** Maps a legacy `outcome` back onto a decision, for older callers. */
function decisionFromOutcome(outcome) {
  switch (outcome) {
    case 'refund_giver':
      return 'full_refund';
    case 'split':
      return 'partial_refund';
    case 'release_taker':
    case 'no_action':
      return 'no_refund';
    default:
      return null;
  }
}

/** What this job could be refunded in total, across its payments. */
function totalRefundable(payments) {
  return payments.reduce((sum, p) => sum + refundService.refundableAmount(p), 0);
}

/**
 * @param {object} args
 * @param {Dispute} args.dispute      Mongoose document, saved by the caller.
 * @param {string}  args.decision     One of DECISIONS.
 * @param {number}  [args.refundAmount] Required for partial_refund.
 * @param {string}  [args.note]       Admin's reasoning, shown to the user.
 * @param {string}  [args.adminId]
 * @returns {Promise<{ok:boolean, error?:string, summary:object}>}
 */
async function applyDecision({
  dispute,
  decision,
  refundAmount,
  note,
  adminId,
}) {
  if (!DECISIONS.includes(decision)) {
    return { ok: false, error: `Unknown decision "${decision}"` };
  }

  const payments = await refundService.paymentsForJob(dispute.job);
  const mode = payments.length ? refundService.currentMode(payments[0]) : null;
  const refundable = totalRefundable(payments);

  const summary = {
    decision,
    paymentMode: mode,
    approvedAmount: 0,
    refundedAmount: 0,
    refundStatus: 'not_applicable',
    refundReference: null,
    refundProvider: null,
    settlementStatus: null,
    recoveredFromWorker: 0,
    platformAbsorbed: 0,
    perPayment: [],
  };

  if (decision === 'no_refund') {
    for (const p of payments) await refundService.markSettled(p);
    summary.settlementStatus = payments.length
      ? payments[0].settlementStatus
      : null;
    return { ok: true, summary };
  }

  if (!payments.length) {
    return {
      ok: false,
      error: 'There is no payment on this job to refund',
      summary,
    };
  }

  // Cash and anything else the platform cannot reverse is refused here as
  // well as at dispute-raise time: an old cash dispute, or one raised
  // before this rule existed, must not be resolvable into a refund that
  // cannot happen.
  const blocked = refundService.refundBlockedReason(payments[0]);
  if (blocked) return { ok: false, error: blocked, summary };

  const approved =
    decision === 'full_refund' ? refundable : Number(refundAmount);

  if (!Number.isFinite(approved) || approved <= 0) {
    return {
      ok: false,
      error: 'Enter the refund amount to approve',
      summary,
    };
  }
  if (approved > refundable + 0.009) {
    return {
      ok: false,
      error: `Only Rs ${refundable.toFixed(2)} can still be refunded on this job`,
      summary,
    };
  }
  if (decision === 'partial_refund' && approved >= refundable - 0.009) {
    // Not a hard error, but recorded honestly: approving the entire
    // remaining balance is a full refund whatever the button said.
    summary.decision = 'full_refund';
  }

  summary.approvedAmount = approved;

  let remaining = approved;
  let anyFailed = false;
  let anyPending = false;

  for (const payment of payments) {
    if (remaining <= 0.009) break;
    const slice = Math.min(remaining, refundService.refundableAmount(payment));
    if (slice <= 0) continue;

    const result = await refundService.processRefund({
      payment,
      amount: slice,
      reason: note || `Dispute ${dispute.code}`,
      disputeId: dispute._id,
      adminId,
      receipt: dispute.code,
    });

    summary.perPayment.push({
      payment: payment._id,
      mode: result.mode,
      amount: result.amount,
      ok: result.ok,
      refundId: result.refundId || null,
      provider: result.provider,
      status: result.status || 'failed',
      error: result.error,
      settlementStatus: payment.settlementStatus,
    });

    if (!result.ok) {
      anyFailed = true;
      continue;
    }
    remaining -= result.amount;
    summary.refundedAmount += result.amount;
    summary.recoveredFromWorker += result.recoveredFromWorker || 0;
    summary.platformAbsorbed += result.platformAbsorbed || 0;
    if (!summary.refundReference && result.refundId) {
      summary.refundReference = result.refundId;
    }
    summary.refundProvider = summary.refundProvider || result.provider;
    if (result.status === 'pending') anyPending = true;
  }

  summary.settlementStatus = payments[0].settlementStatus;
  summary.refundStatus = summary.refundedAmount <= 0
    ? 'failed'
    : anyFailed || anyPending
      ? 'pending'
      : 'processed';

  if (summary.refundedAmount <= 0) {
    const firstError = summary.perPayment.find((p) => p.error)?.error;
    return {
      ok: false,
      error: firstError || 'The refund could not be processed',
      summary,
    };
  }

  return { ok: true, summary };
}

/** Tells both sides what was decided and what it means for their money. */
async function notifyParties({ dispute, summary, job }) {
  const title =
    summary.decision === 'no_refund'
      ? 'Your request was reviewed'
      : 'Refund approved';
  const jobTitle = job?.title ? `"${job.title}"` : 'your job';
  const forGiver =
    summary.decision === 'no_refund'
      ? `Support reviewed ${dispute.code} for ${jobTitle} and the original payment stands.`
      : `Rs ${summary.refundedAmount} is being refunded for ${jobTitle} (${dispute.code}).` +
        (summary.refundStatus === 'pending'
          ? ' It can take 5-7 working days to reach your account.'
          : '');

  const forWorker =
    summary.decision === 'no_refund'
      ? `Support reviewed ${dispute.code} for ${jobTitle}. No refund was approved.`
      : `Rs ${summary.refundedAmount} was refunded to the client for ${jobTitle} (${dispute.code}).` +
        (summary.recoveredFromWorker > 0
          ? ` Rs ${summary.recoveredFromWorker} was adjusted from your wallet.`
          : '');

  const targets = [
    [dispute.raisedBy, dispute.raisedBy?.toString() === job?.jobgiver?.toString() ? forGiver : forWorker],
    [dispute.against, dispute.against?.toString() === job?.jobgiver?.toString() ? forGiver : forWorker],
  ];

  for (const [user, body] of targets) {
    if (!user) continue;
    await pushToUser(user, {
      type: 'payment',
      title,
      body,
      data: {
        disputeId: dispute._id,
        jobId: dispute.job,
        decision: summary.decision,
        refundAmount: summary.refundedAmount,
        refundReference: summary.refundReference,
      },
    });
  }
}

module.exports = {
  DECISIONS,
  OUTCOME_FOR,
  decisionFromOutcome,
  applyDecision,
  notifyParties,
  totalRefundable,
};
