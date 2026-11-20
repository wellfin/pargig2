const asyncHandler = require('express-async-handler');
const Setting = require('../models/settingModel');
const secretBox = require('../utils/secretBox');
const gatewayConfig = require('../utils/gatewayConfig');
const razorpay = require('../utils/razorpay');

/**
 * Payment gateway settings, as typed into the admin panel.
 *
 * Razorpay hands over a key id, a key secret and (once a webhook is
 * added) a webhook secret. Those three strings are all that stand
 * between this install and live card payments, so:
 *
 *   - the secrets are encrypted before they are stored
 *   - they are never sent back to the browser, only masked
 *   - a blank secret in an update means "leave it alone", never "clear
 *     it", because a form that silently wipes a credential it couldn't
 *     show you is a trap
 */

const KEY = Setting.PAYMENT_GATEWAY;

/** GET /api/admin/settings/payment */
const getPaymentSettings = asyncHandler(async (req, res) => {
  const doc = await Setting.findOne({ key: KEY }).lean();
  const config = await gatewayConfig.getConfig();
  res.json({
    ...gatewayConfig.publicShape(config, {
      ...(doc?.value || {}),
      updatedAt: doc?.updatedAt,
      updatedByName: doc?.updatedByName,
    }),
    // Pasted into the Razorpay dashboard when adding the webhook.
    // Built from the request so it is right whether the panel is open
    // on the IP, a domain, or behind a proxy.
    webhookUrl: `${publicOrigin(req)}/api/payments/webhook/razorpay`,
    // Which events the webhook should subscribe to, so nobody has to
    // guess in the dashboard.
    webhookEvents: ['payment.captured', 'payment.failed', 'refund.processed'],
  });
});

/**
 * PUT /api/admin/settings/payment
 *
 * THE KEY IS THE SWITCH. There is no provider to choose: a Key ID
 * saved here means Razorpay, and clearing it means the built-in
 * stand-in. That is more honest than a dropdown, because the key
 * already decides what happens — rzp_live_ charges real cards
 * whatever a label beside it says, which is a second truth that can
 * disagree with the first.
 *
 * Clearing the Key ID is the deliberate way back to the stand-in and
 * it removes the stored secrets with it. There is also an `enabled`
 * tick, which keeps the credentials but runs the stand-in — that is
 * what to reach for during an outage, rather than deleting keys you
 * will want back in an hour.
 */
