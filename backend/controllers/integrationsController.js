const asyncHandler = require('express-async-handler');
const Setting = require('../models/settingModel');
const secretBox = require('../utils/secretBox');
const smsConfig = require('../utils/smsConfig');
const routingConfig = require('../utils/routingConfig');
const sms = require('../utils/sms');

/**
 * The third-party services this install depends on, other than the
 * payment gateway — which has its own controller because its stakes
 * are different and its form is twice the size.
 *
 * Two of them here:
 *
 *   MSG91, which carries login OTPs. Saving a key is what switches
 *   real SMS on, and the same act switches off the development code
 *   that comes back in the response — authController only echoes a
 *   code when nothing was delivered, so there is no second toggle to
 *   remember and no state where both are true.
 *
 *   OSRM, which measures road distances. No key, no account: what is
 *   configurable is which server, because the public one is a demo
 *   and the answer when it starts rate-limiting is to run your own.
 *
 * Secrets are encrypted before they are stored and are never sent
 * back, only masked. A blank secret in an update means "leave it
 * alone", never "clear it" — a form that silently wipes a credential
 * it could not show you is a trap.
 */

// ------------------------------------------------------------- MSG91

/** GET /api/admin/settings/sms */
const getSmsSettings = asyncHandler(async (req, res) => {
  const doc = await Setting.findOne({ key: smsConfig.KEY }).lean();
  res.json({
    ...(await smsConfig.publicShape(doc)),
    defaultBaseUrl: smsConfig.DEFAULT_BASE,
    // So the panel can say plainly what saving will do, rather than
    // leaving somebody to discover it.
    devCodeInUse: !(await smsConfig.isConfigured()),
  });
});

/** PUT /api/admin/settings/sms */
const updateSmsSettings = asyncHandler(async (req, res) => {
  const existing = await Setting.findOne({ key: smsConfig.KEY });
  const prev = existing?.value || {};

  const templateId = String(req.body.templateId || '').trim();
  const authKey = String(req.body.authKey || '').trim();
  const enabled = req.body.enabled !== false;

  // Blank means unchanged, so the form does not demand the key back
  // every time somebody edits the sender id.
  const authKeyEnc = authKey ? secretBox.encrypt(authKey) : prev.authKeyEnc || '';

  // Both halves or neither. Half-configured is the worst state: MSG91
  // accepts the request and rejects it per message, so every user sees
  // a delivery failure while the panel says it is set up.
  if (enabled && (authKeyEnc || templateId) && !(authKeyEnc && templateId)) {
    res.status(400);
    throw new Error(
      'MSG91 needs both the auth key and the template id. With only one, '
      + 'every message is rejected and it looks like a delivery fault.',
    );
  }
  if (authKey && !secretBox.isConfigured()) {
    res.status(500);
    throw new Error(
      'Server cannot store secrets: set SETTINGS_ENCRYPTION_KEY or JWT_SECRET',
    );
  }

  const value = {
    enabled,
    authKeyEnc,
    templateId,
    senderId: String(req.body.senderId || '').trim(),
    countryCode: String(req.body.countryCode || '91').replace(/\D/g, '') || '91',
    baseUrl: String(req.body.baseUrl || smsConfig.DEFAULT_BASE).trim(),
    timeoutMs: parseInt(req.body.timeoutMs, 10) || 12000,
  };

  const doc = await Setting.findOneAndUpdate(
    { key: smsConfig.KEY },
    {
      key: smsConfig.KEY,
      value,
      updatedBy: req.admin?._id,
      updatedByName: req.admin?.name,
    },
    { upsert: true, returnDocument: 'after' },
  ).lean();

  smsConfig.invalidate();

  res.json({
    ...(await smsConfig.publicShape(doc)),
    defaultBaseUrl: smsConfig.DEFAULT_BASE,
    devCodeInUse: !(await smsConfig.isConfigured()),
  });
});

