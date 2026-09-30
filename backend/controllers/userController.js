const asyncHandler = require('express-async-handler');
const mongoose = require('mongoose');
const User = require('../models/userModel');
const Job = require('../models/jobModel');
const { fileUrl } = require('../middleware/uploadMiddleware');

const getMe = asyncHandler(async (req, res) => {
  res.json(req.user);
});

const updateProfile = asyncHandler(async (req, res) => {
  const scalarFields = [
    'name', 'email', 'photo', 'preference', 'bio',
    'skills', 'yearsOfExperience', 'searchRadiusKm', 'searchRadiusLabel',
    // Top-level *Label fields are DEPRECATED — kept here so legacy
    // client builds don't 400. updateProfile mirrors them into the
    // matching subdoc.label below so new clients only need to look at
    // workArea.label / currentLocation.label.
    'workAreaLabel', 'currentLocationLabel'
  ];
  scalarFields.forEach((f) => {
    if (req.body[f] !== undefined) req.user[f] = req.body[f];
  });

  // workArea — accept the full subdoc shape (coords + address parts +
  // label). Key rule: when coords CHANGE and the body doesn't provide
  // new address parts, CLEAR them. The old address parts belong to the
  // old location and would mislead the admin (e.g. coords say Bangalore
  // but city says New Delhi). Sub-fields that the body explicitly
  // provides always win.
  if (req.body.workArea && typeof req.body.workArea === 'object') {
    const incoming = req.body.workArea;
    const existing = req.user.workArea?.toObject?.() || req.user.workArea || {};
    const coordsChanged =
      Array.isArray(incoming.coordinates) &&
      JSON.stringify(incoming.coordinates) !== JSON.stringify(existing.coordinates);
    const carry = (field) =>
      incoming[field] !== undefined
        ? incoming[field]
        : (coordsChanged ? '' : existing[field]);
    req.user.workArea = {
      type: 'Point',
      coordinates: Array.isArray(incoming.coordinates)
        ? incoming.coordinates
        : (existing.coordinates || [0, 0]),
      address: carry('address'),
      city:    carry('city'),
      state:   carry('state'),
      pincode: carry('pincode'),
      label:   incoming.label !== undefined ? incoming.label : existing.label,
    };
    req.user.markModified('workArea');
  }
  // Legacy: top-level workAreaLabel mirrors into workArea.label.
  if (req.body.workAreaLabel !== undefined) {
    req.user.workArea = req.user.workArea || { type: 'Point', coordinates: [0, 0] };
    req.user.workArea.label = req.body.workAreaLabel;
    req.user.markModified('workArea');
  }

  // currentLocation — same rule for clearing stale address parts on
  // coord change. updatedAt stamps when coords actually change.
  if (req.body.currentLocation && typeof req.body.currentLocation === 'object') {
    const incoming = req.body.currentLocation;
    const existing = req.user.currentLocation?.toObject?.() || req.user.currentLocation || {};
    const coordsChanged =
      Array.isArray(incoming.coordinates) &&
      JSON.stringify(incoming.coordinates) !== JSON.stringify(existing.coordinates);
    const carry = (field) =>
      incoming[field] !== undefined
        ? incoming[field]
        : (coordsChanged ? '' : existing[field]);
    req.user.currentLocation = {
      type: 'Point',
      coordinates: Array.isArray(incoming.coordinates)
        ? incoming.coordinates
        : (existing.coordinates || [0, 0]),
      address: carry('address'),
      city:    carry('city'),
      state:   carry('state'),
      pincode: carry('pincode'),
      label:   incoming.label !== undefined ? incoming.label : existing.label,
      updatedAt: coordsChanged ? new Date() : existing.updatedAt,
    };
    req.user.markModified('currentLocation');
    if (coordsChanged) req.user.currentLocationUpdatedAt = new Date();
  }
  if (req.body.currentLocationLabel !== undefined) {
    req.user.currentLocation = req.user.currentLocation || { type: 'Point', coordinates: [0, 0] };
    req.user.currentLocation.label = req.body.currentLocationLabel;
    req.user.markModified('currentLocation');
  }

  await req.user.save();
  res.json(req.user);
});

const uploadPhoto = asyncHandler(async (req, res) => {
  if (!req.file) {
    res.status(400);
    throw new Error('Photo file required');
  }
  req.user.photo = fileUrl(req.file);
  await req.user.save();
  res.json({ photo: req.user.photo, user: req.user });
});

