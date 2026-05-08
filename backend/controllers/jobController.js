const asyncHandler = require('express-async-handler');
const Job = require('../models/jobModel');
const User = require('../models/userModel');
const { generateOtp } = require('../utils/otp');
const { pushToUser } = require('../utils/notify');

const createJob = asyncHandler(async (req, res) => {
  const {
    title, description, voiceNoteUrl, category, photos,
    location, scheduledAt, preference, priceMode, proposedBudget,
    isUrgent, isBoosted
  } = req.body;
  if (!title) {
    res.status(400);
    throw new Error('Title required');
  }
  let locationDoc;
  if (location) {
    const hasCoords = typeof location.lat === 'number' && typeof location.lng === 'number';
    const hasText = location.address || location.city || location.pincode;
    if (hasCoords || hasText) {
      locationDoc = {
        type: 'Point',
        coordinates: hasCoords ? [location.lng, location.lat] : [0, 0],
        address: location.address,
        city: location.city,
        pincode: location.pincode
      };
    }
  }
  const job = await Job.create({
    jobgiver: req.user._id,
    title,
    description,
    voiceNoteUrl,
    category,
    photos: Array.isArray(photos) ? photos : [],
    location: locationDoc,
    scheduledAt,
    preference: preference || 'anyone',
    priceMode: priceMode || 'open',
    proposedBudget,
    isUrgent: !!isUrgent,
    isBoosted: !!isBoosted
  });
  res.status(201).json(job);
});

const uploadJobPhoto = asyncHandler(async (req, res) => {
  if (!req.file) {
    res.status(400);
    throw new Error('Photo file required');
  }
  res.json({ url: `/uploads/${req.file.filename}` });
});

const updateJob = asyncHandler(async (req, res) => {
  const job = await Job.findById(req.params.id);
  if (!job) { res.status(404); throw new Error('Job not found'); }
  if (job.jobgiver.toString() !== req.user._id.toString()) {
    res.status(403); throw new Error('Not your job');
  }
  if (!['open'].includes(job.status)) {
    res.status(400); throw new Error('Cannot edit after confirmation');
  }
  const editable = ['title', 'description', 'voiceNoteUrl', 'category', 'photos', 'scheduledAt', 'preference', 'priceMode', 'proposedBudget'];
  editable.forEach((k) => { if (req.body[k] !== undefined) job[k] = req.body[k]; });
  if (req.body.location && req.body.location.lat && req.body.location.lng) {
    job.location = {
      type: 'Point',
      coordinates: [req.body.location.lng, req.body.location.lat],
      address: req.body.location.address,
      city: req.body.location.city,
      pincode: req.body.location.pincode
    };
  }
  await job.save();
  res.json(job);
});

const browseCategories = asyncHandler(async (req, res) => {
  // Aggregate the count of open jobs per category. The mobile home screen
  // overlays this onto its curated category list.
  const rows = await Job.aggregate([
    { $match: { status: 'open' } },
    { $group: { _id: { $ifNull: ['$category', 'Other'] }, count: { $sum: 1 } } },
    { $project: { _id: 0, category: '$_id', count: 1 } },
    { $sort: { count: -1 } }
  ]);
  res.json(rows);
});

const browseJobs = asyncHandler(async (req, res) => {
  const {
    lat, lng, radiusKm = 5, q, page = 1, limit = 20,
    minPrice, maxPrice, categories, sortBy
  } = req.query;
  const filter = { status: 'open' };
  if (q) filter.title = { $regex: q, $options: 'i' };

  // Multi-category filter — accept comma-separated string or array.
  if (categories) {
    const list = Array.isArray(categories)
      ? categories
      : String(categories).split(',').map((s) => s.trim()).filter(Boolean);
    if (list.length > 0) filter.category = { $in: list };
  }

  // Price range filter — applied to whichever of finalPrice / proposedBudget
  // is present on the job.
  if (minPrice !== undefined || maxPrice !== undefined) {
    const min = minPrice !== undefined ? parseFloat(minPrice) : null;
    const max = maxPrice !== undefined ? parseFloat(maxPrice) : null;
    const range = {};
    if (min !== null && !Number.isNaN(min)) range.$gte = min;
    if (max !== null && !Number.isNaN(max)) range.$lte = max;
    if (Object.keys(range).length > 0) {
      filter.$or = [{ finalPrice: range }, { proposedBudget: range }];
    }
  }

  // Geo filter. We use $near (auto-sorts by distance) only when the caller
  // wants nearest-first. For any other sortBy (priceHigh / priceLow / recent)
  // we use $geoWithin so MongoDB doesn't impose its distance sort, letting
  // our explicit .sort() take effect.
  if (lat && lng) {
    const radiusMeters = parseFloat(radiusKm) * 1000;
    if (!sortBy || sortBy === 'nearest') {
      filter.location = {
        $near: {
          $geometry: { type: 'Point', coordinates: [parseFloat(lng), parseFloat(lat)] },
          $maxDistance: radiusMeters
        }
      };
    } else {
      filter.location = {
        $geoWithin: {
          $centerSphere: [
            [parseFloat(lng), parseFloat(lat)],
            // $centerSphere expects radius in radians (Earth ≈ 6378.1 km).
            parseFloat(radiusKm) / 6378.1
          ]
        }
      };
    }
  }

  // Exclude jobs the requesting user posted themselves
  if (req.headers.authorization?.startsWith('Bearer ')) {
    try {
      const jwt = require('jsonwebtoken');
      const token = req.headers.authorization.split(' ')[1];
      const decoded = jwt.verify(token, process.env.JWT_SECRET);
      if (decoded?.id) filter.jobgiver = { $ne: decoded.id };
    } catch (_) { /* invalid token, ignore filter */ }
  }

  let sort = '-createdAt';
  switch (sortBy) {
    case 'priceHigh': sort = '-finalPrice -proposedBudget'; break;
    case 'priceLow':  sort = 'finalPrice proposedBudget'; break;
    case 'recent':    sort = '-createdAt'; break;
    case 'nearest':   sort = ''; break; // $near already sorts by distance
    default:          sort = '-createdAt';
  }

  const query = Job.find(filter).populate('jobgiver', 'name photo rating');
  if (sort) query.sort(sort);
  const jobs = await query
    .skip((page - 1) * limit)
    .limit(parseInt(limit));
  res.json(jobs);
});

