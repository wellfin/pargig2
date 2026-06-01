// Populates the Pargig DB with sample jobs so the mobile home screen shows
// data out of the box. Safe to re-run — idempotent on a tagged demo giver.
//
// Usage:
//   node seed.js                          # only seeds open jobs (Bangalore)
//   node seed.js +91XXXXXXXXXX            # also bumps stats for that user
//                                         # (rating, jobsCompleted, walletBalance,
//                                         #  plus completed jobs for the
//                                         #  earnings card)
//   node seed.js +91XXXXXXXXXX noida      # ALSO insert ~12 demo workers in
//                                         # concentric rings around Sector 135,
//                                         # Noida (0.3 km → 22 km) and place
//                                         # the user there as job-giver. Use
//                                         # this to test the nearby-workers
//                                         # ranking by distance.

const dotenv = require('dotenv');
dotenv.config();

const mongoose = require('mongoose');
const connectDB = require('./config/db');

const Job = require('./models/jobModel');
const User = require('./models/userModel');

const DEMO_GIVER_MOBILE = '9999900001';

// All locations are spread around Koramangala, Bangalore (default for the
// home screen header demo data). The Haversine distance from the screen's
// center is < ~3 km for every entry so the Jobs Near You list populates.
const BASE_LAT = 12.9352;
const BASE_LNG = 77.6245;

function jitter(amount = 0.015) {
  return (Math.random() - 0.5) * amount * 2;
}

function loc(name, addr) {
  return {
    type: 'Point',
    coordinates: [BASE_LNG + jitter(), BASE_LAT + jitter()],
    address: addr,
    city: name,
    state: 'Karnataka',
    pincode: '560034',
  };
}

const SAMPLE_JOBS = [
  {
    title: 'Kitchen sink leakage',
    description: 'Pipe under sink is dripping water; need urgent fix.',
    category: 'Plumbing',
    proposedBudget: 600,
    preference: 'experienced',
    priceMode: 'fixed',
    location: loc('Bangalore', '5th Block, Koramangala'),
  },
  {
    title: 'Bathroom tap replacement',
    description: 'Replace two old taps with new ones.',
    category: 'Plumbing',
    proposedBudget: 450,
    location: loc('Bangalore', '6th Block, Koramangala'),
  },
  {
    title: 'Bookshelf assembly',
    description: 'IKEA-style bookshelf, 4 shelves, with drawer.',
    category: 'Carpentry',
    proposedBudget: 800,
    location: loc('Bangalore', '7th Block, Koramangala'),
  },
  {
    title: 'Bedroom door repair',
    description: 'Door hinge loose; need carpenter for an hour.',
    category: 'Carpentry',
    proposedBudget: 350,
    location: loc('Bangalore', '4th Block, Koramangala'),
  },
  {
    title: 'Living room wall painting',
    description: 'One accent wall, paint provided. ~60 sq ft.',
    category: 'Painting',
    proposedBudget: 1500,
    location: loc('Bangalore', '1st Block, Koramangala'),
  },
  {
    title: 'Entire 1BHK painting',
    description: 'Full apartment, walls + ceilings. 2-day job.',
    category: 'Painting',
    proposedBudget: 9000,
    location: loc('Bangalore', '8th Block, Koramangala'),
  },
  {
    title: 'Deep cleaning - 2BHK',
    description: 'Move-out clean, kitchen + 2 baths + balcony.',
    category: 'Cleaning',
    proposedBudget: 1800,
    preference: 'experienced',
    priceMode: 'fixed',
    location: loc('Bangalore', '3rd Block, Koramangala'),
  },
  {
    title: 'Sofa & carpet cleaning',
    description: '3-seater sofa + 6x4 ft carpet.',
    category: 'Cleaning',
    proposedBudget: 700,
    location: loc('Bangalore', '2nd Block, Koramangala'),
  },
  {
    title: 'Ceiling fan installation',
    description: 'Two new fans, wiring already in place.',
    category: 'Electrical',
    proposedBudget: 500,
    location: loc('Bangalore', 'HSR Layout Sector 2'),
  },
  {
    title: 'Smart switch wiring',
    description: 'Replace 4 regular switches with smart ones.',
    category: 'Electrical',
    proposedBudget: 900,
    location: loc('Bangalore', 'HSR Layout Sector 6'),
  },
  {
    title: 'Evening babysitter',
    description: '3 hours, 6yo and 8yo, dinner included.',
    category: 'Babysitting',
    proposedBudget: 600,
    preference: 'experienced',
    location: loc('Bangalore', 'Indiranagar'),
  },
  {
    title: 'Weekend nanny',
    description: 'Sat & Sun afternoons, 4 hrs each.',
    category: 'Babysitting',
    proposedBudget: 1200,
    location: loc('Bangalore', 'BTM Layout'),
  },
  {
    title: 'Grocery pickup',
    description: 'Pick up grocery order from BigBasket store.',
    category: 'Delivery',
    proposedBudget: 200,
    location: loc('Bangalore', 'Sarjapur Road'),
  },
  {
    title: 'Move 1 bookshelf to new flat',
    description: 'Short distance, ~2 km, need 1-2 hands.',
    category: 'Helper',
    proposedBudget: 400,
    location: loc('Bangalore', 'Ejipura'),
  },
  {
    title: 'AC servicing - split AC',
    description: 'Filter clean, gas check.',
    category: 'Repair',
    proposedBudget: 700,
    preference: 'experienced',
    priceMode: 'fixed',
    location: loc('Bangalore', 'Koramangala 1st Block'),
  },
];

