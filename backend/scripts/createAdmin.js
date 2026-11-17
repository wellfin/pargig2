/**
 * Create an admin panel account.
 *
 *   npm run admin:create
 *
 * This replaces GET /api/admin/seed, which was a public URL that
 * created a superadmin. It was open to the internet, it answered
 * questions about which accounts existed, and on an empty database it
 * handed out a working login to whoever asked first. None of that is
 * fixable while it is an HTTP route, because the one thing it cannot
 * do is require a login — so it stopped being one.
 *
 * Creating an admin now needs shell access to the server, which is a
 * far smaller set of people than "anyone who can reach the site".
 *
 * Works on an empty database and on a full one, so it is also how a
 * second admin is added — a support or finance account, which the
 * panel still has no page for.
 */
require('dotenv').config();

const Admin = require('../models/adminModel');
// Connect through the Mongoose instance the MODELS are built on. See
// scripts/checkAdminReset.js for why that is not always the same
// object as require('mongoose') from this folder.
const mongoose = Admin.base;
const prompt = require('./_prompt');
const { ask, askNewPassword } = prompt;

const ROLES = ['superadmin', 'support', 'finance'];

async function main() {
  if (!process.env.MONGO_URI) {
    console.error('MONGO_URI is not set. Run this from the backend folder.');
    process.exit(1);
  }
  await mongoose.connect(process.env.MONGO_URI);

  const existing = await Admin.find({}).select('name email role isActive').lean();
  if (existing.length === 0) {
    console.log('\nNo admin accounts yet. This will be the first.\n');
  } else {
    console.log('\nAdmin accounts already in this database:\n');
    existing.forEach((a) => {
      console.log(
        `  ${a.email}  —  ${a.name} (${a.role})${a.isActive ? '' : ' [inactive]'}`,
      );
    });
    console.log('');
  }

  const email = (await ask('Email: ')).trim().toLowerCase();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    console.error('That does not look like an email address.');
    process.exit(1);
  }
  if (await Admin.exists({ email })) {
    console.error(
      `${email} already exists. To change its password instead:\n` +
      '  npm run admin:password ' + email,
    );
    process.exit(1);
  }

  // The address has to be real and reachable, because it is the only
  // way back in: forgot-password mails the code there and nowhere else.
  console.log(
    '\nThis address must be a real mailbox you can open — a forgotten\n' +
    'password is recovered by emailing a code to it.\n',
  );

  const name = (await ask('Name: ')).trim() || 'Admin';

  const firstEver = existing.length === 0;
  let role = 'superadmin';
  if (!firstEver) {
    const typed = (await ask(`Role [${ROLES.join(' / ')}]: `)).trim().toLowerCase();
    if (typed && !ROLES.includes(typed)) {
      console.error(`Role must be one of: ${ROLES.join(', ')}`);
      process.exit(1);
    }
    role = typed || 'support';
  } else {
    console.log('Role: superadmin (the first account always is)');
  }

  const password = await askNewPassword(`Password for ${email}`);
  if (password === null) process.exit(1);

  const admin = await Admin.create({ name, email, password, role });
  console.log(`\nCreated ${admin.email} as ${admin.role}.`);
  console.log('Sign in at the admin panel with that email and password.');
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
