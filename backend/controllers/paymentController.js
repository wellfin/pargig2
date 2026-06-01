const asyncHandler = require('express-async-handler');
const Payment = require('../models/paymentModel');
const Job = require('../models/jobModel');
const User = require('../models/userModel');
const Transaction = require('../models/transactionModel');
const { calculatePlatformFee } = require('../utils/feeCalculator');
const { pushToUser } = require('../utils/notify');

// Worker-side "Request to Pay" from the Payment Request screen.
// Stores the worker's preferred payout method on the job and pushes
// a notification to the jobgiver so they know payment is being
// requested. The actual money movement still goes through
// initiatePayment/confirmPayment when the giver pays.
const requestPayment = asyncHandler(async (req, res) => {
  const { jobId, method } = req.body;
  const allowed = ['cash', 'upi', 'card'];
  if (!allowed.includes(method)) {
    res.status(400); throw new Error('Invalid payout method');
  }
  const job = await Job.findById(jobId).populate('jobgiver', 'name');
  if (!job) { res.status(404); throw new Error('Job not found'); }
  if (!job.selectedJobtaker ||
      job.selectedJobtaker.toString() !== req.user._id.toString()) {
    res.status(403); throw new Error('Not the assigned jobtaker');
  }
  if (!['in_progress', 'completed'].includes(job.status)) {
    res.status(400); throw new Error('Job not ready for payment');
  }
  job.payoutMethod = method;
  job.payoutRequestedAt = new Date();
  await job.save();

  const label = method === 'upi' ? 'UPI' : method[0].toUpperCase() + method.slice(1);
  pushToUser(job.jobgiver._id || job.jobgiver, {
    type: 'payment',
    title: 'Worker is requesting payment',
    body: `${req.user.name || 'Worker'} requested payment via ${label}`,
    data: { jobId: job._id, method }
  });

  res.json({ ok: true, payoutMethod: method });
});

const initiatePayment = asyncHandler(async (req, res) => {
  const job = await Job.findById(req.body.jobId);
  if (!job) { res.status(404); throw new Error('Job not found'); }
  if (job.jobgiver.toString() !== req.user._id.toString()) {
    res.status(403); throw new Error('Not your job');
  }
  if (!job.finalPrice) { res.status(400); throw new Error('Final price not set'); }

  const platformFee = calculatePlatformFee(job.finalPrice, req.user.freeJobsRemaining);
  const payment = await Payment.create({
    job: job._id,
    jobgiver: job.jobgiver,
    jobtaker: job.selectedJobtaker,
    amount: job.finalPrice,
    platformFee,
    payoutAmount: job.finalPrice - platformFee,
    gateway: req.body.gateway || 'razorpay'
  });
  // TODO: integrate actual payment gateway. For now just return order shell.
  res.json({
    payment,
    gatewayOrder: { id: `order_${payment._id}`, amount: job.finalPrice * 100, currency: 'INR' }
  });
});

const confirmPayment = asyncHandler(async (req, res) => {
  const { paymentId, gatewayPaymentId, gatewaySignature } = req.body;
  const payment = await Payment.findById(paymentId);
  if (!payment) { res.status(404); throw new Error('Payment not found'); }
  payment.gatewayPaymentId = gatewayPaymentId;
  payment.gatewaySignature = gatewaySignature;
  payment.status = 'on_hold';
  payment.heldAt = new Date();
  await payment.save();

  await Transaction.create({
    user: payment.jobgiver,
    type: 'payment',
    amount: -payment.amount,
    reference: payment._id,
    referenceModel: 'Payment',
    note: 'Payment held in escrow'
  });

  res.json(payment);
});

const releasePayment = asyncHandler(async (req, res) => {
  const payment = await Payment.findById(req.params.id);
  if (!payment) { res.status(404); throw new Error('Payment not found'); }
  if (payment.jobgiver.toString() !== req.user._id.toString()) {
    res.status(403); throw new Error('Only job giver can release');
  }
  if (payment.status !== 'on_hold') {
    res.status(400); throw new Error('Payment not on hold');
  }

  const job = await Job.findById(payment.job);
  if (!job || job.status !== 'completed') {
    res.status(400); throw new Error('Job not completed');
  }

  payment.status = 'released';
  payment.releasedAt = new Date();
  await payment.save();

  // credit jobtaker wallet
  const taker = await User.findById(payment.jobtaker);
  taker.walletBalance = (taker.walletBalance || 0) + payment.payoutAmount;
  if (taker.freeJobsRemaining > 0) taker.freeJobsRemaining -= 1;
  await taker.save();

  await Transaction.create({
    user: taker._id,
    type: 'payout',
    amount: payment.payoutAmount,
    balanceAfter: taker.walletBalance,
    reference: payment._id,
    referenceModel: 'Payment',
    note: `Payout for job ${job.title}`
  });
  if (payment.platformFee > 0) {
    await Transaction.create({
      user: payment.jobgiver,
      type: 'fee',
      amount: -payment.platformFee,
      reference: payment._id,
      referenceModel: 'Payment',
      note: 'Platform fee'
    });
  }

  pushToUser(taker._id, {
    type: 'payment',
    title: 'Payment released',
    body: `Rs ${payment.payoutAmount} credited to your wallet`,
    data: { paymentId: payment._id }
  });

  res.json(payment);
});