const updateLocation = asyncHandler(async (req, res) => {
  const { lat, lng, address, city, state, pincode } = req.body;
  // Coords are OPTIONAL — the wizard's address screen is the single
  // place that owns this endpoint, and Next must always proceed even
  // when no real coordinates can be captured. We treat the null-island
  // sentinel (0,0) THE SAME as "no coords sent" — save the typed
  // address fields but don't bother writing [0,0] over whatever's
  // already there. (Older Flutter builds still send (0,0) as the
  // "unknown" sentinel — handling it here avoids a hard 400.)
  const hasCoords =
    typeof lat === 'number' &&
    typeof lng === 'number' &&
    !(lat === 0 && lng === 0);
  // Merge: only overwrite address/city/state/pincode when the caller
  // explicitly provides them, so a coords-only heartbeat doesn't wipe
  // typed text. Coords stay at whatever they were unless hasCoords.
  const existing = req.user.location?.toObject?.() || req.user.location || {};
  req.user.location = {
    type: 'Point',
    coordinates: hasCoords ? [lng, lat] : (existing.coordinates || [0, 0]),
    address: address !== undefined ? address : existing.address,
    city: city !== undefined ? city : existing.city,
    state: state !== undefined ? state : existing.state,
    pincode: pincode !== undefined ? pincode : existing.pincode,
    label: existing.label || '',
  };
  if (hasCoords) req.user.lastLocationAt = new Date();

  // First-save bootstrap: when the wizard saves real GPS coords, seed
  // workArea + currentLocation from them so the admin record is complete.
  // Skip seeding entirely if no coords were sent — typed-only users keep
  // those fields empty until they later visit Find Work / Hire Workers
  // setup. We only seed when the field is missing or still at [0,0] so
  // we never trample a real Find Work pick.
  const isEmpty = (coords) =>
    !Array.isArray(coords) ||
    coords.length !== 2 ||
    (coords[0] === 0 && coords[1] === 0);

  if (hasCoords) {
    // Seed workArea and currentLocation with the full home-address
    // shape so the admin sees consistent sub-fields across all three
    // location columns. Only seed when empty / [0,0] — never trample a
    // real Find Work pick.
    const seedLabel = [city, state].filter((s) => s && String(s).trim()).join(', ');
    if (isEmpty(req.user.workArea?.coordinates)) {
      req.user.workArea = {
        type: 'Point',
        coordinates: [lng, lat],
        address, city, state, pincode,
        label: req.user.workArea?.label || seedLabel || undefined,
      };
      req.user.markModified('workArea');
    } else if (!req.user.workArea?.label && seedLabel) {
      req.user.workArea.label = seedLabel;
      req.user.markModified('workArea');
    }
    // Legacy top-level mirror (kept temporarily for old clients).
    if (!req.user.workAreaLabel && seedLabel) req.user.workAreaLabel = seedLabel;

    if (isEmpty(req.user.currentLocation?.coordinates)) {
      req.user.currentLocation = {
        type: 'Point',
        coordinates: [lng, lat],
        address, city, state, pincode,
        label: req.user.currentLocation?.label || seedLabel || undefined,
        updatedAt: new Date(),
      };
      req.user.markModified('currentLocation');
      req.user.currentLocationUpdatedAt = new Date();
    } else if (!req.user.currentLocation?.label && seedLabel) {
      req.user.currentLocation.label = seedLabel;
      req.user.markModified('currentLocation');
    }
    if (!req.user.currentLocationLabel && seedLabel) req.user.currentLocationLabel = seedLabel;
  }
  if (req.user.searchRadiusKm == null) {
    req.user.searchRadiusKm = 10;
  }

  await req.user.save();
  res.json(req.user);
});

const switchRole = asyncHandler(async (req, res) => {
  const { role, mode } = req.body;
  if (!['jobgiver', 'jobtaker'].includes(role)) {
    res.status(400);
    throw new Error('Invalid role');
  }
  // mode='replace' (default) → first-time role pick from Find Work /
  // Hire Workers. roles array becomes [role] so the user is only that.
  // mode='add' → Profile screen's "Switch Mode" toggle. We append the
  // new role so the user ends up with BOTH roles (and activeRole flips
  // to the one they just switched to). This is how a user becomes a
  // "both" user that the admin panel will display with two roles.
  if (mode === 'add') {
    if (!req.user.roles.includes(role)) req.user.roles.push(role);
  } else {
    req.user.roles = [role];
  }
  req.user.activeRole = role;
  await req.user.save();
  res.json(req.user);
});

const uploadDocument = asyncHandler(async (req, res) => {
  const { type } = req.body;
  if (!req.file) {
    res.status(400);
    throw new Error('File required');
  }
  req.user.documents.push({
    type: type || 'other',
    url: fileUrl(req.file),
    status: 'pending'
  });
  await req.user.save();
  res.json(req.user);
});

