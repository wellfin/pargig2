const asyncHandler = require('express-async-handler');
const Rating = require('../models/ratingModel');
const Job = require('../models/jobModel');
const User = require('../models/userModel');
const { pushToUser } = require('../utils/notify');

const submitRating = asyncHandler(async (req, res) => {
  const { jobId, stars, review, tags } = req.body;
  const job = await Job.findById(jobId);
  if (!job) { res.status(404); throw new Error('Job not found'); }
  // Workers rate from /job-completed right after Submit Completion,
  // which already flips the job to 'completed'. 'in_progress' stays
  // allowed for legacy jobs that never got past the old PIN hand-off.
  if (!['in_progress', 'completed'].includes(job.status)) {
    res.status(400); throw new Error('Job not ready for rating');
  }

  const isGiver = job.jobgiver.toString() === req.user._id.toString();
  const isTaker = job.selectedJobtaker && job.selectedJobtaker.toString() === req.user._id.toString();
  if (!isGiver && !isTaker) { res.status(403); throw new Error('Not part of this job'); }

  const ratee = isGiver ? job.selectedJobtaker : job.jobgiver;
  if (!ratee) {
    res.status(400);
    throw new Error('There is nobody to rate on this job yet');
  }

  // One rating per person per job — the model enforces it with a unique
  // index, which would otherwise surface as a raw E11000 duplicate-key
  // 500. Check first so the caller gets a clear 409 it can show.
  const existing = await Rating.findOne({ job: jobId, rater: req.user._id });
  if (existing) {
    res.status(409);
    throw new Error('You have already rated this job');
  }

  const starCount = Number(stars);
  if (!Number.isInteger(starCount) || starCount < 1 || starCount > 5) {
    res.status(400);
    throw new Error('Give a rating between 1 and 5 stars');
  }
  const cleanTags = Array.isArray(tags)
    ? tags.filter((t) => typeof t === 'string' && t.trim().length > 0).slice(0, 10)
    : [];
  const rating = await Rating.create({
    job: jobId,
    rater: req.user._id,
    ratee,
    stars: starCount,
    review,
    tags: cleanTags
  });

  // recompute average
  const agg = await Rating.aggregate([
    { $match: { ratee: rating.ratee } },
    { $group: { _id: null, avg: { $avg: '$stars' }, n: { $sum: 1 } } }
  ]);
  let newAverage = null;
  let newCount = null;
  if (agg[0]) {
    newAverage = Math.round(agg[0].avg * 10) / 10;
    newCount = agg[0].n;
    await User.findByIdAndUpdate(rating.ratee, {
      'rating.average': newAverage,
      'rating.count': newCount
    });
  }

  // Tell the person who was rated. Without this the rating landed
  // silently: a worker's average moved with nothing saying who rated them
  // or what they gave.
  if (ratee) {
    const starWord = starCount === 1 ? 'star' : 'stars';
    const who = req.user.name || (isGiver ? 'The job giver' : 'The worker');
    const reviewText = typeof review === 'string' ? review.trim() : '';
    await pushToUser(ratee, {
      type: 'job_status',
      title: `You received ${starCount} ${starWord}`,
      body: reviewText
        ? `${who} rated you ${starCount}/5 for "${job.title}" — "${reviewText}"`
        : `${who} rated you ${starCount}/5 for "${job.title}"`,
      data: {
        jobId: job._id,
        ratingId: rating._id,
        stars: starCount,
        // The recomputed figures, so the app can show the new standing
        // straight from the notification without another round trip.
        average: newAverage,
        count: newCount
      }
    });
  }

  res.status(201).json(rating);
});

