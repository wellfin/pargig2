const asyncHandler = require('express-async-handler');
const mongoose = require('mongoose');
const User = require('../models/userModel');
const Job = require('../models/jobModel');
const Payment = require('../models/paymentModel');
const Issue = require('../models/issueModel');
const Transaction = require('../models/transactionModel');
const Rating = require('../models/ratingModel');

const dashboard = asyncHandler(async (req, res) => {
  const [
    users, jobs, completedJobs, payments, issues, openIssues,
    pendingVerifications, revenueAgg
  ] = await Promise.all([
      User.countDocuments({}),
      Job.countDocuments({}),
      Job.countDocuments({ status: 'completed' }),
      Payment.countDocuments({}),
      Issue.countDocuments({}),
      Issue.countDocuments({ status: { $in: ['open', 'under_review'] } }),
      // People waiting on a human decision. Counted per USER, not per
      // document: someone who sent three files is one queue entry, and
      // badging the sidebar with 3 would overstate the work.
      User.countDocuments({ 'documents.status': 'pending' }),
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
    pendingVerifications,
    platformRevenue: revenueAgg[0]?.total || 0
  });
});

// Every job status with its count, plus the lifecycle funnel.
//
// Status is where a job stands NOW, so it cannot answer "how many ever
// reached the worker-arrived step" — a completed job is only
// 'completed', and counting current statuses as a funnel would read as
// if those jobs never passed through the stages before it. The funnel
// is therefore built from the durable marks each stage leaves behind
// (an applicant, a hire, an issued start PIN, a completion stamp),
// which is why its steps only ever go down.
//
// One $facet so the whole panel costs a single round trip: the
// dashboard polls this every few seconds and a dozen countDocuments
// calls on every tick is not free.
const jobStats = asyncHandler(async (req, res) => {
  const [agg] = await Job.aggregate([
    {
      $facet: {
        total: [{ $count: 'n' }],
        byStatus: [{ $group: { _id: '$status', n: { $sum: 1 } } }],
        applied: [
          { $match: { 'interested.0': { $exists: true } } },
          { $count: 'n' }
        ],
        hired: [
          { $match: { selectedJobtaker: { $exists: true, $ne: null } } },
          { $count: 'n' }
        ],
        reached: [
          { $match: { 'startOtp.issuedAt': { $exists: true, $ne: null } } },
          { $count: 'n' }
        ],
        completed: [
          { $match: { completedAt: { $exists: true, $ne: null } } },
          { $count: 'n' }
        ]
      }
    }
  ]);

  const one = (arr) => (arr && arr[0] ? arr[0].n : 0);
  const total = one(agg?.total);

  // Seeded from the schema's enum rather than from what the grouping
  // happened to return, so a status with no jobs in it shows as 0
  // instead of vanishing from the panel.
  const statuses = Job.schema.path('status').enumValues;
  const counts = Object.fromEntries(statuses.map((s) => [s, 0]));
  for (const row of agg?.byStatus || []) {
    if (row._id) counts[row._id] = row.n;
  }

  res.json({
    total,
    byStatus: statuses.map((status) => ({
      status,
      count: counts[status],
      // Sent rather than divided in the browser so every surface that
      // reads this agrees on the rounding.
      percent: total > 0 ? Math.round((counts[status] / total) * 1000) / 10 : 0
    })),
    funnel: [
      { stage: 'created', label: 'Created', count: total },
      { stage: 'applied', label: 'Got applicants', count: one(agg?.applied) },
      { stage: 'hired', label: 'Worker hired', count: one(agg?.hired) },
      { stage: 'reached', label: 'Worker reached', count: one(agg?.reached) },
      { stage: 'completed', label: 'Completed', count: one(agg?.completed) }
    ].map((step) => ({
      ...step,
      percent: total > 0 ? Math.round((step.count / total) * 1000) / 10 : 0
    }))
  });
});

