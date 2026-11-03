/**
 * MSG91 SMS client — the delivery channel for login / registration OTPs.
 *
 * MSG91 also offers to generate and verify the code for us. We don't use
 * that half: the code is generated here, stored on the user record with
 * its own expiry and attempt counter, and checked here. MSG91 is only
 * the thing that carries it to the handset. That keeps one source of
 * truth for "is this code valid", keeps the dev flow (no SMS, code
 * echoed in the response) working unchanged, and means an outage at
 * MSG91 can never silently accept a login.
 *
 * Credentials come from the environment, not the database — unlike the
 * payment gateway. An SMS key is set once per deployment and changing
 * it is a server job, not an everyday admin task. See MSG91_SETUP.md.
 */

const DEFAULT_BASE = 'https://control.msg91.com/api/v5';

/** Nothing is cached: env is read per call so tests can point the
 *  client at a local stub without reloading the module. */
function config() {
  return {
    authKey: (process.env.MSG91_AUTH_KEY || '').trim(),
    templateId: (process.env.MSG91_TEMPLATE_ID || '').trim(),
    senderId: (process.env.MSG91_SENDER_ID || '').trim(),
    countryCode: (process.env.MSG91_COUNTRY_CODE || '91').replace(/\D/g, ''),
    baseUrl: (process.env.MSG91_BASE_URL || DEFAULT_BASE).replace(/\/+$/, ''),
    timeoutMs: parseInt(process.env.MSG91_TIMEOUT_MS || '12000', 10),
  };
}

/**
 * Both are required. An auth key without a template id reaches MSG91
 * and is rejected per message, which costs nothing but looks like a
 * delivery failure to every user — better to treat it as "not
 * configured" and keep the dev path.
 */
function isConfigured() {
  const c = config();
  return Boolean(c.authKey && c.templateId);
}

/** What the admin/ops side can be told without leaking the key. */
function status() {
  const c = config();
  return {
    provider: 'msg91',
    configured: isConfigured(),
    hasAuthKey: Boolean(c.authKey),
    hasTemplateId: Boolean(c.templateId),
    senderId: c.senderId || null,
    countryCode: c.countryCode,
  };
}

/**
 * MSG91 wants the number with its country code and no punctuation.
 * Our users type ten digits; stored numbers are ten digits. Anything
 * already carrying 91, a leading zero or a +91 is normalised rather
 * than rejected, because a number that round-trips through a contact
 * picker picks those up.
 */
function toMsisdn(mobile, countryCode) {
  const cc = String(countryCode || '91');
  let d = String(mobile || '').replace(/\D/g, '');
  if (d.startsWith('00')) d = d.slice(2);
  if (d.length > 10 && d.startsWith(cc)) return d;
  if (d.length === 11 && d.startsWith('0')) d = d.slice(1);
  return cc + d;
}

class SmsNotConfiguredError extends Error {
  constructor() {
    super('SMS is not configured');
    this.name = 'SmsNotConfiguredError';
  }
}

class SmsSendError extends Error {
  constructor(message, { status, body } = {}) {
    super(message);
    this.name = 'SmsSendError';
    this.status = status;
    this.body = body;
  }
}

/**
 * Sends one OTP SMS. Resolves with MSG91's request id — worth keeping,
 * because it is the only handle their support will accept when a user
 * swears the message never arrived.
 *
 * `otpExpiryMinutes` is MSG91's own window, not ours. Ours is the one
 * that decides whether a code still works; theirs only governs how long
 * they will treat a repeat request as a resend of the same message.
 * Keeping them in step stops the two disagreeing in a support log.
 */
async function sendOtp({ mobile, otp, ttlSeconds }) {
  if (!isConfigured()) throw new SmsNotConfiguredError();
  const c = config();

  const params = new URLSearchParams({
    template_id: c.templateId,
    mobile: toMsisdn(mobile, c.countryCode),
    otp: String(otp),
    otp_expiry: String(Math.max(1, Math.round((ttlSeconds || 300) / 60))),
    // Without this MSG91 queues and answers 200 immediately, so a
    // rejected template or an exhausted balance would look like a
    // successful send and the user would wait for nothing.
    realTimeResponse: '1',
  });
  if (c.senderId) params.set('sender', c.senderId);

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), c.timeoutMs);
  let res;
  try {
    res = await fetch(`${c.baseUrl}/otp?${params.toString()}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        authkey: c.authKey,
      },
      // The OTP itself travels as a query parameter above; the body is
      // where extra template variables would go, and ours has none.
      body: '{}',
      signal: controller.signal,
    });
  } catch (err) {
    throw new SmsSendError(
      err.name === 'AbortError'
        ? 'MSG91 did not respond in time'
        : `Could not reach MSG91: ${err.message}`,
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

  // MSG91 answers 200 with {"type":"error"} for most of the mistakes an
  // operator actually makes — wrong template id, number not on the DLT
  // whitelist, no balance. The HTTP status alone is not the verdict.
  const type = String(data?.type || '').toLowerCase();
  if (!res.ok || type === 'error') {
    const described =
      (typeof data?.message === 'string' && data.message) ||
      data?.errors?.[0]?.message ||
      `MSG91 rejected the request (HTTP ${res.status})`;
    throw new SmsSendError(described, { status: res.status, body: data });
  }

  // On success `message` is the request id. Older responses used
  // `request_id`; accept either rather than lose the handle.
  return { requestId: data?.request_id || data?.message || null };
}

module.exports = {
  sendOtp,
  isConfigured,
  status,
  toMsisdn,
  SmsNotConfiguredError,
  SmsSendError,
};