async function ensureDemoGiver() {
  let user = await User.findOne({ mobile: DEMO_GIVER_MOBILE });
  if (!user) {
    user = await User.create({
      mobile: DEMO_GIVER_MOBILE,
      name: 'Demo Job Giver',
      roles: ['jobgiver'],
      activeRole: 'jobgiver',
      location: {
        type: 'Point',
        coordinates: [BASE_LNG, BASE_LAT],
        address: 'Koramangala, Bangalore',
        city: 'Bangalore',
        state: 'Karnataka',
        pincode: '560034',
      },
    });
    console.log(`✓ Created demo giver user (${DEMO_GIVER_MOBILE})`);
  }
  return user;
}

async function seedJobs(giver) {
  // Wipe any prior demo jobs from this giver before re-seeding so the script
  // is idempotent.
  const removed = await Job.deleteMany({ jobgiver: giver._id });
  if (removed.deletedCount > 0) {
    console.log(`✓ Cleared ${removed.deletedCount} previous demo jobs`);
  }

  const docs = SAMPLE_JOBS.map((j) => ({
    ...j,
    jobgiver: giver._id,
    status: 'open',
  }));
  await Job.insertMany(docs);
  console.log(`✓ Inserted ${docs.length} open jobs across ${
    new Set(SAMPLE_JOBS.map((j) => j.category)).size
  } categories`);
}

const DEMO_WORKERS = [
  {
    mobile: '9999900011',
    name: 'Raj Kumar',
    skills: ['Plumbing', 'Electrical'],
    yearsOfExperience: '5-10 years',
    rating: { average: 4.8, count: 124 },
    jobsCompleted: 32,
    isVerifiedProfessional: true,
  },
  {
    mobile: '9999900012',
    name: 'Amit Singh',
    skills: ['Cleaning', 'Painting'],
    yearsOfExperience: '3-5 years',
    rating: { average: 4.9, count: 89 },
    jobsCompleted: 41,
    isVerifiedProfessional: true,
  },
  {
    mobile: '9999900013',
    name: 'Suresh Patel',
    skills: ['Carpentry', 'Repair'],
    yearsOfExperience: '5-10 years',
    rating: { average: 4.7, count: 156 },
    jobsCompleted: 67,
    isVerifiedProfessional: true,
  },
  {
    mobile: '9999900014',
    name: 'Kiran Verma',
    skills: ['Cleaning', 'Babysitting'],
    yearsOfExperience: '1-2 years',
    rating: { average: 4.6, count: 52 },
    jobsCompleted: 18,
    isVerifiedProfessional: false,
  },
];