// Who is posting the work, and how much of it comes back.
//
// "Active" deliberately means posted a job in the last 30 days, not
// `isActive` on the account. An account nobody has disabled is not the
// same as a client who still uses the platform, and a marketplace that
// counts the first as the second flatters itself.
//
// 30 days rather than a caller-supplied window: every figure here is
// read against the others on one panel, and a window that moves per
// request would let two of them disagree.
const jobGiverInsights = asyncHandler(async (req, res) => {
  const WINDOW_DAYS = 30;
  const since = new Date(Date.now() - WINDOW_DAYS * 24 * 60 * 60 * 1000);
  const one = (arr) => (arr && arr[0] ? arr[0].n : 0);

  const [people, work] = await Promise.all([
    User.aggregate([
      { $match: { roles: 'jobgiver' } },
      {
        $facet: {
          total: [{ $count: 'n' }],
          joined: [{ $match: { createdAt: { $gte: since } } }, { $count: 'n' }],
          blocked: [{ $match: { isBlocked: true } }, { $count: 'n' }]
        }
      }
    ]),
    Job.aggregate([
      {
        $facet: {
          jobsAll: [{ $count: 'n' }],
          jobsRecent: [
            { $match: { createdAt: { $gte: since } } },
            { $count: 'n' }
          ],
          // Distinct givers who posted inside the window.
          active: [
            { $match: { createdAt: { $gte: since } } },
            { $group: { _id: '$jobgiver' } },
            { $count: 'n' }
          ],
          // Anyone who has ever posted, so "repeat" has a base that is
          // not the full signup list — most accounts never post at all.
          everPosted: [{ $group: { _id: '$jobgiver' } }, { $count: 'n' }],
          repeat: [
            { $group: { _id: '$jobgiver', n: { $sum: 1 } } },
            { $match: { n: { $gte: 2 } } },
            { $count: 'n' }
          ],
          top: [
            {
              $group: {
                _id: '$jobgiver',
                jobs: { $sum: 1 },
                completed: {
                  $sum: { $cond: [{ $eq: ['$status', 'completed'] }, 1, 0] }
                },
                lastPostedAt: { $max: '$createdAt' }
              }
            },
            { $sort: { jobs: -1, lastPostedAt: -1 } },
            { $limit: 8 },
            // Money actually settled to workers, not money promised:
            // an order that was opened and abandoned is not spend.
            {
              $lookup: {
                from: 'payments',
                let: { giver: '$_id' },
                pipeline: [
                  {
                    $match: {
                      $expr: { $eq: ['$jobgiver', '$$giver'] },
                      status: 'released'
                    }
                  },
                  { $group: { _id: null, total: { $sum: '$amount' } } }
                ],
                as: 'pay'
              }
            },
            {
              $lookup: {
                from: 'users',
                localField: '_id',
                foreignField: '_id',
                as: 'user'
              }
            },
            // A job whose giver has since been deleted keeps its row in
            // the jobs collection; without this it would surface here as
            // a blank name with a real count behind it.
            { $match: { 'user.0': { $exists: true } } },
            {
              $project: {
                _id: 1,
                jobs: 1,
                completed: 1,
                lastPostedAt: 1,
                spend: { $ifNull: [{ $arrayElemAt: ['$pay.total', 0] }, 0] },
                name: { $arrayElemAt: ['$user.name', 0] },
                mobile: { $arrayElemAt: ['$user.mobile', 0] },
                isBlocked: { $arrayElemAt: ['$user.isBlocked', 0] }
              }
            }
          ]
        }
      }
    ])
  ]);

  const p = people[0] || {};
  const w = work[0] || {};

  res.json({
    windowDays: WINDOW_DAYS,
    total: one(p.total),
    joined: one(p.joined),
    blocked: one(p.blocked),
    active: one(w.active),
    everPosted: one(w.everPosted),
    repeat: one(w.repeat),
    jobsAll: one(w.jobsAll),
    jobsRecent: one(w.jobsRecent),
    top: w.top || []
  });
});

