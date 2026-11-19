const Setting = require('../models/settingModel');

/**
 * What each admin role is allowed to open in the panel.
 *
 * Until now every signed-in admin could do everything except touch the
 * payment keys. That is fine with one admin and wrong with three: the
 * person answering support chats has no business deleting users, and
 * the person reconciling payments has no reason to read disputes.
 *
 * Permissions hang off the ROLE, not the account. With a handful of
 * admins, per-account checkboxes are a lot of surface for very little:
 * you end up unable to answer "what can a support admin do?" because
 * the answer is different for each of them. A role is a job title, and
 * a job title is the thing the owner actually has an opinion about.
 *
 * The defaults below are what a fresh install uses. An owner can edit
 * them in Settings; what they save is stored as ONE settings document
 * keyed `admin_role_permissions`, holding only the roles that differ.
 *
 * Three things are not negotiable:
 *
 *   - superadmin always holds everything, and is never stored or
 *     edited. A grid that can take permissions away from superadmin
 *     can take away `admins`, and then nobody can grant it back.
 *   - `admins` belongs to superadmin alone. Granting it to another
 *     role is not delegation, it is promotion: whoever holds it can
 *     create a superadmin and sign in as one. If that is what is
 *     wanted, make the person a superadmin and mean it.
 *   - `payment_settings` likewise. The gateway keys are the switch
 *     between test payments and real money leaving real cards, and
 *     replacing them redirects every future payment on the platform.
 *     That is an owner's decision, not a job function, so it does not
 *     travel with a role someone can be given.
 *
 * A key marked superadminOnly is filtered out of anything an admin
 * saves, so an older grid that granted one simply stops carrying it —
 * no migration, and no window where a stale row still works.
 */

/**
 * The catalogue. `key` is what the middleware and the panel check;
 * everything else is for the humans reading the grid.
 */
const PERMISSIONS = [
  {
    key: 'dashboard',
    label: 'Dashboard',
    hint: 'The home page: totals, revenue and the activity charts.',
  },
  {
    key: 'users',
    label: 'Users',
    hint: 'Browse user accounts, block them, delete them.',
  },
  {
    key: 'verifications',
    label: 'Verifications',
    hint: 'The KYC queue — approve or reject identity documents.',
  },
  {
    key: 'jobs',
    label: 'Jobs',
    hint: 'Every job and its full detail.',
  },
  {
    key: 'payments',
    label: 'Payments',
    hint: 'The payment ledger, and issuing refunds.',
  },
  {
    key: 'disputes',
    label: 'Disputes',
    hint: 'Read disputes and decide them.',
  },
  {
    key: 'support',
    label: 'Support Chat',
    hint: 'Answer the shared support inbox.',
  },
  {
    key: 'analytics',
    label: 'Analytics',
    hint: 'Trends, insights and the geography breakdown.',
  },
  {
    key: 'reports',
    label: 'Reports',
    hint:
      'The export page. It can only export the lists this role can ' +
      'already read, so Users and Payments exports also need those.',
  },
  {
    key: 'payment_settings',
    label: 'Payment gateway keys',
    hint:
      'Read and replace the live Razorpay credentials. This is the ' +
      'switch between test payments and real ones.',
    superadminOnly: true,
    lockNote:
      'These keys decide whether real money moves, and replacing them ' +
      'redirects every future payment. That is an owner\u2019s call, not a ' +
      'job function.',
  },
  {
    key: 'admins',
    label: 'Admin accounts & permissions',
    hint:
      'Create admins, change roles, and edit this grid.',
    superadminOnly: true,
    lockNote:
      'Whoever holds this can create a superadmin and sign in as one, ' +
      'so granting it is promotion rather than delegation.',
  },
];

const ROLES = ['superadmin', 'support', 'finance'];

const ALL_KEYS = PERMISSIONS.map((p) => p.key);

