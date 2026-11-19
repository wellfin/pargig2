const jwt = require('jsonwebtoken');
const asyncHandler = require('express-async-handler');
const User = require('../models/userModel');
const Admin = require('../models/adminModel');
const adminPermissions = require('../utils/adminPermissions');

const protect = asyncHandler(async (req, res, next) => {
  let token;
  if (req.headers.authorization && req.headers.authorization.startsWith('Bearer')) {
    token = req.headers.authorization.split(' ')[1];
  }
  if (!token) {
    res.status(401);
    throw new Error('Not authorized, no token');
  }
  // jwt.verify throws on a malformed, tampered or expired token, and
  // that error carries no status — so the handler defaulted it to 500.
  // An expired session is the caller's problem to fix by signing in
  // again, not a server fault, and 401 is what says so.
  let decoded;
  try {
    decoded = jwt.verify(token, process.env.JWT_SECRET);
  } catch (err) {
    res.status(401);
    throw new Error(
      err.name === 'TokenExpiredError'
        ? 'Session expired, please sign in again'
        : 'Not authorized, invalid token'
    );
  }
  if (decoded.kind === 'admin') {
    req.admin = await Admin.findById(decoded.id).select('-password');
    if (!req.admin) {
      res.status(401);
      throw new Error('Admin not found');
    }
    // Checked on every request, not just at sign-in. Deactivating an
    // account has to take effect now; a JWT is not revocable, so an
    // admin who was switched off would otherwise keep full access
    // until their token happened to expire. 401 rather than 403, so
    // the panel signs them out instead of showing a dead page.
    if (req.admin.isActive === false) {
      res.status(401);
      throw new Error('This admin account has been deactivated');
    }
  } else {
    req.user = await User.findById(decoded.id);
    if (!req.user) {
      res.status(401);
      throw new Error('User not found');
    }
    if (req.user.isBlocked) {
      res.status(403);
      throw new Error('Account blocked');
    }
  }
  next();
});

const requireUser = (req, res, next) => {
  if (!req.user) {
    res.status(401);
    return next(new Error('User auth required'));
  }
  next();
};

const requireAdmin = (req, res, next) => {
  if (!req.admin) {
    res.status(403);
    return next(new Error('Admin only'));
  }
  next();
};

const requireRole = (role) => (req, res, next) => {
  if (!req.user || !req.user.roles.includes(role)) {
    res.status(403);
    return next(new Error(`Role ${role} required`));
  }
  next();
};

/**
 * Narrows an admin route to admins whose ROLE carries a permission.
 *
 * Several keys mean "any of these", because some endpoints feed more
 * than one page: the dashboard tiles and the analytics charts read
 * the same insight routes, and either permission is reason enough.
 *
 * This is the only enforcement there is. The panel also hides what it
 * cannot use, but hiding a link does not stop anyone from calling the
 * endpoint it pointed at.
 */
const requirePermission = (...keys) =>
  asyncHandler(async (req, res, next) => {
    if (!req.admin) {
      res.status(403);
      throw new Error('Admin only');
    }
    const allowed = await adminPermissions.can(req.admin, ...keys);
    if (!allowed) {
      res.status(403);
      const labels = keys
        .map((k) => adminPermissions.PERMISSIONS.find((p) => p.key === k)?.label || k)
        .join(' or ');
      throw new Error(`Your admin role does not have access to ${labels}`);
    }
    next();
  });

module.exports = {
  protect,
  requireUser,
  requireAdmin,
  requirePermission,
  requireRole,
};
