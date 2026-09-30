const asyncHandler = require('express-async-handler');
const Issue = require('../models/issueModel');
const Job = require('../models/jobModel');
const { pushToUser } = require('../utils/notify');

const OPEN_STATES = ['open', 'under_review'];

/**
 * The issue types and their sub-issues, for the Need Help screens.
 *
 * `role` picks the catalogue: a giver complains about the work, a worker
 * about the client, and offering either side the other's list would let
 * them file something that cannot be true of them.
 */
const issueCatalog = asyncHandler(async (req, res) => {
  const role = req.query.role === 'jobtaker' ? 'jobtaker' : 'jobgiver';
  res.json({
    role,
    types: Issue.typesForRole(role),
    subIssues: Issue.SUB_ISSUES
  });
});

/**
 * Job History: this user's completed jobs, with any issue they have
 * already raised against each one attached.
 *
 * Completed only, by design — Need Help asks about work that has been
 * done, and an open job has nothing to report yet.
 *
 * `role` decides which side of the job they are on, and therefore which
 * jobs are theirs and who the counterparty is. Both are populated either
 * way: the card names the other person, and which one that is depends on
 * who is looking.
 */
const jobHistory = asyncHandler(async (req, res) => {
  const role = req.query.role === 'jobtaker' ? 'jobtaker' : 'jobgiver';
  const mine = role === 'jobtaker'
    ? { selectedJobtaker: req.user._id }
    : { jobgiver: req.user._id };

  const jobs = await Job.find({
    ...mine,
    status: { $in: ['completed', 'disputed'] }
  })
    .populate('selectedJobtaker', 'name photo rating jobsCompleted isVerified')
    .populate('jobgiver', 'name photo rating isVerified')
    .sort('-updatedAt')
    .lean();

  if (jobs.length === 0) return res.json({ jobs: [], total: 0 });

  // Attach the issue behind each job so the list can mark rows the user
  // has already reported, without a request per card. Scoped to their own
  // issues: whether the other side has complained about them is not shown
  // here, and would only invite a tit-for-tat.
  const issues = await Issue.find({
    job: { $in: jobs.map((j) => j._id) },
    raisedBy: req.user._id
  })
    .sort('-createdAt')
    .lean();
  const latest = new Map();
  for (const i of issues) {
    const key = i.job.toString();
    if (!latest.has(key)) latest.set(key, i);
  }
  for (const job of jobs) {
    const i = latest.get(job._id.toString());
    job.issue = i
      ? { _id: i._id, code: i.code, status: i.status, issueType: i.issueType }
      : null;
  }

  res.json({ role, jobs, total: jobs.length });
});

/** Raises an issue against one completed job. */
const createIssue = asyncHandler(async (req, res) => {
  const { jobId, issueType, subIssues, description, photos } = req.body;

  const text = typeof description === 'string' ? description.trim() : '';
  // Matches the app's own counter, so a message the app accepted is never
  // rejected here and vice versa.
  if (text.length < 10) {
    res.status(400);
    throw new Error('Describe the issue in at least 10 characters');
  }
  if (text.length > 500) {
    res.status(400);
    throw new Error('Keep the description under 500 characters');
  }

  const job = await Job.findById(jobId);
  if (!job) { res.status(404); throw new Error('Job not found'); }

  // Which side of this job they are. Derived from the job itself rather
  // than trusted from the request: the role decides which catalogue
  // applies, so letting the caller assert it would let a giver file a
  // worker's complaint about themselves.
  const me = req.user._id.toString();
  const isGiver = job.jobgiver.toString() === me;
  const isTaker = job.selectedJobtaker
    && job.selectedJobtaker.toString() === me;
  if (!isGiver && !isTaker) {
    res.status(403);
    throw new Error('This is not your job');
  }
  const role = isGiver ? 'jobgiver' : 'jobtaker';

  if (!Issue.typesForRole(role).includes(issueType)) {
    res.status(400);
    throw new Error('Choose what kind of issue this is');
  }

  if (!['completed', 'disputed'].includes(job.status)) {
    res.status(400);
    throw new Error('You can only report an issue on a completed job');
  }

  // One open issue per job: tapping Need Help twice would otherwise create
  // two tickets over the same work for support to resolve separately.
  const existing = await Issue.findOne({
    job: jobId,
    raisedBy: req.user._id,
    status: { $in: OPEN_STATES }
  });
  if (existing) {
    res.status(409);
    throw new Error(`You already have an open issue (${existing.code}) for this job`);
  }

  // Only sub-issues this type actually offers, so a stale app build
  // cannot file a ticket saying something the type does not mean.
  const allowed = Issue.SUB_ISSUES[issueType] || [];
  const picked = Array.isArray(subIssues)
    ? subIssues.filter((s) => allowed.includes(s))
    : [];

  const issue = await Issue.create({
    job: jobId,
    raisedBy: req.user._id,
    raisedByRole: role,
    against: isGiver ? job.selectedJobtaker : job.jobgiver,
    issueType,
    subIssues: picked,
    description: text,
    photos: Array.isArray(photos) ? photos.filter(Boolean).slice(0, 10) : []
  });

  await pushToUser(req.user._id, {
    type: 'dispute',
    title: 'Issue submitted',
    body: `We have your report on "${job.title}" (${issue.code}). Our team will review it and get back to you.`,
    data: { issueId: issue._id, jobId: job._id }
  });

  res.status(201).json(issue);
});

