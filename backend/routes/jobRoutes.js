const router = require('express').Router();
const { protect, requireUser } = require('../middleware/authMiddleware');
const upload = require('../middleware/uploadMiddleware');
const ctrl = require('../controllers/jobController');

router.post('/', protect, requireUser, ctrl.createJob);
router.post('/photo', protect, requireUser, upload.single('photo'), ctrl.uploadJobPhoto);
router.post('/voice', protect, requireUser, upload.single('voice'), ctrl.uploadJobVoiceNote);
router.get('/browse', ctrl.browseJobs);
router.get('/categories', ctrl.browseCategories);
router.get('/posted/me', protect, requireUser, ctrl.myPostedJobs);
router.get('/applied/me', protect, requireUser, ctrl.myAppliedJobs);
router.get('/:id', ctrl.getJob);
router.put('/:id', protect, requireUser, ctrl.updateJob);
router.put('/:id/tip', protect, requireUser, ctrl.setTip);

router.post('/:id/interest', protect, requireUser, ctrl.showInterest);
router.post('/:id/confirm', protect, requireUser, ctrl.confirmJobtaker);
// Jobgiver declines an applicant — removes them from `interested` and
// blocks them from re-applying / seeing the post again.
router.post('/:id/reject', protect, requireUser, ctrl.rejectApplicant);
// Atomic first-come-first-served claim for URGENT jobs only. Used by
// the urgent-job popup's "Accept Job" button so the worker auto-
// confirms (no jobgiver approval step) and the next worker to tap
// gets a 409.
router.post('/:id/claim-urgent', protect, requireUser, ctrl.claimUrgent);
router.post('/:id/reach', protect, requireUser, ctrl.reachLocation);
router.post('/:id/start/verify', protect, requireUser, ctrl.verifyStartOtp);
router.post('/:id/complete', protect, requireUser, ctrl.completeJob);
router.post('/:id/complete/verify', protect, requireUser, ctrl.verifyCompleteOtp);
router.post('/:id/cancel', protect, requireUser, ctrl.cancelJob);

module.exports = router;
