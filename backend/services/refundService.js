const Payment = require('../models/paymentModel');
const User = require('../models/userModel');
const Transaction = require('../models/transactionModel');
const razorpay = require('../utils/razorpay');
const {
  resolvePaymentMode,
  isRefundableMode,
  isGatewayMode,
  modeLabel,
} = require('../utils/paymentMode');

/**
 * The one place a refund happens.
 *
 * Every caller — admin dispute resolution today, an automated rule or a
 * self-serve cancellation later — goes through here, so there is exactly
 * one implementation of "who gets the money back, where from, and what do
 * we write down about it".
 *
 * Routing is by payment mode:
 *   upi / card / netbanking -> Razorpay refund (real when RAZORPAY_KEY_ID
 *                              is set, simulated otherwise)
 *   wallet                  -> credited to the payer's Pargig wallet
 *   cash                    -> refused; the platform never held the money
 *
 * Where the money comes from when the worker has already been paid: it is
 * taken back from their wallet as far as their balance allows, and any
 * shortfall is recorded as `platformAbsorbed` rather than silently
 * overdrawing them. A negative balance would be a debt the app has no way
 * to collect, so the books show who is actually out of pocket.
 */

/** How much of this payment can still be refunded. */
function refundableAmount(payment) {
  return Math.max(
    0,
    Number(payment.amount || 0) - Number(payment.refundedAmount || 0)
  );
}

function currentMode(payment) {
  return (
    payment.mode ||
    resolvePaymentMode({ isCod: payment.isCod, method: payment.method })
  );
}

/** Why this payment cannot be refunded, or null when it can. */
function refundBlockedReason(payment) {
  const mode = currentMode(payment);
  if (!isRefundableMode(mode)) {
    return mode === 'cash'
      ? 'This job was paid in cash, so Pargig never held the money and cannot refund it'
      : `Payments made by ${modeLabel(mode)} cannot be refunded automatically`;
  }
  if (payment.status === 'failed') return 'This payment never succeeded';
  if (refundableAmount(payment) <= 0) {
    return 'This payment has already been fully refunded';
  }
  return null;
}

/**
 * Takes the refund back off the worker, as far as their balance allows.
 *
 * Only for money that already reached them: a payment still on hold has
 * not been paid out, so there is nothing to recover.
 */
async function recoverFromWorker({ payment, amount, note }) {
  if (payment.status !== 'released' || !payment.jobtaker || amount <= 0) {
    return { recovered: 0, absorbed: amount > 0 ? amount : 0 };
  }
  // Cash payouts never touched the wallet, so there is no balance of ours
  // to take back — the worker was paid in hand.
  if (payment.isCod) return { recovered: 0, absorbed: amount };

  const worker = await User.findById(payment.jobtaker);
  if (!worker) return { recovered: 0, absorbed: amount };

  const available = Math.max(0, Number(worker.walletBalance || 0));
  const recovered = Math.min(available, amount);
  if (recovered > 0) {
    worker.walletBalance = available - recovered;
    await worker.save();
    await Transaction.create({
      user: worker._id,
      type: 'wallet_deduct',
      amount: -recovered,
      balanceAfter: worker.walletBalance,
      reference: payment._id,
      referenceModel: 'Payment',
      note: note || 'Refund recovered after dispute',
    });
  }
  return { recovered, absorbed: amount - recovered };
}

/** Credits the job giver, either through the gateway or to their wallet. */
async function payBackGiver({ payment, amount, mode, reason, receipt }) {
  if (mode === 'wallet') {
    const giver = await User.findById(payment.jobgiver);
    if (!giver) {
      return { ok: false, error: 'Payer account not found', provider: 'wallet' };
    }
    giver.walletBalance = Number(giver.walletBalance || 0) + amount;
    await giver.save();
    await Transaction.create({
      user: giver._id,
      type: 'refund',
      amount,
      balanceAfter: giver.walletBalance,
      reference: payment._id,
      referenceModel: 'Payment',
      note: reason || 'Dispute refund credited to wallet',
    });
    return {
      ok: true,
      provider: 'wallet',
      // The wallet credit is its own reference; there is no gateway id.
      refundId: null,
      status: 'processed',
      live: true,
    };
  }

  if (isGatewayMode(mode)) {
    // A gateway refund lands in the payer's bank in a few days. The
    // webhook flips a 'pending' one to its final state.
    return razorpay.createRefund({
      gatewayPaymentId: payment.gatewayPaymentId,
      amount,
      notes: {
        jobId: String(payment.job || ''),
        paymentId: String(payment._id),
        reason: reason || 'Dispute resolution',
      },
      receipt,
    });
  }

  return {
    ok: false,
    provider: 'none',
    error: `No refund route for mode ${mode}`,
  };
}

