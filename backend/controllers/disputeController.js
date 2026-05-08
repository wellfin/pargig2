const asyncHandler = require('express-async-handler');
const Dispute = require('../models/disputeModel');
const Job = require('../models/jobModel');
const Payment = require('../models/paymentModel');

const raiseDispute = asyncHandler(async (req, res) => {
  const { jobId, reason, details, attachments } = req.body;
  const job = await Job.findById(jobId);
  if (!job) { res.status(404); throw new Error('Job not found'); }
  const isGiver = job.jobgiver.toString() === req.user._id.toString();
  const isTaker = job.selectedJobtaker && job.selectedJobtaker.toString() === req.user._id.toString();
  if (!isGiver && !isTaker) { res.status(403); throw new Error('Not part of this job'); }

  const dispute = await Dispute.create({
    job: jobId,
    raisedBy: req.user._id,
    against: isGiver ? job.selectedJobtaker : job.jobgiver,
    reason,
    details,
    attachments: attachments || []
  });

  job.status = 'disputed';
  await job.save();
  // freeze related on_hold payment so admin reviews
  await Payment.updateMany({ job: jobId, status: 'on_hold' }, { $set: { status: 'on_hold' } });

  res.status(201).json(dispute);
});

const myDisputes = asyncHandler(async (req, res) => {
  const disputes = await Dispute.find({
    $or: [{ raisedBy: req.user._id }, { against: req.user._id }]
  }).populate('job', 'title status').sort('-createdAt');
  res.json(disputes);
});

module.exports = { raiseDispute, myDisputes };
