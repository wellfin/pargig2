const router = require('express').Router();
const { protect, requireUser } = require('../middleware/authMiddleware');
const ctrl = require('../controllers/chatController');
const support = require('../controllers/supportChatController');

router.post('/job/:jobId/open', protect, requireUser, ctrl.openOrGetRoom);
router.post('/direct/with/:userId/open',
  protect, requireUser, ctrl.openOrGetDirect);
// Before '/rooms/:roomId' would ever see it, and before the job and
// direct openers, so none of them can swallow the word "support".
router.post('/support/open', protect, requireUser, support.openSupport);
router.get('/rooms', protect, requireUser, ctrl.myRooms);
router.get('/unread', protect, requireUser, ctrl.unreadCount);
router.get('/rooms/:roomId', protect, requireUser, ctrl.getRoom);
router.post('/rooms/:roomId/messages', protect, requireUser, ctrl.sendMessage);
router.post('/notify', protect, requireUser, ctrl.notifyChatMessage);

module.exports = router;