// Who is doing the work, and what they take home.
//
// Mirrors jobGiverInsights, and keeps the same 30-day window so the two
// panels can be read against each other. "Active" is again the act, not
// the account: a worker who applied to something inside the window.
// Applications carry their own timestamp, so this is the real date the
// worker did something rather than the date the job was posted.
//
// Earnings come from the payout ledger, not from the payments. On a
// cash job the worker is handed the full amount in person and nothing
// is credited to their wallet, so summing payouts on the Payment
// records would quietly undercount every worker who takes cash. The
// transaction is what each of them actually received.
const jobTakerInsights = asyncHandler(async (req, res) => {
  const WINDOW_DAYS = 30;
  const since = new Date(Date.now() - WINDOW_DAYS * 24 * 60 * 60 * 1000);
  const one = (arr) => (arr && arr[0] ? arr[0].n : 0);
  const sum = (arr) => (arr && arr[0] ? arr[0].total : 0);

  const [people, work, earned] = await Promise.all([
    User.aggregate([
      { $match: { roles: 'jobtaker' } },
      {
        $facet: {
          total: [{ $count: 'n' }],
          joined: [{ $match: { createdAt: { $gte: since } } }, { $count: 'n' }],
          blocked: [{ $match: { isBlocked: true } }, { $count: 'n' }]
        }
      }
    ]),
    Job.aggregate([
      {
        $facet: {
          // Hired, all time and inside the window. A job counts as
          // accepted once a worker is on it, which is the giver's
          // decision — applying is not accepting.
          accepted: [
            { $match: { selectedJobtaker: { $exists: true, $ne: null } } },
            { $count: 'n' }
          ],
          acceptedRecent: [
            {
              $match: {
                selectedJobtaker: { $exists: true, $ne: null },
                createdAt: { $gte: since }
              }
            },
            { $count: 'n' }
          ],
          completed: [
            { $match: { completedAt: { $exists: true, $ne: null } } },
            { $count: 'n' }
          ],
          completedRecent: [
            { $match: { completedAt: { $gte: since } } },
            { $count: 'n' }
          ],
          // Distinct workers who applied to anything in the window.
          active: [
            { $unwind: '$interested' },
            { $match: { 'interested.createdAt': { $gte: since } } },
            { $group: { _id: '$interested.jobtaker' } },
            { $count: 'n' }
          ],
          everWorked: [
            { $match: { selectedJobtaker: { $exists: true, $ne: null } } },
            { $group: { _id: '$selectedJobtaker' } },
            { $count: 'n' }
          ],
          top: [
            { $match: { selectedJobtaker: { $exists: true, $ne: null } } },
            {
              $group: {
                _id: '$selectedJobtaker',
                accepted: { $sum: 1 },
                completed: {
                  $sum: { $cond: [{ $ne: ['$completedAt', null] }, 1, 0] }
                },
                lastJobAt: { $max: '$createdAt' }
              }
            },
            { $sort: { completed: -1, accepted: -1, lastJobAt: -1 } },
            { $limit: 8 },
            {
              $lookup: {
                from: 'transactions',
                let: { taker: '$_id' },
                pipeline: [
                  {
                    $match: {
                      $expr: { $eq: ['$user', '$$taker'] },
                      type: 'payout'
                    }
                  },
                  { $group: { _id: null, total: { $sum: '$amount' } } }
                ],
                as: 'paid'
              }
            },
            {
              $lookup: {
                from: 'users',
                localField: '_id',
                foreignField: '_id',
                as: 'user'
              }
            },
            // A deleted worker leaves their jobs behind; without this
            // the row would show a blank name over real counts.
            { $match: { 'user.0': { $exists: true } } },
            {
              $project: {
                _id: 1,
                accepted: 1,
                completed: 1,
                earned: { $ifNull: [{ $arrayElemAt: ['$paid.total', 0] }, 0] },
                name: { $arrayElemAt: ['$user.name', 0] },
                mobile: { $arrayElemAt: ['$user.mobile', 0] },
                rating: { $arrayElemAt: ['$user.rating.average', 0] },
                ratingCount: { $arrayElemAt: ['$user.rating.count', 0] },
                isBlocked: { $arrayElemAt: ['$user.isBlocked', 0] }
              }
            }
          ]
        }
      }
    ]),
    Transaction.aggregate([
      { $match: { type: 'payout' } },
      {
        $facet: {
          all: [{ $group: { _id: null, total: { $sum: '$amount' } } }],
          recent: [
            { $match: { createdAt: { $gte: since } } },
            { $group: { _id: null, total: { $sum: '$amount' } } }
          ]
        }
      }
    ])
  ]);

  const p = people[0] || {};
  const w = work[0] || {};
  const e = earned[0] || {};

  res.json({
    windowDays: WINDOW_DAYS,
    total: one(p.total),
    joined: one(p.joined),
    blocked: one(p.blocked),
    active: one(w.active),
    everWorked: one(w.everWorked),
    accepted: one(w.accepted),
    acceptedRecent: one(w.acceptedRecent),
    completed: one(w.completed),
    completedRecent: one(w.completedRecent),
    earnings: sum(e.all),
    earningsRecent: sum(e.recent),
    top: w.top || []
  });
});

