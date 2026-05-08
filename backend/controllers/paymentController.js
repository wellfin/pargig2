const asyncHandler = require('express-async-handler');
const Payment = require('../models/paymentModel');
const Job = require('../models/jobModel');
const User = require('../models/userModel');
const Transaction = require('../models/transactionModel');
const { calculatePlatformFee } = require('../utils/feeCalculator');
const { pushToUser } = require('../utils/notify');

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
  initiatePayment, confirmPayment, releasePayment,
  refundPayment, myPayments, myEarnings, topupWallet
};
