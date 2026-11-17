const asyncHandler = require('express-async-handler');
const Payment = require('../models/paymentModel');
const razorpay = require('../utils/razorpay');
const { recomputeSettlement } = require('../services/refundService');

/**
 * Razorpay webhook receiver.
 *
 * A refund is asked for over the API and completes minutes to days
 * later, so the API response is only ever "accepted". The final
 * settlement state — processed, or failed and the money returned to us —
 * arrives here, which is why reconciliation reads `settlementStatus`
 * rather than assuming the decision succeeded.
 *
 * Signature is checked against the raw bytes before anything is trusted.
 * Unsigned or wrongly signed calls are rejected: this endpoint is public
 * by necessity, and anything less would let anyone mark refunds
 * processed.
 *
 * Always answers 200 to a well-formed, correctly signed event, even for
 * events it does not handle. A gateway that gets an error retries with
 * backoff for hours, and a retry storm over an event we ignore on
 * purpose is worse than silence.
 */
const razorpayWebhook = asyncHandler(async (req, res) => {
  const signature = req.get('x-razorpay-signature');

  // In dummy mode there is no webhook secret to verify against. The
  // endpoint still works so the flow can be tested end to end, but it
  // refuses to run unverified in production, where a real secret is the
  // only thing standing between this route and forged refunds.
  const verified = razorpay.verifyWebhookSignature(req.rawBody, signature);
  if (!verified) {
    const secretSet = Boolean((process.env.RAZORPAY_WEBHOOK_SECRET || '').trim());
    if (secretSet || process.env.NODE_ENV === 'production') {
      res.status(400);
      throw new Error('Invalid webhook signature');
    }
  }

  const event = req.body?.event;
  const entity = req.body?.payload?.refund?.entity;

  if (!event || !event.startsWith('refund.') || !entity?.id) {
    return res.json({ ok: true, ignored: true, event: event || null });
  }

  // Locate by the refund id we recorded when the refund was created.
  const payment = await Payment.findOne({ 'refunds.refundId': entity.id });
  if (!payment) {
    // Not ours, or recorded under a different account. Acknowledged so
    // the gateway stops retrying; logged so it is not lost silently.
    console.warn(`[razorpay] refund ${entity.id} matches no payment`);
    return res.json({ ok: true, unmatched: true });
  }

  const entry = payment.refunds.find((r) => r.refundId === entity.id);
  const previous = entry.status;

  if (event === 'refund.processed') entry.status = 'processed';
  else if (event === 'refund.failed') entry.status = 'failed';
  else if (event === 'refund.speed_changed') entry.status = entry.status;
  entry.raw = entity;

  // A refund that failed after we counted it has to be uncounted, or the
  // books show money returned that the payer never received.
  if (previous !== 'failed' && entry.status === 'failed') {
    payment.refundedAmount = Math.max(
      0,
      Number(payment.refundedAmount || 0) - Number(entry.amount || 0)
    );
    recomputeSettlement(payment);
    payment.settlementStatus = 'refund_failed';
  } else if (previous === 'failed' && entry.status === 'processed') {
    payment.refundedAmount =
      Number(payment.refundedAmount || 0) + Number(entry.amount || 0);
    recomputeSettlement(payment);
  } else {
    recomputeSettlement(payment);
  }

  await payment.save();
  res.json({ ok: true, refundId: entity.id, status: entry.status });
});

module.exports = { razorpayWebhook };
