const router = require('express').Router();
const { protect, requireUser } = require('../middleware/authMiddleware');
const ctrl = require('../controllers/ratingController');

router.post('/', protect, requireUser, ctrl.submitRating);
// Before '/user/:userId' is irrelevant here (distinct prefixes), but
// '/given' must precede nothing dynamic at the same depth — keep it
// explicit anyway so a future '/:id' cannot swallow it.
router.get('/given', protect, requireUser, ctrl.getMyGivenRatings);
router.get('/job/:jobId', protect, requireUser, ctrl.getJobRatings);
router.get('/user/:userId', ctrl.getUserRatings);

module.exports = router;