/** The issues this user has raised, newest first. */
const myIssues = asyncHandler(async (req, res) => {
  const issues = await Issue.find({ raisedBy: req.user._id })
    .populate('job', 'title category')
    .sort('-createdAt')
    .limit(100);
  res.json({ issues, total: issues.length });
});

/** One issue, for the user who raised it. */
const getIssue = asyncHandler(async (req, res) => {
  const issue = await Issue.findById(req.params.id)
    .populate('job', 'title category finalPrice')
    .populate('against', 'name photo rating');
  if (!issue) { res.status(404); throw new Error('Issue not found'); }
  if (issue.raisedBy.toString() !== req.user._id.toString()) {
    res.status(403);
    throw new Error('Not your issue');
  }
  res.json(issue);
});

// ------------------------------------------------------------- admin

/** Admin list, filterable by status and type. */
const adminListIssues = asyncHandler(async (req, res) => {
  const { status, issueType, role } = req.query;
  const page = Math.max(1, parseInt(req.query.page, 10) || 1);
  const limit = Math.min(100, Math.max(1, parseInt(req.query.limit, 10) || 20));

  const filter = {};
  // Comma-separated so a dashboard tile can link to "open,under_review"
  // and land on exactly the rows it counted.
  if (status) filter.status = { $in: String(status).split(',') };
  if (issueType) filter.issueType = issueType;
  if (role === 'jobgiver' || role === 'jobtaker') filter.raisedByRole = role;

  const [issues, total] = await Promise.all([
    Issue.find(filter)
      .populate('job', 'title category finalPrice')
      .populate('raisedBy', 'name mobile')
      .populate('against', 'name mobile')
      .sort('-createdAt')
      .skip((page - 1) * limit)
      .limit(limit),
    Issue.countDocuments(filter)
  ]);

  res.json({ issues, total, page, limit });
});

/** Everything about one issue, for the admin review screen. */
const adminIssueDetail = asyncHandler(async (req, res) => {
  const issue = await Issue.findById(req.params.id)
    .populate('job', 'title category description finalPrice status location scheduledAt')
    .populate('raisedBy', 'name mobile photo rating')
    .populate('against', 'name mobile photo rating jobsCompleted');
  if (!issue) { res.status(404); throw new Error('Issue not found'); }

  // Their history, so a pattern of complaints is visible at the point of
  // decision rather than after it.
  const [byUser, againstWorker] = await Promise.all([
    Issue.countDocuments({ raisedBy: issue.raisedBy?._id ?? issue.raisedBy }),
    issue.against
      ? Issue.countDocuments({ against: issue.against?._id ?? issue.against })
      : 0
  ]);

  res.json({ issue, otherIssuesByUser: byUser - 1, issuesAgainstWorker: againstWorker });
});

/** Moves an issue along, or closes it with a note. */
const adminUpdateIssue = asyncHandler(async (req, res) => {
  const { status, note } = req.body;
  const allowed = ['open', 'under_review', 'resolved', 'rejected'];
  if (!allowed.includes(status)) {
    res.status(400);
    throw new Error('Choose a valid status');
  }

  const issue = await Issue.findById(req.params.id).populate('job', 'title');
  if (!issue) { res.status(404); throw new Error('Issue not found'); }
  if (!OPEN_STATES.includes(issue.status)) {
    res.status(409);
    throw new Error(`This issue was already ${issue.status}`);
  }

  const closing = ['resolved', 'rejected'].includes(status);
  if (closing && !String(note || '').trim()) {
    // The note is what the user is shown. Closing without one leaves them
    // with a verdict and no reason for it.
    res.status(400);
    throw new Error('Add a note explaining the decision');
  }

  issue.status = status;
  if (note) {
    issue.resolution = {
      note: String(note).trim(),
      decidedBy: req.admin._id,
      decidedAt: closing ? new Date() : issue.resolution?.decidedAt
    };
  }
  await issue.save();

  if (closing) {
    await pushToUser(issue.raisedBy, {
      type: 'dispute',
      title: status === 'resolved' ? 'Issue resolved' : 'Issue reviewed',
      body: `${issue.code} for "${issue.job?.title || 'your job'}": ${issue.resolution.note}`,
      data: { issueId: issue._id, status }
    });
  }

  res.json(issue);
});

module.exports = {
  issueCatalog,
  jobHistory,
  createIssue,
  myIssues,
  getIssue,
  adminListIssues,
  adminIssueDetail,
  adminUpdateIssue
};
