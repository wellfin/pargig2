const crypto = require('crypto');

/**
 * Dummy payment gateway.
 *
 * Stands in for a real PSP (Razorpay/Stripe/PhonePe) so the whole
 * job -> complete -> request -> pay -> release workflow can be exercised
 * end to end without credentials or real money. It deliberately mirrors
 * the shape of a real integration — create an order, hand the client
 * something to pay with, then verify a signed confirmation — so swapping
 * in the real thing means replacing the bodies of these three functions
 * and nothing else.
 *
 * WHEN GOING LIVE, replace:
 *   createOrder  -> POST https://api.razorpay.com/v1/orders
 *   verify       -> HMAC check of razorpay_signature
 *   payUri       -> the PSP's own checkout/intent URI
 * Callers (paymentController) need no changes: they already treat the
 * order id, payment id and signature as opaque strings.
 */

const PROVIDER = process.env.PAYMENT_GATEWAY || 'dummy';
// Shared secret used to sign dummy confirmations. Any real PSP replaces
// this with their webhook secret.
const SECRET = process.env.PAYMENT_GATEWAY_SECRET || 'pargig-dummy-secret';

const isDummy = () => PROVIDER === 'dummy';

/** Opaque, provider-shaped ids so nothing downstream assumes a format. */
const newId = (prefix) =>
  `${prefix}_${crypto.randomBytes(9).toString('base64url')}`;

/**
 * Opens an order to be paid.
 * @returns {{orderId:string, amount:number, currency:string,
 *            provider:string, payUri:string, createdAt:Date}}
 */
function createOrder({ amount, jobId, payeeName, payeeVpa }) {
  const orderId = newId('order');
  return {
    orderId,
    amount,
    currency: 'INR',
    provider: PROVIDER,
    // UPI intent the payer's app can open or the QR can encode. Real
    // gateways return their own checkout URL here instead.
    payUri: buildUpiUri({ amount, payeeName, payeeVpa, note: `Job ${jobId}` }),
    createdAt: new Date(),
  };
}

/**
 * Confirms an order was paid.
 *
 * The dummy provider always succeeds and mints a signed payment id, which
 * is what lets the app drive the flow with a "simulate payment" tap. A
 * real gateway instead verifies the signature it sent us and rejects
 * anything that doesn't match — hence the same return shape.
 *
 * @returns {{ok:boolean, paymentId?:string, signature?:string, reason?:string}}
 */
function confirmOrder({ orderId, paymentId, signature }) {
  if (!orderId) return { ok: false, reason: 'Missing order id' };

  if (isDummy()) {
    const id = paymentId || newId('pay');
    return { ok: true, paymentId: id, signature: sign(`${orderId}|${id}`) };
  }

  // Real provider: the client hands back what the PSP gave it and we
  // check the signature before trusting a single rupee of it.
  if (!paymentId || !signature) {
    return { ok: false, reason: 'Missing payment id or signature' };
  }
  const expected = sign(`${orderId}|${paymentId}`);
  const a = Buffer.from(expected);
  const b = Buffer.from(signature);
  const valid = a.length === b.length && crypto.timingSafeEqual(a, b);
  return valid
    ? { ok: true, paymentId, signature }
    : { ok: false, reason: 'Signature verification failed' };
}

function sign(payload) {
  return crypto.createHmac('sha256', SECRET).update(payload).digest('hex');
}

/** `upi://pay?...` deeplink — scannable by any UPI app. */
function buildUpiUri({ amount, payeeName, payeeVpa, note }) {
  const params = new URLSearchParams({
    pa: payeeVpa || 'pargig@ybl',
    pn: payeeName || 'Pargig Worker',
    am: Number(amount || 0).toFixed(2),
    cu: 'INR',
    tn: note || 'Pargig job payment',
  });
  return `upi://pay?${params.toString()}`;
}

module.exports = { createOrder, confirmOrder, buildUpiUri, isDummy, PROVIDER };
