const asyncHandler = require('express-async-handler');
const User = require('../models/userModel');
const Job = require('../models/jobModel');
const Payment = require('../models/paymentModel');
const Issue = require('../models/issueModel');
const Transaction = require('../models/transactionModel');
const Rating = require('../models/ratingModel');

const dashboard = asyncHandler(async (req, res) => {
  const [users, jobs, completedJobs, payments, issues, openIssues, revenueAgg] =
    await Promise.all([
      User.countDocuments({}),
      Job.countDocuments({}),
      Job.countDocuments({ status: 'completed' }),
      Payment.countDocuments({}),
      Issue.countDocuments({}),
      Issue.countDocuments({ status: { $in: ['open', 'under_review'] } }),
      Transaction.aggregate([
        { $match: { type: 'fee' } },
        { $group: { _id: null, total: { $sum: { $abs: '$amount' } } } }
      ])
    ]);
  res.json({
    users,
    jobs,
    completedJobs,
    payments,
    issues,
    openIssues,
    platformRevenue: revenueAgg[0]?.total || 0
  });
});

const listUsers = asyncHandler(async (req, res) => {
  const { q, page = 1, limit = 30, role, blocked } = req.query;
  const filter = {};
  if (q) filter.$or = [
    { name: { $regex: q, $options: 'i' } },
    { mobile: { $regex: q, $options: 'i' } }
  ];
  if (role) filter.roles = role;
  if (blocked === 'true') filter.isBlocked = true;
  const users = await User.find(filter)
    .sort('-createdAt')
    .skip((page - 1) * limit)
    .limit(parseInt(limit));
  const total = await User.countDocuments(filter);
  res.json({ users, total });
});

const setUserStatus = asyncHandler(async (req, res) => {
  const user = await User.findById(req.params.id);
  if (!user) { res.status(404); throw new Error('User not found'); }
  if (req.body.isBlocked !== undefined) user.isBlocked = !!req.body.isBlocked;
  if (req.body.blockReason !== undefined) user.blockReason = req.body.blockReason;
  if (req.body.isActive !== undefined) user.isActive = !!req.body.isActive;
  await user.save();
  res.json(user);
});

const deleteUser = asyncHandler(async (req, res) => {
  // Safety: an admin cannot delete their own account through the panel.
  // (Stops the "I just nuked the only admin and can't log in" footgun.)
  // The endpoint runs through requireAdmin, so the auth middleware sets
  // req.admin (not req.user) — reading req.user._id here crashed the
  // request with "Cannot read properties of undefined (reading '_id')".
  if (req.admin && req.params.id === req.admin._id.toString()) {
    res.status(400);
    throw new Error("You can't delete your own admin account");
  }
  const user = await User.findById(req.params.id);
  if (!user) {
    res.status(404);
    throw new Error('User not found');
  }
  await user.deleteOne();
  res.json({ ok: true, id: req.params.id });
});

const verifyDocument = asyncHandler(async (req, res) => {
  const { userId, docId, status, remark } = req.body;
  const user = await User.findById(userId);
  if (!user) { res.status(404); throw new Error('User not found'); }
  const doc = user.documents.id(docId);
  if (!doc) { res.status(404); throw new Error('Document not found'); }
  doc.status = status;
  doc.remark = remark;
  if (status === 'approved') {
    user.isVerifiedProfessional = true;
    user.badge = 'verified';
  }
  await user.save();
  res.json(user);
});

const listJobs = asyncHandler(async (req, res) => {
  const { status, page = 1, limit = 30 } = req.query;
  const filter = {};
  if (status) filter.status = status;
  const jobs = await Job.find(filter)
    .populate('jobgiver', 'name mobile')
    .populate('selectedJobtaker', 'name mobile')
    .sort('-createdAt')
    .skip((page - 1) * limit)
    .limit(parseInt(limit));
  const total = await Job.countDocuments(filter);
  res.json({ jobs, total });
});

const listPayments = asyncHandler(async (req, res) => {
  const { status, page = 1, limit = 30 } = req.query;
  const filter = {};
  if (status) filter.status = status;
  const payments = await Payment.find(filter)
    .populate('job', 'title status')
    .populate('jobgiver', 'name mobile')
    .populate('jobtaker', 'name mobile')
    .sort('-createdAt')
    .skip((page - 1) * limit)
    .limit(parseInt(limit));
  const total = await Payment.countDocuments(filter);
  res.json({ payments, total });
});