/** Keys any role other than superadmin may be granted. */
const GRANTABLE_KEYS = PERMISSIONS
  .filter((p) => !p.superadminOnly)
  .map((p) => p.key);

/**
 * What a fresh install gives each role.
 *
 * support: the queues a person answering users works out of. Users is
 * included because a support admin needs to see who they are talking
 * to — blocking and deleting are the same permission, which is a
 * blunt edge worth knowing about.
 *
 * finance: the money, and the numbers that explain it. No disputes
 * and no support, because neither is their decision to make — and not
 * the gateway keys either, which are superadmin-only above. Reading
 * the ledger and holding the credentials that charge cards are
 * different jobs, and only one of them is reconciliation.
 */
const DEFAULTS = {
  superadmin: [...ALL_KEYS],
  support: ['dashboard', 'users', 'verifications', 'jobs', 'disputes', 'support'],
  finance: ['dashboard', 'jobs', 'payments', 'analytics', 'reports'],
};

const KEY = 'admin_role_permissions';

// Resolved on nearly every admin request, so it is cached rather than
// fetched each time. Saving invalidates it immediately in this
// process; the TTL is what catches a second process on the same
// database, where the write happened somewhere else.
const CACHE_MS = 30 * 1000;
let cache = null;
let cachedAt = 0;

function invalidate() {
  cache = null;
  cachedAt = 0;
}

/**
 * Keep only real, grantable keys, de-duplicated.
 *
 * Returns null for anything that is not an array, so a caller can tell
 * "nothing saved for this role" from "saved as empty" — an empty array
 * is a deliberate choice meaning no access, and must not fall back to
 * the defaults.
 */
function clean(list) {
  if (!Array.isArray(list)) return null;
  return [...new Set(list.filter((k) => GRANTABLE_KEYS.includes(k)))];
}

/** The full role -> permission map, defaults filled in. */
async function getRolePermissions() {
  if (cache && Date.now() - cachedAt < CACHE_MS) return cache;

  const doc = await Setting.findOne({ key: KEY }).lean();
  const saved = doc?.value || {};

  const out = { superadmin: [...ALL_KEYS] };
  for (const role of ROLES) {
    if (role === 'superadmin') continue;
    out[role] = clean(saved[role]) || [...DEFAULTS[role]];
  }

  cache = out;
  cachedAt = Date.now();
  return out;
}

/** What this admin may do. A deactivated account may do nothing. */
async function permissionsFor(admin) {
  if (!admin || admin.isActive === false) return [];
  const map = await getRolePermissions();
  return map[admin.role] || [];
}

/** True when the admin holds ANY of the given keys. */
async function can(admin, ...keys) {
  if (!keys.length) return false;
  const mine = await permissionsFor(admin);
  return keys.some((k) => mine.includes(k));
}

/**
 * Save the editable part of the grid.
 *
 * `next` is a role -> keys map. superadmin is ignored if present, and
 * so is any key that is not grantable — the caller does not get to
 * decide either of those, and silently dropping them is safer than
 * trusting the client to have sent the right thing.
 */
async function saveRolePermissions(next, by) {
  const value = {};
  for (const role of ROLES) {
    if (role === 'superadmin') continue;
    const cleaned = clean(next?.[role]);
    value[role] = cleaned || [...DEFAULTS[role]];
  }

  await Setting.findOneAndUpdate(
    { key: KEY },
    {
      key: KEY,
      value,
      updatedBy: by?._id,
      updatedByName: by?.name,
    },
    // The return value is not used: the cache is dropped below and
    // getRolePermissions() re-reads with the defaults filled in.
    { upsert: true },
  );

  invalidate();
  return getRolePermissions();
}

module.exports = {
  PERMISSIONS,
  ROLES,
  ALL_KEYS,
  GRANTABLE_KEYS,
  DEFAULTS,
  KEY,
  getRolePermissions,
  permissionsFor,
  can,
  saveRolePermissions,
  invalidate,
};