// Jobs created, completed, cancelled and disputed over time, plus the
// value of the work that finished, bucketed for charting.
//
// Each measure is counted on its OWN date, not on the job's createdAt:
// a job posted in March and finished in April is a March creation and
// an April completion. Counting both on the posting date would draw two
// lines that rise and fall together and hide every delay between them,
// which is the one thing this chart exists to show.
//
// Buckets are chosen from the span rather than asked for, so Today is
// not a single dot and a quarter is not ninety cramped ticks. IST,
// because that is the day the people reading this work to.
const TZ = 'Asia/Kolkata';

const timeline = asyncHandler(async (req, res) => {
  const now = new Date();
  const parse = (v, fallback) => {
    const d = new Date(v);
    return v && !Number.isNaN(d.getTime()) ? d : fallback;
  };
  let to = parse(req.query.to, now);
  let from = parse(
    req.query.from,
    new Date(now.getTime() - 29 * 24 * 60 * 60 * 1000)
  );
  if (from > to) [from, to] = [to, from];
  // A range nobody asked for is a range nobody should be able to ask
  // for by accident: an open-ended `from` would scan the collection.
  const MAX_DAYS = 366;
  if (to - from > MAX_DAYS * 24 * 60 * 60 * 1000) {
    from = new Date(to.getTime() - MAX_DAYS * 24 * 60 * 60 * 1000);
  }
  const spanDays = (to - from) / (24 * 60 * 60 * 1000);
  const unit = spanDays <= 2 ? 'hour' : spanDays <= 70 ? 'day' : 'week';

  const bucket = (field) => ({
    $dateTrunc: { date: '$' + field, unit, timezone: TZ }
  });
  const within = (field) => ({ [field]: { $gte: from, $lte: to } });

  const [jobs, issues] = await Promise.all([
    Job.aggregate([
      {
        $facet: {
          created: [
            { $match: within('createdAt') },
            { $group: { _id: bucket('createdAt'), n: { $sum: 1 } } }
          ],
          completed: [
            { $match: within('completedAt') },
            {
              $group: {
                _id: bucket('completedAt'),
                n: { $sum: 1 },
                // What the job was actually worth: the agreed price
                // where one was settled, the asking price until then,
                // and the tip on top, because the giver paid that too.
                value: {
                  $sum: {
                    $add: [
                      {
                        $ifNull: [
                          '$finalPrice',
                          { $ifNull: ['$proposedBudget', 0] }
                        ]
                      },
                      { $ifNull: ['$tip', 0] }
                    ]
                  }
                }
              }
            }
          ],
          cancelled: [
            { $match: within('cancellation.at') },
            { $group: { _id: bucket('cancellation.at'), n: { $sum: 1 } } }
          ]
        }
      }
    ]),
    Issue.aggregate([
      { $match: within('createdAt') },
      { $group: { _id: bucket('createdAt'), n: { $sum: 1 } } }
    ])
  ]);

  const j = jobs[0] || {};
  const index = (rows) => {
    const m = new Map();
    for (const r of rows || []) {
      if (r._id) m.set(new Date(r._id).getTime(), r);
    }
    return m;
  };
  const created = index(j.created);
  const completed = index(j.completed);
  const cancelled = index(j.cancelled);
  const disputed = index(issues);

  const step =
    unit === 'hour' ? 3600e3 : unit === 'day' ? 86400e3 : 7 * 86400e3;
  // The aggregation truncates in IST, so match it here: shift into IST,
  // cut, shift back. Doing it in UTC would put every bucket 5.5 hours
  // off the ones the database produced and line up with none of them.
  const truncate = (d) => {
    const ist = new Date(new Date(d).getTime() + 5.5 * 3600e3);
    ist.setUTCMinutes(0, 0, 0);
    if (unit !== 'hour') ist.setUTCHours(0);
    if (unit === 'week') ist.setUTCDate(ist.getUTCDate() - ist.getUTCDay());
    return new Date(ist.getTime() - 5.5 * 3600e3);
  };

  // Walk the whole range and emit every bucket, the empty ones too. A
  // line drawn only through the days that had data slopes straight
  // across a quiet week as if nothing had stopped.
  const points = [];
  for (
    let t = truncate(from).getTime();
    t <= to.getTime() && points.length <= 400;
    t += step
  ) {
    const c = completed.get(t);
    points.push({
      t: new Date(t).toISOString(),
      created: created.get(t)?.n || 0,
      completed: c?.n || 0,
      cancelled: cancelled.get(t)?.n || 0,
      disputed: disputed.get(t)?.n || 0,
      value: c?.value || 0
    });
  }

  const sumOf = (key) => points.reduce((a, p) => a + p[key], 0);
  res.json({
    from: from.toISOString(),
    to: to.toISOString(),
    unit,
    points,
    totals: {
      created: sumOf('created'),
      completed: sumOf('completed'),
      cancelled: sumOf('cancelled'),
      disputed: sumOf('disputed'),
      value: sumOf('value')
    }
  });
});