const setFcmToken = asyncHandler(async (req, res) => {
  req.user.fcmToken = req.body.fcmToken;
  await req.user.save();
  res.json({ ok: true });
});

const nearbyWorkers = asyncHandler(async (req, res) => {
  // Returns up to `limit` job-takers near `(lat,lng)` within `radiusKm`,
  // skipping the caller themselves. Used by the Hire view on the mobile
  // home screen. The previous version filtered by isAvailable + a fresh
  // lastLocationAt heartbeat — that whole online/heartbeat feature has
  // been removed, so we now surface every active, non-blocked jobtaker.
  const { lat, lng, radiusKm = 5, limit = 20 } = req.query;

  // Resolve the caller's reference point. The mobile usually passes it
  // explicitly via query params, but when it doesn't (e.g. the user
  // hasn't pinned their location yet) we fall back to whichever of
  // currentLocation / workArea / location has real coords on their
  // record so the OSRM enrichment block still runs.
  let originLat = lat != null ? parseFloat(lat) : NaN;
  let originLng = lng != null ? parseFloat(lng) : NaN;
  if (!Number.isFinite(originLat) || !Number.isFinite(originLng) ||
      (originLat === 0 && originLng === 0)) {
    originLat = NaN; originLng = NaN;
    for (const key of ['currentLocation', 'workArea', 'location']) {
      const sub = req.user && req.user[key];
      const c = sub && sub.coordinates;
      if (!Array.isArray(c) || c.length !== 2) continue;
      const [cLng, cLat] = c;
      if (typeof cLng !== 'number' || typeof cLat !== 'number') continue;
      if (cLat === 0 && cLng === 0) continue;
      originLat = cLat;
      originLng = cLng;
      break;
    }
  }
  const haveOrigin = Number.isFinite(originLat) && Number.isFinite(originLng);

  const filter = {
    roles: 'jobtaker',
    isActive: true,
    isBlocked: { $ne: true },
    _id: { $ne: req.user._id },
  };

  const projection =
    'name photo rating jobsCompleted skills isVerifiedProfessional '
    'location currentLocation';

  let users;
  if (haveOrigin) {
    filter['location.coordinates'] = { $ne: [0, 0] };
    users = await User.find({
      ...filter,
      location: {
        $near: {
          $geometry: {
            type: 'Point',
            coordinates: [originLng, originLat],
          },
          $maxDistance: parseFloat(radiusKm) * 1000,
        },
      },
    })
      .select(projection)
      .limit(parseInt(limit));
  } else {
    users = await User.find(filter)
      .select(projection)
      .sort('-rating.average')
      .limit(parseInt(limit));
  }

  // Enrich each worker with road-driving distance (km) from the
  // caller's reference point. Primary source is the OSRM Table API
  // (true driving route); when OSRM is unreachable we fall back to
  // a 1.35× scaled haversine so the field is always populated and
  // the mobile card never displays a misleadingly-short straight-
  // line distance.
  if (haveOrigin && users.length > 0) {
    const { roadDistancesKm, estimatedRoadKm } = require('../utils/routing');

    // Per worker, prefer their fresher currentLocation (last live GPS
    // ping) over the static home location for the distance calc —
    // otherwise a worker who set up at the same address as the
    // jobgiver but is actually across town shows 0 m. Returns
    // [lng, lat] or null when neither has usable coords.
    const pickCoords = (u) => {
      for (const key of ['currentLocation', 'location']) {
        const raw = u && u[key];
        const coords = raw && raw.coordinates;
        if (!Array.isArray(coords) || coords.length !== 2) continue;
        const [lng, lat] = coords;
        if (typeof lng !== 'number' || typeof lat !== 'number') continue;
        if (lat === 0 && lng === 0) continue;
        return [lng, lat];
      }
      return null;
    };

    const points = [{ lat: originLat, lng: originLng }];
    const slots = []; // tracks which workers are in `points`
    for (const u of users) {
      const coords = pickCoords(u);
      if (!coords) continue;
      const [wLng, wLat] = coords;
      points.push({ lat: wLat, lng: wLng });
      slots.push({ user: u, coords });
    }
    if (slots.length > 0) {
      const { kms, sources } = await roadDistancesKm(points);
      const out = users.map((u) => u.toObject());
      const slotIdx = new Map(
        slots.map((s, i) => [s.user._id.toString(), i]),
      );
      for (const obj of out) {
        const i = slotIdx.get(obj._id.toString());
        if (i == null) continue;
        const km = kms[i];
        if (typeof km === 'number' && Number.isFinite(km)) {
          obj.roadDistanceKm = km;
          obj.distanceSource = sources[i] || 'route';
        } else {
          const [wLng, wLat] = slots[i].coords;
          obj.roadDistanceKm =
            estimatedRoadKm(originLat, originLng, wLat, wLng);
          obj.distanceSource = 'estimated';
        }
      }
      res.json(out);
      return;
    }
  }
  res.json(users);
});

