const router = require('express').Router();
const { protect, requireUser } = require('../middleware/authMiddleware');
const ctrl = require('../controllers/disputeController');

router.post('/', protect, requireUser, ctrl.raiseDispute);
router.get('/me', protect, requireUser, ctrl.myDisputes);

module.exports = router;
