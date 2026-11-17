const router = require('express').Router();
const {
  protect,
  requireAdmin,
  requireAdminRole,
} = require('../middleware/authMiddleware');
const ctrl = require('../controllers/adminController');
const issues = require('../controllers/issueController');
const support = require('../controllers/supportChatController');
const settings = require('../controllers/settingsController');

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

router.get('/dashboard', protect, requireAdmin, ctrl.dashboard);
router.get('/users', protect, requireAdmin, ctrl.listUsers);
router.put('/users/:id/status', protect, requireAdmin, ctrl.setUserStatus);
router.delete('/users/:id', protect, requireAdmin, ctrl.deleteUser);
router.get('/verifications', protect, requireAdmin, ctrl.pendingVerifications);
router.post('/users/document/verify', protect, requireAdmin, ctrl.verifyDocument);
router.get('/users/:id', protect, requireAdmin, ctrl.userDetail);

router.get('/jobs', protect, requireAdmin, ctrl.listJobs);
// Ahead of '/jobs/:id', or Express hands 'stats' to it as an id.
router.get('/jobs/stats', protect, requireAdmin, ctrl.jobStats);
// Full detail for one job / user — the list views can't show voice
// notes, completion proof, applicants or the wallet ledger.
router.get('/jobs/:id', protect, requireAdmin, ctrl.jobDetail);
router.get('/payments', protect, requireAdmin, ctrl.listPayments);
router.get('/insights/job-givers', protect, requireAdmin, ctrl.jobGiverInsights);
router.get('/insights/job-takers', protect, requireAdmin, ctrl.jobTakerInsights);
router.get('/insights/timeline', protect, requireAdmin, ctrl.timeline);
router.get('/insights/geography', protect, requireAdmin, ctrl.geography);
router.get('/alerts', protect, requireAdmin, ctrl.alerts);

// Need Help issues raised by job givers.
router.get('/issues', protect, requireAdmin, issues.adminListIssues);
router.get('/issues/:id', protect, requireAdmin, issues.adminIssueDetail);
router.put('/issues/:id', protect, requireAdmin, issues.adminUpdateIssue);

// Live support chat. Anyone who can sign in to the panel can answer —
// the desk is a shared inbox, not a per-admin one.
router.get('/support/chats', protect, requireAdmin, support.listSupportChats);
router.get('/support/chats/:roomId', protect, requireAdmin, support.getSupportChat);
router.post(
  '/support/chats/:roomId/messages',
  protect,
  requireAdmin,
  support.replySupportChat,
);

router.get('/reports', protect, requireAdmin, ctrl.reports);

// Payment gateway credentials. Restricted to the roles that are
// accountable for money — a support admin never needs to see these,
// and the fewer people who can swap a live key, the better.
const financeOnly = [protect, requireAdminRole('superadmin', 'finance')];
router.get('/settings/payment', ...financeOnly, settings.getPaymentSettings);
router.put('/settings/payment', ...financeOnly, settings.updatePaymentSettings);
router.post(
  '/settings/payment/test',
  ...financeOnly,
  settings.testPaymentSettings,
);

module.exports = router;
