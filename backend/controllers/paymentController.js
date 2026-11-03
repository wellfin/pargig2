const asyncHandler = require('express-async-handler');
const Payment = require('../models/paymentModel');
const Job = require('../models/jobModel');
const User = require('../models/userModel');
const Transaction = require('../models/transactionModel');
const GatewayOrder = require('../models/gatewayOrderModel');
const { calculatePlatformFee } = require('../utils/feeCalculator');
const { pushToUser } = require('../utils/notify');
const gateway = require('../utils/paymentGateway');
const { resolvePaymentMode } = require('../utils/paymentMode');
const gatewayConfig = require('../utils/gatewayConfig');
const razorpay = require('../utils/razorpay');

// Receipt reference shown on the Payment Successful screen. Cash
// settlements don't get one — there's nothing to reference.
const generateTransactionId = () =>
  `TXN${Date.now().toString(36).toUpperCase()}${Math.floor(Math.random() * 46656)
    .toString(36)
    .toUpperCase()
    .padStart(3, '0')}`;

// Worker-side "Request to Pay" from the Payment Request screen.
// Stores the worker's preferred payout method on the job and pushes
// a notification to the jobgiver so they know payment is being
// requested. The actual money movement still goes through
// initiatePayment/confirmPayment when the giver pays.
const requestPayment = asyncHandler(async (req, res) => {
  const { jobId, method } = req.body;
  const allowed = ['cash', 'upi', 'card', 'wallet'];
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

  const label = method === 'upi'
    ? 'UPI'
    : method === 'wallet'
      ? 'Pargig Wallet'
      : method[0].toUpperCase() + method.slice(1);
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

  // Platform fee applies only to the job price — tips are exempt (the
  // worker keeps 100% of any tip, matching normal tipping convention).
  const tipAmount = job.tip || 0;
  const platformFee = calculatePlatformFee(job.finalPrice, req.user.freeJobsRemaining);
  const totalAmount = job.finalPrice + tipAmount;
  const payment = await Payment.create({
    job: job._id,
    jobgiver: job.jobgiver,
    jobtaker: job.selectedJobtaker,
    amount: totalAmount,
    platformFee,
    tipAmount,
    payoutAmount: job.finalPrice - platformFee + tipAmount,
    gateway: req.body.gateway || 'razorpay',
    mode: resolvePaymentMode({ mode: req.body.mode, method: req.body.methodLabel })
  });
  // TODO: integrate actual payment gateway. For now just return order shell.
  res.json({
    payment,
    gatewayOrder: { id: `order_${payment._id}`, amount: totalAmount * 100, currency: 'INR' }
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
  // Held payments are online by construction, but never credit cash.
  if (!payment.isCod) {
    taker.walletBalance = (taker.walletBalance || 0) + payment.payoutAmount;
  }
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
  // Platform fee applies only to the job price — tips are exempt (the
  // worker keeps 100% of any tip, matching normal tipping convention).
  const tipAmount = job.tip || 0;

  // How the giver settled up, from Select Payment Method. Cash gets no
  // transaction reference; anything online does.
  const isCod = req.body.isCod === true || req.body.method === 'cod';
  const methodLabel =
    typeof req.body.methodLabel === 'string' && req.body.methodLabel.trim()
      ? req.body.methodLabel.trim().slice(0, 60)
      : (isCod ? 'Cash on Delivery' : 'Online');
  const transactionId = isCod ? null : generateTransactionId();
  // Canonical mode recorded alongside the human label, so refunds and
  // reconciliation never have to guess from "HDFC Debit Card ****9232".
  const mode = resolvePaymentMode({
    mode: req.body.mode,
    isCod,
    method: methodLabel,
  });

  // Paying from the Pargig wallet is the one method where the money
  // actually leaves the giver here. Every other method is settled with
  // the provider outside this call, so nothing of theirs is debited —
  // crediting the worker without taking it from the payer would mint
  // money, so the balance is checked and debited before the payout runs.
  let payerTransaction = null;
  if (mode === 'wallet') {
    const total = amount + tipAmount;
    const payer = await User.findById(req.user._id);
    const balance = Number(payer?.walletBalance || 0);
    if (balance < total) {
      res.status(400);
      throw new Error(
        `Your wallet has Rs ${balance.toFixed(2)}, which is short of the ` +
        `Rs ${total.toFixed(2)} due. Add money and try again.`
      );
    }
    payer.walletBalance = balance - total;
    await payer.save();
    payerTransaction = await Transaction.create({
      user: payer._id,
      type: 'wallet_deduct',
      amount: -total,
      balanceAfter: payer.walletBalance,
      reference: job._id,
      referenceModel: 'Job',
      note: `Paid for job ${job.title}`,
    });
  }

  const payment = await settleJob({
    job,
    freeJobsRemaining: req.user.freeJobsRemaining,
    methodLabel,
    mode,
    isCod,
    transactionId,
    payerName: req.user.name,
  });

  res.json({
    ok: true,
    paymentId: payment._id,
    payoutAmount: payment.payoutAmount,
    paymentReleasedAt: job.paymentReleasedAt,
    method: methodLabel,
    mode,
    isCod,
    transactionId,
    // So the app can show the giver their new balance straight away
    // rather than making them open the wallet to find out.
    walletBalance: payerTransaction ? payerTransaction.balanceAfter : undefined,
  });
});

// Moves the money and closes the job out. Shared by the direct release
// (giver taps Confirm & Pay) and the gateway confirmation, so both paths
// credit the worker, write the same transactions and stamp the job
// identically — there is exactly one place where a job becomes paid.
async function settleJob({
  job,
  freeJobsRemaining,
  methodLabel,
  mode,
  isCod,
  transactionId,
  payerName,
  gatewayOrderId,
  gatewayPaymentId,
  gatewayName,
}) {
  const amount = Number(job.finalPrice || 0);
  const tipAmount = job.tip || 0;

  // Reuse a held payment when one exists; otherwise create it outright so
  // the flow still works when the giver skipped /initiate + /confirm.
  let payment = await Payment.findOne({ job: job._id, status: 'on_hold' });
  const platformFee = calculatePlatformFee(amount, freeJobsRemaining);
  const payoutAmount = amount - platformFee + tipAmount;

  if (payment) {
    // Top up by any tip added after the hold was created, so the worker
    // still receives it.
    const missingTip = tipAmount - (payment.tipAmount || 0);
    if (missingTip > 0) {
      payment.tipAmount = tipAmount;
      payment.amount += missingTip;
      payment.payoutAmount += missingTip;
    }
    payment.status = 'released';
    payment.releasedAt = new Date();
    payment.method = methodLabel;
    payment.mode = resolvePaymentMode({ mode, isCod, method: methodLabel });
    payment.isCod = isCod;
    payment.transactionId = transactionId;
    if (gatewayOrderId) payment.gatewayOrderId = gatewayOrderId;
    if (gatewayPaymentId) payment.gatewayPaymentId = gatewayPaymentId;
    await payment.save();
  } else {
    payment = await Payment.create({
      job: job._id,
      jobgiver: job.jobgiver,
      jobtaker: job.selectedJobtaker,
      amount: amount + tipAmount,
      platformFee,
      tipAmount,
      payoutAmount,
      // Which rails the money actually took. 'manual' covers cash
      // and anything settled without a provider; a real gateway
      // payment says so, because a refund has to know whether there
      // is anything to reverse.
      gateway: gatewayName || 'manual',
      status: 'released',
      releasedAt: new Date(),
      method: methodLabel,
      mode: resolvePaymentMode({ mode, isCod, method: methodLabel }),
      isCod,
      transactionId,
      gatewayOrderId,
      gatewayPaymentId,
    });
  }

  // Credit the worker wallet and write a payout transaction.
  //
  // Cash is the exception: the giver handed the money over in person, so
  // the worker already holds it. Crediting the wallet as well paid them
  // twice — once in hand, once in the app. For cash the balance is left
  // alone and the payout is recorded for earnings history only, at the
  // full amount they were handed.
  const taker = await User.findById(payment.jobtaker);
  if (taker) {
    const received = isCod ? payment.amount || 0 : payment.payoutAmount || 0;
    if (!isCod) {
      taker.walletBalance = (taker.walletBalance || 0) + received;
    }
    if (taker.freeJobsRemaining > 0) taker.freeJobsRemaining -= 1;
    await taker.save();
    await Transaction.create({
      user: taker._id,
      type: 'payout',
      amount: received,
      balanceAfter: taker.walletBalance || 0,
      reference: payment._id,
      referenceModel: 'Payment',
      isCash: isCod,
      note: isCod
        ? `Cash received for job ${job.title}`
        : `Payout for job ${job.title}`,
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
      title: 'Payment received',
      body: isCod
        ? `${payerName || 'The client'} paid you Rs ${received} in cash`
        : `Rs ${received} credited to your wallet`,
      data: { paymentId: payment._id, jobId: job._id },
    });
  }

  job.paymentReleasedAt = new Date();
  await job.save();
  return payment;
}

// --------------------------------------------------------------- gateway
//
// Two-step flow matching how real PSPs work, so swapping the dummy for a
// live gateway doesn't change the app:
//   1. POST /payments/jobs/:jobId/order    -> order + a UPI URI to pay
//   2. POST /payments/jobs/:jobId/confirm  -> verify, then settle the job
// Either party may open the order (the giver pays; the worker shows the
// QR), but only a verified confirmation moves money.

const createGatewayOrder = asyncHandler(async (req, res) => {
  const job = await Job.findById(req.params.jobId).populate(
    'selectedJobtaker',
    'name upiId',
  );
  if (!job) { res.status(404); throw new Error('Job not found'); }

  const me = req.user._id.toString();
  const isGiver = job.jobgiver.toString() === me;
  const isTaker = job.selectedJobtaker && job.selectedJobtaker._id.toString() === me;
  if (!isGiver && !isTaker) {
    res.status(403); throw new Error('Not part of this job');
  }
  if (job.status !== 'completed') {
    res.status(400); throw new Error('Job not completed');
  }
  if (job.paymentReleasedAt) {
    res.status(400); throw new Error('Payment already released');
  }

  // The worker is the payee — the QR must credit them, not the platform.
  const taker = job.selectedJobtaker;
  const amount = Number(job.finalPrice || 0) + Number(job.tip || 0);
  if (!amount || amount <= 0) {
    res.status(400); throw new Error('Final price not set');
  }

  const order = await gateway.createOrder({
    amount,
    jobId: job._id.toString(),
    payeeName: taker?.name || 'Pargig Worker',
    payeeVpa: taker?.upiId,
    notes: { purpose: 'job', jobTitle: String(job.title || '').slice(0, 80) },
  });

  // Remember what this order was for. Confirmation reads the amount
  // back from here rather than from the request body, so no client can
  // pay one figure and claim another.
  await GatewayOrder.create({
    orderId: order.orderId,
    provider: order.provider,
    purpose: 'job',
    amount: order.amount,
    currency: order.currency,
    user: req.user._id,
    job: job._id,
    notes: { jobTitle: job.title },
  });

  res.json({
    ...order,
    jobTitle: job.title,
    payeeName: taker?.name || 'Worker',
    // The app opens the provider's checkout with these; `isDummy` is
    // what keeps the "simulate payment" affordance out of a live build.
    isDummy: order.isDummy,
  });
});

const confirmGatewayPayment = asyncHandler(async (req, res) => {
  const job = await Job.findById(req.params.jobId);
  if (!job) { res.status(404); throw new Error('Job not found'); }

  const me = req.user._id.toString();
  const isGiver = job.jobgiver.toString() === me;
  const isTaker =
    job.selectedJobtaker && job.selectedJobtaker.toString() === me;
  if (!isGiver && !isTaker) {
    res.status(403); throw new Error('Not part of this job');
  }
  if (job.status !== 'completed') {
    res.status(400); throw new Error('Job not completed');
  }
  // Idempotent: a double-tap or a retried webhook returns the existing
  // result rather than paying twice.
  if (job.paymentReleasedAt) {
    const existing = await Payment.findOne({ job: job._id }).sort('-createdAt');
    return res.json({
      ok: true,
      alreadyPaid: true,
      transactionId: existing?.transactionId || null,
      payoutAmount: existing?.payoutAmount || 0,
      paymentReleasedAt: job.paymentReleasedAt,
      method: existing?.method || 'Online',
    });
  }
  if (!job.selectedJobtaker) {
    res.status(400); throw new Error('No worker assigned');
  }

  const orderId = String(req.body.orderId || '');
  const opened = await GatewayOrder.findOne({ orderId });
  if (!opened) {
    res.status(400);
    throw new Error('Unknown order — open a new payment and try again');
  }
  if (opened.purpose !== 'job' || String(opened.job) !== job._id.toString()) {
    res.status(400);
    throw new Error('This order belongs to a different payment');
  }

  const verdict = await gateway.confirmOrder({
    orderId,
    paymentId: req.body.paymentId,
    signature: req.body.signature,
  });
  if (!verdict.ok) {
    opened.status = 'failed';
    opened.failureReason = String(verdict.reason || '').slice(0, 300);
    await opened.save();
    res.status(400);
    throw new Error(verdict.reason || 'Payment could not be verified');
  }

  // Claim the order before settling. A double tap, or a tap racing the
  // webhook, both reach here; only the one that wins this update is
  // allowed to move money.
  const claimed = await GatewayOrder.findOneAndUpdate(
    { _id: opened._id, settledAt: null },
    {
      $set: {
        status: 'paid',
        settledAt: new Date(),
        paymentId: verdict.paymentId,
        signature: verdict.signature,
      },
    },
    { new: true },
  );
  if (!claimed) {
    res.status(409);
    throw new Error('This order has already been settled');
  }

  const methodLabel =
    typeof req.body.methodLabel === 'string' && req.body.methodLabel.trim()
      ? req.body.methodLabel.trim().slice(0, 60)
      : 'UPI';
  const transactionId = generateTransactionId();

  // Fee is charged against the giver's free-job allowance regardless of
  // who tapped confirm, so a worker-initiated confirmation prices the
  // same as a giver-initiated one.
  const giver = await User.findById(job.jobgiver).select('freeJobsRemaining name');
  const payment = await settleJob({
    job,
    freeJobsRemaining: giver?.freeJobsRemaining,
    methodLabel,
    // The gateway path is never cash. What the provider says the
    // payer actually used beats both the client's hint and the
    // human label — the app offers "UPI" and the payer may well tap
    // a card on the checkout sheet.
    mode: resolvePaymentMode({
      mode: verdict.method || req.body.mode,
      isCod: false,
      method: methodLabel,
    }),
    isCod: false,
    transactionId,
    payerName: giver?.name,
    gatewayOrderId: orderId,
    gatewayPaymentId: verdict.paymentId,
    gatewayName: verdict.provider === 'razorpay' ? 'razorpay' : 'manual',
  });

  res.json({
    ok: true,
    transactionId,
    paymentId: payment._id,
    payoutAmount: payment.payoutAmount,
    paymentReleasedAt: job.paymentReleasedAt,
    method: methodLabel,
    mode: payment.mode,
    isCod: false,
  });
});

const refundPayment = asyncHandler(async (req, res) => {
  // admin-only via routes
  const payment = await Payment.findById(req.params.id);
  if (!payment) { res.status(404); throw new Error('Payment not found'); }
  if (!['on_hold', 'paid'].includes(payment.status)) {
    res.status(400); throw new Error('Cannot refund in current state');
  }
  // Try to send it back the way it came. A gateway payment can be
  // reversed to the same card or UPI handle; cash and wallet payments
  // never touched the provider, so there is nothing there to reverse
  // and somebody has to move the money by hand.
  const attempt = await gateway.refundPayment({
    paymentId: payment.gatewayPaymentId,
    amount: payment.amount,
    reason: req.body.reason,
    gateway: payment.gateway,
  });
  // A provider that was reachable and said no is a failure worth
  // stopping on: marking the payment refunded when it isn't would put
  // the books out by the whole amount.
  if (!attempt.ok && !attempt.manual) {
    res.status(502);
    throw new Error(`Gateway refused the refund: ${attempt.reason}`);
  }

  payment.status = 'refunded';
  payment.refundedAt = new Date();
  payment.refundReason = req.body.reason;
  if (attempt.ok) payment.gatewayRefundId = attempt.id;
  await payment.save();

  await Transaction.create({
    user: payment.jobgiver,
    type: 'refund',
    amount: payment.amount,
    reference: payment._id,
    referenceModel: 'Payment',
    note: attempt.ok
      ? `Refund via gateway: ${req.body.reason || ''}`
      : `Refund (pay out manually): ${req.body.reason || ''}`
  });
  res.json({
    ...payment.toObject(),
    refundedThroughGateway: attempt.ok,
    // True when an admin still has to move the money themselves.
    needsManualPayout: !attempt.ok,
    refundNote: attempt.ok ? null : attempt.reason,
  });
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
  const txns = await Transaction.find({ user: req.user._id })
    .sort('-createdAt')
    .limit(200);
  const totalEarnings = txns
    .filter((t) => t.type === 'payout')
    .reduce((s, t) => s + t.amount, 0);

  // Calendar-month buckets for the wallet's Earnings Summary. Computed
  // from payouts only — a wallet top-up is the user's own money moving
  // in, not something they earned.
  const now = new Date();
  const thisMonthStart = new Date(now.getFullYear(), now.getMonth(), 1);
  const lastMonthStart = new Date(now.getFullYear(), now.getMonth() - 1, 1);
  const sumPayouts = (from, to) =>
    txns
      .filter((t) => t.type === 'payout')
      .filter((t) => t.createdAt >= from && (!to || t.createdAt < to))
      .reduce((s, t) => s + t.amount, 0);

  res.json({
    walletBalance: req.user.walletBalance || 0,
    totalEarnings,
    thisMonthEarnings: sumPayouts(thisMonthStart, null),
    lastMonthEarnings: sumPayouts(lastMonthStart, thisMonthStart),
    transactions: txns,
  });
});

// Wallet top-ups run through the same gateway as job payments, so there
// is one payment path in the app rather than a second, weaker one. The
// old version credited the wallet the moment it was called, which meant
// anyone could mint themselves money by hitting the endpoint directly.
const createWalletOrder = asyncHandler(async (req, res) => {
  const amount = parseFloat(req.body.amount);
  if (!amount || amount <= 0 || !Number.isFinite(amount)) {
    res.status(400); throw new Error('Enter a valid amount');
  }
  if (amount > 100000) {
    res.status(400); throw new Error('Amount is too large');
  }
  const order = await gateway.createOrder({
    amount,
    jobId: `wallet-${req.user._id}`,
    payeeName: 'Pargig',
    payeeVpa: process.env.PLATFORM_UPI_VPA,
    notes: { purpose: 'wallet' },
  });
  await GatewayOrder.create({
    orderId: order.orderId,
    provider: order.provider,
    purpose: 'wallet',
    amount: order.amount,
    currency: order.currency,
    user: req.user._id,
  });
  res.json({ ...order, isDummy: order.isDummy });
});

const confirmWalletTopup = asyncHandler(async (req, res) => {
  const orderId = String(req.body.orderId || '');
  const opened = await GatewayOrder.findOne({ orderId });
  if (!opened) {
    res.status(400);
    throw new Error('Unknown order — start the top-up again');
  }
  if (opened.purpose !== 'wallet') {
    res.status(400);
    throw new Error('This order belongs to a different payment');
  }
  if (String(opened.user) !== req.user._id.toString()) {
    res.status(403);
    throw new Error('This order belongs to another account');
  }

  // THE amount. Not the one in the body: crediting what the client
  // claims would let anyone pay a rupee and bank ten thousand.
  const amount = Number(opened.amount);
  if (!amount || amount <= 0) {
    res.status(400); throw new Error('Order has no amount');
  }

  const verdict = await gateway.confirmOrder({
    orderId,
    paymentId: req.body.paymentId,
    signature: req.body.signature,
  });
  if (!verdict.ok) {
    opened.status = 'failed';
    opened.failureReason = String(verdict.reason || '').slice(0, 300);
    await opened.save();
    res.status(400);
    throw new Error(verdict.reason || 'Payment could not be verified');
  }

  // One credit per order, however many times this is called.
  const claimed = await GatewayOrder.findOneAndUpdate(
    { _id: opened._id, settledAt: null },
    {
      $set: {
        status: 'paid',
        settledAt: new Date(),
        paymentId: verdict.paymentId,
        signature: verdict.signature,
      },
    },
    { new: true },
  );
  if (!claimed) {
    res.status(409);
    throw new Error('This top-up has already been credited');
  }

  const user = await User.findById(req.user._id);
  user.walletBalance = (user.walletBalance || 0) + amount;
  await user.save();

  const method =
    typeof req.body.methodLabel === 'string' && req.body.methodLabel.trim()
      ? req.body.methodLabel.trim().slice(0, 60)
      : 'Online';
  const transactionId = generateTransactionId();
  await Transaction.create({
    user: user._id,
    type: 'wallet_topup',
    amount,
    balanceAfter: user.walletBalance,
    note: `Added to wallet via ${method}`,
  });

  res.json({
    ok: true,
    walletBalance: user.walletBalance,
    amount,
    method,
    transactionId,
  });
});

// --------------------------------------------------------------- webhook
//
// Razorpay tells us what happened out of band, which matters because
// the in-app confirmation is the fragile half of the flow: the payer
// can lose signal, background the app, or kill it between paying and
// the confirm call landing. Without this, their money is gone and the
// worker is still waiting.
//
// Public route, no session — the signature IS the authentication.

const razorpayWebhook = asyncHandler(async (req, res) => {
  const config = await gatewayConfig.getConfig();
  const signature = req.headers['x-razorpay-signature'];

  if (!config.webhookSecret) {
    // Nothing to check it with. Accept so Razorpay stops retrying, but
    // do not act on it: an unverified webhook is a stranger's claim
    // that someone paid.
    return res.status(202).json({ ok: false, reason: 'No webhook secret configured' });
  }
  const valid = razorpay.verifyWebhookSignature({
    webhookSecret: config.webhookSecret,
    rawBody: req.rawBody,
    signature,
  });
  if (!valid) {
    res.status(400);
    throw new Error('Invalid webhook signature');
  }

  const event = req.body?.event;
  const entity =
    req.body?.payload?.payment?.entity || req.body?.payload?.refund?.entity;
  const orderId = entity?.order_id;

  // Always 200 from here on. A non-2xx makes Razorpay retry for 24
  // hours, and an event we cannot act on will not become actionable on
  // the fourth attempt.
  if (!orderId) return res.json({ ok: true, ignored: event || 'unknown' });

  const opened = await GatewayOrder.findOne({ orderId });
  if (!opened) return res.json({ ok: true, ignored: 'unknown order' });

  if (event === 'payment.failed') {
    if (!opened.settledAt) {
      opened.status = 'failed';
      opened.failureReason = String(
        entity?.error_description || 'Payment failed',
      ).slice(0, 300);
      await opened.save();
    }
    return res.json({ ok: true });
  }

  if (event !== 'payment.captured') {
    return res.json({ ok: true, ignored: event });
  }

  // Claim it the same way the in-app path does, so whichever arrives
  // first settles and the other finds the door closed.
  const claimed = await GatewayOrder.findOneAndUpdate(
    { _id: opened._id, settledAt: null },
    {
      $set: {
        status: 'paid',
        settledAt: new Date(),
        paymentId: entity.id,
      },
    },
    { new: true },
  );
  if (!claimed) return res.json({ ok: true, alreadySettled: true });

  try {
    if (claimed.purpose === 'wallet') {
      const user = await User.findById(claimed.user);
      if (user) {
        user.walletBalance = (user.walletBalance || 0) + claimed.amount;
        await user.save();
        await Transaction.create({
          user: user._id,
          type: 'wallet_topup',
          amount: claimed.amount,
          balanceAfter: user.walletBalance,
          note: 'Added to wallet (confirmed by gateway)',
        });
      }
    } else if (claimed.job) {
      const job = await Job.findById(claimed.job);
      if (job && !job.paymentReleasedAt && job.selectedJobtaker) {
        const giver = await User.findById(job.jobgiver).select(
          'freeJobsRemaining name',
        );
        await settleJob({
          job,
          freeJobsRemaining: giver?.freeJobsRemaining,
          methodLabel: 'Online',
          mode: resolvePaymentMode({ mode: entity.method, isCod: false }),
          isCod: false,
          transactionId: generateTransactionId(),
          payerName: giver?.name,
          gatewayOrderId: orderId,
          gatewayPaymentId: entity.id,
          gatewayName: 'razorpay',
        });
      }
    }
  } catch (err) {
    // Settlement failed after the order was claimed. Say so loudly in
    // the logs and hand the claim back, so the in-app confirmation (or
    // Razorpay's retry) can try again rather than the money vanishing
    // into a settled-but-unpaid order.
    console.error('[razorpay webhook] settle failed', orderId, err.message);
    await GatewayOrder.updateOne(
      { _id: claimed._id },
      { $set: { settledAt: null, status: 'created', failureReason: err.message } },
    );
    res.status(500);
    throw new Error('Could not settle this payment');
  }

  res.json({ ok: true, settled: true });
});

module.exports = {
  requestPayment,
  razorpayWebhook,
  initiatePayment, confirmPayment, releasePayment, releaseForJob,
  createGatewayOrder, confirmGatewayPayment,
  refundPayment, myPayments, myEarnings,
  createWalletOrder, confirmWalletTopup
};
