const asyncHandler = require('express-async-handler');
const Job = require('../models/jobModel');
const User = require('../models/userModel');
const Payment = require('../models/paymentModel');
const { generateJobOtp } = require('../utils/otp');
const { pushToUser } = require('../utils/notify');
const { fileUrl } = require('../middleware/uploadMiddleware');

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
  res.json({ url: fileUrl(req.file) });
});

// Voice-note upload for the Post Job description recorder. Same shape
// as uploadJobPhoto — multer stores the clip (a 16 kHz mono .wav) in
// S3 (or on local disk when S3 isn't configured) and we return its URL
// so the mobile client can put it into voiceNoteUrl on the subsequent
// createJob call. The file is stored and later served back
// byte-for-byte: workers hear the giver's actual recorded voice.
//
// No transcription happens here or anywhere else — speech-to-text is
// currently disabled in the app, so the recording IS the description and
// the typed description is a separate, optional field.
const uploadJobVoiceNote = asyncHandler(async (req, res) => {
  if (!req.file) {
    res.status(400);
    throw new Error('Voice note file required');
  }
  res.json({ url: fileUrl(req.file) });
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
  const editable = ['title', 'description', 'voiceNoteUrl', 'category', 'photos', 'scheduledAt', 'preference', 'priceMode', 'proposedBudget', 'isUrgent'];
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

// Job giver sets/updates the tip on their own post. The tip is stored
// separately from finalPrice/proposedBudget — it is NOT folded into the
// working price; the worker just sees it as an extra incentive.
const setTip = asyncHandler(async (req, res) => {
  const job = await Job.findById(req.params.id);
  if (!job) { res.status(404); throw new Error('Job not found'); }
  if (job.jobgiver.toString() !== req.user._id.toString()) {
    res.status(403); throw new Error('Not your job');
  }
  const tip = Number(req.body.tip);
  if (!Number.isFinite(tip) || tip < 0) {
    res.status(400); throw new Error('Enter a valid tip amount');
  }
  job.tip = Math.round(tip);
  await job.save();
  res.json(job);
});

const browseCategories = asyncHandler(async (req, res) => {
  // Aggregate the count of open jobs per category. The mobile home screen
  // overlays this onto its curated category list. Exclude posts the
  // calling user previously cancelled (mirrors the browseJobs filter)
  // so the category badge doesn't count jobs the user can't actually
  // see in the feed.
  const match = { status: 'open' };
  if (req.headers.authorization?.startsWith('Bearer ')) {
    try {
      const jwt = require('jsonwebtoken');
      const mongoose = require('mongoose');
      const token = req.headers.authorization.split(' ')[1];
      const decoded = jwt.verify(token, process.env.JWT_SECRET);
      if (decoded?.id) {
        const meId = new mongoose.Types.ObjectId(decoded.id);
        match.jobgiver = { $ne: meId };
        match.blockedJobtakers = { $ne: meId };
      }
    } catch (_) { /* invalid token, ignore filter */ }
  }
  const rows = await Job.aggregate([
    { $match: match },
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

  // Exclude jobs the requesting user posted themselves, and jobs they
  // previously claimed-then-cancelled (their _id sits in
  // blockedJobtakers so the post is now hidden from THEM, even though
  // it's open again for everyone else).
  if (req.headers.authorization?.startsWith('Bearer ')) {
    try {
      const jwt = require('jsonwebtoken');
      const token = req.headers.authorization.split(' ')[1];
      const decoded = jwt.verify(token, process.env.JWT_SECRET);
      if (decoded?.id) {
        filter.jobgiver = { $ne: decoded.id };
        filter.blockedJobtakers = { $ne: decoded.id };
      }
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
    .populate('interested.jobtaker', 'name photo rating jobsCompleted location')
    // lean() so the payment summary can be attached — Mongoose documents
    // ignore assignment of fields that are not in the schema.
    .lean();
  if (!job) { res.status(404); throw new Error('Job not found'); }
  // Job Details shows how the job was actually paid under the price, and
  // that lives on Payment rather than Job.
  await attachPayments([job]);
  res.json(job);
});

// Attaches the payment behind each job as `job.payment` (null when there
// is none). My Services / Service Detail show the transaction id and the
// amount actually paid, and My Jobs / My Posted Jobs build the invoice
// from it — all of which live on Payment rather than Job, so without this
// join those screens had nothing to show once the payment screen closed.
//
// Expects lean() documents: Mongoose documents silently ignore assignment
// of fields that are not in the schema.
async function attachPayments(jobs) {
  if (jobs.length === 0) return;

  const payments = await Payment.find({ job: { $in: jobs.map((j) => j._id) } })
    .sort('-createdAt')
    .lean();

  const latestByJob = new Map();
  for (const p of payments) {
    const key = p.job.toString();
    // Sorted newest-first, so the first one seen for a job is the latest.
    // A job can carry several payments (a retry after a failure, or a
    // separate tip), and the most recent is the one worth showing.
    if (!latestByJob.has(key)) latestByJob.set(key, p);
  }

  for (const job of jobs) {
    const p = latestByJob.get(job._id.toString());
    job.payment = p
      ? {
          _id: p._id,
          // Null for cash-on-delivery — there is no gateway reference to
          // show, which is different from "we failed to look it up".
          transactionId: p.transactionId || null,
          amount: p.amount,
          platformFee: p.platformFee,
          tipAmount: p.tipAmount,
          status: p.status,
          method: p.method || null,
          // Canonical mode (upi / card / netbanking / wallet / cash), so
          // the app can print "UPI" under the amount without parsing a
          // label like "HDFC Debit Card ****9232".
          mode: p.mode || null,
          isCod: !!p.isCod,
          paidAt: p.createdAt,
          // When the money actually moved; the invoice date. paidAt is
          // when the payment record was opened, which can be earlier.
          releasedAt: p.releasedAt || null,
        }
      : null;
  }
}

const myPostedJobs = asyncHandler(async (req, res) => {
  const jobs = await Job.find({ jobgiver: req.user._id })
    // Populate the assigned worker so the Hire-mode My Posted Jobs
    // "In Progress" card can render their name + photo + ★ rating
    // without needing a second fetch.
    .populate('selectedJobtaker', 'name photo rating')
    .sort('-createdAt')
    // lean() so the payment summary below can be attached — Mongoose
    // documents ignore assignment of fields that aren't in the schema.
    .lean();

  await attachPayments(jobs);
  res.json(jobs);
});

const myAppliedJobs = asyncHandler(async (req, res) => {
  // Jobs the worker applied to (in `interested`) OR was directly assigned
  // (`selectedJobtaker`). Urgent jobs are claimed via /claim-urgent which
  // sets selectedJobtaker without adding an `interested` entry — without
  // the $or they'd never show up in the worker's My Jobs.
  const jobs = await Job.find({
    $or: [
      { 'interested.jobtaker': req.user._id },
      { selectedJobtaker: req.user._id }
    ]
  })
    .populate('jobgiver', 'name photo rating mobile')
    .sort('-createdAt')
    .lean();

  // Only on jobs this worker was actually hired for. Jobs they merely
  // applied to and lost belong to someone else's payment, and what the
  // giver paid the winning worker is none of their business.
  const me = req.user._id.toString();
  await attachPayments(
    jobs.filter((j) => j.selectedJobtaker && j.selectedJobtaker.toString() === me)
  );
  res.json(jobs);
});

const showInterest = asyncHandler(async (req, res) => {
  const job = await Job.findById(req.params.id);
  if (!job) { res.status(404); throw new Error('Job not found'); }
  if (job.status !== 'open') { res.status(400); throw new Error('Job not open'); }

  if (!req.user.roles.includes('jobtaker')) {
    res.status(403); throw new Error('Only job takers can apply');
  }

  // Wallet-deposit gate temporarily disabled per product decision —
  // first-time / low-completion jobtakers can apply without holding
  // Rs 20 in their wallet. Re-enable by uncommenting this block when
  // the deposit rule comes back.
  //
  // const proposedPrice = req.body.proposedPrice || job.proposedBudget || 0;
  // const freeBelow = parseFloat(process.env.FIRST_JOB_FREE_BELOW || '1000');
  // const deposit = parseFloat(process.env.WALLET_DEPOSIT_AMOUNT || '20');
  // const isFirstFreeJob = req.user.jobsCompleted === 0 && proposedPrice < freeBelow;
  // if (!isFirstFreeJob && req.user.jobsCompleted < 3) {
  //   if (req.user.walletBalance < deposit) {
  //     res.status(402);
  //     throw new Error(`Wallet deposit of Rs ${deposit} required to apply`);
  //   }
  // }
  const proposedPrice = req.body.proposedPrice || job.proposedBudget || 0;

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

// Jobgiver rejects (declines) an applicant from the Applicants screen.
// Removing them from `interested` alone isn't enough — the worker could
// simply re-apply and reappear, and the job would still surface in their
// "Applied Jobs" list (myAppliedJobs matches on interested.jobtaker). So
// we also push the worker into blockedJobtakers, which:
//   - hides the post from that worker in browseJobs / browseCategories,
//   - blocks them from re-claiming an urgent job (claimUrgent filter).
// The job stays `open` so other workers can still apply / be accepted.
const rejectApplicant = asyncHandler(async (req, res) => {
  const job = await Job.findById(req.params.id);
  if (!job) { res.status(404); throw new Error('Job not found'); }
  if (job.jobgiver.toString() !== req.user._id.toString()) {
    res.status(403); throw new Error('Not your job');
  }
  const { jobtakerId } = req.body;
  if (!jobtakerId) {
    res.status(400); throw new Error('jobtakerId required');
  }
  // Can't reject the worker already assigned to the job.
  if (job.selectedJobtaker && job.selectedJobtaker.toString() === jobtakerId.toString()) {
    res.status(400); throw new Error('Cannot reject the accepted worker — cancel the job instead');
  }
  job.interested = job.interested.filter(
    (i) => i.jobtaker.toString() !== jobtakerId.toString()
  );
  if (!job.blockedJobtakers.some((b) => b.toString() === jobtakerId.toString())) {
    job.blockedJobtakers.push(jobtakerId);
  }
  await job.save();

  pushToUser(jobtakerId, {
    type: 'job_status',
    title: 'Application not selected',
    body: `Your application for "${job.title}" was not selected`,
    data: { jobId: job._id }
  });

  res.json(job);
});

// Atomic first-come-first-served claim for URGENT jobs.
// Worker taps "Accept Job" on the urgent popup; we need to:
//   - Guarantee only the FIRST request wins even if two devices tap at
//     the same millisecond (race-safe via findOneAndUpdate with status
//     filter — the second request's filter no longer matches because
//     the first request flipped status to 'confirmed').
//   - Skip the jobgiver-approval step entirely (urgent jobs don't have
//     time for manual selection).
//   - Set selectedJobtaker / finalPrice / status in one DB write so the
//     job IS assigned before /reach can be called.
const claimUrgent = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const proposedPrice = Number(req.body?.proposedPrice);

  // Urgent "Accept" REGISTERS INTEREST — it does not hire anyone.
  //
  // This used to atomically flip the job to `confirmed` and set
  // selectedJobtaker, so the first worker to tap Accept was hired with no
  // input from the giver. That is the auto-accept being removed: hiring is
  // the giver's decision on every job, urgent or not, and happens only
  // through confirmJobtaker (which checks the caller owns the job).
  //
  // The endpoint is kept rather than deleted so already-installed builds
  // that still call it stop auto-hiring the moment this deploys, instead
  // of continuing against an older server contract.
  const job = await Job.findById(id);
  if (!job) {
    res.status(404); throw new Error('Job not found');
  }
  if (!job.isUrgent) {
    res.status(400); throw new Error('This job is not urgent — use the regular apply flow');
  }
  if (job.status !== 'open') {
    res.status(409); throw new Error('This job is no longer accepting applications');
  }
  if (!req.user.roles.includes('jobtaker')) {
    res.status(403); throw new Error('Only job takers can apply');
  }
  // A worker the giver previously declined must not reappear in the list.
  const blocked = (job.blockedJobtakers || []).some(
    (b) => b && b.toString() === req.user._id.toString()
  );
  if (blocked) {
    res.status(403); throw new Error('You can no longer apply to this job');
  }

  const settledPrice = Number.isFinite(proposedPrice) && proposedPrice > 0
    ? proposedPrice
    : (job.finalPrice || job.proposedBudget || 0);

  // Same shape as showInterest, so an urgent applicant appears in the
  // giver's applicant list exactly like any other and can be accepted or
  // declined there.
  const already = (job.interested || []).find(
    (i) => i.jobtaker && i.jobtaker.toString() === req.user._id.toString()
  );
  if (already) {
    already.proposedPrice = settledPrice;
    if (req.body?.message !== undefined) already.message = req.body.message;
  } else {
    job.interested.push({
      jobtaker: req.user._id,
      proposedPrice: settledPrice,
      message: req.body?.message
    });
  }
  await job.save();

  pushToUser(job.jobgiver, {
    type: 'job_alert',
    title: 'New interest in your urgent job',
    body: `${req.user.name || 'A worker'} wants to take "${job.title}"`,
    data: { jobId: job._id }
  });

  res.json(job);
});

const reachLocation = asyncHandler(async (req, res) => {
  const job = await Job.findById(req.params.id);
  if (!job) { res.status(404); throw new Error('Job not found'); }
  if (!job.selectedJobtaker) {
    // selectedJobtaker is optional in the schema and is set when the
    // jobgiver accepts an applicant. Hitting this branch means the
    // worker tried to act on a job that hasn't been assigned yet —
    // shouldn't happen via the normal UI flow but guards against the
    // "Cannot read properties of undefined (reading 'toString')"
    // crash that hits if old data has confirmed status without an
    // assignment.
    res.status(400); throw new Error('Job has not been assigned to a worker yet');
  }
  if (job.selectedJobtaker.toString() !== req.user._id.toString()) {
    res.status(403); throw new Error('Not the assigned jobtaker');
  }
  // Allow both first-call (confirmed → reached) AND resend while still
  // at 'reached' (worker tapped "Resend OTP" because client didn't
  // receive / lost the previous code). Block once verification has
  // moved the job to in_progress or beyond.
  if (job.status !== 'confirmed' && job.status !== 'reached') {
    res.status(400); throw new Error('Job not confirmed yet');
  }
  // The arrival slot the worker picked on "Choose your arrival type".
  // Recorded here rather than at application time because this call is
  // the one that proves they are the assigned worker — anyone who merely
  // applied must not be able to move the job's schedule.
  //
  // It is what the start PIN is gated on, so a bad value would either
  // lock the job shut or open it early: an unparseable date is ignored
  // rather than stored.
  if (req.body.scheduledAt) {
    const when = new Date(req.body.scheduledAt);
    if (!Number.isNaN(when.getTime())) job.scheduledAt = when;
  }

  const code = generateJobOtp();
  job.startOtp = { code, issuedAt: new Date(), verifiedAt: null };
  job.status = 'reached';
  await job.save();

  pushToUser(job.jobgiver, {
    type: 'job_status',
    title: 'Worker has reached',
    body: `Share PIN ${code} with the worker to start the job`,
    data: { jobId: job._id, otp: code }
  });

  // Dummy delivery: real SMS / reliable push is not wired up yet, so
  // we return the 6-digit code in the response so the jobgiver app
  // (which polls /jobs/:id) can render it on screen for the client
  // to read out to the worker.
  res.json({ message: 'Reached. PIN sent to job giver.', otp: code });
});

const verifyStartOtp = asyncHandler(async (req, res) => {
  const job = await Job.findById(req.params.id);
  if (!job) { res.status(404); throw new Error('Job not found'); }
  if (!job.selectedJobtaker) {
    // selectedJobtaker is optional in the schema and is set when the
    // jobgiver accepts an applicant. Hitting this branch means the
    // worker tried to act on a job that hasn't been assigned yet —
    // shouldn't happen via the normal UI flow but guards against the
    // "Cannot read properties of undefined (reading 'toString')"
    // crash that hits if old data has confirmed status without an
    // assignment.
    res.status(400); throw new Error('Job has not been assigned to a worker yet');
  }
  if (job.selectedJobtaker.toString() !== req.user._id.toString()) {
    res.status(403); throw new Error('Not the assigned jobtaker');
  }
  if (!job.startOtp || !job.startOtp.code) {
    res.status(400); throw new Error('No start PIN issued');
  }
  if (job.startOtp.code !== req.body.otp) {
    res.status(400); throw new Error('Invalid PIN');
  }
  // The PIN opens the job at its scheduled time, not before. A correct
  // PIN entered early is not an error on the worker's part, so it is
  // refused with the time it becomes usable rather than a flat "invalid".
  //
  // Checked after the code itself so a wrong PIN still reads as wrong:
  // telling someone to come back at six would otherwise confirm they had
  // guessed the right digits.
  if (job.scheduledAt && Date.now() < new Date(job.scheduledAt).getTime()) {
    res.status(425);
    const err = new Error('This PIN becomes valid at the scheduled time');
    err.scheduledAt = job.scheduledAt;
    throw err;
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
  if (!job.selectedJobtaker) {
    // selectedJobtaker is optional in the schema and is set when the
    // jobgiver accepts an applicant. Hitting this branch means the
    // worker tried to act on a job that hasn't been assigned yet —
    // shouldn't happen via the normal UI flow but guards against the
    // "Cannot read properties of undefined (reading 'toString')"
    // crash that hits if old data has confirmed status without an
    // assignment.
    res.status(400); throw new Error('Job has not been assigned to a worker yet');
  }
  if (job.selectedJobtaker.toString() !== req.user._id.toString()) {
    res.status(403); throw new Error('Not the assigned jobtaker');
  }
  if (job.status !== 'in_progress') {
    res.status(400); throw new Error('Job not in progress');
  }
  // Optional proof-of-completion payload from the worker's Complete
  // Job screen — photos already uploaded via /jobs/photo, so we only
  // store the returned URLs. Note is freeform text.
  if (Array.isArray(req.body.photos)) {
    job.completionPhotos = req.body.photos
      .filter((p) => typeof p === 'string' && p.trim().length > 0)
      .slice(0, 8);
  }
  if (typeof req.body.note === 'string') {
    job.completionNote = req.body.note.trim().slice(0, 2000);
  }
  // Submitting proof IS the completion. There is no second PIN hand-off:
  // the worker goes straight on to Rate Experience / Request Payment and
  // the job must already read "Completed" on both sides by then. The
  // giver still controls the money — releasing payment is a separate,
  // explicit action on My Posted Jobs.
  job.status = 'completed';
  job.completedAt = new Date();
  await job.save();

  await User.findByIdAndUpdate(job.selectedJobtaker, { $inc: { jobsCompleted: 1 } });

  pushToUser(job.jobgiver, {
    type: 'job_status',
    title: 'Job completed',
    body: `"${job.title}" is done — release the payment when you're ready`,
    data: { jobId: job._id }
  });

  res.json(job);
});

// Legacy endpoint. /jobs/:id/complete now finishes the job outright, so
// no completion PIN is ever issued and nothing in the app calls this.
// Kept so an older client build doesn't error out: a job that's already
// completed just gets echoed back.
const verifyCompleteOtp = asyncHandler(async (req, res) => {
  const job = await Job.findById(req.params.id);
  if (!job) { res.status(404); throw new Error('Job not found'); }
  if (job.jobgiver.toString() !== req.user._id.toString()) {
    res.status(403); throw new Error('Not the job giver');
  }
  if (job.status === 'completed') {
    return res.json(job);
  }
  if (!job.completeOtp || !job.completeOtp.code) {
    res.status(400); throw new Error('No completion PIN issued');
  }
  if (job.completeOtp.code !== req.body.otp) {
    res.status(400); throw new Error('Invalid PIN');
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
  // Worker already uploaded completion proof and is waiting on the
  // giver's PIN to release payment — the work is done, so the giver
  // can't cancel out of paying for it at this point. Only blocks the
  // giver; the worker themselves can still bail (handled below).
  if (isGiver && job.completeOtp && job.completeOtp.code && !job.completeOtp.verifiedAt) {
    res.status(400);
    throw new Error('Worker already marked this job complete — verify the PIN or wait for payment release instead of cancelling');
  }
  job.cancellation = {
    by: isGiver ? 'jobgiver' : 'jobtaker',
    reason: req.body.reason,
    at: new Date()
  };
  if (isTaker) {
    // Jobtaker bails out — DON'T permanently cancel the post.
    // Re-open it so other workers can claim it, but block the
    // canceller so they never see it again in their feed or
    // urgent popup. Also clear selectedJobtaker so /reach can't
    // be called by anyone until a new worker claims the job.
    if (!job.blockedJobtakers) job.blockedJobtakers = [];
    const meId = req.user._id.toString();
    if (!job.blockedJobtakers.some((id) => id.toString() === meId)) {
      job.blockedJobtakers.push(req.user._id);
    }
    job.selectedJobtaker = undefined;
    job.startOtp = undefined;
    job.status = 'open';
    await job.save();
    await User.findByIdAndUpdate(req.user._id, { $inc: { jobsCancelled: 1 } });
    // Tell the jobgiver their assigned worker dropped so the post
    // is live again.
    pushToUser(job.jobgiver, {
      type: 'job_status',
      title: 'Worker cancelled — your job is live again',
      body: `Someone else can now accept "${job.title}".`,
      data: { jobId: job._id }
    });
  } else {
    // Jobgiver cancellation is permanent (unchanged behaviour).
    job.status = 'cancelled';
    await job.save();
  }
  res.json(job);
});

module.exports = {
  createJob, updateJob, setTip, browseJobs, browseCategories, getJob,
  myPostedJobs, myAppliedJobs, showInterest, confirmJobtaker, rejectApplicant,
  claimUrgent,
  reachLocation, verifyStartOtp, completeJob, verifyCompleteOtp, cancelJob,
  uploadJobPhoto, uploadJobVoiceNote
};
