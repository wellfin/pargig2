// Road-distance helpers used by the Hire-mode Nearby Workers feed.
//
// Distance source priority:
//   1. OSRM Table API — free, no key. Override the host with
//      OSRM_BASE_URL for self-hosted (router.project-osrm.org is the
//      default public endpoint).
//   2. Haversine × ROAD_DETOUR_FACTOR — straight-line × 1.35. Used
//      only when OSRM is unreachable, so the mobile card always has
//      a "reasonable road distance" to show instead of falling back
//      to crow-flies.

// Both of these now come from utils/routingConfig, which reads what a
// superadmin saved in Settings -> Third party and falls back to the
// environment and then to these. They are kept as the last-resort
// constants rather than as the source of truth.
const routingConfig = require('./routingConfig');

const ROAD_DETOUR_FACTOR = routingConfig.DEFAULT_FACTOR;

// `points` shape: [{ lat, lng }, ...]; element 0 is the origin. The
// returned array has one entry per destination (points[1..]). Each
// entry is the road-driving distance in KM, or null when OSRM
// couldn't resolve a route for that pair.
//
// Returns { kms, sources } — sources[i] is 'osrm' or null, so the
// caller can attach distanceSource per-worker for the mobile UI.
async function roadDistancesKm(points) {
  const dests = points.slice(1);
  if (dests.length === 0) return { kms: [], sources: [] };
  const origin = points[0];
  const fallback = () => ({
    kms: dests.map(() => null),
    sources: dests.map(() => null),
  });
  if (!origin || typeof origin.lat !== 'number' ||
      typeof origin.lng !== 'number') {
    return fallback();
  }

  const cfg = await routingConfig.getConfig();
  // Switched off in the panel means every pair falls back to the
  // straight-line estimate, without a request going out. The point of
  // the switch is a bad day at the OSRM end, so it has to stop the
  // call rather than only ignore the answer.
  if (!cfg.enabled) return fallback();

  const osrm = await _osrmTable(origin, dests, cfg);
  if (osrm) {
    return {
      kms: osrm,
      sources: osrm.map((v) => v == null ? null : 'osrm'),
    };
  }
  return fallback();
}

async function _osrmTable(origin, dests, cfg) {
  const points = [origin, ...dests];
  // OSRM public server caps at 100 coords / request — slice to be safe.
  const sliced = points.slice(0, 95);
  const csv = sliced
    .map((p) => `${p.lng},${p.lat}`)
    .join(';');
  const url =
    `${cfg.baseUrl}/table/v1/driving/${csv}?sources=0&annotations=distance`;

  // AbortController + setTimeout works on Node 16+; AbortSignal.timeout
  // is only Node 17.3+, so prefer the wider-compat form.
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), cfg.timeoutMs || 8000);
  try {
    const r = await fetch(url, { signal: controller.signal });
    if (!r.ok) {
      console.warn(`[routing] OSRM ${r.status} for ${dests.length} dest(s)`);
      return null;
    }
    const data = await r.json();
    const row = Array.isArray(data && data.distances) ? data.distances[0] : null;
    if (!Array.isArray(row)) {
      console.warn('[routing] OSRM response missing distances row');
      return null;
    }
    return dests.map((_, i) => {
      const meters = row[i + 1];
      if (typeof meters !== 'number') return null;
      return meters / 1000;
    });
  } catch (e) {
    console.warn(
      '[routing] OSRM call failed:',
      e && e.name === 'AbortError' ? 'timeout' : (e && e.message) || e,
    );
    return null;
  } finally {
    clearTimeout(timer);
  }
}

// Great-circle distance between two lat/lng points, in KM.
function haversineKm(aLat, aLng, bLat, bLng) {
  const toRad = (v) => (v * Math.PI) / 180;
  const R = 6371;
  const dLat = toRad(bLat - aLat);
  const dLng = toRad(bLng - aLng);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(aLat)) * Math.cos(toRad(bLat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

// Estimate of road-driving distance based on the haversine. Used
// when OSRM is unreachable so the mobile card still shows a number
// that's roughly road-realistic rather than the obviously-short
// crow-flies.
//
// The factor is a parameter with a default rather than an await,
// because this is called inside a per-worker loop that is otherwise
// synchronous. Callers that already hold the config pass it; the rest
// get the built-in, which is what the constant was before any of this
// was configurable.
function estimatedRoadKm(aLat, aLng, bLat, bLng, factor = ROAD_DETOUR_FACTOR) {
  return haversineKm(aLat, aLng, bLat, bLng) * factor;
}

/** The detour factor in force, for a caller looping synchronously. */
async function detourFactor() {
  return (await routingConfig.getConfig()).detourFactor;
}

module.exports = {
  roadDistancesKm,
  haversineKm,
  estimatedRoadKm,
  detourFactor,
};
