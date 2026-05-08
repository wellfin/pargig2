const router = require('express').Router();
const { protect, requireUser } = require('../middleware/authMiddleware');
const upload = require('../middleware/uploadMiddleware');
const ctrl = require('../controllers/userController');

router.get('/me', protect, requireUser, ctrl.getMe);
router.put('/me', protect, requireUser, ctrl.updateProfile);
router.post('/me/photo', protect, requireUser, upload.single('photo'), ctrl.uploadPhoto);
router.put('/me/location', protect, requireUser, ctrl.updateLocation);
router.put('/me/role', protect, requireUser, ctrl.switchRole);
router.put('/me/fcm', protect, requireUser, ctrl.setFcmToken);
router.post('/me/accept-terms', protect, requireUser, ctrl.acceptTerms);
router.get('/me/earnings', protect, requireUser, ctrl.getEarnings);
router.get('/nearby-workers', protect, requireUser, ctrl.nearbyWorkers);
router.post('/me/document', protect, requireUser, upload.single('file'), ctrl.uploadDocument);
router.get('/:id/public', ctrl.getPublicProfile);

module.exports = router;
