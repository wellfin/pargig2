const asyncHandler = require('express-async-handler');
const User = require('../models/userModel');
const generateToken = require('../utils/generateToken');
const { generateOtp, otpExpiry } = require('../utils/otp');
const sms = require('../utils/sms');
const mailer = require('../utils/mailer');
const throttle = require('../utils/otpThrottle');

const ttlSeconds = () => parseInt(process.env.OTP_TTL_SECONDS || '300', 10);

const requestOtp = asyncHandler(async (req, res) => {
  const { mobile, role } = req.body;
  if (!mobile || !/^\d{10}$/.test(mobile)) {
    res.status(400);
    throw new Error('Valid 10-digit mobile required');
  }

  // Checked before the user is looked up, let alone created: a loop
  // against this endpoint costs an SMS and a database row per call, and
  // the row is written even for a number that will never log in.
  // With no SMS gateway configured a code costs nothing to produce, so
  // the two caps that exist to bound the bill are off and only the
  // cooldown applies. That is the development path, and it behaves the
  // way it did before MSG91 existed.
  const smsOn = await sms.isConfigured();
  const ip = throttle.clientIp(req);
  const byIp = smsOn ? throttle.checkIp(ip) : { ok: true };
  if (!byIp.ok) {
    res.set('Retry-After', String(byIp.retryAfter));
    res.status(429);
    throw new Error(byIp.message);
  }
  // role comes from the pre-auth onboarding screen (Post Job → 'jobgiver',
  // Find Job → 'jobtaker'). Optional — older clients won't send it, in
  // which case we fall back to 'jobgiver' to preserve historical behaviour.
  // Only honoured for NEW accounts; an existing user's role is never
  // rewritten by this endpoint — they have to go through switchRole.
  const onboardingRole =
    role === 'jobtaker' || role === 'jobgiver' ? role : 'jobgiver';
  let user = await User.findOne({ mobile });
  if (!user) {
    // Materialize the nested geo subdocs on first create so every user
    // record has these fields present in Atlas from day one (without
    // this, Mongoose only emits `location` / `workArea` / `currentLocation`
    // into the doc after the first save that touches them). All three
    // subdocs share the same shape (coords + address parts + label)
    // so the admin sees a consistent column structure.
    const blankGeo = {
      type: 'Point',
      coordinates: [0, 0],
      address: '',
      city: '',
      state: '',
      pincode: '',
      label: '',
    };
    user = await User.create({
      mobile,
      roles: [onboardingRole],
      activeRole: onboardingRole,
      location: { ...blankGeo },
      workArea: { ...blankGeo },
      currentLocation: { ...blankGeo, updatedAt: null },
    });
  }
  const byMobile = throttle.checkMobile(user, { dailyCap: smsOn });
  if (!byMobile.ok) {
    res.set('Retry-After', String(byMobile.retryAfter));
    res.status(429);
    throw new Error(byMobile.message);
  }

  const code = generateOtp();
  const ttl = ttlSeconds();

  // Send first, save second. If MSG91 refuses, the code that failed to
  // go anywhere is never written, so the previous one — which may well
  // be sitting in the user's inbox — keeps working.
  let delivered = false;
  let requestId = null;
  let sendError = null;
  if (smsOn) {
    try {
      const sent = await sms.sendOtp({ mobile, otp: code, ttlSeconds: ttl });
      requestId = sent.requestId;
      delivered = true;
    } catch (err) {
      sendError = err;
      console.error('[otp] MSG91 send failed for', mobile, '-', err.message);
    }
  }

  if (delivered || !smsOn) {
    user.otp = { code, expiresAt: otpExpiry(), attempts: 0, requestId };
  }
  // The cooldown applies either way — a gateway that is failing should
  // not be hammered — but a message nobody received does not come out
  // of the user's daily allowance.
  throttle.noteSent(user, { delivered: delivered || !smsOn });
  await user.save();
  if (smsOn) throttle.noteIp(ip);

  if (sendError) {
    res.status(502);
    // The gateway's own wording ("number not on the DLT whitelist",
    // "insufficient balance") is what whoever is watching the logs
    // needs; a user staring at a login screen does not. Production
    // gets the neutral sentence, everyone else gets the cause.
    throw new Error(
      process.env.NODE_ENV === 'production'
        ? 'Could not send the OTP right now. Please try again in a moment.'
        : `Could not send OTP: ${sendError.message}`,
    );
  }

  const payload = {
    message: delivered ? 'OTP sent' : 'OTP generated',
    // So the app's resend countdown matches the server's rule instead
    // of guessing at it.
    resendAfter: parseInt(process.env.OTP_RESEND_COOLDOWN_SECONDS || '30', 10),
  };
  // Only ever when nothing was actually sent — i.e. no SMS gateway is
  // configured — and never in production. Once MSG91 is set up this
  // branch stops being reachable.
  if (!delivered && process.env.NODE_ENV !== 'production') {
    payload.devOtp = code;
  }
  res.json(payload);
});