async function ensureDemoWorkers() {
  for (const w of DEMO_WORKERS) {
    let user = await User.findOne({ mobile: w.mobile });
    const data = {
      mobile: w.mobile,
      name: w.name,
      roles: ['jobtaker'],
      activeRole: 'jobtaker',
      skills: w.skills,
      yearsOfExperience: w.yearsOfExperience,
      rating: w.rating,
      jobsCompleted: w.jobsCompleted,
      isVerifiedProfessional: w.isVerifiedProfessional,
      location: {
        type: 'Point',
        coordinates: [BASE_LNG + jitter(), BASE_LAT + jitter()],
        address: 'Koramangala, Bangalore',
        city: 'Bangalore',
        state: 'Karnataka',
        pincode: '560034',
      },
    };
    if (!user) {
      user = await User.create(data);
    } else {
      Object.assign(user, data);
      await user.save();
    }
  }
  console.log(`✓ Ensured ${DEMO_WORKERS.length} demo worker accounts (jobtakers near Koramangala)`);
}

async function seedActiveJobsForGiver(user) {
  // Wipe any prior demo-posted jobs from this giver to keep the script
  // idempotent. We tag them via the giver field — we don't touch jobs
  // posted from a different mobile flow.
  await Job.deleteMany({ jobgiver: user._id });

  const taker = await User.findOne({ mobile: '9999900011' });
  const docs = [
    {
      jobgiver: user._id,
      title: 'Home Cleaning',
      description: 'Need a deep clean of 2BHK before guests arrive.',
      category: 'Cleaning',
      proposedBudget: 500,
      priceMode: 'fixed',
      status: 'open',
      createdAt: new Date(Date.now() - 2 * 3600 * 1000),
      interested: taker
        ? [
            { jobtaker: taker._id, proposedPrice: 500, message: 'I can come today.' },
            { jobtaker: taker._id, proposedPrice: 480 },
            { jobtaker: taker._id, proposedPrice: 520 },
            { jobtaker: taker._id, proposedPrice: 500 },
            { jobtaker: taker._id, proposedPrice: 510 },
          ]
        : [],
      location: {
        type: 'Point',
        coordinates: [BASE_LNG + jitter(), BASE_LAT + jitter()],
        address: 'Koramangala 5th Block',
        city: 'Bangalore',
        state: 'Karnataka',
        pincode: '560034',
      },
    },
    {
      jobgiver: user._id,
      title: 'AC Repair',
      description: 'Bedroom AC not cooling, needs urgent service.',
      category: 'Repair',
      proposedBudget: 1200,
      priceMode: 'fixed',
      status: 'in_progress',
      selectedJobtaker: taker?._id,
      finalPrice: 1200,
      createdAt: new Date(Date.now() - 26 * 3600 * 1000),
      startedAt: new Date(Date.now() - 30 * 60 * 1000),
      location: {
        type: 'Point',
        coordinates: [BASE_LNG + jitter(), BASE_LAT + jitter()],
        address: 'Koramangala 6th Block',
        city: 'Bangalore',
        state: 'Karnataka',
        pincode: '560034',
      },
    },
  ];
  await Job.insertMany(docs);
  console.log(`✓ Inserted ${docs.length} active posted jobs for giver`);
}

// ---------- Noida demo workers (for distance-ranking tests) ----------

// Sector 135 Noida — anchor where the test job-giver (e.g. Parveen) is placed.
const NOIDA_LAT = 28.5119;
const NOIDA_LNG = 77.4170;

