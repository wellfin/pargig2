const router = require('express').Router();
const { protect, requireUser } = require('../middleware/authMiddleware');
const ctrl = require('../controllers/issueController');

// Static paths first, so none is swallowed by '/:id'.
router.get('/catalog', ctrl.issueCatalog);
router.get('/job-history', protect, requireUser, ctrl.jobHistory);
router.get('/me', protect, requireUser, ctrl.myIssues);

router.post('/', protect, requireUser, ctrl.createIssue);
router.get('/:id', protect, requireUser, ctrl.getIssue);

module.exports = router;