/**
 * POST /api/admin/settings/sms/test
 *
 * Sends one real OTP-shaped message to a number the admin names.
 * Real, because the only question worth answering here is whether a
 * handset rings — a dry run that checks the key is well-formed proves
 * nothing about the DLT template, the sender id or the balance, which
 * is where this actually goes wrong.
 */
const testSmsSettings = asyncHandler(async (req, res) => {
  const mobile = String(req.body.mobile || '').replace(/\D/g, '');
  if (mobile.length < 10) {
    res.status(400);
    throw new Error('Give a mobile number to send the test to');
  }
  if (!(await smsConfig.isConfigured())) {
    res.status(400);
    throw new Error('Save an auth key and template id first');
  }

  const code = String(Math.floor(1000 + Math.random() * 9000));
  try {
    const out = await sms.sendOtp({ mobile, otp: code, ttlSeconds: 300 });
    res.json({
      ok: true,
      message:
        `Sent to ${mobile}. If it does not arrive, the key is fine and the `
        + 'problem is the template, the sender id or the balance.',
      requestId: out?.requestId || null,
    });
  } catch (err) {
    // MSG91's own wording is what whoever is reading this needs — it
    // names the DLT whitelist, the template, the balance.
    res.status(502);
    throw new Error(`MSG91 refused it: ${err.message}`);
  }
});

// -------------------------------------------------------------- OSRM

/** GET /api/admin/settings/routing */
const getRoutingSettings = asyncHandler(async (req, res) => {
  const doc = await Setting.findOne({ key: routingConfig.KEY }).lean();
  res.json(await routingConfig.publicShape(doc));
});

/** PUT /api/admin/settings/routing */
const updateRoutingSettings = asyncHandler(async (req, res) => {
  const baseUrl = String(req.body.baseUrl || routingConfig.DEFAULT_BASE).trim();
  if (!/^https?:\/\/[^\s]+$/i.test(baseUrl)) {
    res.status(400);
    throw new Error('The OSRM address has to be a URL starting http:// or https://');
  }

  const value = {
    enabled: req.body.enabled !== false,
    baseUrl,
    detourFactor: routingConfig.saneFactor(req.body.detourFactor),
    timeoutMs: parseInt(req.body.timeoutMs, 10) || 4000,
  };

  const doc = await Setting.findOneAndUpdate(
    { key: routingConfig.KEY },
    {
      key: routingConfig.KEY,
      value,
      updatedBy: req.admin?._id,
      updatedByName: req.admin?.name,
    },
    { upsert: true, returnDocument: 'after' },
  ).lean();

  routingConfig.invalidate();
  res.json(await routingConfig.publicShape(doc));
});

/**
 * POST /api/admin/settings/routing/test
 *
 * Asks the configured server for one real distance between two
 * points in Delhi. A reachable server that cannot route is a
 * different problem from an unreachable one, and the panel should be
 * able to tell them apart.
 */
const testRoutingSettings = asyncHandler(async (req, res) => {
  const { roadDistancesKm } = require('../utils/routing');
  const started = Date.now();
  const out = await roadDistancesKm([
    { lat: 28.6139, lng: 77.2090 },
    { lat: 28.5355, lng: 77.3910 },
  ]);
  const km = out?.kms?.[0];
  const ms = Date.now() - started;

  if (km == null) {
    res.status(502);
    throw new Error(
      `No route came back in ${ms}ms. Distances will fall back to the `
      + 'straight-line estimate until this is reachable.',
    );
  }
  res.json({
    ok: true,
    km: Math.round(km * 10) / 10,
    ms,
    message: `Answered in ${ms}ms with ${Math.round(km)} km for a known route.`,
  });
});

module.exports = {
  getSmsSettings,
  updateSmsSettings,
  testSmsSettings,
  getRoutingSettings,
  updateRoutingSettings,
  testRoutingSettings,
};
