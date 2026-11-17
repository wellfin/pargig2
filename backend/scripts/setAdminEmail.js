/**
 * Change an admin's email address.
 *
 *   npm run admin:email                   # lists them, then asks
 *   npm run admin:email old@example.com
 *
 * Exists because the only admin on this deployment was seeded as
 * admin@pargig.com, which is not a mailbox anyone can open. That is
 * harmless while the password is known and fatal the moment it is
 * not: forgot-password emails the code to the address on the account
 * and nowhere else, so an account with an unreachable address has no
 * recovery path at all. Changing it is the difference between a
 * working way back in and a decorative one.
 *
 * The address is also the login, so this changes how the person signs
 * in. It is printed back and confirmed before anything is written.
 */
require('dotenv').config();

const Admin = require('../models/adminModel');
// The models' own Mongoose instance — see scripts/checkAdminReset.js.
const mongoose = Admin.base;
const prompt = require('./_prompt');
const { ask } = prompt;

async function main() {
  if (!process.env.MONGO_URI) {
    console.error('MONGO_URI is not set. Run this from the backend folder.');
    process.exit(1);
  }
  await mongoose.connect(process.env.MONGO_URI);

  const admins = await Admin.find({}).select('name email role isActive').lean();
  if (admins.length === 0) {
    console.error('There are no admin accounts in this database.');
    console.error('Create one with:  npm run admin:create');
    process.exit(1);
  }

  let current = (process.argv[2] || '').trim().toLowerCase();
  if (!current) {
    console.log('\nAdmin accounts in this database:\n');
    admins.forEach((a) => {
      console.log(
        `  ${a.email}  —  ${a.name} (${a.role})${a.isActive ? '' : ' [inactive]'}`,
      );
    });
    console.log('');
    current = (await ask('Which one do you want to change? ')).trim().toLowerCase();
  }

  const admin = await Admin.findOne({ email: current });
  if (!admin) {
    console.error(`No admin with the email ${current}.`);
    process.exit(1);
  }

  console.log(
    '\nThe new address must be a real mailbox you can open — it is both\n' +
    'the login and the only place a password reset code is sent.\n',
  );
  const next = (await ask('New email: ')).trim().toLowerCase();

  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(next)) {
    console.error('That does not look like an email address.');
    process.exit(1);
  }
  if (next === current) {
    console.log('That is the address it already has. Nothing changed.');
    return;
  }
  // The field is uniquely indexed, so this would fail at save anyway —
  // but failing here says which address is the problem.
  if (await Admin.exists({ email: next })) {
    console.error(`${next} is already used by another admin account.`);
    process.exit(1);
  }

  const ok = (await ask(`Sign in as ${next} from now on? [y/N] `)).trim().toLowerCase();
  if (ok !== 'y' && ok !== 'yes') {
    console.log('Nothing changed.');
    return;
  }

  admin.email = next;
  // Any reset code in flight was sent to the OLD mailbox. Leaving it
  // valid would mean whoever can read that mailbox can still take the
  // account over, which is the exact thing this change is undoing.
  admin.resetOtpHash = undefined;
  admin.resetOtpExpiresAt = undefined;
  admin.resetOtpAttempts = 0;
  admin.resetOtpSentAt = undefined;
  await admin.save();

  console.log(`\nDone. ${current} is now ${admin.email}.`);
  console.log('The password did not change. Sign in with the new address');
  console.log('and the same password.');
}

main()
  .catch((err) => {
    if (err && err.code === 11000) {
      console.error('Failed: that email is already taken.');
    } else {
      console.error('Failed:', err.message);
    }
    process.exitCode = 1;
  })
  .finally(() => {
    prompt.close();
    return mongoose.connection.close();
  });
