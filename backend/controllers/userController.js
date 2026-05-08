const asyncHandler = require('express-async-handler');
const User = require('../models/userModel');

const getMe = asyncHandler(async (req, res) => {
  res.json(req.user);
});

const updateProfile = asyncHandler(async (req, res) => {
  const fields = ['name', 'email', 'photo', 'preference', 'bio', 'skills', 'yearsOfExperience'];
  fields.forEach((f) => {
    if (req.body[f] !== undefined) req.user[f] = req.body[f];
  });
  await req.user.save();
  res.json(req.user);
});

const uploadPhoto = asyncHandler(async (req, res) => {
  if (!req.file) {
    res.status(400);
    throw new Error('Photo file required');
  }
  req.user.photo = `/uploads/${req.file.filename}`;
  await req.user.save();
  res.json({ photo: req.user.photo, user: req.user });
});

const updateLocation = asyncHandler(async (req, res) => {
  const { lat, lng, address, city, state, pincode } = req.body;
  if (typeof lat !== 'number' || typeof lng !== 'number') {
    res.status(400);
    throw new Error('lat and lng required as numbers');
  }
  req.user.location = {
    type: 'Point',
    coordinates: [lng, lat],
    address,
    city,
    state,
    pincode
  };
  await req.user.save();
  res.json(req.user);
});

const switchRole = asyncHandler(async (req, res) => {
  const { role } = req.body;
  if (!['jobgiver', 'jobtaker'].includes(role)) {
    res.status(400);
    throw new Error('Invalid role');
  }
  if (!req.user.roles.includes(role)) req.user.roles.push(role);
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
    url: `/uploads/${req.file.filename}`,
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
  // home screen.
  const { lat, lng, radiusKm = 5, limit = 20 } = req.query;
  const filter = {
    roles: 'jobtaker',
    isActive: true,
    isBlocked: { $ne: true },
    _id: { $ne: req.user._id },
  };
  let users;
  if (lat && lng) {
    filter['location.coordinates'] = { $ne: [0, 0] };
    users = await User.find({
      ...filter,
      location: {
        $near: {
          $geometry: {
            type: 'Point',
            coordinates: [parseFloat(lng), parseFloat(lat)],
          },
          $maxDistance: parseFloat(radiusKm) * 1000,
        },
      },
    })
      .select(
        'name photo rating jobsCompleted skills isVerifiedProfessional location'
      )
      .limit(parseInt(limit));
  } else {
    users = await User.find(filter)
      .select(
        'name photo rating jobsCompleted skills isVerifiedProfessional location'
      )
      .sort('-rating.average')
      .limit(parseInt(limit));
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
  getPublicProfile
};
