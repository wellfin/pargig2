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
 * Two things are not negotiable:
 *
 *   - superadmin always holds everything, and is never stored or
 *     edited. A grid that can take permissions away from superadmin
 *     can take away `admins`, and then nobody can grant it back.
 *   - `integrations` is superadmin's alone. The gateway keys are
 *     the switch between test payments and real money leaving real
 *     cards, and replacing them redirects every future payment on the
 *     platform. That is an owner's decision, not a job function, so
 *     it does not travel with a role someone can be given.
 *
 * A key marked superadminOnly is filtered out of anything an admin
 * saves, so an older grid that granted one simply stops carrying it —
 * no migration, and no window where a stale row still works.
 *
 * `admins` IS grantable, so an owner can hand over account and role
 * management without handing over everything. That is only safe
 * because of one rule, enforced in saveRoles and in the account
 * controller: an admin can never grant what they do not themselves
 * hold, nor create or touch a superadmin. Without it, delegation is
 * promotion — whoever manages accounts could mint a superadmin, set
 * its password, and sign in as it.
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
    // Renamed from payment_settings when SMS and routing joined it.
    // Safe to rename in place: a superadminOnly key is filtered out of
    // anything an admin can save, so no stored role has ever carried
    // it and there is nothing to migrate.
    key: 'integrations',
    label: 'Third-party services',
    hint:
      'The Razorpay keys, the MSG91 SMS credentials and the distance ' +
      'server. Between them these decide whether real money moves, ' +
      'whether anyone can log in, and how far away a worker looks.',
    superadminOnly: true,
    lockNote:
      'These accounts belong to whoever owns the business, and the ' +
      'keys in them decide whether real money moves and whether ' +
      'anyone can log in at all. That is an owner\u2019s call, not a job ' +
      'function.',
  },
  {
    key: 'admins',
    label: 'Admin accounts & permissions',
    hint:
      'Create admins, change roles, add roles and edit this grid. ' +
      'Never more than the holder has themselves: they cannot grant a ' +
      'permission they lack, nor create or edit a superadmin.',
  },
];

const ALL_KEYS = PERMISSIONS.map((p) => p.key);

/** Keys any role other than superadmin may be granted. */
const GRANTABLE_KEYS = PERMISSIONS
  .filter((p) => !p.superadminOnly)
  .map((p) => p.key);

/**
 * The one role that is not data.
 *
 * It is never stored, never edited and never deleted, and it always
 * holds every key. Everything else about roles can be changed from
 * the panel, which is exactly why this one cannot: an editor that can
 * strip superadmin can strip `admins`, and then there is nobody left
 * who can give it back.
 */
const SUPERADMIN = {
  key: 'superadmin',
  label: 'Superadmin',
  hint: 'Everything, including the gateway keys and the roles themselves.',
  builtIn: true,
};

/**
 * The roles a fresh install starts with.
 *
 * These are a starting point, not a fixed set — they can be renamed,
 * re-permissioned or deleted from Settings, and new ones added beside
 * them. They are here so an install that has never opened that page
 * still has something sensible.
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
const DEFAULT_ROLES = [
  {
    key: 'support',
    label: 'Support',
    hint: 'The queues: users, verifications, disputes and chat.',
    permissions: ['dashboard', 'users', 'verifications', 'jobs', 'disputes', 'support'],
  },
  {
    key: 'finance',
    label: 'Finance',
    hint: 'Payments, reports and analytics. Not the gateway keys.',
    permissions: ['dashboard', 'jobs', 'payments', 'analytics', 'reports'],
  },
];

const KEY = 'admin_role_permissions';

/** A role's stored key: lowercase, no spaces, safe in a URL. */
const MAX_LABEL = 40;
const MAX_HINT = 160;

function slug(v) {
  return String(v || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 32);
}

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
 * Returns null for anything that is not an array, so a caller can
 * tell "nothing saved" from "saved as empty" — an empty array is a
 * deliberate choice meaning no access, and must not quietly become
 * the defaults.
 */
function clean(list) {
  if (!Array.isArray(list)) return null;
  return [...new Set(list.filter((k) => GRANTABLE_KEYS.includes(k)))];
}

/**
 * Read the stored roles, tolerating the shape they used to have.
 *
 * Before roles were editable, this document was a plain map of
 * role -> keys with no labels, because the role list was in the
 * source. Installs that saved one still have it, so it is converted
 * on read rather than migrated: a migration is a deploy-time step
 * that has to run exactly once, and this costs nothing and cannot be
 * half-applied.
 */
function parseStored(value) {
  if (!value || typeof value !== 'object') return null;

  if (Array.isArray(value.roles)) {
    return value.roles
      .filter((r) => r && slug(r.key) && slug(r.key) !== SUPERADMIN.key)
      .map((r) => ({
        key: slug(r.key),
        label: String(r.label || r.key).trim().slice(0, MAX_LABEL),
        hint: String(r.hint || '').trim().slice(0, MAX_HINT),
        permissions: clean(r.permissions) || [],
      }));
  }

  // Legacy: { support: [...], finance: [...] }
  const legacy = Object.entries(value)
    .filter(([k, v]) => Array.isArray(v) && slug(k) && slug(k) !== SUPERADMIN.key)
    .map(([k, v]) => {
      const known = DEFAULT_ROLES.find((d) => d.key === slug(k));
      return {
        key: slug(k),
        label: known?.label || slug(k),
        hint: known?.hint || '',
        permissions: clean(v) || [],
      };
    });
  return legacy.length ? legacy : null;
}