const verifyOtp = asyncHandler(async (req, res) => {
  const { mobile, otp } = req.body;
  const user = await User.findOne({ mobile });
  if (!user || !user.otp || !user.otp.code) {
    res.status(400);
    throw new Error('Request OTP first');
  }
  if (user.otp.expiresAt < new Date()) {
    res.status(400);
    throw new Error('OTP expired');
  }
  if (user.otp.attempts >= 5) {
    res.status(429);
    throw new Error('Too many attempts');
  }
  if (user.otp.code !== otp) {
    user.otp.attempts += 1;
    await user.save();
    res.status(400);
    throw new Error('Invalid OTP');
  }
  user.otp = undefined;
  user.lastLoginAt = new Date();
  await user.save();

  res.json({
    token: generateToken(user._id),
    user
  });
});

const adminLogin = asyncHandler(async (req, res) => {
  const Admin = require('../models/adminModel');
  const { email, password } = req.body;
  const admin = await Admin.findOne({ email: (email || '').toLowerCase() });
  if (!admin || !(await admin.matchPassword(password))) {
    res.status(401);
    throw new Error('Invalid credentials');
  }
  if (!admin.isActive) {
    res.status(403);
    throw new Error('Admin disabled');
  }
  res.json({
    token: generateToken(admin._id, 'admin'),
    admin: { _id: admin._id, name: admin.name, email: admin.email, role: admin.role }
  });
});

// ------------------------------------------------- admin password reset

const RESET_TTL_MINUTES = 10;
const RESET_RESEND_SECONDS = 60;
const RESET_MAX_ATTEMPTS = 5;
const ADMIN_MIN_PASSWORD = 10;

/** Six digits. Four would be a thousand guesses to exhaust. */
const resetCode = () =>
  String(require('crypto').randomInt(100000, 1000000));

/**
 * HMAC rather than a plain hash: JWT_SECRET acts as a pepper, so the
 * million possible codes cannot be pre-hashed from a database dump
 * alone. Same cost to verify, no extra storage.
 */
const hashCode = (code) =>
  require('crypto')
    .createHmac('sha256', process.env.JWT_SECRET || 'pargig')
    .update(String(code))
    .digest('hex');

/**
 * Step one of "forgot password": email a code to an admin.
 *
 * Always answers the same way, whether or not the address belongs to
 * anybody. The alternative tells a stranger which addresses are admin
 * accounts, which is the harder half of a login to guess — and this
 * endpoint has to be open to be useful, so it cannot ask who is
 * calling.
 *
 * With no SMTP server configured the code comes back in the response
 * instead, exactly as the mobile OTP does on a development machine,
 * and only when NODE_ENV is not production.
 */
const adminForgotPassword = asyncHandler(async (req, res) => {
  const Admin = require('../models/adminModel');
  const email = (req.body.email || '').trim().toLowerCase();

  // Bound the loop before doing any work. Sending mail costs money and
  // reputation, and a flood of it to a real mailbox is itself the
  // attack.
  const ip = throttle.clientIp(req);
  const byIp = throttle.checkIp(ip);
  if (!byIp.ok) {
    res.set('Retry-After', String(byIp.retryAfter));
    res.status(429);
    throw new Error(byIp.message);
  }

  const neutral = {
    message:
      'If that email belongs to an admin account, a code is on its way. ' +
      'It is valid for ' + RESET_TTL_MINUTES + ' minutes.'
  };

  const admin = await Admin.findOne({ email }).select(
    '+resetOtpHash +resetOtpExpiresAt +resetOtpAttempts +resetOtpSentAt'
  );
  // A disabled account is treated as no account — reactivating it is a
  // decision for a person, not a side effect of a reset.
  if (!admin || !admin.isActive) return res.json(neutral);

  const since = admin.resetOtpSentAt
    ? (Date.now() - new Date(admin.resetOtpSentAt).getTime()) / 1000
    : Infinity;
  if (since < RESET_RESEND_SECONDS) {
    // The wait is reported rather than hidden: the caller here is
    // almost always the real admin pressing the button twice, and
    // telling them to wait 40 seconds is the useful answer. It leaks
    // nothing a correct guess would not already have revealed.
    const retryAfter = Math.ceil(RESET_RESEND_SECONDS - since);
    res.set('Retry-After', String(retryAfter));
    res.status(429);
    throw new Error(`A code was just sent. Try again in ${retryAfter}s.`);
  }

  const code = resetCode();
  admin.resetOtpHash = hashCode(code);
  admin.resetOtpExpiresAt = new Date(Date.now() + RESET_TTL_MINUTES * 60000);
  admin.resetOtpAttempts = 0;
  admin.resetOtpSentAt = new Date();
  await admin.save();
  throttle.noteIp(ip);

  let delivered = false;
  if (mailer.isConfigured()) {
    try {
      await mailer.sendMail({
        to: admin.email,
        subject: `Pargig admin password reset code: ${code}`,
        text:
          `Someone asked to reset the password for the Pargig admin\n` +
          `account ${admin.email}.\n\n` +
          `Your code is ${code}\n\n` +
          `It expires in ${RESET_TTL_MINUTES} minutes and can be used once.\n\n` +
          `If this was not you, you do not need to do anything — the code\n` +
          `is useless without access to this mailbox. Your current password\n` +
          `still works and has not been changed.`,
        html:
          `<p>Someone asked to reset the password for the Pargig admin ` +
          `account <strong>${admin.email}</strong>.</p>` +
          `<p style="font-size:26px;letter-spacing:5px;margin:22px 0">` +
          `<strong>${code}</strong></p>` +
          `<p>It expires in ${RESET_TTL_MINUTES} minutes and can be used once.</p>` +
          `<p style="color:#666">If this was not you, you do not need to do ` +
          `anything — the code is useless without access to this mailbox. ` +
          `Your current password still works and has not been changed.</p>`
      });
      delivered = true;
    } catch (err) {
      // Logged, not returned. Which mail server refused and why is
      // operational detail; to the caller it is still "check your
      // inbox", because saying more would confirm the account exists.
      console.error('[admin-reset] mail failed:', err.message);
    }
  }

  const out = { ...neutral };
  if (!delivered && process.env.NODE_ENV !== 'production') {
    // Development only, and only when nothing was sent — the same
    // escape hatch the mobile OTP uses so the flow can be built and
    // tested before a mail server exists.
    out.devCode = code;
    out.note = mailer.isConfigured()
      ? 'Mail send failed; code returned because this is not production.'
      : 'No SMTP configured; code returned because this is not production.';
  }
  res.json(out);
});

