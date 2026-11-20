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
 *   SMS, from one of two providers: the development code, which is
 *   returned in the sign-in response and sends nothing, or MSG91,
 *   which sends a real message and therefore needs a key and a
 *   template. Choosing MSG91 is what stops the dev code —
 *   authController only echoes a code when nothing was delivered, so
 *   there is no state where both are true. Choosing the dev code
 *   again keeps the credentials.
 *
 *   Road distances, from one of two providers. OSRM needs no account
 *   and the question is only which server; Google Distance Matrix
 *   needs a key and is billed per element. Saving a Google key and
 *   choosing Google is what switches OSRM off.
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
  const provider = req.body.provider === 'msg91' ? 'msg91' : 'dev';

  // Blank means unchanged, so the form does not demand the key back
  // every time somebody edits the sender id — or switches provider
  // and back.
  const authKeyEnc = authKey ? secretBox.encrypt(authKey) : prev.authKeyEnc || '';

  if (authKey && !secretBox.isConfigured()) {
    res.status(500);
    throw new Error(
      'Server cannot store secrets: set SETTINGS_ENCRYPTION_KEY or JWT_SECRET',
    );
  }
  // Both halves or neither, and only when MSG91 is the one chosen.
  // Half-configured is the worst state available: MSG91 accepts the
  // request and rejects it per message, so every user sees a delivery
  // failure while the panel says it is set up.
  if (provider === 'msg91' && !(authKeyEnc && templateId)) {
    res.status(400);
    throw new Error(
      'MSG91 needs both an auth key and a template id. With only one, '
      + 'every message is rejected and it looks like a delivery fault.',
    );
  }

  const value = {
    provider,
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
    throw new Error(
      'Choose MSG91 as the provider and save an auth key and template id '
      + 'first — on the development code there is nothing to send with.',
    );
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
  const existing = await Setting.findOne({ key: routingConfig.KEY });
  const prev = existing?.value || {};

  const baseUrl = String(req.body.baseUrl || routingConfig.DEFAULT_BASE).trim();
  if (!/^https?:\/\/[^\s]+$/i.test(baseUrl)) {
    res.status(400);
    throw new Error('The OSRM address has to be a URL starting http:// or https://');
  }

  const provider = routingConfig.PROVIDERS.includes(req.body.provider)
    ? req.body.provider
    : 'osrm';

  // Blank means unchanged, so switching provider back and forth does
  // not demand the key again.
  const googleKey = String(req.body.googleKey || '').trim();
  const googleKeyEnc = googleKey
    ? secretBox.encrypt(googleKey)
    : prev.googleKeyEnc || '';

  if (googleKey && !secretBox.isConfigured()) {
    res.status(500);
    throw new Error(
      'Server cannot store secrets: set SETTINGS_ENCRYPTION_KEY or JWT_SECRET',
    );
  }
  // Choosing Google without a key would read as switched-on while
  // every request came back REQUEST_DENIED and every card quietly
  // showed an estimate. Refuse it here rather than let it look live.
  if (provider === 'google' && !googleKeyEnc) {
    res.status(400);
    throw new Error(
      'Google Distance Matrix needs an API key. Without one every '
      + 'request is denied and distances fall back to an estimate.',
    );
  }

  const value = {
    provider,
    googleKeyEnc,
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
 * Asks whichever provider is in force for one real distance between
 * two points in Delhi, and reports which one answered. A reachable
 * provider that cannot route is a different problem from an
 * unreachable one, and the panel should be able to tell them apart.
 *
 * On Google this costs one element, which is the point: a test that
 * does not spend anything would not prove the billing is on, and
 * billing is the usual reason a key that looks right still fails.
 */
const testRoutingSettings = asyncHandler(async (req, res) => {
  const { roadDistancesKm } = require('../utils/routing');
  const cfg = await routingConfig.getConfig();
  const started = Date.now();
  const out = await roadDistancesKm([
    { lat: 28.6139, lng: 77.2090 },
    { lat: 28.5355, lng: 77.3910 },
  ]);
  const km = out?.kms?.[0];
  const ms = Date.now() - started;
  const who = cfg.provider === 'google' ? 'Google' : 'OSRM';

  if (km == null) {
    res.status(502);
    throw new Error(
      `${who} did not return a route in ${ms}ms. Distances fall back to `
      + 'the straight-line estimate until this works. The server log has '
      + "the provider's own reason.",
    );
  }
  res.json({
    ok: true,
    provider: cfg.provider,
    km: Math.round(km * 10) / 10,
    ms,
    message: `${who} answered in ${ms}ms with ${Math.round(km)} km for a known route.`,
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