const updatePaymentSettings = asyncHandler(async (req, res) => {
  const existing = await Setting.findOne({ key: KEY });
  const prev = existing?.value || {};

  // Blank Key ID means "no gateway". Undefined means "unchanged", so
  // a form that does not send the field cannot wipe a live gateway by
  // omission.
  const rawKeyId = req.body.keyId;
  const keyIdGiven = rawKeyId !== undefined;
  const keyId = String(rawKeyId ?? prev.keyId ?? '').trim();
  const provider = keyId ? 'razorpay' : 'dummy';

  const value = { provider, enabled: req.body.enabled !== false };

  // Clearing it takes the secrets with it. Leaving an encrypted
  // secret behind for a key that is gone is a credential nobody is
  // watching any more.
  if (keyIdGiven && !keyId) {
    value.keyId = '';
    value.keySecretEnc = '';
    value.webhookSecretEnc = '';
    value.mode = 'test';
    value.lastVerifiedAt = null;
    value.lastVerifiedMode = null;
  }

  if (provider === 'razorpay') {
    if (!secretBox.isConfigured()) {
      res.status(500);
      throw new Error(
        'Server cannot store secrets: set SETTINGS_ENCRYPTION_KEY or JWT_SECRET',
      );
    }
    if (!/^rzp_(test|live)_[A-Za-z0-9]+$/.test(keyId)) {
      res.status(400);
      throw new Error(
        'That does not look like a Razorpay Key ID — it starts with rzp_test_ or rzp_live_',
      );
    }

    // Blank means unchanged. The form cannot show the saved secret, so
    // it cannot ask the admin to retype it every time they flip a
    // toggle.
    const keySecret = String(req.body.keySecret || '').trim();
    const webhookSecret = String(req.body.webhookSecret ?? '').trim();

    value.keyId = keyId;
    value.keySecretEnc = keySecret
      ? secretBox.encrypt(keySecret)
      : prev.keySecretEnc || '';
    if (!value.keySecretEnc) {
      res.status(400);
      throw new Error('Key Secret is required');
    }

    // The webhook secret is optional — payments work without it, only
    // the out-of-band confirmations don't. An explicit null clears it.
    if (req.body.webhookSecret === null) {
      value.webhookSecretEnc = '';
    } else {
      value.webhookSecretEnc = webhookSecret
        ? secretBox.encrypt(webhookSecret)
        : prev.webhookSecretEnc || '';
    }

    // The key id itself says whether it is a test or live credential,
    // and it outranks the dropdown: a live key in "test mode" charges
    // real cards whatever the label says.
    value.mode = razorpay.modeOfKeyId(keyId) || 'test';
    value.lastVerifiedAt = prev.lastVerifiedAt || null;
    value.lastVerifiedMode = prev.lastVerifiedMode || null;
    // A changed key pair has not been verified yet.
    if (keySecret || keyId !== prev.keyId) {
      value.lastVerifiedAt = null;
      value.lastVerifiedMode = null;
    }
  }

  const doc = await Setting.findOneAndUpdate(
    { key: KEY },
    {
      key: KEY,
      value,
      updatedBy: req.admin?._id,
      updatedByName: req.admin?.name || req.admin?.email || 'Admin',
    },
    { new: true, upsert: true },
  );
  gatewayConfig.invalidate();

  const config = await gatewayConfig.getConfig();
  res.json({
    ok: true,
    ...gatewayConfig.publicShape(config, {
      ...doc.value,
      updatedAt: doc.updatedAt,
      updatedByName: doc.updatedByName,
    }),
    webhookUrl: `${publicOrigin(req)}/api/payments/webhook/razorpay`,
  });
});

/**
 * POST /api/admin/settings/payment/test
 *
 * Asks Razorpay whether the saved credentials work. Tests what is
 * stored, not what is on screen, so a green tick means payments will
 * actually go through — not that the typing was correct.
 */
const testPaymentSettings = asyncHandler(async (req, res) => {
  const config = await gatewayConfig.getConfig();
  if (config.provider !== 'razorpay') {
    res.status(400);
    throw new Error(
      config.source === 'disabled'
        ? 'Gateway is saved but switched off — enable it first'
        : 'No Razorpay credentials saved yet',
    );
  }
  try {
    await razorpay.verifyCredentials({ creds: config });
  } catch (err) {
    res.status(400);
    throw new Error(err.message || 'Razorpay rejected these credentials');
  }

  await Setting.updateOne(
    { key: KEY },
    {
      $set: {
        'value.lastVerifiedAt': new Date(),
        'value.lastVerifiedMode': config.mode,
      },
    },
  );
  gatewayConfig.invalidate();

  res.json({
    ok: true,
    mode: config.mode,
    keyId: config.keyId,
    message:
      config.mode === 'live'
        ? 'Live credentials verified — real payments are enabled'
        : 'Test credentials verified — use Razorpay test cards',
  });
});

/**
 * The origin a browser or a phone would use to reach this server.
 * Honours the proxy headers nginx sets, because the server itself only
 * ever sees http on a private port.
 */
function publicOrigin(req) {
  const proto = (req.headers['x-forwarded-proto'] || req.protocol || 'http')
    .split(',')[0]
    .trim();
  const host = (req.headers['x-forwarded-host'] || req.get('host') || '')
    .split(',')[0]
    .trim();
  return `${proto}://${host}`;
}

module.exports = {
  getPaymentSettings,
  updatePaymentSettings,
  testPaymentSettings,
};
