/**
 * Limits on /auth/otp/request.
 *
 * Until now the only brake on this endpoint was a 30-second countdown
 * in the mobile app, which is no brake at all — it is a public,
 * unauthenticated POST. That was survivable while the "SMS" was a
 * number echoed back in the JSON. With MSG91 behind it, every call
 * spends money and every unknown number also creates a User row, so
 * both have to be capped here.
 *
 * Two limits, for two different abuses:
 *
 *   per mobile  — stored on the user document, so it survives a restart
 *                 (a deploy is exactly when someone is retrying) and is
 *                 correct even if the server is ever run as more than
 *                 one process.
 *   per IP      — in memory, because it only needs to blunt a loop, and
 *                 a loop does not pause for a deploy.
 */

const COOLDOWN_SECONDS = () =>
  parseInt(process.env.OTP_RESEND_COOLDOWN_SECONDS || '30', 10);
const MAX_PER_DAY = () => parseInt(process.env.OTP_MAX_PER_DAY || '10', 10);
const MAX_PER_IP_PER_HOUR = () =>
  parseInt(process.env.OTP_MAX_PER_IP_PER_HOUR || '20', 10);

/**
 * Day boundary in IST, not UTC. A cap that resets at 05:30 local time
 * would hand a user their fresh ten sends in the middle of the night
 * and leave them stuck at 05:29 in the evening.
 */
function dayKey(now = new Date()) {
  const ist = new Date(now.getTime() + 5.5 * 3600 * 1000);
  return ist.toISOString().slice(0, 10);
}

/**
 * May this number be sent another code?
 *
 * Returns `{ ok }` or `{ ok: false, retryAfter, message }` where
 * retryAfter is seconds — the value for the Retry-After header and for
 * the countdown the app shows.
 *
 * `dailyCap` is off when no SMS gateway is configured. The cap is there
 * to bound a bill; with nothing sending, there is no bill, and a tester
 * logging in and out all afternoon should not be cut off at ten. The
 * cooldown still applies either way — the app has always enforced that
 * one client-side, so nothing regresses.
 */
function checkMobile(user, { dailyCap = true, now = new Date() } = {}) {
  const cooldown = COOLDOWN_SECONDS();
  const last = user.otpSentAt ? new Date(user.otpSentAt).getTime() : 0;
  const since = (now.getTime() - last) / 1000;
  if (last && since < cooldown) {
    const retryAfter = Math.max(1, Math.ceil(cooldown - since));
    return {
      ok: false,
      retryAfter,
      message: `Please wait ${retryAfter}s before asking for another code`,
    };
  }

  const today = dayKey(now);
  const count = user.otpSentDay === today ? user.otpSentCount || 0 : 0;
  if (dailyCap && count >= MAX_PER_DAY()) {
    // Until midnight IST. Reporting the real wait is kinder than a flat
    // "try later", and it is also the honest number.
    const ist = new Date(now.getTime() + 5.5 * 3600 * 1000);
    const midnight = Date.UTC(
      ist.getUTCFullYear(),
      ist.getUTCMonth(),
      ist.getUTCDate() + 1,
    );
    return {
      ok: false,
      retryAfter: Math.max(60, Math.ceil((midnight - ist.getTime()) / 1000)),
      message:
        'Too many codes requested for this number today. ' +
        'Try again tomorrow or contact support.',
    };
  }

  return { ok: true };
}

/**
 * Records that a code went out. `delivered` is false when nothing was
 * actually sent (the dev path, or a gateway that refused): the cooldown
 * still applies, so a failing gateway is not hammered, but the daily
 * allowance is not spent on a message the user never received.
 */
function noteSent(user, { delivered = true, now = new Date() } = {}) {
  const today = dayKey(now);
  if (user.otpSentDay !== today) {
    user.otpSentDay = today;
    user.otpSentCount = 0;
  }
  user.otpSentAt = now;
  if (delivered) user.otpSentCount = (user.otpSentCount || 0) + 1;
}

// --- per-IP ---------------------------------------------------------

const buckets = new Map(); // ip -> { count, resetAt }
let lastSweep = 0;

function sweep(now) {
  // Cheap enough to do inline, and it keeps the map from growing for
  // the lifetime of the process under a distributed attempt.
  if (now - lastSweep < 60_000) return;
  lastSweep = now;
  for (const [ip, b] of buckets) {
    if (b.resetAt <= now) buckets.delete(ip);
  }
}

/**
 * Loopback and link-local addresses are not limited. If the reverse
 * proxy is not forwarding the real client address, every user arrives
 * as 127.0.0.1 and an IP cap would lock out the entire app at twenty
 * logins an hour. Failing open there is the safer wrong answer: the
 * per-mobile cap still holds, and it is the one that bounds the bill.
 */
function skipIp(ip) {
  if (!ip) return true;
  const a = String(ip).replace(/^::ffff:/, '');
  return a === '127.0.0.1' || a === '::1' || a.startsWith('169.254.');
}

function checkIp(ip, now = Date.now()) {
  if (skipIp(ip)) return { ok: true };
  sweep(now);
  const b = buckets.get(ip);
  if (!b || b.resetAt <= now) return { ok: true };
  if (b.count < MAX_PER_IP_PER_HOUR()) return { ok: true };
  return {
    ok: false,
    retryAfter: Math.max(1, Math.ceil((b.resetAt - now) / 1000)),
    message: 'Too many OTP requests from this network. Try again later.',
  };
}

function noteIp(ip, now = Date.now()) {
  if (skipIp(ip)) return;
  const b = buckets.get(ip);
  if (!b || b.resetAt <= now) {
    buckets.set(ip, { count: 1, resetAt: now + 3600_000 });
    return;
  }
  b.count += 1;
}

/**
 * The caller's address as far as we can tell. Express only trusts
 * X-Forwarded-For when `trust proxy` is set (app.js sets it to 1 for
 * the Nginx in front); without that, req.ip is the socket address and
 * a forged header is ignored, which is the behaviour we want.
 */
function clientIp(req) {
  return req.ip || req.socket?.remoteAddress || null;
}

/** Test seam. */
function _reset() {
  buckets.clear();
  lastSweep = 0;
}

module.exports = {
  checkMobile,
  noteSent,
  checkIp,
  noteIp,
  clientIp,
  dayKey,
  _reset,
};
