const router = require('express').Router();
const { protect, requireUser } = require('../middleware/authMiddleware');
const ctrl = require('../controllers/ratingController');

router.post('/', protect, requireUser, ctrl.submitRating);
// Before '/user/:userId' is irrelevant here (distinct prefixes), but
// '/given' must precede nothing dynamic at the same depth — keep it
// explicit anyway so a future '/:id' cannot swallow it.
// The rating this user still owes, checked when the app opens so a
// mandatory rating survives the app being closed.
router.get('/pending', protect, requireUser, ctrl.pendingRating);
router.get('/given', protect, requireUser, ctrl.getMyGivenRatings);
router.get('/job/:jobId', protect, requireUser, ctrl.getJobRatings);
router.get('/user/:userId', ctrl.getUserRatings);

module.exports = router;
