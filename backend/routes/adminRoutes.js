const router = require('express').Router();
const {
  protect,
  requireAdmin,
  requirePermission,
} = require('../middleware/authMiddleware');
const ctrl = require('../controllers/adminController');
const issues = require('../controllers/issueController');
const support = require('../controllers/supportChatController');
const settings = require('../controllers/settingsController');
const accounts = require('../controllers/adminAccountController');
const integrations = require('../controllers/integrationsController');

// There are no unauthenticated routes in this file, and none may be
// added. Creating an admin and seeding demo data used to live here as
// open URLs. GET /api/admin/seed created a superadmin for whoever
// asked first and named the existing admin's email to everyone else;
// GET /api/admin/seed-demo?wipe=1 emptied the jobs, payments,
// ratings, issues, notifications and transactions collections from a
// browser address bar.
//
// Demo seeding is gone from the repository altogether. Admin accounts
// are managed over SSH instead, because the one thing admin creation
// cannot do is require a login — on an empty database there is nobody
// to log in as, and no guard rescues an endpoint that hands out a
// superadmin to the first caller:
//
//   npm run admin:create     — create an admin (first or additional)
//   npm run admin:password   — change an existing admin's password
//
// Past the first account, admins are managed in the panel instead:
// Settings -> Admin Users. The scripts remain the way back in when
// nobody can sign in at all.
//
// Every route below names the permission it needs. That name is the
// enforcement — the panel also hides what a role cannot use, but
// hiding a link does nothing to the endpoint behind it. Several names
// mean "any of these": the dashboard tiles and the analytics charts
// read the same insight routes, and either permission is reason
// enough to answer.

/** Who am I and what may I see. Every signed-in admin may ask. */
router.get('/me', protect, requireAdmin, accounts.me);

router.get('/dashboard', protect, requirePermission('dashboard', 'analytics'), ctrl.dashboard);
router.get('/users', protect, requirePermission('users'), ctrl.listUsers);
router.put('/users/:id/status', protect, requirePermission('users'), ctrl.setUserStatus);
router.delete('/users/:id', protect, requirePermission('users'), ctrl.deleteUser);
router.get('/verifications', protect, requirePermission('verifications'), ctrl.pendingVerifications);
router.post('/users/document/verify', protect, requirePermission('verifications'), ctrl.verifyDocument);
router.get('/users/:id', protect, requirePermission('users'), ctrl.userDetail);

router.get('/jobs', protect, requirePermission('jobs'), ctrl.listJobs);
// Ahead of '/jobs/:id', or Express hands 'stats' to it as an id.
router.get('/jobs/stats', protect, requirePermission('dashboard', 'analytics'), ctrl.jobStats);
// Full detail for one job / user — the list views can't show voice
// notes, completion proof, applicants or the wallet ledger.
router.get('/jobs/:id', protect, requirePermission('jobs'), ctrl.jobDetail);
router.get('/payments', protect, requirePermission('payments'), ctrl.listPayments);
router.get('/insights/job-givers', protect, requirePermission('dashboard', 'analytics'), ctrl.jobGiverInsights);
router.get('/insights/job-takers', protect, requirePermission('dashboard', 'analytics'), ctrl.jobTakerInsights);
router.get('/insights/timeline', protect, requirePermission('analytics', 'dashboard'), ctrl.timeline);
router.get('/insights/geography', protect, requirePermission('analytics', 'dashboard'), ctrl.geography);
router.get('/alerts', protect, requirePermission('dashboard', 'analytics'), ctrl.alerts);

// Need Help issues raised by job givers.
router.get('/issues', protect, requirePermission('disputes'), issues.adminListIssues);
router.get('/issues/:id', protect, requirePermission('disputes'), issues.adminIssueDetail);
router.put('/issues/:id', protect, requirePermission('disputes'), issues.adminUpdateIssue);

// Live support chat. Anyone who can sign in to the panel can answer —
// the desk is a shared inbox, not a per-admin one.
router.get('/support/chats', protect, requirePermission('support'), support.listSupportChats);
router.get('/support/chats/:roomId', protect, requirePermission('support'), support.getSupportChat);
router.post(
  '/support/chats/:roomId/messages',
  protect,
  requirePermission('support'),
  support.replySupportChat,
);

router.get('/reports', protect, requirePermission('reports'), ctrl.reports);

// Third-party credentials: the payment gateway, the SMS gateway and
// the distance server. One permission over all three, because they
// are the same kind of thing — accounts that belong to whoever owns
// the business — and because `integrations` is superadmin-only, which
// is where they belong.
//
// They live in the database rather than the environment so that
// turning SMS on, or moving off the public OSRM server, does not
// require somebody with SSH. See utils/smsConfig.js.
const thirdParty = [protect, requirePermission('integrations')];

router.get('/settings/payment', ...thirdParty, settings.getPaymentSettings);
router.put('/settings/payment', ...thirdParty, settings.updatePaymentSettings);
router.post('/settings/payment/test', ...thirdParty, settings.testPaymentSettings);

router.get('/settings/sms', ...thirdParty, integrations.getSmsSettings);
router.put('/settings/sms', ...thirdParty, integrations.updateSmsSettings);
router.post('/settings/sms/test', ...thirdParty, integrations.testSmsSettings);

router.get('/settings/routing', ...thirdParty, integrations.getRoutingSettings);
router.put('/settings/routing', ...thirdParty, integrations.updateRoutingSettings);
router.post(
  '/settings/routing/test',
  ...thirdParty,
  integrations.testRoutingSettings,
);

// Admin accounts and the permission grid. `admins` belongs to
// superadmin alone and cannot be granted to another role: whoever
// holds it can create a superadmin and sign in as one, so handing it
// out is promotion rather than delegation.
const adminsOnly = [protect, requirePermission('admins')];
router.get('/admins', ...adminsOnly, accounts.listAdmins);
router.post('/admins', ...adminsOnly, accounts.createAdmin);
router.put('/admins/:id', ...adminsOnly, accounts.updateAdmin);
router.put('/admins/:id/password', ...adminsOnly, accounts.setAdminPassword);
router.delete('/admins/:id', ...adminsOnly, accounts.deleteAdmin);
router.get('/permissions', ...adminsOnly, accounts.getPermissions);
router.put('/permissions', ...adminsOnly, accounts.updatePermissions);

module.exports = router;
