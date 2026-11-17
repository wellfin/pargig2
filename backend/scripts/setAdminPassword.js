/**
 * Change an admin panel password.
 *
 *   node scripts/setAdminPassword.js            # lists the admins
 *   node scripts/setAdminPassword.js <email>    # then prompts
 *
 * Why a script and not a page in the panel: the account this is most
 * urgently needed for is the seeded one, whose password was a constant
 * written in the repository. Anyone who can read the repo can read it,
 * so "sign in and change it in Settings" is advice an attacker can
 * follow first. A script run over SSH needs access to the server,
 * which is a different and much smaller set of people.
 *
 * The password is typed at a prompt rather than passed as an argument,
 * because an argument ends up in the shell history and in `ps` output
 * where any other user on the box can read it. Typing is not echoed.
 *
 * This writes to whatever MONGO_URI points at — in production, the
 * live database. It changes exactly one field on one document.
 */
require('dotenv').config();

const mongoose = require('mongoose');
const readline = require('readline');
const Admin = require('../models/adminModel');

const MIN_LENGTH = 10;

/** Prompt, echoing the typed characters. */
function ask(question) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer);
    });
  });
}

/**
 * Prompt without echoing.
 *
 * readline writes every keypress to `output`; overriding that one
 * method is what keeps the password off the screen — and off the
 * screen of anyone looking over a shoulder or recording the session.
 */
function askSecret(question) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    terminal: true,
  });
  let first = true;
  rl._writeToOutput = (chunk) => {
    // Let the question itself through once, then swallow everything.
    if (first) {
      rl.output.write(chunk);
      if (chunk.includes(question)) first = false;
    }
  };
  rl.output.write(question);
  first = false;
  return new Promise((resolve) => {
    rl.question('', (answer) => {
      rl.output.write('\n');
      rl.close();
      resolve(answer);
    });
  });
}

async function main() {
  if (!process.env.MONGO_URI) {
    console.error('MONGO_URI is not set. Run this from the backend folder.');
    process.exit(1);
  }
  await mongoose.connect(process.env.MONGO_URI);

  const admins = await Admin.find({}).select('name email role isActive').lean();
  if (admins.length === 0) {
    console.error('There are no admin accounts in this database.');
    console.error('Create the first one with GET /api/admin/seed.');
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

  const pw = await askSecret(`New password for ${admin.email}: `);
  if (pw.trim().length < MIN_LENGTH) {
    // Short enough to guess is the problem this script exists to fix,
    // so it will not help you recreate it.
    console.error(`Too short — use at least ${MIN_LENGTH} characters.`);
    process.exit(1);
  }
  const again = await askSecret('Type it again: ');
  if (pw !== again) {
    console.error('Those do not match. Nothing was changed.');
    process.exit(1);
  }

  // Assigning and saving is what triggers the pre-save hook that
  // hashes it. An updateOne() would store the plain text.
  admin.password = pw;
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
  .finally(() => mongoose.connection.close());
