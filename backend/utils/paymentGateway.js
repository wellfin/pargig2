const crypto = require('crypto');
const razorpay = require('./razorpay');
const gatewayConfig = require('./gatewayConfig');

/**
 * The one seam between Pargig and whoever is moving the money.
 *
 * Two providers live behind it:
 *
 *   dummy     — the stand-in. Mints signed ids locally so the whole
 *               job -> complete -> request -> pay -> release flow can be
 *               exercised with no credentials and no real money.
 *   razorpay  — the real thing, driven by credentials an admin types
 *               into the panel (Settings -> Payment Gateway).
 *
 * Which one runs is decided per call, not at boot, because the
 * credentials can be saved while the server is up. That is why every
 * function here is async even when the dummy path does no I/O.
 *
 * Callers treat order ids, payment ids and signatures as opaque
 * strings, so nothing outside this file changes when the provider does.
 */

// Signing key for the stand-in gateway's own confirmations. Derived
// from the JWT secret so two servers sharing a deployment agree, and so
// a confirmation minted on one install cannot be replayed on another.
const DUMMY_SECRET =
  process.env.PAYMENT_GATEWAY_SECRET ||
  process.env.JWT_SECRET ||
  'pargig-dummy-secret';

const newId = (prefix) =>
  `${prefix}_${crypto.randomBytes(9).toString('base64url')}`;

const signDummy = (payload) =>
  crypto.createHmac('sha256', DUMMY_SECRET).update(payload).digest('hex');

/**
 * Opens an order to be paid.
 *
 * @param {object} args
 * @param {number} args.amount     rupees
 * @param {string} args.jobId      our own reference, echoed back by the PSP
 * @param {string} [args.payeeName]
 * @param {string} [args.payeeVpa]
 * @param {object} [args.notes]
 * @returns {Promise<{orderId:string, amount:number, currency:string,
 *   provider:string, keyId:string, payUri:string, isDummy:boolean,
 *   createdAt:Date}>}
 */
async function createOrder({ amount, jobId, payeeName, payeeVpa, notes }) {
  const config = await gatewayConfig.getConfig();

  if (config.provider === 'razorpay') {
    const order = await razorpay.createOrder({
      creds: config,
      amount,
      receipt: String(jobId || '').slice(0, 40),
      notes: { jobId: String(jobId || ''), ...(notes || {}) },
    });
    return {
      orderId: order.id,
      amount: order.amount,
      currency: order.currency,
      provider: 'razorpay',
      // The app needs the publishable key id to open checkout. It is
      // public by design — the secret is what never leaves the server.
      keyId: config.keyId,
      mode: config.mode,
      // Still useful: a QR the payer can scan from another device.
      payUri: buildUpiUri({ amount, payeeName, payeeVpa, note: `Job ${jobId}` }),
      isDummy: false,
      createdAt: new Date(),
    };
  }

  return {
    orderId: newId('order'),
    amount: Number(amount || 0),
    currency: 'INR',
    provider: 'dummy',
    keyId: '',
    mode: 'test',
    payUri: buildUpiUri({ amount, payeeName, payeeVpa, note: `Job ${jobId}` }),
    isDummy: true,
    createdAt: new Date(),
  };
}

/**
 * Confirms an order was paid.
 *
 * The stand-in always succeeds and mints a signed payment id, which is
 * what lets the app drive the flow with a "simulate payment" tap. The
 * real provider instead verifies the signature it issued and rejects
 * anything that doesn't match — same return shape either way.
 *
 * @returns {Promise<{ok:boolean, paymentId?:string, signature?:string,
 *   provider?:string, reason?:string}>}
 */
async function confirmOrder({ orderId, paymentId, signature }) {
  if (!orderId) return { ok: false, reason: 'Missing order id' };
  const config = await gatewayConfig.getConfig();

  if (config.provider === 'dummy') {
    const id = paymentId || newId('pay');
    return {
      ok: true,
      paymentId: id,
      signature: signDummy(`${orderId}|${id}`),
      provider: 'dummy',
    };
  }

  if (!paymentId || !signature) {
    return { ok: false, reason: 'Missing payment id or signature' };
  }
  const valid = razorpay.verifyCheckoutSignature({
    keySecret: config.keySecret,
    orderId,
    paymentId,
    signature,
  });
  if (!valid) return { ok: false, reason: 'Signature verification failed' };

  // The signature proves the three strings belong together. It does not
  // prove the money arrived — an authorised-but-failed payment carries
  // a valid signature too. Ask the provider what actually happened
  // before anyone is told they have been paid.
  try {
    const payment = await razorpay.fetchPayment({ creds: config, paymentId });
    if (!['captured', 'authorized'].includes(payment?.status)) {
      return {
        ok: false,
        reason: `Payment not completed (status: ${payment?.status || 'unknown'})`,
      };
    }
    return {
      ok: true,
      paymentId,
      signature,
      provider: 'razorpay',
      amount: razorpay.toRupees(payment.amount),
      method: payment.method || null,
      status: payment.status,
    };
  } catch (err) {
    // Reaching Razorpay failed, but the signature was good. Refusing
    // here would strand a payer who has genuinely paid, so accept it
    // and let the webhook reconcile.
    return {
      ok: true,
      paymentId,
      signature,
      provider: 'razorpay',
      unverifiedWithProvider: true,
      reason: err.message,
    };
  }
}

/**
 * Sends money back for a payment that went through a real gateway.
 *
 * Returns `{ok:false, manual:true}` for anything the provider cannot
 * reverse — a cash job, a wallet transfer, or a dummy-gateway payment.
 * The caller still records the refund; it just has to be paid out by
 * hand. Reporting a refund that never left the building would be worse
 * than saying so.
 */
async function refundPayment({ paymentId, amount, reason, gateway }) {
  const config = await gatewayConfig.getConfig();
  const providerPayment =
    gateway === 'razorpay' && typeof paymentId === 'string' &&
    paymentId.startsWith('pay_');

  if (config.provider !== 'razorpay' || !providerPayment) {
    return {
      ok: false,
      manual: true,
      reason: 'No gateway payment to reverse — refund must be paid manually',
    };
  }
  try {
    const r = await razorpay.refund({
      creds: config,
      paymentId,
      amount,
      notes: { reason: String(reason || '').slice(0, 200) },
    });
    return { ok: true, manual: false, ...r };
  } catch (err) {
    return { ok: false, manual: false, reason: err.message };
  }
}

/** True while no real gateway is in play. */
async function isDummy() {
  return gatewayConfig.isDummy();
}

/** The provider that would handle a payment right now. */
async function provider() {
  return (await gatewayConfig.getConfig()).provider;
}

/** `upi://pay?...` deeplink — scannable by any UPI app. */
function buildUpiUri({ amount, payeeName, payeeVpa, note }) {
  const params = new URLSearchParams({
    pa: payeeVpa || process.env.PLATFORM_UPI_VPA || 'pargig@ybl',
    pn: payeeName || 'Pargig Worker',
    am: Number(amount || 0).toFixed(2),
    cu: 'INR',
    tn: note || 'Pargig job payment',
  });
  return `upi://pay?${params.toString()}`;
}

module.exports = {
  createOrder,
  confirmOrder,
  refundPayment,
  buildUpiUri,
  isDummy,
  provider,
};
