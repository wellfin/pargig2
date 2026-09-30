const User = require('../models/userModel');
const Job = require('../models/jobModel');
const Payment = require('../models/paymentModel');
const Rating = require('../models/ratingModel');
const Issue = require('../models/issueModel');
const Notification = require('../models/notificationModel');
const Transaction = require('../models/transactionModel');

const givers = [
  {
    mobile: '9810000001',
    name: 'Rohan Sharma',
    email: 'rohan.sharma@example.com',
    photo: 'https://i.pravatar.cc/150?img=11',
    location: { coordinates: [77.2090, 28.6139], address: 'Connaught Place', city: 'New Delhi', pincode: '110001' }
  },
  {
    mobile: '9810000002',
    name: 'Anita Verma',
    email: 'anita.verma@example.com',
    photo: 'https://i.pravatar.cc/150?img=47',
    location: { coordinates: [72.8777, 19.0760], address: 'Bandra West', city: 'Mumbai', pincode: '400050' }
  },
  {
    mobile: '9810000003',
    name: 'Karthik Iyer',
    email: 'karthik.iyer@example.com',
    photo: 'https://i.pravatar.cc/150?img=12',
    location: { coordinates: [77.5946, 12.9716], address: 'Koramangala', city: 'Bengaluru', pincode: '560034' }
  },
  {
    mobile: '9810000004',
    name: 'Priya Nair',
    email: 'priya.nair@example.com',
    photo: 'https://i.pravatar.cc/150?img=48',
    location: { coordinates: [78.4867, 17.3850], address: 'Banjara Hills', city: 'Hyderabad', pincode: '500034' }
  }
];

const takers = [
  {
    mobile: '9820000001',
    name: 'Suresh Kumar',
    email: 'suresh.k@example.com',
    photo: 'https://i.pravatar.cc/150?img=13',
    isVerifiedProfessional: true,
    badge: 'verified',
    rating: { average: 4.6, count: 24 },
    jobsCompleted: 24,
    walletBalance: 1840,
    documents: [
      { type: 'aadhaar', url: '/uploads/demo-aadhaar-1.jpg', status: 'approved', remark: 'Verified by admin' },
      { type: 'license', url: '/uploads/demo-license-1.jpg', status: 'approved' }
    ]
  },
  {
    mobile: '9820000002',
    name: 'Lakshmi Devi',
    email: 'lakshmi@example.com',
    photo: 'https://i.pravatar.cc/150?img=44',
    isVerifiedProfessional: true,
    badge: 'verified',
    rating: { average: 4.8, count: 51 },
    jobsCompleted: 51,
    walletBalance: 3260,
    documents: [
      { type: 'aadhaar', url: '/uploads/demo-aadhaar-2.jpg', status: 'approved' }
    ]
  },
  {
    mobile: '9820000003',
    name: 'Imran Khan',
    email: 'imran.k@example.com',
    photo: 'https://i.pravatar.cc/150?img=14',
    rating: { average: 4.2, count: 8 },
    jobsCompleted: 8,
    walletBalance: 420,
    documents: [
      { type: 'aadhaar', url: '/uploads/demo-aadhaar-3.jpg', status: 'pending' },
      { type: 'certification', url: '/uploads/demo-cert-3.jpg', status: 'pending' }
    ]
  },
  {
    mobile: '9820000004',
    name: 'Meera Pillai',
    email: 'meera.p@example.com',
    photo: 'https://i.pravatar.cc/150?img=45',
    rating: { average: 3.9, count: 12 },
    jobsCompleted: 12,
    jobsCancelled: 2,
    walletBalance: 220,
    documents: [
      { type: 'aadhaar', url: '/uploads/demo-aadhaar-4.jpg', status: 'rejected', remark: 'Photo unclear, please re-upload' }
    ]
  },
  {
    mobile: '9820000005',
    name: 'Vikram Singh',
    email: 'vikram@example.com',
    photo: 'https://i.pravatar.cc/150?img=15',
    isBlocked: true,
    blockReason: 'Multiple complaints about no-show',
    rating: { average: 2.4, count: 6 },
    jobsCompleted: 4,
    jobsCancelled: 5,
    documents: []
  }
];