const getJob = asyncHandler(async (req, res) => {
  const job = await Job.findById(req.params.id)
    .populate('jobgiver', 'name photo rating mobile')
    .populate('selectedJobtaker', 'name photo rating mobile')
    .populate('interested.jobtaker', 'name photo rating jobsCompleted');
  if (!job) { res.status(404); throw new Error('Job not found'); }
  res.json(job);
});

const myPostedJobs = asyncHandler(async (req, res) => {
  const jobs = await Job.find({ jobgiver: req.user._id }).sort('-createdAt');
  res.json(jobs);
});

const myAppliedJobs = asyncHandler(async (req, res) => {
  const jobs = await Job.find({ 'interested.jobtaker': req.user._id }).sort('-createdAt');
  res.json(jobs);
});

const showInterest = asyncHandler(async (req, res) => {
  const job = await Job.findById(req.params.id);
  if (!job) { res.status(404); throw new Error('Job not found'); }
  if (job.status !== 'open') { res.status(400); throw new Error('Job not open'); }

  if (!req.user.roles.includes('jobtaker')) {
    res.status(403); throw new Error('Only job takers can apply');
  }

  // first job under Rs 1000 is free; jobs 1-3 require Rs 20 wallet deposit
  const proposedPrice = req.body.proposedPrice || job.proposedBudget || 0;
  const freeBelow = parseFloat(process.env.FIRST_JOB_FREE_BELOW || '1000');
  const deposit = parseFloat(process.env.WALLET_DEPOSIT_AMOUNT || '20');
  const isFirstFreeJob = req.user.jobsCompleted === 0 && proposedPrice < freeBelow;
  if (!isFirstFreeJob && req.user.jobsCompleted < 3) {
    if (req.user.walletBalance < deposit) {
      res.status(402);
      throw new Error(`Wallet deposit of Rs ${deposit} required to apply`);
    }
  }

  const already = job.interested.find((i) => i.jobtaker.toString() === req.user._id.toString());
  if (already) {
    already.proposedPrice = proposedPrice;
    already.message = req.body.message;
  } else {
    job.interested.push({
      jobtaker: req.user._id,
      proposedPrice,
      message: req.body.message
    });
  }
  await job.save();

  pushToUser(job.jobgiver, {
    type: 'job_alert',
    title: 'New interest in your job',
    body: `${req.user.name || 'Someone'} is interested in "${job.title}"`,
    data: { jobId: job._id }
  });

  res.json(job);
});

const confirmJobtaker = asyncHandler(async (req, res) => {
  const job = await Job.findById(req.params.id);
  if (!job) { res.status(404); throw new Error('Job not found'); }
  if (job.jobgiver.toString() !== req.user._id.toString()) {
    res.status(403); throw new Error('Not your job');
  }
  if (job.status !== 'open') {
    res.status(400); throw new Error('Job not open');
  }
  const { jobtakerId, finalPrice } = req.body;
  const interested = job.interested.find((i) => i.jobtaker.toString() === jobtakerId);
  if (!interested) {
    res.status(400); throw new Error('Jobtaker did not show interest');
  }
  job.selectedJobtaker = jobtakerId;
  job.finalPrice = finalPrice || interested.proposedPrice || job.proposedBudget;
  job.status = 'confirmed';
  await job.save();

  pushToUser(jobtakerId, {
    type: 'job_status',
    title: 'You got the job!',
    body: `Your interest in "${job.title}" was selected`,
    data: { jobId: job._id }
  });

  res.json(job);
});

