// 4-digit code, used for login / registration OTP (mobile otp_screen
// is built for 4 boxes).
const generateOtp = () => Math.floor(1000 + Math.random() * 9000).toString();

// 6-digit code, used for the job start + completion OTP that the
// jobgiver (client) reads out to the worker. Mobile enter_otp_screen
// is built for 6 boxes.
const generateJobOtp = () => Math.floor(100000 + Math.random() * 900000).toString();

const otpExpiry = () => {
  const ttl = parseInt(process.env.OTP_TTL_SECONDS || '300', 10);
  return new Date(Date.now() + ttl * 1000);
};

module.exports = { generateOtp, generateJobOtp, otpExpiry };