const jobTemplates = [
  { title: 'Fix leaking kitchen tap', description: 'Hot water tap dripping continuously, need plumber today evening', category: 'Plumbing' },
  { title: 'Living room ceiling fan installation', description: 'New fan delivered, need installation + earthing check', category: 'Electrician' },
  { title: 'Deep cleaning 2BHK apartment', description: 'Move-in cleaning, kitchen + 2 bathrooms + bedrooms', category: 'Cleaning' },
  { title: 'AC service before summer', description: '1.5 ton split AC needs gas check and filter clean', category: 'AC Repair' },
  { title: 'Wall painting 1 bedroom', description: 'Asian Paints emulsion, off-white. Materials provided.', category: 'Painting' },
  { title: 'Sofa shifting to 3rd floor', description: '5-seater L-shape sofa, no lift available', category: 'Moving' },
  { title: 'Geyser not heating', description: 'Bajaj 25L geyser, indicator on but water cold', category: 'Electrician' },
  { title: 'Carpentry: shoe rack repair', description: 'Hinge broken on top shelf', category: 'Carpentry' }
];

async function seedDemo({ wipe = false } = {}) {
  if (wipe) {
    await Promise.all([
      User.deleteMany({ mobile: { $regex: /^98[12]0000/ } }),
      Job.deleteMany({}),
      Payment.deleteMany({}),
      Rating.deleteMany({}),
      Issue.deleteMany({}),
      Notification.deleteMany({}),
      Transaction.deleteMany({})
    ]);
  }

  // Upsert users
  const giverDocs = [];
  for (const g of givers) {
    const u = await User.findOneAndUpdate(
      { mobile: g.mobile },
      {
        $set: {
          name: g.name,
          email: g.email,
          photo: g.photo,
          roles: ['jobgiver'],
          activeRole: 'jobgiver',
          location: { type: 'Point', ...g.location }
        }
      },
      { upsert: true, new: true, setDefaultsOnInsert: true }
    );
    giverDocs.push(u);
  }

  const takerDocs = [];
  for (const t of takers) {
    const u = await User.findOneAndUpdate(
      { mobile: t.mobile },
      {
        $set: {
          name: t.name,
          email: t.email,
          photo: t.photo,
          roles: ['jobtaker'],
          activeRole: 'jobtaker',
          isVerifiedProfessional: !!t.isVerifiedProfessional,
          badge: t.badge || 'none',
          rating: t.rating || { average: 0, count: 0 },
          jobsCompleted: t.jobsCompleted || 0,
          jobsCancelled: t.jobsCancelled || 0,
          walletBalance: t.walletBalance || 0,
          isBlocked: !!t.isBlocked,
          blockReason: t.blockReason,
          documents: t.documents || []
        }
      },
      { upsert: true, new: true, setDefaultsOnInsert: true }
    );
    takerDocs.push(u);
  }

  // Helper to create a job in a given status
  const makeJob = async ({ giver, taker, template, status, finalPrice, daysAgo = 1 }) => {
    const created = new Date(Date.now() - daysAgo * 24 * 3600 * 1000);
    const baseLoc = giver.location?.coordinates || [77.2090, 28.6139];

    const job = await Job.create({
      jobgiver: giver._id,
      title: template.title,
      description: template.description,
      category: template.category,
      photos: [],
      location: {
        type: 'Point',
        coordinates: baseLoc,
        address: giver.location?.address,
        city: giver.location?.city,
        pincode: giver.location?.pincode
      },
      preference: 'anyone',
      priceMode: 'open',
      proposedBudget: Math.round(finalPrice * 0.9),
      finalPrice: ['open'].includes(status) ? null : finalPrice,
      status,
      selectedJobtaker: ['open'].includes(status) ? null : taker?._id,
      interested: taker
        ? [{ jobtaker: taker._id, proposedPrice: finalPrice, message: 'Available today, can start in 1 hour' }]
        : [],
      startOtp: ['reached', 'in_progress', 'completed'].includes(status)
        ? { code: '123456', issuedAt: created, verifiedAt: ['in_progress', 'completed'].includes(status) ? created : undefined }
        : undefined,
      completeOtp: status === 'completed'
        ? { code: '654321', issuedAt: created, verifiedAt: created }
        : undefined,
      startedAt: ['in_progress', 'completed'].includes(status) ? created : undefined,
      completedAt: status === 'completed' ? created : undefined,
      cancellation: status === 'cancelled'
        ? { by: 'jobtaker', reason: 'Got a closer job, sorry', at: created }
        : undefined,
      createdAt: created,
      updatedAt: created
    });
    return job;
  };

  // Seed jobs across all statuses
  const created = [];

  // OPEN — 2 jobs with multiple applicants
  let j = await makeJob({ giver: giverDocs[0], template: jobTemplates[0], status: 'open', finalPrice: 350, daysAgo: 0 });
  j.interested.push({ jobtaker: takerDocs[0]._id, proposedPrice: 380, message: 'Can come within 30 mins' });
  j.interested.push({ jobtaker: takerDocs[1]._id, proposedPrice: 320, message: 'Free this evening' });
  j.interested.push({ jobtaker: takerDocs[2]._id, proposedPrice: 350, message: 'Available now' });
  await j.save();
  created.push(j);

  created.push(await makeJob({ giver: giverDocs[1], template: jobTemplates[1], status: 'open', finalPrice: 800, daysAgo: 0 }));

  // CONFIRMED
  created.push(await makeJob({ giver: giverDocs[2], taker: takerDocs[0], template: jobTemplates[2], status: 'confirmed', finalPrice: 2200, daysAgo: 1 }));

  // REACHED
  created.push(await makeJob({ giver: giverDocs[0], taker: takerDocs[1], template: jobTemplates[3], status: 'reached', finalPrice: 600, daysAgo: 0 }));

  // IN PROGRESS
  created.push(await makeJob({ giver: giverDocs[3], taker: takerDocs[1], template: jobTemplates[4], status: 'in_progress', finalPrice: 4500, daysAgo: 0 }));

  // COMPLETED — multiple, with payments + ratings
  const completed1 = await makeJob({ giver: giverDocs[0], taker: takerDocs[0], template: jobTemplates[5], status: 'completed', finalPrice: 1200, daysAgo: 3 });
  const completed2 = await makeJob({ giver: giverDocs[1], taker: takerDocs[1], template: jobTemplates[6], status: 'completed', finalPrice: 750, daysAgo: 5 });
  const completed3 = await makeJob({ giver: giverDocs[2], taker: takerDocs[3], template: jobTemplates[7], status: 'completed', finalPrice: 480, daysAgo: 7 });
  created.push(completed1, completed2, completed3);

  // CANCELLED
  created.push(await makeJob({ giver: giverDocs[3], taker: takerDocs[2], template: jobTemplates[2], status: 'cancelled', finalPrice: 1800, daysAgo: 4 }));

  // A completed job with a payment still held behind it.
  const heldPaymentJob = await makeJob({ giver: giverDocs[1], taker: takerDocs[3], template: jobTemplates[0], status: 'completed', finalPrice: 500, daysAgo: 2 });
  created.push(heldPaymentJob);

  // ===== Payments =====
  // 3 completed jobs → released payments
  for (const cj of [completed1, completed2, completed3]) {
    const platformFee = Math.max(10, cj.finalPrice * 0.05);
    await Payment.create({
      job: cj._id,
      jobgiver: cj.jobgiver,
      jobtaker: cj.selectedJobtaker,
      amount: cj.finalPrice,
      platformFee,
      payoutAmount: cj.finalPrice - platformFee,
      gateway: 'razorpay',
      gatewayOrderId: `order_demo_${cj._id.toString().slice(-6)}`,
      gatewayPaymentId: `pay_demo_${cj._id.toString().slice(-6)}`,
      transactionId: `TXN-${cj._id.toString().slice(-6).toUpperCase()}`,
      status: 'released',
      heldAt: cj.createdAt,
      releasedAt: cj.completedAt
    });
    await Transaction.create({
      user: cj.jobgiver,
      type: 'fee',
      amount: -platformFee,
      reference: cj._id,
      referenceModel: 'Payment',
      note: 'Platform fee'
    });
    await Transaction.create({
      user: cj.selectedJobtaker,
      type: 'payout',
      amount: cj.finalPrice - platformFee,
      note: `Payout for: ${cj.title}`
    });
  }

  // In-progress job → on_hold payment
  const inProg = created.find((j) => j.status === 'in_progress');
  if (inProg) {
    const platformFee = Math.max(10, inProg.finalPrice * 0.05);
    await Payment.create({
      job: inProg._id,
      jobgiver: inProg.jobgiver,
      jobtaker: inProg.selectedJobtaker,
      amount: inProg.finalPrice,
      platformFee,
      payoutAmount: inProg.finalPrice - platformFee,
      gateway: 'razorpay',
      gatewayOrderId: `order_demo_${inProg._id.toString().slice(-6)}`,
      gatewayPaymentId: `pay_demo_${inProg._id.toString().slice(-6)}`,
      status: 'on_hold',
      heldAt: new Date()
    });
  }

  const platformFee = Math.max(10, heldPaymentJob.finalPrice * 0.05);
  await Payment.create({
    job: heldPaymentJob._id,
    jobgiver: heldPaymentJob.jobgiver,
    jobtaker: heldPaymentJob.selectedJobtaker,
    amount: heldPaymentJob.finalPrice,
    platformFee,
    payoutAmount: heldPaymentJob.finalPrice - platformFee,
    gateway: 'razorpay',
    gatewayOrderId: `order_demo_${heldPaymentJob._id.toString().slice(-6)}`,
    gatewayPaymentId: `pay_demo_${heldPaymentJob._id.toString().slice(-6)}`,
    status: 'on_hold',
    heldAt: new Date()
  });

  // Cancelled job → refunded payment
  const cancelled = created.find((j) => j.status === 'cancelled');
  if (cancelled) {
    await Payment.create({
      job: cancelled._id,
      jobgiver: cancelled.jobgiver,
      jobtaker: cancelled.selectedJobtaker,
      amount: cancelled.finalPrice,
      platformFee: 0,
      payoutAmount: 0,
      gateway: 'razorpay',
      gatewayOrderId: `order_demo_${cancelled._id.toString().slice(-6)}`,
      gatewayPaymentId: `pay_demo_${cancelled._id.toString().slice(-6)}`,
      status: 'refunded',
      heldAt: cancelled.createdAt,
      refundedAt: new Date(),
      refundReason: 'Job cancelled before start'
    });
    await Transaction.create({
      user: cancelled.jobgiver,
      type: 'refund',
      amount: cancelled.finalPrice,
      note: 'Refund: Job cancelled'
    });
  }

  // Initiated payment (giver started checkout, hasn't completed)
  await Payment.create({
    job: created[0]._id,
    jobgiver: created[0].jobgiver,
    amount: 350,
    platformFee: 17.5,
    payoutAmount: 332.5,
    gateway: 'razorpay',
    gatewayOrderId: `order_demo_pending`,
    status: 'initiated'
  });




  // ===== My Services demo set =====
  //
  // The My Services history, all owned by giverDocs[0] — the account
  // this seed reports as the sample login — so signing in as that mobile
  // shows the whole list without hunting for which demo user owns what.
  const svcTemplates = [
    { title: 'Home AC Repair', description: 'Service completed successfully. Cooling restored.', category: 'AC Repair' },
    { title: 'Plumbing Service', description: 'Kitchen sink pipe repair.', category: 'Plumbing' },
    { title: 'Electrical Repair', description: 'Living room wiring and socket replacement.', category: 'Electrical' },
    { title: 'Full Home Painting', description: 'Two-bedroom flat repaint, walls and ceiling.', category: 'Painting' },
    { title: 'Deep Cleaning', description: 'Full 2BHK deep clean including kitchen and bathrooms.', category: 'Cleaning' }
  ];

  // One completed service plus the payment sitting behind it.
  const makeService = async ({ taker, template, price, daysAgo, paymentStatus }) => {
    const job = await makeJob({
      giver: giverDocs[0],
      taker,
      template,
      status: 'completed',
      finalPrice: price,
      daysAgo
    });
    const fee = Math.max(10, Math.round(price * 0.05));
    await Payment.create({
      job: job._id,
      jobgiver: job.jobgiver,
      jobtaker: job.selectedJobtaker,
      amount: price,
      platformFee: fee,
      payoutAmount: price - fee,
      gateway: 'razorpay',
      gatewayOrderId: `order_svc_${job._id.toString().slice(-6)}`,
      gatewayPaymentId: `pay_svc_${job._id.toString().slice(-6)}`,
      transactionId: `TXN-${job._id.toString().slice(-6).toUpperCase()}`,
      status: paymentStatus,
      ...(paymentStatus === 'refunded'
        ? { refundedAt: new Date(), refundReason: 'Refunded to the customer' }
        : {}),
      ...(paymentStatus === 'released' ? { releasedAt: new Date() } : {})
    });
    return job;
  };

  const hoursAgo = (h) => new Date(Date.now() - h * 3600 * 1000);
  const daysBack = (d) => new Date(Date.now() - d * 24 * 3600 * 1000);

  // 1) UNDER REVIEW — payment still frozen in escrow, evidence attached.
  const svcAc = await makeService({
    taker: takerDocs[0], template: svcTemplates[0],
    price: 850, daysAgo: 3, paymentStatus: 'on_hold'
  });

  // 2) PARTIAL REFUND — the split outcome, matching the design's
  //    "Refund 500 / Released to Provider 350" breakdown.
  const svcPlumb = await makeService({
    taker: takerDocs[1], template: svcTemplates[1],
    price: 850, daysAgo: 12, paymentStatus: 'released'
  });

  // 3) FULL REFUND — provider never turned up.
  const svcElec = await makeService({
    taker: takerDocs[2], template: svcTemplates[2],
    price: 450, daysAgo: 18, paymentStatus: 'refunded'
  });

  // 4) REJECTED — the "we couldn't approve this" branch.
  const svcPaint = await makeService({
    taker: takerDocs[3], template: svcTemplates[3],
    price: 2000, daysAgo: 26, paymentStatus: 'released'
  });

  // 5) A clean completed service, so the row is
  //    reachable and the happy path can be walked end to end.
  await makeService({
    taker: takerDocs[0], template: svcTemplates[4],
    price: 1500, daysAgo: 6, paymentStatus: 'released'
  });

  // ===== Need Help issues =====
  //
  // One per state, all on giverDocs[0]'s jobs, so signing in as the
  // sample login shows a reported job, a job under review and a closed
  // one alongside jobs with no issue at all.
  await Issue.create({
    job: svcPlumb._id,
    raisedBy: svcPlumb.jobgiver,
    against: svcPlumb.selectedJobtaker,
    issueType: 'service_quality',
    subIssues: ['Poor Quality Work'],
    description: 'The sink still leaks after the repair and the area was left wet.',
    status: 'open'
  });

  await Issue.create({
    job: svcElec._id,
    raisedBy: svcElec.jobgiver,
    against: svcElec.selectedJobtaker,
    issueType: 'worker_behavior',
    subIssues: ['Arrived Late', 'Rude Behaviour'],
    description: 'Arrived two hours late and was short with us when asked about it.',
    status: 'under_review'
  });

  await Issue.create({
    job: svcPaint._id,
    raisedBy: svcPaint.jobgiver,
    against: svcPaint.selectedJobtaker,
    issueType: 'payment',
    subIssues: ['Extra Charges Demanded'],
    description: 'Asked for extra cash on top of the agreed price before finishing.',
    status: 'resolved',
    resolution: {
      note: 'Spoke to the worker; the extra amount was returned to you.',
      decidedAt: new Date()
    }
  });

  // Raised by a WORKER against a client, so the admin panel shows both
  // sides of the issue module out of the box.
  await Issue.create({
    job: completed3._id,
    raisedBy: completed3.selectedJobtaker,
    raisedByRole: 'jobtaker',
    against: completed3.jobgiver,
    issueType: 'payment_not_received',
    subIssues: ['Paid Less Than Agreed'],
    description: 'We agreed on a higher amount on the call but less was released.',
    status: 'open'
  });

  // 6) Cancelled — populates the Cancelled tab.
  await makeJob({
    giver: giverDocs[0], taker: takerDocs[1], template: svcTemplates[1],
    status: 'cancelled', finalPrice: 700, daysAgo: 9
  });

  // ===== Ratings =====
  await Rating.findOneAndUpdate(
    { job: completed1._id, rater: completed1.jobgiver },
    {
      $set: {
        ratee: completed1.selectedJobtaker,
        stars: 5,
        review: 'Excellent work, very professional and on time'
      }
    },
    { upsert: true, new: true }
  );
  await Rating.findOneAndUpdate(
    { job: completed1._id, rater: completed1.selectedJobtaker },
    {
      $set: {
        ratee: completed1.jobgiver,
        stars: 5,
        review: 'Clear instructions, paid quickly. Will work for again.'
      }
    },
    { upsert: true, new: true }
  );
  await Rating.findOneAndUpdate(
    { job: completed3._id, rater: completed3.jobgiver },
    {
      $set: {
        ratee: completed3.selectedJobtaker,
        stars: 3,
        review: 'Job done but took longer than promised'
      }
    },
    { upsert: true, new: true }
  );

  // ===== Notifications =====
  await Notification.create({
    user: giverDocs[0]._id,
    type: 'job_alert',
    title: 'New interest in your job',
    body: 'Suresh Kumar is interested in "Fix leaking kitchen tap"',
    isRead: false
  });
  await Notification.create({
    user: takerDocs[0]._id,
    type: 'job_status',
    title: 'You got the job!',
    body: 'You were selected for "Sofa shifting to 3rd floor"',
    isRead: true
  });
  await Notification.create({
    user: takerDocs[0]._id,
    type: 'payment',
    title: 'Payment released',
    body: '₹1140 credited to your wallet',
    isRead: false
  });

  return {
    counts: {
      givers: giverDocs.length,
      takers: takerDocs.length,
      jobs: await Job.countDocuments({}),
      payments: await Payment.countDocuments({}),
      ratings: await Rating.countDocuments({}),
      notifications: await Notification.countDocuments({}),
      transactions: await Transaction.countDocuments({}),
      issues: await Issue.countDocuments({})
    },
    sample: {
      jobgiverMobile: giverDocs[0].mobile,
      jobtakerMobile: takerDocs[0].mobile
    }
  };
}

module.exports = seedDemo;
