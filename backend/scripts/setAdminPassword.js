/**
 * Change an admin panel password.
 *
 *   npm run admin:password            # lists the admins, then asks
 *   npm run admin:password <email>
 *
 * Why a script and not a page in the panel: the account this was first
 * needed for was the seeded one, whose password was a constant written
 * in the repository — and still is, in the history. Anyone who can
 * read the repo can read it, so "sign in and change it in Settings" is
 * advice an attacker can follow first. A script run over SSH needs
 * access to the server, which is a much smaller set of people.
 *
 * The password is typed at a prompt rather than passed as an argument,
 * because an argument ends up in the shell history and in `ps` output
 * where any other user on the box can read it. Typing is not echoed.
 *
 * This writes to whatever MONGO_URI points at — in production, the
 * live database. It changes one field on one document.
 */
require('dotenv').config();

const Admin = require('../models/adminModel');
// Connect through the Mongoose instance the MODELS are built on. See
// scripts/checkAdminReset.js for why that is not always the same
// object as require('mongoose') from this folder.
const mongoose = Admin.base;
const prompt = require('./_prompt');
const { ask, askNewPassword } = prompt;

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

  let email = (process.argv[2] || '').trim().toLowerCase();
  if (!email) {
    console.log('\nAdmin accounts in this database:\n');
    admins.forEach((a) => {
      console.log(
        `  ${a.email}  —  ${a.name} (${a.role})${a.isActive ? '' : ' [inactive]'}`,
      );
    });
    console.log('');
    email = (await ask('Which email? ')).trim().toLowerCase();
  }

  const admin = await Admin.findOne({ email });
  if (!admin) {
    console.error(`No admin with the email ${email}.`);
    process.exit(1);
  }

  const password = await askNewPassword(`New password for ${admin.email}`);
  if (password === null) process.exit(1);

  // Assigning and saving is what triggers the pre-save hook that
  // hashes it. An updateOne() would store the plain text.
  admin.password = password;
  // Any reset code sitting on the account is void now — the password
  // it would have changed is already gone.
  admin.resetOtpHash = undefined;
  admin.resetOtpExpiresAt = undefined;
  admin.resetOtpAttempts = 0;
  await admin.save();

  console.log(`\nDone. ${admin.email} now uses the new password.`);
  console.log('Anyone signed in on the old one stays signed in until');
  console.log('their token expires — JWTs are not checked against it.');
}

main()
  .catch((err) => {
    console.error('Failed:', err.message);
    process.exitCode = 1;
  })
  .finally(() => {
    prompt.close();
    return mongoose.connection.close();
  });
