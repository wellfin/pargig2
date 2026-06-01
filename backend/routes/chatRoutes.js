const router = require('express').Router();
const { protect, requireUser } = require('../middleware/authMiddleware');
const ctrl = require('../controllers/chatController');

router.post('/job/:jobId/open', protect, requireUser, ctrl.openOrGetRoom);
router.post('/direct/with/:userId/open',
  protect, requireUser, ctrl.openOrGetDirect);
router.get('/rooms', protect, requireUser, ctrl.myRooms);
router.get('/unread', protect, requireUser, ctrl.unreadCount);
router.get('/rooms/:roomId', protect, requireUser, ctrl.getRoom);
router.post('/rooms/:roomId/messages', protect, requireUser, ctrl.sendMessage);
router.post('/notify', protect, requireUser, ctrl.notifyChatMessage);

module.exports = router;
