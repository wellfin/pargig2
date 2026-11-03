const asyncHandler = require('express-async-handler');
const User = require('../models/userModel');
const generateToken = require('../utils/generateToken');
const { generateOtp, otpExpiry } = require('../utils/otp');
const sms = require('../utils/sms');
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
  const ip = throttle.clientIp(req);
  const byIp = throttle.checkIp(ip);
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
  const byMobile = throttle.checkMobile(user);
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
  if (sms.isConfigured()) {
    try {
      const sent = await sms.sendOtp({ mobile, otp: code, ttlSeconds: ttl });
      requestId = sent.requestId;
      delivered = true;
    } catch (err) {
      sendError = err;
      console.error('[otp] MSG91 send failed for', mobile, '-', err.message);
    }
  }

  if (delivered || !sms.isConfigured()) {
    user.otp = { code, expiresAt: otpExpiry(), attempts: 0, requestId };
  }
  // The cooldown applies either way — a gateway that is failing should
  // not be hammered — but a message nobody received does not come out
  // of the user's daily allowance.
  throttle.noteSent(user, { delivered: delivered || !sms.isConfigured() });
  await user.save();
  throttle.noteIp(ip);

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

module.exports = { requestOtp, verifyOtp, adminLogin };