// Every rating this user has RECEIVED, newest first. Powers the app's
// Reviews screen, where a worker can finally see what each job giver
// actually gave them — the profile only ever showed the average.
const getUserRatings = asyncHandler(async (req, res) => {
  const ratings = await Rating.find({ ratee: req.params.userId })
    .populate('rater', 'name photo')
    // Without the job the list cannot say what each rating was for, which
    // is most of the point of showing them individually.
    .populate('job', 'title category')
    .sort('-createdAt')
    .limit(100);

  const summary = ratings.reduce(
    (acc, r) => {
      acc.total += 1;
      acc.sum += r.stars || 0;
      const s = String(r.stars);
      if (acc.breakdown[s] !== undefined) acc.breakdown[s] += 1;
      return acc;
    },
    { total: 0, sum: 0, breakdown: { '1': 0, '2': 0, '3': 0, '4': 0, '5': 0 } }
  );

  res.json({
    ratings,
    total: summary.total,
    average: summary.total
      ? Math.round((summary.sum / summary.total) * 10) / 10
      : 0,
    breakdown: summary.breakdown
  });
});

// Every rating this user has GIVEN, newest first — the other half of
// the Reviews screen. Received and given are genuinely different lists
// (different counterparty, different direction), so they are kept apart
// rather than merged into one feed the reader has to decode.
//
// Scoped to the caller: what you thought of someone is yours to look
// back on, not a public record keyed by user id the way received
// ratings are.
const getMyGivenRatings = asyncHandler(async (req, res) => {
  const ratings = await Rating.find({ rater: req.user._id })
    .populate('ratee', 'name photo')
    .populate('job', 'title category')
    .sort('-createdAt')
    .limit(100);

  res.json({ ratings, total: ratings.length });
});

// Which of this job's two ratings the caller has already left, so the
// app can label a past job "You rated 4" instead of offering a button
// that only earns a 409.
const getJobRatings = asyncHandler(async (req, res) => {
  const ratings = await Rating.find({ job: req.params.jobId })
    .populate('rater', 'name photo')
    .populate('ratee', 'name photo');

  const me = req.user._id.toString();
  res.json({
    given: ratings.find((r) => r.rater._id.toString() === me) || null,
    received: ratings.find((r) => r.ratee._id.toString() === me) || null
  });
});

/**
 * The rating this job giver still owes, if any.
 *
 * Rating the worker is mandatory once a job is finished and paid, and
 * the app is expected to take the giver back to it when they reopen —
 * so the obligation has to outlive the app process. It is derived here
 * from the jobs themselves rather than stored as a flag: a flag could
 * drift out of step with reality, whereas "paid and not yet rated" is
 * the obligation, restated from the record every time.
 *
 * Deriving it also means it survives a reinstall or a new phone, which
 * a note kept on the device would not.
 *
 * Oldest first: if two jobs are waiting, the one that has been owed
 * longest is the one to ask for.
 */
const pendingRating = asyncHandler(async (req, res) => {
  const settled = await Job.find({
    jobgiver: req.user._id,
    status: 'completed',
    paymentReleasedAt: { $ne: null },
    selectedJobtaker: { $ne: null }
  })
    .populate('selectedJobtaker', 'name photo')
    .sort('paymentReleasedAt')
    .limit(20)
    .lean();

  if (settled.length === 0) return res.json({ pending: null });

  // One query for all of them rather than one each: a giver with a long
  // history would otherwise pay for a round trip per job.
  const rated = await Rating.find({
    job: { $in: settled.map((j) => j._id) },
    rater: req.user._id
  })
    .select('job')
    .lean();
  const ratedIds = new Set(rated.map((r) => r.job.toString()));

  const owed = settled.find((j) => !ratedIds.has(j._id.toString()));
  if (!owed) return res.json({ pending: null });

  res.json({
    pending: {
      jobId: owed._id,
      jobTitle: owed.title,
      workerName: owed.selectedJobtaker?.name || 'the worker',
      workerPhoto: owed.selectedJobtaker?.photo || null,
      paidAt: owed.paymentReleasedAt
    }
  });
});

module.exports = {
  submitRating,
  pendingRating,
  getUserRatings,
  getMyGivenRatings,
  getJobRatings
};
