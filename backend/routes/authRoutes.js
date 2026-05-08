const router = require('express').Router();
const { requestOtp, verifyOtp, adminLogin } = require('../controllers/authController');

router.post('/otp/request', requestOtp);
router.post('/otp/verify', verifyOtp);
router.post('/admin/login', adminLogin);

module.exports = router;
