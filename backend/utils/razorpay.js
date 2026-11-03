const crypto = require('crypto');

/**
 * Razorpay REST client.
 *
 * Deliberately not the `razorpay` npm package: everything we need is
 * four HTTP calls and two HMACs, and Node has had global `fetch` since
 * 18. One less dependency in the path that moves money is worth more
 * than the convenience methods we would be importing.
 *
 * Every function takes the credentials as an argument rather than
 * reading them from the environment, because they live in the database
 * and can change while the server is running — see utils/gatewayConfig.
 */

const API = 'https://api.razorpay.com/v1';

/**
 * Razorpay counts in paise, we count in rupees. Rounding here rather
 * than at each call site: a float that arrives as 2099.9999999 must
 * become 209999 paise once, consistently, or the order and the
 * reconciliation disagree by a rupee.
 */
const toPaise = (rupees) => Math.round(Number(rupees || 0) * 100);
const toRupees = (paise) => Number(paise || 0) / 100;

function authHeader({ keyId, keySecret }) {
  const token = Buffer.from(`${keyId}:${keySecret}`).toString('base64');
  return `Basic ${token}`;
}

/**
 * One place where a Razorpay failure becomes an Error we can show.
 *
 * Their errors arrive as `{error: {code, description, ...}}`; the
 * description is written for a developer but is specific enough to be
 * worth surfacing ("The api key provided is invalid" is exactly what an
 * admin who pasted the wrong field needs to read).
 */
async function call(path, { method = 'GET', body, creds, timeoutMs = 20000 }) {
  if (!creds?.keyId || !creds?.keySecret) {
    throw new Error('Razorpay is not configured: missing key id or secret');
  }
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  let res;
  try {
    res = await fetch(`${API}${path}`, {
      method,
      headers: {
        Authorization: authHeader(creds),
        'Content-Type': 'application/json',
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: controller.signal,
    });
  } catch (err) {
    // A network failure must not read like a declined payment.
    throw new Error(
      err.name === 'AbortError'
        ? 'Razorpay did not respond in time'
        : `Could not reach Razorpay: ${err.message}`,
    );
  } finally {
    clearTimeout(timer);
  }

  const text = await res.text();
  let data = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch (_) {
    data = null;
  }
  if (!res.ok) {
    const described = data?.error?.description;
    const err = new Error(
      described || `Razorpay request failed (HTTP ${res.status})`,
    );
    err.status = res.status;
    err.code = data?.error?.code;
    throw err;
  }
  return data;
}

/**
 * Opens an order. `receipt` is our own reference — Razorpay echoes it
 * back on the payment and in the dashboard, which is what makes a
 * payment traceable to a job without a lookup table.
 */
async function createOrder({ creds, amount, receipt, notes }) {
  const paise = toPaise(amount);
  if (!paise || paise < 100) {
    // Razorpay's own floor is ₹1. Failing here names the real problem
    // instead of letting their API return a cryptic BAD_REQUEST.
    throw new Error('Amount must be at least ₹1');
  }
  const order = await call('/orders', {
    method: 'POST',
    creds,
    body: {
      amount: paise,
      currency: 'INR',
      receipt: String(receipt || '').slice(0, 40),
      notes: notes || {},
      // Capture automatically: an authorised-but-uncaptured payment
      // expires after five days and silently refunds itself, which
      // would leave a worker marked paid and no money anywhere.
      payment_capture: 1,
    },
  });
  return {
    id: order.id,
    amount: toRupees(order.amount),
    amountPaise: order.amount,
    currency: order.currency,
    status: order.status,
    receipt: order.receipt,
  };
}

async function fetchPayment({ creds, paymentId }) {
  return call(`/payments/${encodeURIComponent(paymentId)}`, { creds });
}

/**
 * Refunds a captured payment. `amount` omitted means the full payment.
 */
async function refund({ creds, paymentId, amount, notes }) {
  const body = { notes: notes || {} };
  if (amount !== undefined && amount !== null) body.amount = toPaise(amount);
  const r = await call(`/payments/${encodeURIComponent(paymentId)}/refund`, {
    method: 'POST',
    creds,
    body,
  });
  return {
    id: r.id,
    paymentId: r.payment_id,
    amount: toRupees(r.amount),
    status: r.status,
    speed: r.speed_processed,
  };
}

/**
 * Cheapest call that proves a key pair works — used by the admin
 * panel's Test Connection so credentials are checked when they are
 * typed, not at midnight when someone tries to pay.
 */
async function verifyCredentials({ creds }) {
  await call('/payments?count=1', { creds, timeoutMs: 15000 });
  return true;
}

/**
 * Checkout callback signature: HMAC-SHA256 of "<order_id>|<payment_id>"
 * keyed with the KEY SECRET.
 *
 * This is the whole reason a client cannot fake a payment: the app
 * hands back three strings and only Razorpay and our server know the
 * secret that ties them together.
 */
function verifyCheckoutSignature({ keySecret, orderId, paymentId, signature }) {
  if (!keySecret || !orderId || !paymentId || !signature) return false;
  const expected = crypto
    .createHmac('sha256', keySecret)
    .update(`${orderId}|${paymentId}`)
    .digest('hex');
  return timingSafeEqualHex(expected, signature);
}

/**
 * Webhook signature: HMAC-SHA256 of the RAW request body keyed with the
 * WEBHOOK secret — a different secret from the key secret, and a
 * different payload from the checkout signature. Mixing the two up is
 * the classic Razorpay integration bug.
 *
 * `rawBody` must be the exact bytes received. Re-serialising the parsed
 * JSON changes key order and spacing and fails every time.
 */
function verifyWebhookSignature({ webhookSecret, rawBody, signature }) {
  if (!webhookSecret || !rawBody || !signature) return false;
  const body = Buffer.isBuffer(rawBody)
    ? rawBody.toString('utf8')
    : String(rawBody);
  const expected = crypto
    .createHmac('sha256', webhookSecret)
    .update(body)
    .digest('hex');
  return timingSafeEqualHex(expected, signature);
}

/** Constant-time compare that survives a length mismatch. */
function timingSafeEqualHex(a, b) {
  const x = Buffer.from(String(a));
  const y = Buffer.from(String(b));
  if (x.length !== y.length) return false;
  return crypto.timingSafeEqual(x, y);
}

/**
 * "rzp_test_xxx" or "rzp_live_xxx". Knowing which one is saved is what
 * stops a test key quietly running in production, so the admin panel
 * shows it and the settings controller warns when it disagrees with the
 * selected mode.
 */
function modeOfKeyId(keyId) {
  const k = String(keyId || '');
  if (k.startsWith('rzp_live_')) return 'live';
  if (k.startsWith('rzp_test_')) return 'test';
  return null;
}

module.exports = {
  createOrder,
  fetchPayment,
  refund,
  verifyCredentials,
  verifyCheckoutSignature,
  verifyWebhookSignature,
  modeOfKeyId,
  toPaise,
  toRupees,
};