// The queue: everything on the platform that wants a human to look at
// it, in one place.
//
// Each group carries a count AND the few worst rows, because a number
// on its own tells an admin there is a problem without telling them
// which one. The rows are the handful you would open first; the count
// is how deep the pile goes.
//
// Every threshold is named here rather than buried in a query, and
// each is sent back with the response so the panel can say "open more
// than 7 days" instead of "stale" — a number nobody can see is a
// number nobody can argue with.
const ALERT_RULES = {
  openDays: 7,
  reachedHours: 24,
  valueFloor: 5000,
  cancelWindowDays: 30,
  cancelMin: 3
};

const alerts = asyncHandler(async (req, res) => {
  const now = Date.now();
  const openBefore = new Date(now - ALERT_RULES.openDays * 86400e3);
  const reachedBefore = new Date(now - ALERT_RULES.reachedHours * 3600e3);
  const cancelSince = new Date(now - ALERT_RULES.cancelWindowDays * 86400e3);
  const LIMIT = 6;

  const brief = 'title status createdAt finalPrice proposedBudget tip location.city startOtp.issuedAt';

  // Count and sample in the same pass per group. Two round trips each,
  // but the panel refreshes on a slow timer and the alternative is a
  // facet per group for no real gain.
  const page = (filter, sort) =>
    Promise.all([
      Job.countDocuments(filter),
      Job.find(filter)
        .sort(sort)
        .limit(LIMIT)
        .select(brief)
        .populate('jobgiver', 'name mobile')
        .populate('selectedJobtaker', 'name mobile')
        .lean()
    ]);

  const [
    [disputedCount, disputedRows],
    [staleCount, staleRows],
    [stuckCount, stuckRows],
    valueAgg,
    cancellers
  ] = await Promise.all([
    page({ status: 'disputed' }, '-updatedAt'),
    // Posted, still nobody on it, and old enough that nobody is coming.
    page({ status: 'open', createdAt: { $lte: openBefore } }, 'createdAt'),
    // The worker arrived and the PIN went out, but the job never
    // started: either the client never shared the code or something
    // went wrong on the doorstep. Oldest first — that is the one that
    // has been waiting longest for an answer.
    page(
      { status: 'reached', 'startOtp.issuedAt': { $lte: reachedBefore } },
      'startOtp.issuedAt'
    ),
    Job.aggregate([
      {
        $match: {
          status: { $in: ['open', 'confirmed', 'reached', 'in_progress'] }
        }
      },
      {
        $addFields: {
          value: {
            $add: [
              { $ifNull: ['$finalPrice', { $ifNull: ['$proposedBudget', 0] }] },
              { $ifNull: ['$tip', 0] }
            ]
          }
        }
      },
      { $match: { value: { $gte: ALERT_RULES.valueFloor } } },
      { $sort: { value: -1 } },
      {
        $facet: {
          count: [{ $count: 'n' }],
          rows: [
            { $limit: LIMIT },
            {
              $project: {
                title: 1,
                status: 1,
                value: 1,
                createdAt: 1,
                city: '$location.city'
              }
            }
          ]
        }
      }
    ]),
    Job.aggregate([
      {
        $match: {
          'cancellation.at': { $gte: cancelSince },
          // An admin cancellation is our own doing, not a pattern in
          // somebody's behaviour.
          'cancellation.by': { $in: ['jobgiver', 'jobtaker'] }
        }
      },
      {
        $addFields: {
          who: {
            $cond: [
              { $eq: ['$cancellation.by', 'jobgiver'] },
              '$jobgiver',
              '$selectedJobtaker'
            ]
          }
        }
      },
      { $match: { who: { $ne: null } } },
      {
        $group: {
          _id: { who: '$who', side: '$cancellation.by' },
          n: { $sum: 1 },
          lastAt: { $max: '$cancellation.at' }
        }
      },
      { $match: { n: { $gte: ALERT_RULES.cancelMin } } },
      { $sort: { n: -1, lastAt: -1 } },
      { $limit: LIMIT },
      {
        $lookup: {
          from: 'users',
          localField: '_id.who',
          foreignField: '_id',
          as: 'user'
        }
      },
      { $match: { 'user.0': { $exists: true } } },
      {
        $project: {
          _id: 0,
          userId: '$_id.who',
          side: '$_id.side',
          n: 1,
          lastAt: 1,
          name: { $arrayElemAt: ['$user.name', 0] },
          mobile: { $arrayElemAt: ['$user.mobile', 0] }
        }
      }
    ])
  ]);

  const valueCount = valueAgg[0]?.count?.[0]?.n || 0;
  const valueRows = valueAgg[0]?.rows || [];

  res.json({
    rules: ALERT_RULES,
    groups: [
      {
        id: 'disputed',
        kind: 'job',
        label: 'Disputed jobs',
        hint: 'A job either side has raised a dispute on',
        tone: 'critical',
        count: disputedCount,
        rows: disputedRows
      },
      {
        id: 'stale',
        kind: 'job',
        label: 'Open with nobody on them',
        hint: `Posted more than ${ALERT_RULES.openDays} days ago and still unassigned`,
        tone: 'warning',
        count: staleCount,
        rows: staleRows
      },
      {
        id: 'stuck',
        kind: 'job',
        label: 'Stuck after the worker arrived',
        hint: `Start PIN issued more than ${ALERT_RULES.reachedHours} hours ago, job never started`,
        tone: 'serious',
        count: stuckCount,
        rows: stuckRows
      },
      {
        id: 'highValue',
        kind: 'job',
        label: 'High-value jobs in flight',
        hint: `Worth ₹${ALERT_RULES.valueFloor.toLocaleString('en-IN')} or more and not finished yet`,
        tone: 'watch',
        count: valueCount,
        rows: valueRows
      },
      {
        id: 'cancellers',
        kind: 'user',
        label: 'High cancellation activity',
        hint: `${ALERT_RULES.cancelMin} or more cancellations in the last ${ALERT_RULES.cancelWindowDays} days`,
        tone: 'warning',
        count: cancellers.length,
        rows: cancellers
      }
    ]
  });
});