// Twelve workers spread in concentric rings around Sector 135 so the
// "Nearby Workers" list shows clear distance variation:
//   ring 1  (0.3–1 km)   — should appear at the very top
//   ring 2  (1–3 km)     — close, but a step further
//   ring 3  (3–7 km)     — same city, mid-Noida
//   ring 4  (8–15 km)    — Sec 18 / Sec 62 / Indirapuram
//   ring 5  (16–25 km)   — Outside Noida (cross-city, e.g. South Ex Delhi)
// Each ring is roughly equally populated so the UI feels realistic.
const NOIDA_WORKERS = [
  // Ring 1 — 0.3–1 km
  { mobile: '9999900020', name: 'Ravi Sharma',  lat: 28.5135, lng: 77.4160, address: 'Sector 135, near park',          skills: ['Plumbing', 'Electrical'], rating: { average: 4.9, count: 184 }, jobsCompleted: 92,  isVerifiedProfessional: true,  yearsOfExperience: '5-10 years' },
  { mobile: '9999900021', name: 'Sunita Devi',  lat: 28.5108, lng: 77.4188, address: 'Sector 135, lane 2',             skills: ['Cleaning', 'Cooking'],    rating: { average: 4.8, count: 142 }, jobsCompleted: 65,  isVerifiedProfessional: true,  yearsOfExperience: '3-5 years' },

  // Ring 2 — 1–3 km
  { mobile: '9999900022', name: 'Manoj Kumar',  lat: 28.5070, lng: 77.4280, address: 'Sector 137, Noida',              skills: ['Carpentry', 'Repair'],    rating: { average: 4.7, count: 98 },  jobsCompleted: 47,  isVerifiedProfessional: true,  yearsOfExperience: '5-10 years' },
  { mobile: '9999900023', name: 'Pooja Rani',   lat: 28.5180, lng: 77.4290, address: 'Sector 142, Noida',              skills: ['Painting', 'Cleaning'],   rating: { average: 4.6, count: 71 },  jobsCompleted: 33,  isVerifiedProfessional: false, yearsOfExperience: '1-2 years' },
  { mobile: '9999900024', name: 'Anil Yadav',   lat: 28.5020, lng: 77.4060, address: 'Sector 143, Noida',              skills: ['Plumbing'],               rating: { average: 4.4, count: 58 },  jobsCompleted: 22,  isVerifiedProfessional: false, yearsOfExperience: '1-2 years' },

  // Ring 3 — 3–7 km
  { mobile: '9999900025', name: 'Rekha Singh',  lat: 28.5340, lng: 77.4450, address: 'Sector 75, Noida',               skills: ['Cleaning', 'Babysitting'],rating: { average: 4.8, count: 119 }, jobsCompleted: 54,  isVerifiedProfessional: true,  yearsOfExperience: '3-5 years' },
  { mobile: '9999900026', name: 'Karan Mehta',  lat: 28.4944, lng: 77.4520, address: 'Greater Noida, Pari Chowk side', skills: ['Electrical', 'Repair'],   rating: { average: 4.5, count: 67 },  jobsCompleted: 29,  isVerifiedProfessional: false, yearsOfExperience: '3-5 years' },

  // Ring 4 — 8–15 km
  { mobile: '9999900027', name: 'Vikas Tiwari', lat: 28.5705, lng: 77.3826, address: 'Sector 76, Noida',               skills: ['Plumbing', 'Carpentry'],  rating: { average: 4.6, count: 84 },  jobsCompleted: 38,  isVerifiedProfessional: true,  yearsOfExperience: '5-10 years' },
  { mobile: '9999900028', name: 'Shalini Gupta',lat: 28.5708, lng: 77.3260, address: 'Sector 18, Noida',               skills: ['Cleaning'],               rating: { average: 4.3, count: 41 },  jobsCompleted: 14,  isVerifiedProfessional: false, yearsOfExperience: '1-2 years' },
  { mobile: '9999900029', name: 'Deepak Joshi', lat: 28.6266, lng: 77.3759, address: 'Sector 62, Noida',               skills: ['Painting', 'Carpentry'],  rating: { average: 4.7, count: 96 },  jobsCompleted: 44,  isVerifiedProfessional: true,  yearsOfExperience: '5-10 years' },

  // Ring 5 — 16–25 km (outside Noida — should appear at the bottom)
  { mobile: '9999900030', name: 'Asha Verma',   lat: 28.6450, lng: 77.3777, address: 'Indirapuram, Ghaziabad',         skills: ['Cleaning', 'Cooking'],    rating: { average: 4.4, count: 53 },  jobsCompleted: 19,  isVerifiedProfessional: false, yearsOfExperience: '1-2 years' },
  { mobile: '9999900031', name: 'Imran Khan',   lat: 28.5685, lng: 77.2226, address: 'South Ex, New Delhi',            skills: ['Electrical'],             rating: { average: 4.2, count: 37 },  jobsCompleted: 11,  isVerifiedProfessional: false, yearsOfExperience: '1-2 years' },
];

