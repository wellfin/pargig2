// Full Find Work flow against the live backend on :5014 — exactly what
// the Flutter app does. Catches any path that strips workArea or
// currentLocation between signup and the final Apply Location.

require('dotenv').config();
const mongoose = require('mongoose');
const generateToken = require('./utils/generateToken');
const User = require('./models/userModel');

const TEST_MOBILE = '9000000099';
const BASE = 'http://127.0.0.1:5014/api';

async function dump(prefix) {
  const u = await mongoose.connection.collection('users').findOne({ mobile: TEST_MOBILE });
  const w = u.workArea === undefined ? '❌ STRIPPED' : 'present';
  const c = u.currentLocation === undefined ? '❌ STRIPPED' : 'present';
  console.log(`${prefix}  workArea=${w}  currentLocation=${c}`);
}

async function main() {
  await mongoose.connect(process.env.MONGO_URI);
  await User.deleteOne({ mobile: TEST_MOBILE });

  // 1) Signup (POST /auth/otp/request creates the user).
  let res = await fetch(`${BASE}/auth/otp/request`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ mobile: TEST_MOBILE }),
  });
  console.log(`signup → ${res.status}`);
  await dump('after signup            ');

  // Issue a JWT to skip OTP verify.
  const u = await User.findOne({ mobile: TEST_MOBILE });
  const headers = {
    'Content-Type': 'application/json',
    Authorization: `Bearer ${generateToken(u._id)}`,
  };

  // 2) acceptTerms — fires after OTP verify in the real flow.
  res = await fetch(`${BASE}/users/me/accept-terms`, { method: 'POST', headers, body: '{}' });
  console.log(`acceptTerms → ${res.status}`);
  await dump('after acceptTerms       ');

  // 3) Wizard address save (typed-only path — no GPS).
  res = await fetch(`${BASE}/users/me/location`, {
    method: 'PUT', headers,
    body: JSON.stringify({
      address: 'h no 6 sector 16 faridabad',
      city: 'Faridabad', state: 'Haryana', pincode: '121001',
    }),
  });
  console.log(`wizard address (no GPS) → ${res.status}`);
  await dump('after wizard            ');

  // 4) switchRole — Find Work tap on role-chooser.
  res = await fetch(`${BASE}/users/me/role`, {
    method: 'PUT', headers,
    body: JSON.stringify({ role: 'jobtaker', mode: 'add' }),
  });
  console.log(`switchRole(add) → ${res.status}`);
  await dump('after switchRole(add)   ');

  // 5) Find Work Apply.
  res = await fetch(`${BASE}/users/me/role`, {
    method: 'PUT', headers,
    body: JSON.stringify({ role: 'jobtaker', mode: 'replace' }),
  });
  console.log(`switchRole(replace) → ${res.status}`);
  await dump('after switchRole(rep)   ');

  res = await fetch(`${BASE}/users/me`, {
    method: 'PUT', headers,
    body: JSON.stringify({
      skills: ['Plumbing'],
      yearsOfExperience: '3-5 years',
      searchRadiusKm: 20,
      searchRadiusLabel: '10-20 Kms',
      workArea: { type: 'Point', coordinates: [77.5946, 12.9716] },
      workAreaLabel: 'MG Road, Bangalore',
    }),
  });
  console.log(`updateProfile (Find Work) → ${res.status}`);
  await dump('after Find Work Apply   ');

  // Final raw dump.
  const final = await mongoose.connection.collection('users').findOne({ mobile: TEST_MOBILE });
  console.log('\n=== final raw doc ===');
  console.log('  location        :', JSON.stringify(final.location));
  console.log('  workArea        :', JSON.stringify(final.workArea));
  console.log('  currentLocation :', JSON.stringify(final.currentLocation));

  await User.deleteOne({ mobile: TEST_MOBILE });
  await mongoose.connection.close();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
