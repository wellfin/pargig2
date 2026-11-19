const asyncHandler = require('express-async-handler');
const Admin = require('../models/adminModel');
const perms = require('../utils/adminPermissions');

/**
 * Admin accounts, and what each role may do.
 *
 * The SSH scripts (npm run admin:create / admin:password) stay, and
 * stay the only way in on an empty database — creating the first
 * admin cannot require a login, because there is nobody to log in as.
 * Everything after the first is easier from the panel, so this is
 * that.
 *
 * Every route here needs the `admins` permission, which an owner can
 * now give to another role — so account and role management can be
 * handed over without handing over everything.
 *
 * That makes two different kinds of guard necessary.
 *
 * The first is about PRIVILEGE. Whoever manages accounts could
 * otherwise mint a superadmin, set its password and sign in as it,
 * which would make `admins` a synonym for "everything". So a
 * non-superadmin holding it can never create, edit, deactivate,
 * delete or re-password a superadmin, can never assign the
 * superadmin role, and — in saveRoles — can never grant a permission
 * they do not hold themselves. Everything they can produce is a
 * subset of what they already had.
 *
 * The second is about LOCKOUT, and applies to everyone including the
 * owner: you cannot change your own role, switch yourself off or
 * delete yourself, and the last active superadmin cannot be demoted
 * or deactivated. Each is one click from a panel nobody can get into,
 * recoverable only over SSH.
 */

const MIN_PASSWORD = 10;
const SAFE_FIELDS = 'name email role isActive createdAt updatedAt';

const isEmail = (v) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v);

/**
 * How many admins hold each role.
 *
 * Needed in two places: the grid shows it so nobody deletes a role
 * out from under three people, and the save refuses when they would
 * be left holding a role that no longer resolves to anything.
 */
async function adminsPerRole() {
  const rows = await Admin.aggregate([
    { $group: { _id: '$role', n: { $sum: 1 } } },
  ]);
  return Object.fromEntries(rows.map((r) => [r._id, r.n]));
}

/**
 * Check a role exists, against the live list.
 *
 * The model no longer carries an enum — it cannot, now that roles are
 * created at runtime — so this is the only thing standing between the
 * request body and a role nobody defined.
 */
async function knownRole(role) {
  return (await perms.roleKeys()).includes(String(role));
}

const isOwner = (admin) => admin?.role === perms.SUPERADMIN.key;

/**
 * Refuse when a non-superadmin reaches for a superadmin account.
 *
 * Returns a sentence to throw, or null. Written as one helper
 * because it guards four endpoints and the rule has to be identical
 * in all four — a gap in any one of them is the whole escalation.
 */
function blockedBySeniority(actor, target, verb) {
  if (isOwner(actor)) return null;
  if (target.role !== perms.SUPERADMIN.key) return null;
  return `Only a superadmin can ${verb} another superadmin.`;
}

/** How many superadmins could still sign in, excluding one id. */
const otherActiveSuperadmins = (exceptId) =>
  Admin.countDocuments({
    _id: { $ne: exceptId },
    role: 'superadmin',
    isActive: true,
  });

/** GET /api/admin/admins */
const listAdmins = asyncHandler(async (req, res) => {
  const [admins, roles] = await Promise.all([
    Admin.find({}).select(SAFE_FIELDS).sort({ createdAt: 1 }).lean(),
    perms.getRoles(),
  ]);
  res.json({
    admins,
    // Sent together so the list can say what each row's role means
    // without a second round trip. Each role carries its own label
    // and one-line meaning now that those are editable rather than
    // written into the panel.
    roles,
    permissions: perms.PERMISSIONS,
    me: String(req.admin._id),
    // What the panel may offer THIS admin. It hides what it cannot
    // do rather than showing buttons that answer 403; the refusals
    // above are what actually enforces it.
    isOwner: isOwner(req.admin),
  });
});