async function ensureNoidaWorkers() {
  let inserted = 0;
  let updated = 0;
  for (const w of NOIDA_WORKERS) {
    const existing = await User.findOne({ mobile: w.mobile });
    const data = {
      mobile: w.mobile,
      name: w.name,
      roles: ['jobtaker'],
      activeRole: 'jobtaker',
      skills: w.skills,
      yearsOfExperience: w.yearsOfExperience,
      rating: w.rating,
      jobsCompleted: w.jobsCompleted,
      isVerifiedProfessional: w.isVerifiedProfessional,
      // Critical for testing the nearby-workers filter we just added.
      isAvailable: true,
      lastLocationAt: new Date(),
      location: {
        type: 'Point',
        coordinates: [w.lng, w.lat],     // GeoJSON = [lng, lat]
        address: w.address,
        city: 'Noida',
        state: 'Uttar Pradesh',
        pincode: '201304',
      },
    };
    if (existing) {
      Object.assign(existing, data);
      await existing.save();
      updated++;
    } else {
      await User.create(data);
      inserted++;
    }
  }
  console.log(
    `✓ Noida demo workers: ${inserted} created, ${updated} updated ` +
    `(spread 0.3 km → 22 km from Sector 135, all online)`
  );
}

async function placeGiverInNoida(rawMobile) {
  const mobile = rawMobile.replace(/\D/g, '').slice(-10);
  const user = await User.findOne({ mobile });
  if (!user) {
    console.log(`✗ No user with mobile ${mobile}; skipping Noida placement.`);
    return null;
  }
  // Make sure they're set up as a job-giver and pinned to Sector 135.
  if (!user.roles.includes('jobgiver')) user.roles.push('jobgiver');
  user.activeRole = 'jobgiver';
  user.location = {
    type: 'Point',
    coordinates: [NOIDA_LNG, NOIDA_LAT],
    address: 'Tower 4, Sector 135',
    city: 'Noida',
    state: 'Uttar Pradesh',
    pincode: '201304',
  };
  user.lastLocationAt = new Date();
  await user.save();
  console.log(`✓ Placed ${mobile} as job-giver at Sector 135, Noida`);
  return user;
}

