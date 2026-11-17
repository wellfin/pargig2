const router = require('express').Router();
const { protect, requireUser } = require('../middleware/authMiddleware');
const ctrl = require('../controllers/disputeController');

router.post('/', protect, requireUser, ctrl.raiseDispute);
router.get('/me', protect, requireUser, ctrl.myDisputes);
// Keep '/me' above '/:id' or Express matches "me" as an id.
router.get('/:id', protect, requireUser, ctrl.getDispute);
router.post('/:id/evidence', protect, requireUser, ctrl.addEvidence);

module.exports = router;