/** POST /api/admin/admins */
const createAdmin = asyncHandler(async (req, res) => {
  const name = String(req.body.name || '').trim();
  const email = String(req.body.email || '').trim().toLowerCase();
  const password = String(req.body.password || '');
  const role = String(req.body.role || 'support');

  if (!name) {
    res.status(400);
    throw new Error('Name is required');
  }
  if (!isEmail(email)) {
    res.status(400);
    throw new Error('That does not look like an email address');
  }
  if (!(await knownRole(role))) {
    res.status(400);
    throw new Error(`There is no role called "${role}"`);
  }
  // Creating a superadmin means creating an account with every
  // permission and a password you chose. Only an owner may.
  if (role === perms.SUPERADMIN.key && !isOwner(req.admin)) {
    res.status(403);
    throw new Error('Only a superadmin can create another superadmin.');
  }
  if (password.trim().length < MIN_PASSWORD) {
    res.status(400);
    throw new Error(`The password must be at least ${MIN_PASSWORD} characters`);
  }
  if (await Admin.exists({ email })) {
    res.status(409);
    throw new Error(`${email} already has an admin account`);
  }

  // The address is the login AND the only route a forgotten password
  // can travel, so an unreachable one makes the account unrecoverable
  // the moment the password is lost.
  const admin = await Admin.create({ name, email, password, role });

  res.status(201).json({
    admin: {
      _id: admin._id,
      name: admin.name,
      email: admin.email,
      role: admin.role,
      isActive: admin.isActive,
      createdAt: admin.createdAt,
    },
  });
});

/** PUT /api/admin/admins/:id — name, role, active */
const updateAdmin = asyncHandler(async (req, res) => {
  const admin = await Admin.findById(req.params.id);
  if (!admin) {
    res.status(404);
    throw new Error('No such admin account');
  }

  const isSelf = String(admin._id) === String(req.admin._id);
  const wantsRole = req.body.role !== undefined;
  const wantsActive = req.body.isActive !== undefined;

  const senior = blockedBySeniority(req.admin, admin, 'edit');
  if (senior) {
    res.status(403);
    throw new Error(senior);
  }

  // Your own role and your own switch are the two edits that can end
  // with nobody able to undo them. Changing someone else's is fine;
  // changing your own is how you discover you needed SSH.
  if (isSelf && wantsRole && req.body.role !== admin.role) {
    res.status(400);
    throw new Error(
      'You cannot change your own role. Ask another superadmin, or use ' +
      'npm run admin:create over SSH.',
    );
  }
  if (isSelf && wantsActive && req.body.isActive === false) {
    res.status(400);
    throw new Error('You cannot deactivate your own account');
  }

  if (req.body.name !== undefined) {
    const name = String(req.body.name).trim();
    if (!name) {
      res.status(400);
      throw new Error('Name cannot be empty');
    }
    admin.name = name;
  }

  if (wantsRole) {
    const role = String(req.body.role);
    if (!(await knownRole(role))) {
      res.status(400);
      throw new Error(`There is no role called "${role}"`);
    }
    if (role === perms.SUPERADMIN.key && !isOwner(req.admin)) {
      res.status(403);
      throw new Error('Only a superadmin can promote someone to superadmin.');
    }
    // Demoting the last superadmin leaves the panel with nobody who
    // can promote anyone back.
    if (
      admin.role === 'superadmin' &&
      role !== 'superadmin' &&
      (await otherActiveSuperadmins(admin._id)) === 0
    ) {
      res.status(400);
      throw new Error(
        'This is the only active superadmin. Promote another account first.',
      );
    }
    admin.role = role;
  }

  if (wantsActive) {
    const next = Boolean(req.body.isActive);
    if (
      !next &&
      admin.role === 'superadmin' &&
      (await otherActiveSuperadmins(admin._id)) === 0
    ) {
      res.status(400);
      throw new Error(
        'This is the only active superadmin. Promote another account first.',
      );
    }
    admin.isActive = next;
    // A switched-off account should not keep a live reset code; it
    // would be a way back in that outlives the switch.
    if (!next) {
      admin.resetOtpHash = undefined;
      admin.resetOtpExpiresAt = undefined;
      admin.resetOtpAttempts = 0;
    }
  }

  await admin.save();

  res.json({
    admin: {
      _id: admin._id,
      name: admin.name,
      email: admin.email,
      role: admin.role,
      isActive: admin.isActive,
    },
  });
});

