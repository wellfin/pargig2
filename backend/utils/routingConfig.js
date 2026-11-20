const Setting = require('../models/settingModel');

/**
 * Where road distances come from.
 *
 * There is no API key here, and that is worth saying plainly because
 * it is the usual assumption: distances are measured by OSRM, which
 * is open and free and needs no account. What is configurable is
 * WHICH OSRM — the public demo server by default, or a self-hosted
 * one, which is the thing to move to when the demo server starts
 * rate-limiting or going away at the wrong moment.
 *
 * Precedence is the same as everywhere else in Settings: the panel,
 * then the environment, then the built-in default.
 *
 * When OSRM cannot be reached the caller falls back to straight-line
 * distance multiplied by a detour factor, so a card always has a
 * plausible road distance rather than a crow-flies one. That factor
 * is editable too, because the right number for a dense city is not
 * the right number for a district.
 */

const KEY = 'routing';

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
      resolved = {
        source: 'admin',
        enabled: v.enabled !== false,
        baseUrl: clean(v.baseUrl || DEFAULT_BASE).replace(/\/+$/, ''),
        detourFactor: saneFactor(v.detourFactor),
        timeoutMs: parseInt(v.timeoutMs, 10) || 4000,
      };
    }
  } catch (_) {
    // Fall through to env / default below.
  }

  const config = resolved || {
    source: process.env.OSRM_BASE_URL ? 'env' : 'default',
    enabled: true,
    baseUrl: clean(process.env.OSRM_BASE_URL || DEFAULT_BASE).replace(/\/+$/, ''),
    detourFactor: saneFactor(process.env.ROAD_DETOUR_FACTOR || DEFAULT_FACTOR),
    timeoutMs: parseInt(process.env.OSRM_TIMEOUT_MS || '4000', 10),
  };

  cache = config;
  cachedAt = Date.now();
  return config;
}

/** Everything the panel may see. Nothing here is secret. */
async function publicShape(raw) {
  const c = await getConfig();
  return {
    ...c,
    defaultBaseUrl: DEFAULT_BASE,
    defaultDetourFactor: DEFAULT_FACTOR,
    updatedAt: raw?.updatedAt,
    updatedByName: raw?.updatedByName,
  };
}

module.exports = {
  KEY,
  DEFAULT_BASE,
  DEFAULT_FACTOR,
  getConfig,
  publicShape,
  invalidate,
  saneFactor,
};