const reachLocation = asyncHandler(async (req, res) => {
  const job = await Job.findById(req.params.id);
  if (!job) { res.status(404); throw new Error('Job not found'); }
  if (job.selectedJobtaker.toString() !== req.user._id.toString()) {
    res.status(403); throw new Error('Not the assigned jobtaker');
  }
  if (job.status !== 'confirmed') {
    res.status(400); throw new Error('Job not confirmed yet');
  }
  const code = generateOtp();
  job.startOtp = { code, issuedAt: new Date() };
  job.status = 'reached';
  await job.save();

  pushToUser(job.jobgiver, {
    type: 'job_status',
    title: 'Worker has reached',
    body: `Share OTP ${code} with the worker to start the job`,
    data: { jobId: job._id, otp: code }
  });

  res.json({ message: 'Reached. OTP sent to job giver.' });
});

const verifyStartOtp = asyncHandler(async (req, res) => {
  const job = await Job.findById(req.params.id);
  if (!job) { res.status(404); throw new Error('Job not found'); }
  if (job.selectedJobtaker.toString() !== req.user._id.toString()) {
    res.status(403); throw new Error('Not the assigned jobtaker');
  }
  if (!job.startOtp || !job.startOtp.code) {
    res.status(400); throw new Error('No start OTP issued');
  }
  if (job.startOtp.code !== req.body.otp) {
    res.status(400); throw new Error('Invalid OTP');
  }
  job.startOtp.verifiedAt = new Date();
  job.status = 'in_progress';
  job.startedAt = new Date();
  await job.save();
  res.json(job);
});

const completeJob = asyncHandler(async (req, res) => {
  const job = await Job.findById(req.params.id);
  if (!job) { res.status(404); throw new Error('Job not found'); }
  if (job.selectedJobtaker.toString() !== req.user._id.toString()) {
    res.status(403); throw new Error('Not the assigned jobtaker');
  }
  if (job.status !== 'in_progress') {
    res.status(400); throw new Error('Job not in progress');
  }
  const code = generateOtp();
  job.completeOtp = { code, issuedAt: new Date() };
  await job.save();

  pushToUser(job.jobgiver, {
    type: 'job_status',
    title: 'Worker marked job complete',
    body: `Verify with OTP ${code} to release payment`,
    data: { jobId: job._id, otp: code }
  });

  res.json({ message: 'Completion OTP issued to job giver' });
});

const verifyCompleteOtp = asyncHandler(async (req, res) => {
  const job = await Job.findById(req.params.id);
  if (!job) { res.status(404); throw new Error('Job not found'); }
  if (job.jobgiver.toString() !== req.user._id.toString()) {
    res.status(403); throw new Error('Not the job giver');
  }
  if (!job.completeOtp || !job.completeOtp.code) {
    res.status(400); throw new Error('No completion OTP issued');
  }
  if (job.completeOtp.code !== req.body.otp) {
    res.status(400); throw new Error('Invalid OTP');
  }
  job.completeOtp.verifiedAt = new Date();
  job.status = 'completed';
  job.completedAt = new Date();
  await job.save();

  // increment counters
  await User.findByIdAndUpdate(job.selectedJobtaker, { $inc: { jobsCompleted: 1 } });

  // payment release flow - handled via paymentController.releasePayment
  res.json(job);
});

const cancelJob = asyncHandler(async (req, res) => {
  const job = await Job.findById(req.params.id);
  if (!job) { res.status(404); throw new Error('Job not found'); }
  const isGiver = job.jobgiver.toString() === req.user._id.toString();
  const isTaker = job.selectedJobtaker && job.selectedJobtaker.toString() === req.user._id.toString();
  if (!isGiver && !isTaker) {
    res.status(403); throw new Error('Not authorized');
  }
  if (['completed', 'cancelled'].includes(job.status)) {
    res.status(400); throw new Error('Job already ended');
  }
  job.status = 'cancelled';
  job.cancellation = {
    by: isGiver ? 'jobgiver' : 'jobtaker',
    reason: req.body.reason,
    at: new Date()
  };
  await job.save();
  if (isTaker) {
    await User.findByIdAndUpdate(req.user._id, { $inc: { jobsCancelled: 1 } });
  }
  res.json(job);
});

module.exports = {
  createJob, updateJob, browseJobs, browseCategories, getJob,
  myPostedJobs, myAppliedJobs, showInterest, confirmJobtaker,
  reachLocation, verifyStartOtp, completeJob, verifyCompleteOtp, cancelJob,
  uploadJobPhoto
};