// Where the work is, and how it ends up there.
//
// Cities are grouped case-insensitively and trimmed: "Noida", "noida "
// and "NOIDA" are one place, and leaving them as three would split a
// city's figures across three rows and rank none of them correctly.
// The label keeps the spelling the first row carried rather than
// forcing a casing of our own.
//
// The four buckets cover every status between them, so each row's
// split is a whole and the bar beside it can be read as one. Open
// folds in confirmed, reached and in progress — from a map's distance
// they are the same thing: started, not finished.
const geography = asyncHandler(async (req, res) => {
  const now = new Date();
  const parse = (v, fallback) => {
    const d = new Date(v);
    return v && !Number.isNaN(d.getTime()) ? d : fallback;
  };
  const to = parse(req.query.to, now);
  const from = parse(
    req.query.from,
    new Date(now.getTime() - 29 * 24 * 60 * 60 * 1000)
  );
  const TOP = 15;

  const countIf = (cond) => ({ $sum: { $cond: [cond, 1, 0] } });

  const [out] = await Job.aggregate([
    { $match: { createdAt: { $gte: from, $lte: to } } },
    {
      $addFields: {
        cityKey: {
          $toLower: { $trim: { input: { $ifNull: ['$location.city', ''] } } }
        },
        value: JOB_VALUE
      }
    },
    {
      $group: {
        _id: '$cityKey',
        label: { $first: '$location.city' },
        total: { $sum: 1 },
        open: countIf({
          $in: ['$status', ['open', 'confirmed', 'reached', 'in_progress']]
        }),
        completed: countIf({ $eq: ['$status', 'completed'] }),
        cancelled: countIf({ $eq: ['$status', 'cancelled'] }),
        disputed: countIf({ $eq: ['$status', 'disputed'] }),
        value: { $sum: '$value' }
      }
    },
    { $sort: { total: -1, _id: 1 } },
    {
      $facet: {
        rows: [{ $limit: TOP }],
        summary: [
          {
            $group: {
              _id: null,
              cities: { $sum: 1 },
              total: { $sum: '$total' },
              open: { $sum: '$open' },
              completed: { $sum: '$completed' },
              cancelled: { $sum: '$cancelled' },
              disputed: { $sum: '$disputed' },
              value: { $sum: '$value' }
            }
          }
        ]
      }
    }
  ]);

  const summary = out?.summary?.[0] || {
    cities: 0, total: 0, open: 0, completed: 0, cancelled: 0, disputed: 0, value: 0
  };
  const rows = (out?.rows || []).map((r) => ({
    // A job posted without a city still happened somewhere; it gets a
    // row of its own rather than being dropped, because a gap in the
    // address data is itself worth seeing.
    city: (r.label || '').trim() || 'No city recorded',
    total: r.total,
    open: r.open,
    completed: r.completed,
    cancelled: r.cancelled,
    disputed: r.disputed,
    value: r.value
  }));

  res.json({
    from: from.toISOString(),
    to: to.toISOString(),
    shown: rows.length,
    cities: summary.cities,
    totals: {
      total: summary.total,
      open: summary.open,
      completed: summary.completed,
      cancelled: summary.cancelled,
      disputed: summary.disputed,
      value: summary.value
    },
    rows
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

// Everyone waiting on an identity decision, oldest wait first.
//
// Until now the only route to a pending document was to already know
// whose it was and open that user — so a document nobody thought to
// look for simply sat there. A person who has handed over their
// Aadhaar and heard nothing has no way to chase it from the app
// either, which makes an unattended queue worse than a slow one.
//
// Ordered by the OLDEST pending upload per user, so the person who has
// waited longest is always at the top and nobody is starved by a
// steady trickle of newer arrivals.
const pendingVerifications = asyncHandler(async (req, res) => {
  const page = Math.max(1, parseInt(req.query.page, 10) || 1);
  const limit = Math.min(100, Math.max(1, parseInt(req.query.limit, 10) || 20));

  const [out] = await User.aggregate([
    { $match: { 'documents.status': 'pending' } },
    {
      $project: {
        name: 1,
        mobile: 1,
        photo: 1,
        roles: 1,
        createdAt: 1,
        isVerifiedProfessional: 1,
        isBlocked: 1,
        // Only the pending ones. A user's already-rejected uploads are
        // history; showing them beside the live one invites acting on
        // the wrong row.
        documents: {
          $filter: {
            input: '$documents',
            as: 'd',
            cond: { $eq: ['$$d.status', 'pending'] }
          }
        }
      }
    },
    { $addFields: { waitingSince: { $min: '$documents.uploadedAt' } } },
    { $sort: { waitingSince: 1 } },
    {
      $facet: {
        total: [{ $count: 'n' }],
        rows: [{ $skip: (page - 1) * limit }, { $limit: limit }]
      }
    }
  ]);

  res.json({
    users: out?.rows || [],
    total: out?.total?.[0]?.n || 0
  });
});

const verifyDocument = asyncHandler(async (req, res) => {
  const { userId, docId, status, remark } = req.body;
  const user = await User.findById(userId);
  if (!user) { res.status(404); throw new Error('User not found'); }
  const doc = user.documents.id(docId);
  if (!doc) { res.status(404); throw new Error('Document not found'); }
  if (!['approved', 'rejected', 'pending'].includes(status)) {
    res.status(400);
    throw new Error('status must be approved, rejected or pending');
  }
  doc.status = status;
  doc.remark = remark;

  // The badge follows the documents, in both directions. Setting it on
  // an approval but never clearing it meant one approved-then-revoked
  // document left a permanent "verified" mark on the profile, which is
  // exactly the claim the badge is supposed to make honestly.
  const stillApproved = user.documents.some((d) => d.status === 'approved');
  user.isVerifiedProfessional = stillApproved;
  if (stillApproved) {
    if (user.badge === 'none') user.badge = 'verified';
  } else if (user.badge === 'verified') {
    user.badge = 'none';
  }

  await user.save();
  res.json(user);
});

// A job's price for searching, sorting and display: the agreed figure
// once there is one, the asking figure until then. Defined once so the
// column, the price filter and the value sort can never disagree about
// what a job is worth. The tip is left out — it is the giver's extra,
// not the price the job was listed or settled at.
const JOB_VALUE = {
  $ifNull: ['$finalPrice', { $ifNull: ['$proposedBudget', 0] }]
};

const SORTS = {
  newest: { createdAt: -1 },
  oldest: { createdAt: 1 },
  value_desc: { value: -1, createdAt: -1 },
  value_asc: { value: 1, createdAt: -1 },
  // Alphabetical on the status string, so the same status groups
  // together; the secondary key keeps each group newest-first.
  status: { status: 1, createdAt: -1 }
};

// Anything the operator types goes through here before it reaches a
// regex, so a stray ( or * is searched for rather than compiled.
const escapeRegex = (v) => String(v).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

const listJobs = asyncHandler(async (req, res) => {
  const {
    status, q, city, from, to, minPrice, maxPrice, sort = 'newest'
  } = req.query;
  const page = Math.max(1, parseInt(req.query.page, 10) || 1);
  // 5000 is the export ceiling. A request for everything is still a
  // request somebody has to wait for, and an uncapped limit is how one
  // click reads the whole collection into memory.
  const limit = Math.min(5000, Math.max(1, parseInt(req.query.limit, 10) || 30));

  const match = {};
  if (status) match.status = status;
  if (city) match['location.city'] = { $regex: escapeRegex(city), $options: 'i' };

  const createdAt = {};
  const fromDate = from && new Date(from);
  const toDate = to && new Date(to);
  if (fromDate && !Number.isNaN(fromDate.getTime())) createdAt.$gte = fromDate;
  if (toDate && !Number.isNaN(toDate.getTime())) createdAt.$lte = toDate;
  if (Object.keys(createdAt).length) match.createdAt = createdAt;

  // One search box over four things: the job's id, its title, and the
  // names or numbers on either side of it. The people are resolved
  // first because the ids are what the jobs collection actually holds.
  const term = (q || '').trim();
  if (term) {
    const rx = { $regex: escapeRegex(term), $options: 'i' };
    const people = await User.find({ $or: [{ name: rx }, { mobile: rx }] })
      .select('_id')
      .limit(500)
      .lean();
    const ids = people.map((u) => u._id);
    const or = [
      { title: rx },
      { jobgiver: { $in: ids } },
      { selectedJobtaker: { $in: ids } }
    ];
    if (mongoose.isValidObjectId(term)) or.push({ _id: new mongoose.Types.ObjectId(term) });
    match.$or = or;
  }

  // An empty query string is not a number. Number('') is 0, which is
  // finite, so reading these with a bare Number() turned "no price
  // filter" into "price between 0 and 0" and hid every job on the
  // panel. A blank has to mean absent before it means anything else.
  const asNumber = (v) =>
    v === undefined || v === null || String(v).trim() === '' ? NaN : Number(v);

  const priceMatch = {};
  const min = asNumber(minPrice);
  const max = asNumber(maxPrice);
  if (Number.isFinite(min)) priceMatch.$gte = min;
  if (Number.isFinite(max)) priceMatch.$lte = max;

  const pipeline = [
    { $match: match },
    { $addFields: { value: JOB_VALUE } }
  ];
  if (Object.keys(priceMatch).length) pipeline.push({ $match: { value: priceMatch } });

  pipeline.push({
    $facet: {
      total: [{ $count: 'n' }],
      rows: [
        { $sort: SORTS[sort] || SORTS.newest },
        { $skip: (page - 1) * limit },
        { $limit: limit },
        // After the page is cut, so the join runs over one page of
        // jobs rather than over everything that matched.
        {
          $lookup: {
            from: 'users', localField: 'jobgiver', foreignField: '_id',
            pipeline: [{ $project: { name: 1, mobile: 1 } }], as: 'giver'
          }
        },
        {
          $lookup: {
            from: 'users', localField: 'selectedJobtaker', foreignField: '_id',
            pipeline: [{ $project: { name: 1, mobile: 1 } }], as: 'taker'
          }
        },
        {
          $project: {
            title: 1, status: 1, createdAt: 1, completedAt: 1, value: 1,
            finalPrice: 1, proposedBudget: 1, tip: 1, isUrgent: 1, category: 1,
            location: 1,
            jobgiver: { $arrayElemAt: ['$giver', 0] },
            selectedJobtaker: { $arrayElemAt: ['$taker', 0] }
          }
        }
      ]
    }
  });

  const [out] = await Job.aggregate(pipeline);
  res.json({
    jobs: out?.rows || [],
    total: out?.total?.[0]?.n || 0
  });
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
  listUsers, setUserStatus, deleteUser, verifyDocument, pendingVerifications,
  listJobs, jobDetail, jobStats, listPayments,
  jobGiverInsights, jobTakerInsights,
  timeline,
  alerts,
  geography,
  userDetail,
  reports, seedSuperAdmin, seedDemoData
};
