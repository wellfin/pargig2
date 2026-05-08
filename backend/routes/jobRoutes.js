const router = require('express').Router();
const { protect, requireUser } = require('../middleware/authMiddleware');
const upload = require('../middleware/uploadMiddleware');
const ctrl = require('../controllers/jobController');

router.post('/', protect, requireUser, ctrl.createJob);
router.post('/photo', protect, requireUser, upload.single('photo'), ctrl.uploadJobPhoto);
router.get('/browse', ctrl.browseJobs);
router.get('/categories', ctrl.browseCategories);
router.get('/posted/me', protect, requireUser, ctrl.myPostedJobs);
router.get('/applied/me', protect, requireUser, ctrl.myAppliedJobs);
router.get('/:id', ctrl.getJob);
router.put('/:id', protect, requireUser, ctrl.updateJob);

router.post('/:id/interest', protect, requireUser, ctrl.showInterest);
router.post('/:id/confirm', protect, requireUser, ctrl.confirmJobtaker);
router.post('/:id/reach', protect, requireUser, ctrl.reachLocation);
router.post('/:id/start/verify', protect, requireUser, ctrl.verifyStartOtp);
router.post('/:id/complete', protect, requireUser, ctrl.completeJob);
router.post('/:id/complete/verify', protect, requireUser, ctrl.verifyCompleteOtp);
router.post('/:id/cancel', protect, requireUser, ctrl.cancelJob);

module.exports = router;