/** PUT /api/admin/admins/:id/password */
const setAdminPassword = asyncHandler(async (req, res) => {
  const admin = await Admin.findById(req.params.id);
  if (!admin) {
    res.status(404);
    throw new Error('No such admin account');
  }

  const senior = blockedBySeniority(req.admin, admin, 'set the password of');
  if (senior) {
    res.status(403);
    throw new Error(senior);
  }

  const password = String(req.body.password || '');
  if (password.trim().length < MIN_PASSWORD) {
    res.status(400);
    throw new Error(`The password must be at least ${MIN_PASSWORD} characters`);
  }

  // Assigned and saved so the pre-save hook hashes it. An updateOne
  // would store the plain text.
  admin.password = password;
  // Any reset code in flight was for the password that just stopped
  // existing.
  admin.resetOtpHash = undefined;
  admin.resetOtpExpiresAt = undefined;
  admin.resetOtpAttempts = 0;
  await admin.save();

  res.json({
    ok: true,
    // Said plainly because it surprises people: JWTs are not checked
    // against the password, so an open session survives the change.
    message:
      'Password changed. Anyone already signed in on the old one stays ' +
      'signed in until their session expires.',
  });
});

/** DELETE /api/admin/admins/:id */
const deleteAdmin = asyncHandler(async (req, res) => {
  const admin = await Admin.findById(req.params.id);
  if (!admin) {
    res.status(404);
    throw new Error('No such admin account');
  }
  if (String(admin._id) === String(req.admin._id)) {
    res.status(400);
    throw new Error('You cannot delete your own account');
  }
  const senior = blockedBySeniority(req.admin, admin, 'delete');
  if (senior) {
    res.status(403);
    throw new Error(senior);
  }
  if (
    admin.role === 'superadmin' &&
    (await otherActiveSuperadmins(admin._id)) === 0
  ) {
    res.status(400);
    throw new Error(
      'This is the only active superadmin. Promote another account first.',
    );
  }

  await admin.deleteOne();
  res.json({ ok: true });
});

/** GET /api/admin/permissions */
const getPermissions = asyncHandler(async (req, res) => {
  const [roles, inUse, mine] = await Promise.all([
    perms.getRoles(),
    adminsPerRole(),
    perms.permissionsFor(req.admin),
  ]);
  res.json({
    permissions: perms.PERMISSIONS,
    roles,
    // So the grid can grey out "delete" on a role people still hold,
    // and say how many rather than just refusing.
    inUse,
    defaults: perms.DEFAULT_ROLES,
    isOwner: isOwner(req.admin),
    // The boxes this admin may actually tick. An owner gets the lot;
    // anyone else gets what they hold, because you cannot hand out
    // what you were not given.
    canGrant: isOwner(req.admin) ? perms.ALL_KEYS : mine,
  });
});

/**
 * PUT /api/admin/permissions
 *
 * Takes the whole list of editable roles, not a diff. Adding,
 * renaming, re-permissioning and deleting are all one Save, which
 * matches what the grid is: a thing you adjust and then commit. A
 * per-row endpoint would need the same guards three times and would
 * let a half-applied set of changes exist.
 */
const updatePermissions = asyncHandler(async (req, res) => {
  // `rolePermissions` is what the old shape was called. Accepted so a
  // panel left open across the deploy fails loudly below rather than
  // writing nonsense.
  const next = req.body?.roles ?? req.body?.rolePermissions;
  if (!Array.isArray(next)) {
    res.status(400);
    throw new Error('Nothing to save');
  }

  const inUse = await adminsPerRole();
  // null means superadmin: no ceiling. Anyone else is capped at what
  // they hold, so the grid cannot be used to climb.
  const ceiling = isOwner(req.admin)
    ? null
    : await perms.permissionsFor(req.admin);
  const result = await perms.saveRoles(next, req.admin, inUse, ceiling);
  if (result.error) {
    res.status(400);
    throw new Error(result.error);
  }

  res.json({
    roles: result.roles,
    permissions: perms.PERMISSIONS,
    inUse: await adminsPerRole(),
    isOwner: isOwner(req.admin),
    canGrant: ceiling === null ? perms.ALL_KEYS : ceiling,
  });
});

/**
 * GET /api/admin/me
 *
 * Who the panel is signed in as and what it may show. Needs no
 * permission of its own: the answer for an admin with none is an
 * empty list, which is exactly what the panel has to render.
 */
const me = asyncHandler(async (req, res) => {
  res.json({
    _id: req.admin._id,
    name: req.admin.name,
    email: req.admin.email,
    role: req.admin.role,
    permissions: await perms.permissionsFor(req.admin),
  });
});

module.exports = {
  listAdmins,
  createAdmin,
  updateAdmin,
  setAdminPassword,
  deleteAdmin,
  getPermissions,
  updatePermissions,
  me,
};