/**
 * Step two: the code plus the new password, in one call.
 *
 * One call rather than verify-then-set because an intermediate "this
 * code was correct" token is another credential to issue, carry and
 * expire, and it buys nothing — the form asks for both at once anyway.
 */
const adminResetPassword = asyncHandler(async (req, res) => {
  const Admin = require('../models/adminModel');
  const email = (req.body.email || '').trim().toLowerCase();
  const code = String(req.body.otp || req.body.code || '').trim();
  const password = String(req.body.password || '');

  if (!email || !code) {
    res.status(400);
    throw new Error('Email and code are required');
  }
  if (password.length < ADMIN_MIN_PASSWORD) {
    res.status(400);
    throw new Error(
      `Password must be at least ${ADMIN_MIN_PASSWORD} characters`
    );
  }

  const admin = await Admin.findOne({ email }).select(
    '+resetOtpHash +resetOtpExpiresAt +resetOtpAttempts +resetOtpSentAt'
  );

  // From here on every failure says the same thing. Separating "no
  // such admin" from "wrong code" would turn this into an account
  // lookup for anyone who asks.
  const refuse = () => {
    res.status(400);
    throw new Error('That code is wrong or has expired. Ask for a new one.');
  };

  if (!admin || !admin.isActive || !admin.resetOtpHash) refuse();
  if (!admin.resetOtpExpiresAt || admin.resetOtpExpiresAt < new Date()) {
    admin.resetOtpHash = undefined;
    admin.resetOtpExpiresAt = undefined;
    await admin.save();
    refuse();
  }
  if ((admin.resetOtpAttempts || 0) >= RESET_MAX_ATTEMPTS) {
    // Spent. Destroying it here means the cap cannot be waited out.
    admin.resetOtpHash = undefined;
    admin.resetOtpExpiresAt = undefined;
    await admin.save();
    refuse();
  }

  const crypto = require('crypto');
  const given = Buffer.from(hashCode(code));
  const stored = Buffer.from(admin.resetOtpHash);
  // Constant-time compare. The strings are the same length by
  // construction, so a plain === would leak position-of-first-mismatch
  // through timing; this is cheap enough that there is no reason not to.
  const ok =
    given.length === stored.length && crypto.timingSafeEqual(given, stored);

  if (!ok) {
    admin.resetOtpAttempts = (admin.resetOtpAttempts || 0) + 1;
    await admin.save();
    refuse();
  }

  // Assigned and saved so the model's pre-save hook hashes it. An
  // updateOne here would store the password in plain text.
  admin.password = password;
  admin.resetOtpHash = undefined;
  admin.resetOtpExpiresAt = undefined;
  admin.resetOtpAttempts = 0;
  admin.resetOtpSentAt = undefined;
  await admin.save();

  res.json({
    message: 'Password changed. Sign in with the new one.',
    // Said plainly because it is surprising: tokens are self-contained
    // and are not checked against the password, so a session opened
    // before the reset keeps working until it expires on its own.
    note:
      'Anyone already signed in on the old password stays signed in ' +
      'until their session expires.'
  });
});

module.exports = { requestOtp, verifyOtp, adminLogin, adminForgotPassword, adminResetPassword };
