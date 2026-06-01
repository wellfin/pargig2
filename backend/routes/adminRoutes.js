const router = require('express').Router();
const { protect, requireAdmin } = require('../middleware/authMiddleware');
const ctrl = require('../controllers/adminController');

router.get('/seed', ctrl.seedSuperAdmin);
router.get('/seed-demo', ctrl.seedDemoData);
router.post('/seed-demo', ctrl.seedDemoData);

router.get('/dashboard', protect, requireAdmin, ctrl.dashboard);
router.get('/users', protect, requireAdmin, ctrl.listUsers);
router.put('/users/:id/status', protect, requireAdmin, ctrl.setUserStatus);
router.delete('/users/:id', protect, requireAdmin, ctrl.deleteUser);
router.post('/users/document/verify', protect, requireAdmin, ctrl.verifyDocument);

router.get('/jobs', protect, requireAdmin, ctrl.listJobs);
router.get('/payments', protect, requireAdmin, ctrl.listPayments);
router.get('/disputes', protect, requireAdmin, ctrl.listDisputes);
router.put('/disputes/:id/resolve', protect, requireAdmin, ctrl.resolveDispute);

router.get('/reports', protect, requireAdmin, ctrl.reports);

module.exports = router;
