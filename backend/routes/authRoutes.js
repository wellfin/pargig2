const router = require('express').Router();
const {
  requestOtp,
  verifyOtp,
  adminLogin,
  adminForgotPassword,
  adminResetPassword,
} = require('../controllers/authController');

router.post('/otp/request', requestOtp);
router.post('/otp/verify', verifyOtp);
router.post('/admin/login', adminLogin);
// Open by necessity — someone who has forgotten their password cannot
// prove who they are first. Both are rate limited per IP, the code is
// emailed to the address on the account and nowhere else, and neither
// route ever reveals whether an account exists.
router.post('/admin/forgot-password', adminForgotPassword);
router.post('/admin/reset-password', adminResetPassword);

module.exports = router;