// Convenience endpoint hit from the Hire-mode My Posted Jobs
// "Release Payment" button on a Completed card. The mobile only
// knows the job id, not the Payment doc id, and the demo flow
// usually skips /initiate + /confirm entirely. So this handler:
//   1. Validates the caller is the jobgiver and the job is completed
//   2. Loads an existing Payment for this job — releases it via the
//      same money-movement logic as POST /payments/:id/release if one
//      exists in 'on_hold' state
//   3. Otherwise mock-creates a 'released' Payment inline (no escrow
//      hold), so the worker still gets the payout transaction even
//      though the jobgiver bypassed the gateway flow
// In both branches we stamp job.paymentReleasedAt so My Posted Jobs
// can flip the button to "Payment Released" disabled afterwards.
const releaseForJob = asyncHandler(async (req, res) => {
  const job = await Job.findById(req.params.jobId);
  if (!job) { res.status(404); throw new Error('Job not found'); }
  if (job.jobgiver.toString() !== req.user._id.toString()) {
    res.status(403); throw new Error('Not your job');
  }
  if (job.status !== 'completed') {
    res.status(400); throw new Error('Job not completed');
  }
  if (job.paymentReleasedAt) {
    res.status(400); throw new Error('Payment already released');
  }
  if (!job.selectedJobtaker) {
    res.status(400); throw new Error('No worker assigned');
  }
  const amount = Number(job.finalPrice || 0);
  if (!amount || amount <= 0) {
    res.status(400); throw new Error('Final price not set');
  }

  // Find an existing held payment for this job. If absent, we mock-
  // create one in 'released' state so the demo flow still credits
  // the worker even when the jobgiver skipped /initiate + /confirm.
  let payment = await Payment.findOne({
    job: job._id,
    status: 'on_hold',
  });

  const platformFee = calculatePlatformFee(amount, req.user.freeJobsRemaining);
  const payoutAmount = amount - platformFee;

  if (payment) {
    payment.status = 'released';
    payment.releasedAt = new Date();
    await payment.save();
  } else {
    payment = await Payment.create({
      job: job._id,
      jobgiver: job.jobgiver,
      jobtaker: job.selectedJobtaker,
      amount,
      platformFee,
      payoutAmount,
      gateway: 'manual',
      status: 'released',
      releasedAt: new Date(),
    });
  }

  // Credit the worker wallet and write a payout transaction.
  const taker = await User.findById(payment.jobtaker);
  if (taker) {
    taker.walletBalance =
      (taker.walletBalance || 0) + (payment.payoutAmount || 0);
    if (taker.freeJobsRemaining > 0) taker.freeJobsRemaining -= 1;
    await taker.save();
    await Transaction.create({
      user: taker._id,
      type: 'payout',
      amount: payment.payoutAmount,
      balanceAfter: taker.walletBalance,
      reference: payment._id,
      referenceModel: 'Payment',
      note: `Payout for job ${job.title}`,
    });
    if (payment.platformFee > 0) {
      await Transaction.create({
        user: payment.jobgiver,
        type: 'fee',
        amount: -payment.platformFee,
        reference: payment._id,
        referenceModel: 'Payment',
        note: 'Platform fee',
      });
    }
    pushToUser(taker._id, {
      type: 'payment',
      title: 'Payment released',
      body: `₹${payment.payoutAmount} credited to your wallet`,
      data: { paymentId: payment._id, jobId: job._id },
    });
  }

  job.paymentReleasedAt = new Date();
  await job.save();

  res.json({
    ok: true,
    paymentId: payment._id,
    payoutAmount: payment.payoutAmount,
    paymentReleasedAt: job.paymentReleasedAt,
  });
});

const refundPayment = asyncHandler(async (req, res) => {
  // admin-only via routes
  const payment = await Payment.findById(req.params.id);
  if (!payment) { res.status(404); throw new Error('Payment not found'); }
  if (!['on_hold', 'paid'].includes(payment.status)) {
    res.status(400); throw new Error('Cannot refund in current state');
  }
  payment.status = 'refunded';
  payment.refundedAt = new Date();
  payment.refundReason = req.body.reason;
  await payment.save();

  await Transaction.create({
    user: payment.jobgiver,
    type: 'refund',
    amount: payment.amount,
    reference: payment._id,
    referenceModel: 'Payment',
    note: `Refund: ${req.body.reason || ''}`
  });
  res.json(payment);
});

const myPayments = asyncHandler(async (req, res) => {
  const payments = await Payment.find({
    $or: [{ jobgiver: req.user._id }, { jobtaker: req.user._id }]
  })
    .populate('job', 'title status')
    .sort('-createdAt');
  res.json(payments);
});

const myEarnings = asyncHandler(async (req, res) => {
  const txns = await Transaction.find({ user: req.user._id }).sort('-createdAt').limit(200);
  const totalEarnings = txns
    .filter((t) => t.type === 'payout')
    .reduce((s, t) => s + t.amount, 0);
  res.json({ walletBalance: req.user.walletBalance, totalEarnings, transactions: txns });
});

const topupWallet = asyncHandler(async (req, res) => {
  const amount = parseFloat(req.body.amount);
  if (!amount || amount <= 0) { res.status(400); throw new Error('Invalid amount'); }
  // TODO: real gateway flow. For now, mock immediate credit.
  req.user.walletBalance = (req.user.walletBalance || 0) + amount;
  await req.user.save();
  await Transaction.create({
    user: req.user._id,
    type: 'wallet_topup',
    amount,
    balanceAfter: req.user.walletBalance,
    note: 'Wallet topup'
  });
  res.json({ walletBalance: req.user.walletBalance });
});

module.exports = {
  requestPayment,
  initiatePayment, confirmPayment, releasePayment, releaseForJob,
  refundPayment, myPayments, myEarnings, topupWallet
};
