const router = require('express').Router();
const { protect, requireUser, requireAdmin } = require('../middleware/authMiddleware');
const ctrl = require('../controllers/paymentController');

router.post('/request', protect, requireUser, ctrl.requestPayment);
router.post('/initiate', protect, requireUser, ctrl.initiatePayment);
router.post('/confirm', protect, requireUser, ctrl.confirmPayment);
router.post('/:id/release', protect, requireUser, ctrl.releasePayment);
router.post('/jobs/:jobId/release', protect, requireUser, ctrl.releaseForJob);
router.post('/:id/refund', protect, requireAdmin, ctrl.refundPayment);
router.get('/me', protect, requireUser, ctrl.myPayments);
router.get('/me/earnings', protect, requireUser, ctrl.myEarnings);
router.post('/wallet/topup', protect, requireUser, ctrl.topupWallet);

module.exports = router;