async function bumpUserStats(rawMobile) {
  const mobile = rawMobile.replace(/\D/g, '').slice(-10);
  const user = await User.findOne({ mobile });
  if (!user) {
    console.log(`✗ No user with mobile ${mobile}; skipping stats bump.`);
    return;
  }
  user.jobsCompleted = 24;
  user.rating = { average: 4.8, count: 18 };
  user.walletBalance = 1500;
  // Also set the user's location so the home screen can compute real
  // distances to the seeded jobs (instead of showing "—").
  user.location = {
    type: 'Point',
    coordinates: [BASE_LNG, BASE_LAT],
    address: 'Koramangala 5th Block',
    city: 'Bangalore',
    state: 'Karnataka',
    pincode: '560034',
  };
  await user.save();
  console.log(`✓ Bumped stats on ${mobile}: jobsCompleted=24, rating=4.8, walletBalance=₹1500, location=Koramangala`);

  // Demo workers for the Hire view + posted jobs for this user as giver.
  await ensureDemoWorkers();
  await seedActiveJobsForGiver(user);

  // Also seed a few completed jobs with this user as the taker, dated today
  // and across the past week, so the earnings card reflects real numbers.
  const giver = await ensureDemoGiver();
  await Job.deleteMany({ selectedJobtaker: user._id, status: 'completed' });
  const now = new Date();
  const completed = [
    {
      title: 'Bathroom drain unclog (today)',
      category: 'Plumbing',
      finalPrice: 800,
      proposedBudget: 800,
      completedAt: new Date(now.getFullYear(), now.getMonth(), now.getDate(), 10),
    },
    {
      title: 'Quick sofa clean (today)',
      category: 'Cleaning',
      finalPrice: 700,
      proposedBudget: 700,
      completedAt: new Date(now.getFullYear(), now.getMonth(), now.getDate(), 14),
    },
    {
      title: 'Painting touch-up (yesterday)',
      category: 'Painting',
      finalPrice: 2500,
      proposedBudget: 2500,
      completedAt: new Date(now.getTime() - 24 * 3600 * 1000),
    },
    {
      title: 'Switchboard repair (3 days ago)',
      category: 'Electrical',
      finalPrice: 1200,
      proposedBudget: 1200,
      completedAt: new Date(now.getTime() - 3 * 24 * 3600 * 1000),
    },
    {
      title: 'Kitchen deep clean (5 days ago)',
      category: 'Cleaning',
      finalPrice: 1800,
      proposedBudget: 1800,
      completedAt: new Date(now.getTime() - 5 * 24 * 3600 * 1000),
    },
    {
      title: 'Furniture assembly (last week)',
      category: 'Carpentry',
      finalPrice: 1500,
      proposedBudget: 1500,
      completedAt: new Date(now.getTime() - 8 * 24 * 3600 * 1000),
    },
  ];
  await Job.insertMany(
    completed.map((c) => ({
      ...c,
      jobgiver: giver._id,
      selectedJobtaker: user._id,
      status: 'completed',
      startedAt: new Date(c.completedAt.getTime() - 2 * 3600 * 1000),
      location: {
        type: 'Point',
        coordinates: [BASE_LNG + jitter(), BASE_LAT + jitter()],
        address: 'Koramangala, Bangalore',
        city: 'Bangalore',
        state: 'Karnataka',
        pincode: '560034',
      },
    })),
  );
  console.log(`✓ Inserted ${completed.length} completed jobs in user history`);
}

async function main() {
  await connectDB();

  const userMobile = process.argv[2];
  const region = (process.argv[3] || '').toLowerCase();

  if (region === 'noida') {
    // Skip the Bangalore demo data; this is a Noida test session.
    if (!userMobile) {
      console.log('✗ noida mode needs a mobile, e.g. node seed.js +919466646494 noida');
      await mongoose.connection.close();
      return;
    }
    await placeGiverInNoida(userMobile);
    await ensureNoidaWorkers();
    console.log('\nDone — open the app as a job-giver to see Sector 135 + nearby workers.');
    await mongoose.connection.close();
    return;
  }

  // Default flow (Bangalore demo data).
  const giver = await ensureDemoGiver();
  await seedJobs(giver);

  if (userMobile) {
    await bumpUserStats(userMobile);
  } else {
    console.log('ℹ Pass your mobile (e.g. node seed.js +919466646494)');
    console.log('  to also populate the Performance card and earnings.');
    console.log('  Add "noida" as a 2nd arg to seed Sector 135 workers instead.');
  }

  console.log('\nDone.');
  await mongoose.connection.close();
}

main().catch(async (err) => {
  console.error('Seed failed:', err);
  try {
    await mongoose.connection.close();
  } catch (_) {}
  process.exit(1);
});