/**
 * Derives `settlementStatus` from what has actually been refunded.
 *
 * Kept separate from `status` on purpose: a payment can be 'released' to
 * the worker and still 'partially_refunded' to the giver afterwards.
 */
function recomputeSettlement(payment) {
  const total = Number(payment.amount || 0);
  const refunded = Number(payment.refundedAmount || 0);
  if (refunded <= 0) {
    payment.settlementStatus =
      payment.status === 'released' ? 'settled' : 'pending';
  } else if (refunded + 0.009 >= total) {
    payment.settlementStatus = 'refunded';
    payment.status = 'refunded';
    payment.refundedAt = payment.refundedAt || new Date();
  } else {
    payment.settlementStatus = 'partially_refunded';
  }
}

/**
 * Refunds [amount] of [payment].
 *
 * Returns a record of what happened rather than throwing, because the
 * caller has to write the outcome against the dispute whether the gateway
 * accepted it or not.
 */
async function processRefund({
  payment,
  amount,
  reason,
  disputeId,
  adminId,
  receipt,
}) {
  const mode = currentMode(payment);
  const asked = Number(amount);

  const blocked = refundBlockedReason(payment);
  if (blocked) {
    return { ok: false, amount: 0, mode, error: blocked, provider: 'none' };
  }
  if (!Number.isFinite(asked) || asked <= 0) {
    return {
      ok: false,
      amount: 0,
      mode,
      provider: 'none',
      error: 'Refund amount must be greater than zero',
    };
  }
  const refundable = refundableAmount(payment);
  if (asked > refundable + 0.009) {
    return {
      ok: false,
      amount: 0,
      mode,
      provider: 'none',
      error: `Only Rs ${refundable.toFixed(2)} of this payment can still be refunded`,
    };
  }

  const result = await payBackGiver({
    payment,
    amount: asked,
    mode,
    reason,
    receipt,
  });

  if (!result.ok) {
    // Failed attempts are recorded too: support needs the provider's own
    // words, and a silent failure looks identical to never having tried.
    payment.refunds.push({
      amount: asked,
      provider: result.provider,
      mode,
      status: 'failed',
      reason,
      dispute: disputeId,
      decidedBy: adminId,
      error: result.error,
      raw: result.raw,
    });
    payment.settlementStatus = 'refund_failed';
    await payment.save();
    return {
      ok: false,
      amount: 0,
      mode,
      provider: result.provider,
      error: result.error,
    };
  }

  const recovery = await recoverFromWorker({
    payment,
    amount: asked,
    note: reason ? `Dispute refund: ${reason}` : 'Dispute refund recovered',
  });

  payment.refunds.push({
    amount: asked,
    refundId: result.refundId || null,
    provider: result.provider,
    mode,
    status: result.status === 'pending' ? 'pending' : 'processed',
    reason,
    dispute: disputeId,
    decidedBy: adminId,
    recoveredFromWorker: recovery.recovered,
    platformAbsorbed: recovery.absorbed,
    raw: result.raw,
  });
  payment.refundedAmount = Number(payment.refundedAmount || 0) + asked;
  payment.refundReason = reason || payment.refundReason;
  recomputeSettlement(payment);
  await payment.save();

  return {
    ok: true,
    amount: asked,
    refundId: result.refundId || null,
    provider: result.provider,
    status: result.status === 'pending' ? 'pending' : 'processed',
    mode,
    recoveredFromWorker: recovery.recovered,
    platformAbsorbed: recovery.absorbed,
    live: result.live !== false,
  };
}

/** Marks a payment settled with no refund, for the "No Refund" decision. */
async function markSettled(payment) {
  if (Number(payment.refundedAmount || 0) > 0) return payment;
  payment.settlementStatus = 'settled';
  await payment.save();
  return payment;
}

/** The payments a job's refunds should be taken from, newest first. */
async function paymentsForJob(jobId) {
  return Payment.find({
    job: jobId,
    status: { $in: ['paid', 'on_hold', 'released', 'refunded'] },
  }).sort('-createdAt');
}

module.exports = {
  processRefund,
  markSettled,
  paymentsForJob,
  refundableAmount,
  refundBlockedReason,
  currentMode,
  recomputeSettlement,
};
