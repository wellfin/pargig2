// Road-distance helpers used by the Hire-mode Nearby Workers feed.
//
// One provider is in force, chosen in Settings -> Third party:
//
//   OSRM Table API — free, no key, ~95 points per request. The
//     public demo server by default; see utils/routingConfig.js.
//   Google Distance Matrix — a key, billed per element, 25
//     destinations per request so a screenful is several calls.
//
// Whichever it is, a provider that cannot answer falls back to
// haversine × the detour factor, so the mobile card always has a
// plausible road distance rather than an obviously short crow-flies
// one. That fallback is marked distanceSource: 'estimated', so a
// degraded number is never mistaken for a measured one.

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
  // The estimate is a provider, so choosing it means no request goes
  // out at all. The point of it is a bad day at the routing end, so
  // it has to stop the call rather than only ignore the answer.
  if (cfg.provider === 'estimate') return fallback();

  // One provider, not a chain. A paid service quietly degrading to a
  // free one would change both the bill and the numbers with nothing
  // saying so; the caller falls back to the straight-line estimate
  // instead, which is visible as distanceSource: 'estimated'.
  const provider = cfg.provider === 'google' ? 'google' : 'osrm';
  const kms = provider === 'google'
    ? await _googleMatrix(origin, dests, cfg)
    : await _osrmTable(origin, dests, cfg);

  if (kms) {
    return {
      kms,
      sources: kms.map((v) => (v == null ? null : provider)),
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

/**
 * Google Distance Matrix.
 *
 * Chunked, because Google caps a request at 25 destinations where
 * OSRM takes about 95 — so one screenful of workers is several
 * requests here and one there. The chunks go out together rather than
 * in sequence: the caller is a feed somebody is waiting on, and three
 * round trips end to end is three times the wait for no reason.
 *
 * Each chunk is independent. One failing leaves the others' numbers
 * in place and only its own destinations null, which the caller shows
 * as an estimate — better than throwing away a screenful because the
 * third request timed out.
 *
 * Google answers 200 with a status field for most of what actually
 * goes wrong — REQUEST_DENIED for a bad or unenabled key,
 * OVER_QUERY_LIMIT for billing. The HTTP status alone is not the
 * verdict, so the body is read every time.
 */
async function _googleMatrix(origin, dests, cfg) {
  const size = routingConfig.GOOGLE_MAX_DESTS;
  const chunks = [];
  for (let i = 0; i < dests.length; i += size) {
    chunks.push({ at: i, points: dests.slice(i, i + size) });
  }

  const results = await Promise.all(
    chunks.map((chunk) => _googleChunk(origin, chunk.points, cfg)),
  );

  // A chunk that failed contributes nulls rather than collapsing the
  // whole answer.
  if (results.every((r) => r === null)) return null;

  const out = new Array(dests.length).fill(null);
  chunks.forEach((chunk, ci) => {
    const got = results[ci];
    if (!got) return;
    got.forEach((km, i) => {
      out[chunk.at + i] = km;
    });
  });
  return out;
}

async function _googleChunk(origin, dests, cfg) {
  const params = new URLSearchParams({
    origins: `${origin.lat},${origin.lng}`,
    destinations: dests.map((p) => `${p.lat},${p.lng}`).join('|'),
    // Road distance for a vehicle, which is what the card claims to
    // be showing.
    mode: 'driving',
    units: 'metric',
    key: cfg.googleKey,
  });

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), cfg.timeoutMs || 4000);
  try {
    const base = cfg.googleBaseUrl || routingConfig.GOOGLE_BASE;
    const r = await fetch(`${base}?${params.toString()}`, {
      signal: controller.signal,
    });
    const data = await r.json().catch(() => null);

    const top = String(data?.status || '').toUpperCase();
    if (!r.ok || top !== 'OK') {
      // error_message is where Google says the useful part — "this API
      // project is not authorized", "billing not enabled".
      console.warn(
        `[routing] Google ${top || r.status}:`,
        data?.error_message || 'no detail',
      );
      return null;
    }

    const elements = data?.rows?.[0]?.elements;
    if (!Array.isArray(elements)) {
      console.warn('[routing] Google response missing the elements row');
      return null;
    }

    return dests.map((_, i) => {
      const el = elements[i];
      // ZERO_RESULTS is a real answer: there is no driving route. It
      // is a null for that worker, not a failure of the request.
      if (!el || String(el.status).toUpperCase() !== 'OK') return null;
      const meters = el.distance?.value;
      return typeof meters === 'number' ? meters / 1000 : null;
    });
  } catch (e) {
    console.warn(
      '[routing] Google call failed:',
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
