const Setting = require('../models/settingModel');
const secretBox = require('./secretBox');

/**
 * The live MSG91 configuration.
 *
 * Precedence, highest first:
 *   1. What a superadmin saved in the panel (Settings -> Third party)
 *   2. Environment variables, for a deploy that prefers to pin them
 *   3. Nothing — and "nothing" is a working state, not a broken one
 *
 * The panel wins over the environment for the same reason it does for
 * the payment gateway: the point of typing a key into the panel is
 * that it takes effect without a deploy, and an env var that silently
 * overrode it would make the Save button a lie.
 *
 * This file exists because sms.js used to read process.env directly
 * and said so in a comment: "an SMS key is set once per deployment
 * and changing it is a server job". That turned out to be the wrong
 * call for this deployment — getting into the server to switch SMS on
 * is a bottleneck, and the owner is the person who holds the MSG91
 * account.
 *
 * TWO PROVIDERS, chosen in the panel, the same shape as the distance
 * settings:
 *
 *   dev   — nothing is sent. The OTP is generated and stored exactly
 *           as it would be, and the code comes back in the sign-in
 *           response so development can carry on. This is what a
 *           fresh install runs.
 *   msg91 — real messages, which needs an auth key and a template id.
 *
 * Choosing msg91 is what stops the dev code: authController only
 * echoes a code when nothing was delivered, so the two can never both
 * be true. Choosing dev again keeps the credentials — it is the
 * switch for a bad day at MSG91, not a way of deleting a key you will
 * want back in an hour.
 */

const DEFAULT_BASE = 'https://control.msg91.com/api/v5';

const KEY = 'sms_gateway';

// Read on every OTP request, so it is cached rather than fetched each
// time. Saving invalidates it immediately in this process; the TTL is
// what catches a second process on the same database.
const CACHE_MS = 30 * 1000;
let cache = null;
let cachedAt = 0;

function invalidate() {
  cache = null;
  cachedAt = 0;
}

const clean = (v) => String(v || '').trim();

function fromEnv() {
  const authKey = clean(process.env.MSG91_AUTH_KEY);
  const templateId = clean(process.env.MSG91_TEMPLATE_ID);
  if (!authKey || !templateId) return null;
  return {
    source: 'env',
    provider: 'msg91',
    authKey,
    templateId,
    senderId: clean(process.env.MSG91_SENDER_ID),
    countryCode: clean(process.env.MSG91_COUNTRY_CODE || '91').replace(/\D/g, '') || '91',
    baseUrl: clean(process.env.MSG91_BASE_URL || DEFAULT_BASE).replace(/\/+$/, ''),
    timeoutMs: parseInt(process.env.MSG91_TIMEOUT_MS || '12000', 10),
  };
}

const NONE = {
  source: 'none',
  provider: 'dev',
  authKey: '',
  templateId: '',
  senderId: '',
  countryCode: '91',
  baseUrl: DEFAULT_BASE,
  timeoutMs: 12000,
};

/**
 * Never throws. A database hiccup falls back to the environment and
 * then to "not configured", which still logs people in via the dev
 * code rather than failing every sign-in.
 */
async function getConfig() {
  if (cache && Date.now() - cachedAt < CACHE_MS) return cache;

  let resolved = null;
  try {
    const doc = await Setting.findOne({ key: KEY }).lean();
    const v = doc?.value || null;
    if (v) {
      const authKey = secretBox.decrypt(v.authKeyEnc) || '';
      // `enabled` is what the field was called before there was a
      // provider to choose; a document saved then means the same
      // thing by it.
      const provider = v.provider
        ? (v.provider === 'msg91' ? 'msg91' : 'dev')
        : (v.enabled === false ? 'dev' : 'msg91');
      // A template id without a key, or the other way round, reaches
      // MSG91 and is rejected per message — which costs nothing but
      // looks like a delivery failure to every single user. Treat a
      // half-filled form as not configured and fall through.
      if (authKey && clean(v.templateId)) {
        resolved = {
          source: 'admin',
          provider,
          authKey,
          templateId: clean(v.templateId),
          senderId: clean(v.senderId),
          countryCode: clean(v.countryCode || '91').replace(/\D/g, '') || '91',
          baseUrl: clean(v.baseUrl || DEFAULT_BASE).replace(/\/+$/, ''),
          timeoutMs: parseInt(v.timeoutMs, 10) || 12000,
        };
      }
    }
  } catch (_) {
    // Fall through to env / none below.
  }

  const config = resolved || fromEnv() || NONE;
  // Nothing is collapsed on 'dev'. The credentials stay in the
  // resolved config, unused, so the panel can still show the saved
  // template id and masked key — switching back must not mean typing
  // them in again. isConfigured() is what reads the provider.
  const effective = config;

  cache = effective;
  cachedAt = Date.now();
  return effective;
}

/**
 * Will a real message be sent?
 *
 * Three things, all required: msg91 is the chosen provider, and both
 * halves of the credential are present. On 'dev' the credentials may
 * well be sitting there — that is the point of the switch — so the
 * provider has to be part of the question.
 */
async function isConfigured() {
  const c = await getConfig();
  return c.provider === 'msg91' && Boolean(c.authKey && c.templateId);
}

/**
 * Everything the panel may see. The auth key is masked, never
 * returned — an admin who needs it has it in their MSG91 dashboard,
 * and this is not a place to read a key back out of.
 */
async function publicShape(raw) {
  const c = await getConfig();
  return {
    provider: c.provider,
    providers: ['dev', 'msg91'],
    configured: c.provider === 'msg91' && Boolean(c.authKey && c.templateId),
    source: c.source,
    // The saved key survives a switch to dev, so the panel can say so
    // instead of looking as though it was lost.
    hasAuthKey: Boolean(c.authKey || c.savedKey),
    authKeyMasked: secretBox.mask(c.authKey || c.savedKey || '') || '',
    templateId: c.templateId,
    senderId: c.senderId,
    countryCode: c.countryCode,
    baseUrl: c.baseUrl,
    updatedAt: raw?.updatedAt,
    updatedByName: raw?.updatedByName,
  };
}

module.exports = {
  KEY,
  DEFAULT_BASE,
  getConfig,
  isConfigured,
  publicShape,
  invalidate,
};
