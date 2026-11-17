const asyncHandler = require('express-async-handler');
const Dispute = require('../models/disputeModel');
const Job = require('../models/jobModel');
const Payment = require('../models/paymentModel');
const { currentMode } = require('../services/refundService');

// Only one open dispute per job — otherwise a user tapping "Get Help"
// twice creates two cases over the same money and support resolves them
// independently.
const OPEN_STATES = ['open', 'under_review'];

const raiseDispute = asyncHandler(async (req, res) => {
  const {
    jobId, reason, details, attachments,
    occurredWhen, requestedResolution, amountRequested,
  } = req.body;

  if (!reason || !String(reason).trim()) {
    res.status(400);
    throw new Error('Select what went wrong');
  }

  const job = await Job.findById(jobId);
  if (!job) { res.status(404); throw new Error('Job not found'); }

  const isGiver = job.jobgiver.toString() === req.user._id.toString();
  const isTaker = job.selectedJobtaker &&
    job.selectedJobtaker.toString() === req.user._id.toString();
  if (!isGiver && !isTaker) { res.status(403); throw new Error('Not part of this job'); }

  // Cash is out of scope for disputes: the giver handed the money to the
  // worker in person and it never passed through Pargig, so there is
  // nothing the platform can hold, refund or reverse. Letting one be
  // filed would promise a remedy that cannot be delivered.
  const paid = await Payment.find({
    job: jobId,
    status: { $in: ['paid', 'on_hold', 'released', 'refunded'] }
  }).sort('-createdAt');
  const latest = paid[0];
  if (latest && currentMode(latest) === 'cash') {
    res.status(400);
    throw new Error(
      'This job was paid in cash. Cash payments are not covered by Pargig ' +
      'Protection, so a refund request cannot be raised — please settle it ' +
      'directly with the other person.'
    );
  }

  const existing = await Dispute.findOne({
    job: jobId,
    raisedBy: req.user._id,
    status: { $in: OPEN_STATES },
  });
  if (existing) {
    res.status(409);
    throw new Error(`You already have an open request (${existing.code}) for this service`);
  }

  const files = Array.isArray(attachments) ? attachments.filter(Boolean) : [];

  const dispute = await Dispute.create({
    job: jobId,
    raisedBy: req.user._id,
    paymentMode: latest ? currentMode(latest) : undefined,
    against: isGiver ? job.selectedJobtaker : job.jobgiver,
    reason,
    details,
    occurredWhen: ['during', 'after', 'other'].includes(occurredWhen)
      ? occurredWhen
      : undefined,
    requestedResolution: ['refund', 'correction', 'support_decide']
      .includes(requestedResolution) ? requestedResolution : 'support_decide',
    amountRequested: Number(amountRequested) > 0 ? Number(amountRequested) : 0,
    attachments: files,
    timeline: [
      { label: 'Request Submitted' },
      ...(files.length ? [{ label: 'Evidence Received' }] : []),
      { label: 'Support Review', note: 'Usually takes 24-48 hours' },
    ],
  });

  job.status = 'disputed';
  await job.save();

  // Freeze whatever is still holdable. This used to select on_hold
  // payments and set them to on_hold, which did nothing at all.
  //
  // 'paid' money has not been handed on yet, so it moves to on_hold and
  // stops there. Money already 'released' cannot be un-paid, so it stays
  // as it is and the refund (if any) is recovered from the worker at
  // resolution time — see services/refundService.js.
  await Payment.updateMany(
    { job: jobId, status: 'paid' },
    { $set: { status: 'on_hold', heldAt: new Date() } }
  );

  res.status(201).json(dispute);
});

const myDisputes = asyncHandler(async (req, res) => {
  const { status } = req.query;
  const filter = {
    $or: [{ raisedBy: req.user._id }, { against: req.user._id }],
  };
  // 'under_review' in the app's filter chips covers both pre-review and
  // in-review, which the user experiences as one "we're looking at it".
  if (status === 'under_review') filter.status = { $in: OPEN_STATES };
  else if (status === 'resolved') filter.status = { $in: ['resolved', 'rejected'] };

  const disputes = await Dispute.find(filter)
    .populate('job', 'title status category')
    .populate('against', 'name photo')
    .sort('-createdAt');
  res.json(disputes);
});

// One dispute with everything the tracking screen renders: the timeline,
// the evidence, and how much money is frozen behind it.
const getDispute = asyncHandler(async (req, res) => {
  const dispute = await Dispute.findById(req.params.id)
    .populate('job', 'title status category finalPrice proposedBudget')
    .populate('raisedBy', 'name photo')
    .populate('against', 'name photo rating');
  if (!dispute) { res.status(404); throw new Error('Request not found'); }

  const mine = [dispute.raisedBy?._id, dispute.against?._id]
    .filter(Boolean)
    .some((id) => id.toString() === req.user._id.toString());
  if (!mine) { res.status(403); throw new Error('Not your request'); }

  const payments = await Payment.find({ job: dispute.job?._id ?? dispute.job })
    .sort('-createdAt');
  const onHold = payments
    .filter((p) => p.status === 'on_hold')
    .reduce((sum, p) => sum + (p.amount || 0), 0);
  const paid = payments
    .filter((p) => ['paid', 'on_hold', 'released', 'refunded'].includes(p.status))
    .reduce((sum, p) => sum + (p.amount || 0), 0);

  res.json({ dispute, payments, amountOnHold: onHold, amountPaid: paid });
});

// "Add Evidence" from the Under Review screen. Appending only — removing
// evidence after support has seen it would let someone rewrite the case.
const addEvidence = asyncHandler(async (req, res) => {
  const dispute = await Dispute.findById(req.params.id);
  if (!dispute) { res.status(404); throw new Error('Request not found'); }
  if (dispute.raisedBy.toString() !== req.user._id.toString()) {
    res.status(403); throw new Error('Not your request');
  }
  if (!OPEN_STATES.includes(dispute.status)) {
    res.status(400); throw new Error('This request is already resolved');
  }
  const files = Array.isArray(req.body.attachments)
    ? req.body.attachments.filter(Boolean)
    : [];
  if (!files.length) { res.status(400); throw new Error('No files to add'); }

  dispute.attachments.push(...files);
  dispute.timeline.push({ label: 'Evidence Received' });
  await dispute.save();
  res.json(dispute);
});

module.exports = { raiseDispute, myDisputes, getDispute, addEvidence };
