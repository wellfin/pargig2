const Setting = require('../models/settingModel');
const secretBox = require('./secretBox');

/**
 * Where road distances come from.
 *
 * Two providers, and they are genuinely different trades:
 *
 *   OSRM is open, free and needs no account. The public demo server
 *   is the default; it rate-limits and promises nothing about being
 *   up, so the thing to do when it starts mattering is run your own.
 *   One request carries up to ~95 points.
 *
 *   Google Distance Matrix is accurate and knows about traffic and
 *   one-way streets, and it is BILLED PER ELEMENT. One origin against
 *   twenty workers is twenty elements, charged every time a Hire-mode
 *   feed loads. It also caps a request at 25 destinations, so the
 *   same screenful costs several requests where OSRM costs one.
 *
 * Saving a Google key and choosing Google is what switches OSRM off.
 * One provider is in force at a time — there is no silent fallback
 * from one paid service to a free one, because "it got cheaper and
 * less accurate without telling anybody" is a worse failure than a
 * missing number.
 *
 * Precedence is the same as everywhere else in Settings: the panel,
 * then the environment, then the built-in default.
 *
 * Whichever is in force, a provider that cannot be reached falls back
 * to straight-line distance multiplied by a detour factor, so a card
 * always has a plausible road distance rather than a crow-flies one.
 * That factor is editable because the right number for a dense city
 * is not the right number for a district.
 */

const KEY = 'routing';

// Two providers to choose between. The straight-line estimate is
// NOT one of them: it is the safety net underneath both, used
// automatically when the chosen provider cannot answer, so a card
// always carries a plausible road distance. Offering it as a third
// choice made it look like a mode somebody should consider, when it
// is really what happens anyway on a bad day.
const PROVIDERS = ['osrm', 'google'];

const GOOGLE_BASE = 'https://maps.googleapis.com/maps/api/distancematrix/json';

/** Google caps a Distance Matrix request at 25 destinations. */
const GOOGLE_MAX_DESTS = 25;

/**
 * The Distance Matrix endpoint, overridable by environment.
 *
 * Not something an operator would ever change — it exists so the
 * checks can point the client at a local stub and assert which
 * provider was called, which is the whole of what choosing a provider
 * means and is invisible from the returned number. The SMS client has
 * the same seam for the same reason.
 */
const googleBase = () =>
  String(process.env.GOOGLE_DISTANCE_BASE_URL || GOOGLE_BASE).trim();

const DEFAULT_BASE = 'https://router.project-osrm.org';
const DEFAULT_FACTOR = 1.35;

const CACHE_MS = 30 * 1000;
let cache = null;
let cachedAt = 0;

function invalidate() {
  cache = null;
  cachedAt = 0;
}

const clean = (v) => String(v || '').trim();

/** Keeps the factor somewhere defensible: a road is never shorter
 *  than the straight line, and three times is already absurd. */
function saneFactor(v) {
  const n = Number(v);
  if (!Number.isFinite(n)) return DEFAULT_FACTOR;
  return Math.min(3, Math.max(1, n));
}

/** Never throws: a database hiccup falls back to the public server. */
async function getConfig() {
  if (cache && Date.now() - cachedAt < CACHE_MS) return cache;

  let resolved = null;
  try {
    const doc = await Setting.findOne({ key: KEY }).lean();
    const v = doc?.value || null;
    if (v) {
      const googleKey = secretBox.decrypt(v.googleKeyEnc) || '';
      // Google selected with no key is the dangerous half-state: every
      // request comes back REQUEST_DENIED, which looks like an outage
      // rather than a missing key, and every card silently falls back
      // to an estimate. Treat it as OSRM and say so in publicShape.
      // Documents saved under either of the two earlier shapes — an
      // `enabled` tick, or an 'estimate' provider — land on OSRM,
      // which is what a fresh install runs.
      const wanted = PROVIDERS.includes(v.provider) ? v.provider : 'osrm';
      const provider = wanted === 'google' && !googleKey ? 'osrm' : wanted;
      resolved = {
        source: 'admin',
        provider,
        wantedProvider: wanted,
        googleKey,
        googleBaseUrl: googleBase(),
        baseUrl: clean(v.baseUrl || DEFAULT_BASE).replace(/\/+$/, ''),
        detourFactor: saneFactor(v.detourFactor),
        timeoutMs: parseInt(v.timeoutMs, 10) || 4000,
      };
    }
  } catch (_) {
    // Fall through to env / default below.
  }

  const envGoogleKey = clean(process.env.GOOGLE_DISTANCE_API_KEY);
  const config = resolved || {
    source: process.env.OSRM_BASE_URL || envGoogleKey ? 'env' : 'default',
    provider: envGoogleKey ? 'google' : 'osrm',
    wantedProvider: envGoogleKey ? 'google' : 'osrm',
    googleKey: envGoogleKey,
    googleBaseUrl: googleBase(),
    baseUrl: clean(process.env.OSRM_BASE_URL || DEFAULT_BASE).replace(/\/+$/, ''),
    detourFactor: saneFactor(process.env.ROAD_DETOUR_FACTOR || DEFAULT_FACTOR),
    timeoutMs: parseInt(process.env.OSRM_TIMEOUT_MS || '4000', 10),
  };

  cache = config;
  cachedAt = Date.now();
  return config;
}

/** Everything the panel may see. The Google key is masked, never
 *  returned — it is in the Google Cloud console for anyone who needs
 *  it, and this is not a place to read a key back out of. */
async function publicShape(raw) {
  const c = await getConfig();
  const { googleKey, ...rest } = c;
  return {
    ...rest,
    hasGoogleKey: Boolean(googleKey),
    googleKeyMasked: googleKey ? secretBox.mask(googleKey) : '',
    // True when Google was chosen but cannot run for want of a key,
    // so the panel can say that rather than quietly showing 'osrm'.
    googleNeedsKey: c.wantedProvider === 'google' && !googleKey,
    providers: PROVIDERS,
    googleMaxDests: GOOGLE_MAX_DESTS,
    defaultBaseUrl: DEFAULT_BASE,
    defaultDetourFactor: DEFAULT_FACTOR,
    updatedAt: raw?.updatedAt,
    updatedByName: raw?.updatedByName,
  };
}

module.exports = {
  KEY,
  PROVIDERS,
  DEFAULT_BASE,
  DEFAULT_FACTOR,
  GOOGLE_BASE,
  GOOGLE_MAX_DESTS,
  getConfig,
  publicShape,
  invalidate,
  saneFactor,
};