const getEarnings = asyncHandler(async (req, res) => {
  const Job = require('../models/jobModel');

  const now = new Date();
  const startOfDay = new Date(now);
  startOfDay.setHours(0, 0, 0, 0);

  const startOfWeek = new Date(now);
  // Treat Monday as start of the week (ISO).
  const day = startOfWeek.getDay() || 7;
  startOfWeek.setDate(startOfWeek.getDate() - day + 1);
  startOfWeek.setHours(0, 0, 0, 0);

  const startOfLastWeek = new Date(startOfWeek);
  startOfLastWeek.setDate(startOfLastWeek.getDate() - 7);

  const sumBetween = async (from, to) => {
    const match = {
      selectedJobtaker: req.user._id,
      status: 'completed',
      completedAt: { $gte: from }
    };
    if (to) match.completedAt.$lt = to;
    const rows = await Job.aggregate([
      { $match: match },
      { $group: { _id: null, total: { $sum: { $ifNull: ['$finalPrice', 0] } } } }
    ]);
    return rows[0]?.total || 0;
  };

  const [today, thisWeek, lastWeek] = await Promise.all([
    sumBetween(startOfDay),
    sumBetween(startOfWeek),
    sumBetween(startOfLastWeek, startOfWeek)
  ]);

  let deltaPct = null;
  if (lastWeek > 0) {
    deltaPct = Math.round(((thisWeek - lastWeek) / lastWeek) * 100);
  } else if (thisWeek > 0) {
    deltaPct = 100;
  } else {
    deltaPct = 0;
  }

  res.json({
    today,
    thisWeek,
    lastWeek,
    deltaPct
  });
});

const acceptTerms = asyncHandler(async (req, res) => {
  req.user.acceptedTermsAt = new Date();
  await req.user.save();
  res.json({ acceptedTermsAt: req.user.acceptedTermsAt, user: req.user });
});

const getPublicProfile = asyncHandler(async (req, res) => {
  const user = await User.findById(req.params.id).select(
    'name photo rating jobsCompleted jobsCancelled badge isVerifiedProfessional preference'
  );
  if (!user) {
    res.status(404);
    throw new Error('User not found');
  }
  res.json(user);
});

// Favourite / wishlist actions — see /me/favorites/:jobId routes.
// Stored as an array of Job ObjectIds on the user doc (most-recent first).
// Idempotent on both sides so a double tap from the client doesn't push
// duplicates or 404 on a second remove.
const addFavorite = asyncHandler(async (req, res) => {
  const { jobId } = req.params;
  if (!mongoose.isValidObjectId(jobId)) {
    res.status(400);
    throw new Error('Invalid job id');
  }
  const job = await Job.findById(jobId).select('_id');
  if (!job) {
    res.status(404);
    throw new Error('Job not found');
  }
  // Pull-then-unshift keeps the ordering "most recently saved first"
  // even if the user re-saves a job they already had.
  req.user.favoriteJobs = (req.user.favoriteJobs || [])
    .filter((id) => id.toString() !== jobId);
  req.user.favoriteJobs.unshift(job._id);
  await req.user.save();
  res.json({ ok: true, count: req.user.favoriteJobs.length });
});

const removeFavorite = asyncHandler(async (req, res) => {
  const { jobId } = req.params;
  req.user.favoriteJobs = (req.user.favoriteJobs || [])
    .filter((id) => id.toString() !== jobId);
  await req.user.save();
  res.json({ ok: true, count: req.user.favoriteJobs.length });
});

const listFavorites = asyncHandler(async (req, res) => {
  const populated = await User.findById(req.user._id)
    .populate({ path: 'favoriteJobs' })
    .select('favoriteJobs');
  res.json({ items: populated?.favoriteJobs || [] });
});

module.exports = {
  getMe,
  updateProfile,
  uploadPhoto,
  updateLocation,
  switchRole,
  uploadDocument,
  setFcmToken,
  acceptTerms,
  getEarnings,
  nearbyWorkers,
  getPublicProfile,
  addFavorite,
  removeFavorite,
  listFavorites
};
