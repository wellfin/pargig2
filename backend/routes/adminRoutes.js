const router = require('express').Router();
const {
  protect,
  requireAdmin,
  requireAdminRole,
} = require('../middleware/authMiddleware');
const ctrl = require('../controllers/adminController');
const issues = require('../controllers/issueController');
const settings = require('../controllers/settingsController');

router.get('/seed', ctrl.seedSuperAdmin);
router.get('/seed-demo', ctrl.seedDemoData);
router.post('/seed-demo', ctrl.seedDemoData);

router.get('/dashboard', protect, requireAdmin, ctrl.dashboard);
router.get('/users', protect, requireAdmin, ctrl.listUsers);
router.put('/users/:id/status', protect, requireAdmin, ctrl.setUserStatus);
router.delete('/users/:id', protect, requireAdmin, ctrl.deleteUser);
router.post('/users/document/verify', protect, requireAdmin, ctrl.verifyDocument);
router.get('/users/:id', protect, requireAdmin, ctrl.userDetail);

router.get('/jobs', protect, requireAdmin, ctrl.listJobs);
// Full detail for one job / user — the list views can't show voice
// notes, completion proof, applicants or the wallet ledger.
router.get('/jobs/:id', protect, requireAdmin, ctrl.jobDetail);
router.get('/payments', protect, requireAdmin, ctrl.listPayments);

// Need Help issues raised by job givers.
router.get('/issues', protect, requireAdmin, issues.adminListIssues);
router.get('/issues/:id', protect, requireAdmin, issues.adminIssueDetail);
router.put('/issues/:id', protect, requireAdmin, issues.adminUpdateIssue);

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
