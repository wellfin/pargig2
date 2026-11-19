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
 * Every route here needs the `admins` permission, which belongs to
 * superadmin alone. The guards below are about a different problem:
 * not strangers, but a superadmin locking themselves out by changing
 * their own account, or removing the last one that can undo it. Those
 * are one click away and have no recovery except SSH.
 */

const MIN_PASSWORD = 10;
const SAFE_FIELDS = 'name email role isActive createdAt updatedAt';

const isEmail = (v) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v);

/** How many superadmins could still sign in, excluding one id. */
const otherActiveSuperadmins = (exceptId) =>
  Admin.countDocuments({
    _id: { $ne: exceptId },
    role: 'superadmin',
    isActive: true,
  });

/** GET /api/admin/admins */
const listAdmins = asyncHandler(async (req, res) => {
  const [admins, rolePermissions] = await Promise.all([
    Admin.find({}).select(SAFE_FIELDS).sort({ createdAt: 1 }).lean(),
    perms.getRolePermissions(),
  ]);
  res.json({
    admins,
    // Sent together so the list can say what each row's role means
    // without a second round trip.
    roles: perms.ROLES,
    permissions: perms.PERMISSIONS,
    rolePermissions,
    me: String(req.admin._id),
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
  if (!perms.ROLES.includes(role)) {
    res.status(400);
    throw new Error('Unknown role');
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
    if (!perms.ROLES.includes(role)) {
      res.status(400);
      throw new Error('Unknown role');
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
  res.json({
    permissions: perms.PERMISSIONS,
    roles: perms.ROLES,
    rolePermissions: await perms.getRolePermissions(),
    defaults: perms.DEFAULTS,
  });
});

/** PUT /api/admin/permissions */
const updatePermissions = asyncHandler(async (req, res) => {
  const next = req.body?.rolePermissions;
  if (!next || typeof next !== 'object') {
    res.status(400);
    throw new Error('Nothing to save');
  }

  // superadmin and the `admins` key are dropped rather than rejected —
  // see utils/adminPermissions.js for why neither is editable.
  const rolePermissions = await perms.saveRolePermissions(next, req.admin);

  res.json({
    rolePermissions,
    permissions: perms.PERMISSIONS,
    roles: perms.ROLES,
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
