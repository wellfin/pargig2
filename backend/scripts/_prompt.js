/**
 * Terminal prompts for the admin scripts.
 *
 * Shared because the two scripts that handle passwords must handle
 * them identically. A second copy of askSecret is a second chance to
 * get the echo suppression wrong, and the failure mode there is silent
 * — the password simply appears on screen, and whoever is typing it
 * has already finished by the time they notice.
 */

const readline = require('readline');

/** Prompt, echoing what is typed. */
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
 * readline writes every keypress to `output`; replacing that one
 * method is what keeps the password off the screen — and out of a
 * recorded session or a screen share.
 */
function askSecret(question) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    terminal: true,
  });
  rl._writeToOutput = () => {};
  rl.output.write(question);
  return new Promise((resolve) => {
    rl.question('', (answer) => {
      rl.output.write('\n');
      rl.close();
      resolve(answer);
    });
  });
}

/**
 * Ask for a password twice and check it is long enough.
 *
 * Returns the password, or null when the caller should give up — the
 * message has already been printed in that case.
 */
async function askNewPassword(label, minLength = 10) {
  const pw = await askSecret(`${label}: `);
  if (pw.trim().length < minLength) {
    // Being short enough to guess is the thing these scripts exist to
    // fix, so they will not help you recreate it.
    console.error(`Too short — use at least ${minLength} characters.`);
    return null;
  }
  const again = await askSecret('Type it again: ');
  if (pw !== again) {
    console.error('Those do not match. Nothing was changed.');
    return null;
  }
  return pw;
}

module.exports = { ask, askSecret, askNewPassword };
