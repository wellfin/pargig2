const router = require('express').Router();
const { protect, requireUser } = require('../middleware/authMiddleware');
const ctrl = require('../controllers/ratingController');

router.post('/', protect, requireUser, ctrl.submitRating);
router.get('/user/:userId', ctrl.getUserRatings);

module.exports = router;
