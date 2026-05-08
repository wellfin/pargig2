const asyncHandler = require('express-async-handler');
const User = require('../models/userModel');
const generateToken = require('../utils/generateToken');
const { generateOtp, otpExpiry } = require('../utils/otp');

const requestOtp = asyncHandler(async (req, res) => {
  const { mobile } = req.body;
  if (!mobile || !/^\d{10}$/.test(mobile)) {
    res.status(400);
    throw new Error('Valid 10-digit mobile required');
  }
  let user = await User.findOne({ mobile });
  if (!user) {
    user = await User.create({ mobile, roles: ['jobgiver'], activeRole: 'jobgiver' });
  }
  const code = generateOtp();
  user.otp = { code, expiresAt: otpExpiry(), attempts: 0 };
  await user.save();

  // TODO: integrate SMS gateway. For now we return OTP only in non-production.
  const payload = { message: 'OTP sent' };
  if (process.env.NODE_ENV !== 'production') payload.devOtp = code;
  res.json(payload);
});

const verifyOtp = asyncHandler(async (req, res) => {
  const { mobile, otp } = req.body;
  const user = await User.findOne({ mobile });
  if (!user || !user.otp || !user.otp.code) {
    res.status(400);
    throw new Error('Request OTP first');
  }
  if (user.otp.expiresAt < new Date()) {
    res.status(400);
    throw new Error('OTP expired');
  }
  if (user.otp.attempts >= 5) {
    res.status(429);
    throw new Error('Too many attempts');
  }
  if (user.otp.code !== otp) {
    user.otp.attempts += 1;
    await user.save();
    res.status(400);
    throw new Error('Invalid OTP');
  }
  user.otp = undefined;
  user.lastLoginAt = new Date();
  await user.save();

  res.json({
    token: generateToken(user._id),
    user
  });
});

const adminLogin = asyncHandler(async (req, res) => {
  const Admin = require('../models/adminModel');
  const { email, password } = req.body;
  const admin = await Admin.findOne({ email: (email || '').toLowerCase() });
  if (!admin || !(await admin.matchPassword(password))) {
    res.status(401);
    throw new Error('Invalid credentials');
  }
  if (!admin.isActive) {
    res.status(403);
    throw new Error('Admin disabled');
  }
  res.json({
    token: generateToken(admin._id, 'admin'),
    admin: { _id: admin._id, name: admin.name, email: admin.email, role: admin.role }
  });
});

module.exports = { requestOtp, verifyOtp, adminLogin };
