const Setting = require('../models/settingModel');
const secretBox = require('./secretBox');
const razorpay = require('./razorpay');

/**
 * The live payment gateway configuration.
 *
 * Precedence, highest first:
 *   1. What an admin saved in the panel (Settings -> Payment Gateway)
 *   2. Environment variables, for a deploy that prefers to pin them
 *   3. The built-in stand-in gateway, so a fresh install still works
 *
 * The panel wins over the environment on purpose: the whole point of
 * typing credentials into the panel is that they take effect without a
 * deploy. An env var that silently overrode them would make the Save
 * button a lie.
 */

const CACHE_MS = 30 * 1000;
let cache = null;
let cachedAt = 0;

/** Called after a save so the next payment uses the new keys. */
function invalidate() {
  cache = null;
  cachedAt = 0;
}

function fromEnv() {
  const keyId = process.env.RAZORPAY_KEY_ID || '';
  const keySecret = process.env.RAZORPAY_KEY_SECRET || '';
  if (!keyId || !keySecret) return null;
  return {
    provider: 'razorpay',
    enabled: true,
    source: 'env',
    mode: razorpay.modeOfKeyId(keyId) || 'test',
    keyId,
    keySecret,
    webhookSecret: process.env.RAZORPAY_WEBHOOK_SECRET || '',
  };
}

const DUMMY = {
  provider: 'dummy',
  enabled: true,
  source: 'default',
  mode: 'test',
  keyId: '',
  keySecret: '',
  webhookSecret: '',
};

/**
 * @returns {Promise<{provider:string, enabled:boolean, source:string,
 *   mode:string, keyId:string, keySecret:string, webhookSecret:string}>}
 *
 * Never throws: a database hiccup falls back to the last good config,
 * and failing that to the stand-in. A payment screen that errors is
 * worse than one that cannot take real money yet.
 */
async function getConfig() {
  if (cache && Date.now() - cachedAt < CACHE_MS) return cache;

  let resolved = null;
  try {
    const doc = await Setting.findOne({ key: Setting.PAYMENT_GATEWAY }).lean();
    const v = doc?.value || null;
    if (v && v.provider === 'razorpay') {
      const keySecret = secretBox.decrypt(v.keySecretEnc);
      // Enabled but unusable is the dangerous state: it would send
      // people to a checkout that cannot open. Treat a missing secret
      // as "not configured" and fall through.
      if (v.keyId && keySecret) {
        resolved = {
          provider: 'razorpay',
          enabled: v.enabled !== false,
          source: 'admin',
          mode: v.mode || razorpay.modeOfKeyId(v.keyId) || 'test',
          keyId: v.keyId,
          keySecret,
          webhookSecret: secretBox.decrypt(v.webhookSecretEnc),
        };
      }
    } else if (v && v.provider === 'dummy') {
      resolved = { ...DUMMY, source: 'admin' };
    }
  } catch (_) {
    // Fall through to env / dummy below.
  }

  const config = resolved || fromEnv() || DUMMY;
  // A gateway switched off in the panel still has to leave a working
  // payment path behind it, or every Pay button breaks the moment
  // someone unticks a box.
  const effective = config.enabled === false ? { ...DUMMY, source: 'disabled' } : config;

  cache = effective;
  cachedAt = Date.now();
  return effective;
}

/** True while no real gateway is in play. */
async function isDummy() {
  return (await getConfig()).provider === 'dummy';
}

/**
 * Everything the admin panel may see. Secrets are masked, never
 * returned — an admin who needs the real value has it in their
 * Razorpay dashboard, and the panel is not a place to read it back.
 */
function publicShape(config, raw) {
  // The credential fields come from what is STORED, not from the
  // config in force. On the stand-in the effective config is the
  // stand-in's — no key, no secrets — and reading those would make a
  // saved key pair look lost the moment somebody switched away from
  // Razorpay. The panel has to be able to say "still saved", because
  // that is the whole reason the stand-in keeps them.
  const savedKeyId = raw?.keyId || config.keyId || '';
  const hasSavedSecret = Boolean(raw?.keySecretEnc) || !!config.keySecret;
  const hasSavedHook = Boolean(raw?.webhookSecretEnc) || !!config.webhookSecret;
  return {
    provider: config.provider,
    enabled: config.enabled !== false,
    mode: config.mode,
    source: config.source,
    keyId: savedKeyId,
    keyIdMode: razorpay.modeOfKeyId(savedKeyId),
    hasKeySecret: hasSavedSecret,
    keySecretMasked: secretBox.mask(config.keySecret),
    hasWebhookSecret: hasSavedHook,
    webhookSecretMasked: secretBox.mask(config.webhookSecret),
    canStoreSecrets: secretBox.isConfigured(),
    lastVerifiedAt: raw?.lastVerifiedAt || null,
    lastVerifiedMode: raw?.lastVerifiedMode || null,
    updatedAt: raw?.updatedAt || null,
    updatedByName: raw?.updatedByName || null,
  };
}

module.exports = { getConfig, invalidate, isDummy, publicShape, DUMMY };
