const asyncHandler = require('express-async-handler');
const Rating = require('../models/ratingModel');
const Job = require('../models/jobModel');
const User = require('../models/userModel');

const submitRating = asyncHandler(async (req, res) => {
  const { jobId, stars, review } = req.body;
  const job = await Job.findById(jobId);
  if (!job) { res.status(404); throw new Error('Job not found'); }
  if (job.status !== 'completed') { res.status(400); throw new Error('Job not completed'); }

  const isGiver = job.jobgiver.toString() === req.user._id.toString();
  const isTaker = job.selectedJobtaker && job.selectedJobtaker.toString() === req.user._id.toString();
  if (!isGiver && !isTaker) { res.status(403); throw new Error('Not part of this job'); }

  const ratee = isGiver ? job.selectedJobtaker : job.jobgiver;
  const rating = await Rating.create({ job: jobId, rater: req.user._id, ratee, stars, review });

  // recompute average
  const agg = await Rating.aggregate([
    { $match: { ratee: rating.ratee } },
    { $group: { _id: null, avg: { $avg: '$stars' }, n: { $sum: 1 } } }
  ]);
  if (agg[0]) {
    await User.findByIdAndUpdate(rating.ratee, {
      'rating.average': Math.round(agg[0].avg * 10) / 10,
      'rating.count': agg[0].n
    });
  }
  res.status(201).json(rating);
});

const getUserRatings = asyncHandler(async (req, res) => {
  const ratings = await Rating.find({ ratee: req.params.userId })
    .populate('rater', 'name photo')
    .sort('-createdAt')
    .limit(100);
  res.json(ratings);
});

module.exports = { submitRating, getUserRatings };
