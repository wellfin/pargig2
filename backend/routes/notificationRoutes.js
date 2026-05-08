const router = require('express').Router();
const { protect, requireUser } = require('../middleware/authMiddleware');
const ctrl = require('../controllers/notificationController');

router.get('/', protect, requireUser, ctrl.myNotifications);
router.get('/unread/count', protect, requireUser, ctrl.unreadCount);
router.post('/read', protect, requireUser, ctrl.markRead);

module.exports = router;