/**
 * Every role, superadmin first.
 *
 * Shape: { key, label, hint, permissions, builtIn }. superadmin is
 * prepended rather than stored, so it exists even on a database where
 * the settings document has been deleted.
 */
async function getRoles() {
  if (cache && Date.now() - cachedAt < CACHE_MS) return cache;

  const doc = await Setting.findOne({ key: KEY }).lean();
  const stored = parseStored(doc?.value);

  cache = [
    { ...SUPERADMIN, permissions: [...ALL_KEYS] },
    ...(stored || DEFAULT_ROLES.map((r) => ({ ...r, permissions: [...r.permissions] }))),
  ];
  cachedAt = Date.now();
  return cache;
}

/** The role -> permission map, for callers that want a lookup. */
async function getRolePermissions() {
  const roles = await getRoles();
  return Object.fromEntries(roles.map((r) => [r.key, r.permissions]));
}

/** Just the keys, in display order. */
async function roleKeys() {
  return (await getRoles()).map((r) => r.key);
}

/** What this admin may do. A deactivated account may do nothing. */
async function permissionsFor(admin) {
  if (!admin || admin.isActive === false) return [];
  const roles = await getRoles();
  return roles.find((r) => r.key === admin.role)?.permissions || [];
}

/** True when the admin holds ANY of the given keys. */
async function can(admin, ...keys) {
  if (!keys.length) return false;
  const mine = await permissionsFor(admin);
  return keys.some((k) => mine.includes(k));
}

/**
 * Validate and store the editable roles.
 *
 * Returns { roles } on success, or { error } with a sentence meant to
 * be shown to whoever pressed Save. The caller supplies `inUse` — a
 * map of role key to how many admins hold it — because deciding
 * whether a role may be deleted needs the Admin collection, and this
 * module deliberately does not reach into it.
 *
 * superadmin is dropped if present, and so is any key that is not
 * grantable. Neither is the caller's decision, and silently dropping
 * them is safer than trusting the client to have sent the right
 * thing — a stale panel that still shows an old checkbox must not be
 * able to grant it.
 */
async function saveRoles(next, by, inUse = {}, grantable = null) {
  if (!Array.isArray(next)) return { error: 'Nothing to save' };

  const before = await getRoles();
  const prev = Object.fromEntries(
    before.filter((r) => !r.builtIn).map((r) => [r.key, r.permissions]),
  );

  // What this admin may hand out. null means superadmin: everything.
  // Anything outside it is neither granted nor revoked — the role
  // keeps exactly what it had, so a limited admin pressing Save
  // cannot quietly strip a permission they were not shown either.
  const mayGrant = grantable === null ? null : new Set(grantable);

  const out = [];
  const seen = new Set();

  for (const raw of next) {
    const key = slug(raw?.key || raw?.label);
    if (!key) {
      return { error: 'Every role needs a name.' };
    }
    if (key === SUPERADMIN.key) continue;
    if (seen.has(key)) {
      return { error: `Two roles would both be called "${key}".` };
    }
    seen.add(key);

    const asked = clean(raw.permissions) || [];
    const had = prev[key] || [];
    const permissions = mayGrant
      ? [
          ...new Set([
            ...asked.filter((k) => mayGrant.has(k)),
            ...had.filter((k) => !mayGrant.has(k)),
          ]),
        ]
      : asked;

    out.push({
      key,
      label: String(raw.label || key).trim().slice(0, MAX_LABEL),
      hint: String(raw.hint || '').trim().slice(0, MAX_HINT),
      permissions,
    });
  }

  // A role that still has admins cannot be removed. Deleting it would
  // leave them with a role that resolves to no permissions — signed
  // in, and able to open nothing, with no message saying why.
  const gone = before
    .filter((r) => !r.builtIn)
    .filter((r) => !seen.has(r.key) && (inUse[r.key] || 0) > 0);
  if (gone.length) {
    const g = gone[0];
    const n = inUse[g.key];
    return {
      error:
        `${g.label} still has ${n} admin${n === 1 ? '' : 's'}. ` +
        `Move ${n === 1 ? 'them' : 'them all'} to another role first.`,
    };
  }

  await Setting.findOneAndUpdate(
    { key: KEY },
    {
      key: KEY,
      value: { roles: out },
      updatedBy: by?._id,
      updatedByName: by?.name,
    },
    // The return value is not used: the cache is dropped below and
    // getRoles() re-reads with superadmin prepended.
    { upsert: true },
  );

  invalidate();
  return { roles: await getRoles() };
}

module.exports = {
  PERMISSIONS,
  SUPERADMIN,
  DEFAULT_ROLES,
  ALL_KEYS,
  GRANTABLE_KEYS,
  KEY,
  slug,
  getRoles,
  roleKeys,
  getRolePermissions,
  permissionsFor,
  can,
  saveRoles,
  invalidate,
};