// Everything about one job in a single call, so support can answer "what
// actually happened here?" without touching the database. Includes the
// artefacts the mobile app produces but the list view can't show: the
// giver's voice note, the worker's completion proof, the live OTPs, who
// applied, and how the money settled.
const jobDetail = asyncHandler(async (req, res) => {
  const job = await Job.findById(req.params.id)
    .populate('jobgiver', 'name mobile photo rating isBlocked')
    .populate('selectedJobtaker', 'name mobile photo rating isBlocked')
    .populate('interested.jobtaker', 'name mobile photo rating jobsCompleted');
  if (!job) { res.status(404); throw new Error('Job not found'); }

  const [payments, ratings] = await Promise.all([
    Payment.find({ job: job._id }).sort('-createdAt'),
    Rating.find({ job: job._id })
      .populate('rater', 'name')
      .populate('ratee', 'name')
      .sort('-createdAt'),
  ]);

  res.json({ job, payments, ratings });
});

// One user with the context needed to action them: their money (balance
// plus the ledger behind it), their KYC document, and how much work
// they've actually done. The list view has none of this, so blocking or
// verifying someone was previously a decision made blind.
const userDetail = asyncHandler(async (req, res) => {
  const user = await User.findById(req.params.id).select('-otp -otpExpiresAt');
  if (!user) { res.status(404); throw new Error('User not found'); }

  const [transactions, postedJobs, workedJobs, ratings] = await Promise.all([
    Transaction.find({ user: user._id }).sort('-createdAt').limit(100),
    Job.countDocuments({ jobgiver: user._id }),
    Job.countDocuments({ selectedJobtaker: user._id }),
    Rating.find({ ratee: user._id })
      .populate('rater', 'name')
      .sort('-createdAt')
      .limit(50),
  ]);

  res.json({
    user,
    transactions,
    stats: { postedJobs, workedJobs, ratingCount: ratings.length },
    ratings,
  });
});

const reports = asyncHandler(async (req, res) => {
  const [totalUsers, totalJobs, completedJobs, cancelledJobs, totalRevenueAgg, totalEscrowAgg] =
    await Promise.all([
      User.countDocuments({}),
      Job.countDocuments({}),
      Job.countDocuments({ status: 'completed' }),
      Job.countDocuments({ status: 'cancelled' }),
      Transaction.aggregate([
        { $match: { type: 'fee' } },
        { $group: { _id: null, total: { $sum: { $abs: '$amount' } } } }
      ]),
      Payment.aggregate([
        { $match: { status: 'on_hold' } },
        { $group: { _id: null, total: { $sum: '$amount' } } }
      ])
    ]);
  res.json({
    totalUsers,
    totalJobs,
    completedJobs,
    cancelledJobs,
    platformRevenue: totalRevenueAgg[0]?.total || 0,
    inEscrow: totalEscrowAgg[0]?.total || 0
  });
});

const seedSuperAdmin = asyncHandler(async (req, res) => {
  const Admin = require('../models/adminModel');
  const exists = await Admin.findOne({ email: 'admin@pargig.com' });
  if (exists) return res.json({ message: 'Already seeded', email: exists.email });
  const admin = await Admin.create({
    name: 'Super Admin',
    email: 'admin@pargig.com',
    password: 'admin@123',
    role: 'superadmin'
  });
  res.json({ message: 'Created', email: admin.email, password: 'admin@123' });
});

const seedDemoData = asyncHandler(async (req, res) => {
  const seedDemo = require('../utils/seedDemo');
  const wipe = req.query.wipe === '1' || req.body?.wipe === true;
  const result = await seedDemo({ wipe });
  res.json({ message: wipe ? 'Demo data wiped & re-seeded' : 'Demo data seeded', ...result });
});

module.exports = {
  dashboard,
  listUsers, setUserStatus, deleteUser, verifyDocument,
  listJobs, jobDetail, listPayments,
  userDetail,
  reports, seedSuperAdmin, seedDemoData
};
