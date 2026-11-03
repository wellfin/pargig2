const crypto = require('crypto');

/**
 * Encrypts the handful of secrets that have to live in the database.
 *
 * The payment gateway's key secret and webhook secret are typed into
 * the admin panel, so they can't sit in a .env file — but they also
 * must not sit in Mongo as plain text. Anyone with a read-only database
 * dump (a backup, an Atlas snapshot, a leaked connection string) would
 * otherwise be able to charge cards in our name. Encrypting at rest
 * means a dump alone is not enough: the attacker also needs the key,
 * which only ever exists in the server's environment.
 *
 * AES-256-GCM, so a tampered ciphertext fails to decrypt rather than
 * decrypting to something else.
 */

// Where the master key comes from, in order of preference. A dedicated
// variable is better — rotating the JWT secret would otherwise orphan
// every stored secret — but deriving from JWT_SECRET means an existing
// deployment encrypts correctly without anyone editing .env first.
const MASTER = process.env.SETTINGS_ENCRYPTION_KEY || process.env.JWT_SECRET;

// Fixed salt: this derives one key for one purpose, and a random salt
// would have to be stored next to every ciphertext to be re-derivable.
const SALT = 'pargig.settings.v1';

let cachedKey = null;

/** True when there is a master key to encrypt with at all. */
function isConfigured() {
  return typeof MASTER === 'string' && MASTER.length >= 8;
}

function key() {
  if (cachedKey) return cachedKey;
  if (!isConfigured()) {
    throw new Error(
      'Cannot store secrets: set SETTINGS_ENCRYPTION_KEY (or JWT_SECRET) in the server environment',
    );
  }
  cachedKey = crypto.scryptSync(MASTER, SALT, 32);
  return cachedKey;
}

/**
 * @param {string} plain
 * @returns {string} `v1:<iv>:<tag>:<ciphertext>`, all base64url.
 */
function encrypt(plain) {
  if (plain === undefined || plain === null || plain === '') return '';
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key(), iv);
  const ct = Buffer.concat([
    cipher.update(String(plain), 'utf8'),
    cipher.final(),
  ]);
  return [
    'v1',
    iv.toString('base64url'),
    cipher.getAuthTag().toString('base64url'),
    ct.toString('base64url'),
  ].join(':');
}

/**
 * Returns '' for anything that isn't a well-formed ciphertext, so a
 * half-written or hand-edited settings document reads as "no secret
 * configured" instead of throwing on every payment.
 */
function decrypt(payload) {
  if (!payload || typeof payload !== 'string') return '';
  const parts = payload.split(':');
  if (parts.length !== 4 || parts[0] !== 'v1') return '';
  try {
    const [, iv, tag, ct] = parts;
    const decipher = crypto.createDecipheriv(
      'aes-256-gcm',
      key(),
      Buffer.from(iv, 'base64url'),
    );
    decipher.setAuthTag(Buffer.from(tag, 'base64url'));
    return Buffer.concat([
      decipher.update(Buffer.from(ct, 'base64url')),
      decipher.final(),
    ]).toString('utf8');
  } catch (_) {
    // Wrong key, or tampered bytes. Either way we don't have the
    // secret, and pretending otherwise would send garbage to the PSP.
    return '';
  }
}

/**
 * What the admin panel is allowed to see: enough to recognise which
 * credential is saved, never enough to use it.
 *
 * A key id may show its prefix — "rzp_live_Ab••••3456" — because the
 * prefix is public and is the one thing an admin needs to recognise.
 * Anything else shows four characters at each end and no more: half of
 * a 24-character key secret is still most of a key secret.
 */
function mask(secret) {
  if (!secret) return '';
  const s = String(secret);
  if (s.length <= 8) return '••••';
  const lead = /^rzp_(test|live)_/.test(s) ? 12 : 4;
  return `${s.slice(0, lead)}••••${s.slice(-4)}`;
}

module.exports = { encrypt, decrypt, mask, isConfigured };
