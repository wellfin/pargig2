const generateOtp = () => Math.floor(1000 + Math.random() * 9000).toString();

const otpExpiry = () => {
  const ttl = parseInt(process.env.OTP_TTL_SECONDS || '300', 10);
  return new Date(Date.now() + ttl * 1000);
};

module.exports = { generateOtp, otpExpiry };
