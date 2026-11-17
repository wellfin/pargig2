/**
 * Terminal prompts for the admin scripts.
 *
 * Shared because the scripts that handle passwords must handle them
 * identically. A second copy of askSecret is a second chance to get
 * the echo suppression wrong, and the failure mode there is silent —
 * the password appears on screen, and whoever is typing it has
 * already finished by the time they notice.
 *
 * The design here is about what happens when input is PIPED in rather
 * than typed, which is how anyone automating these will run them.
 *
 * readline is push-based and these scripts are pull-based: they await
 * one answer, do some work, then ask the next question. A person types
 * slowly enough that the difference never shows. A pipe delivers every
 * line and then EOF in one burst, before the second question has been
 * asked — so with rl.question() alone the later lines are emitted into
 * nothing and are gone.
 *
 * So every line is queued as it arrives and handed out one at a time,
 * and a question with nothing left to read REJECTS. That last part
 * matters more than it looks: without it the callback simply never
 * fires, node finds nothing pending, and the process exits 0 having
 * done nothing — indistinguishable from success. For a script whose
 * job is changing a password, that is the worst failure available.
 */

const readline = require('readline');

let shared = null;
let muted = false;
let ended = false;

/** Lines read but not yet asked for. */
const queue = [];
/** The question currently waiting, if any. */
let waiter = null;

const NO_INPUT = 'ran out of input (stdin ended before the last answer)';

function iface() {
  if (shared) return shared;
  const isTty = Boolean(process.stdin.isTTY);
  shared = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    terminal: isTty,
  });

  if (isTty) {
    // readline writes every keypress to `output`; wrapping that one
    // method is what keeps a password off the screen — and out of a
    // recorded session or a screen share. A pipe has no keypresses to
    // echo, so this is only needed on a real terminal.
    const write = shared._writeToOutput.bind(shared);
    shared._writeToOutput = (chunk) => {
      if (!muted) write(chunk);
    };
  }

  shared.on('line', (line) => {
    if (waiter) {
      const w = waiter;
      waiter = null;
      w.resolve(line);
    } else {
      queue.push(line);
    }
  });

  shared.on('close', () => {
    ended = true;
    if (waiter) {
      const w = waiter;
      waiter = null;
      w.reject(new Error(NO_INPUT));
    }
  });

  return shared;
}

function question(text, { secret = false } = {}) {
  const rl = iface();

  rl.output.write(text);
  if (secret) muted = true;

  const finish = (answer) => {
    if (secret) {
      muted = false;
      rl.output.write('\n');
    }
    return answer;
  };

  if (queue.length) return Promise.resolve(finish(queue.shift()));
  if (ended) {
    if (secret) muted = false;
    return Promise.reject(new Error(NO_INPUT));
  }
  return new Promise((resolve, reject) => {
    waiter = {
      resolve: (line) => resolve(finish(line)),
      reject: (err) => {
        if (secret) muted = false;
        reject(err);
      },
    };
  });
}

/** Prompt, echoing what is typed. */
const ask = (text) => question(text);

/** Prompt without echoing. */
const askSecret = (text) => question(text, { secret: true });

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

/**
 * Release stdin. Every script that prompts must call this, or node
 * keeps running with nothing left to do.
 */
function close() {
  if (!shared) return;
  muted = false;
  waiter = null;
  queue.length = 0;
  shared.close();
  shared = null;
  ended = false;
}

module.exports = { ask, askSecret, askNewPassword, close };
