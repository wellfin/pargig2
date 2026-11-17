const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const adminSchema = new mongoose.Schema({
  name: { type: String, required: true },
  email: { type: String, required: true, unique: true, lowercase: true },
  password: { type: String, required: true },
  role: { type: String, enum: ['superadmin', 'support', 'finance'], default: 'superadmin' },
  isActive: { type: Boolean, default: true },

  // --- password reset -------------------------------------------------
  // The emailed code, stored as an HMAC rather than as itself. A
  // six-digit number is trivial to try all of, so the real defences
  // are the ten-minute expiry and the attempt counter below; hashing
  // it means a leaked database dump does not also hand over every
  // reset currently in flight, and the HMAC key is JWT_SECRET, which
  // is not in the database at all.
  resetOtpHash: { type: String, select: false },
  resetOtpExpiresAt: { type: Date, select: false },
  // Wrong guesses against the current code. At the cap the code is
  // destroyed, so brute force costs a new email and a new wait rather
  // than nothing.
  resetOtpAttempts: { type: Number, default: 0, select: false },
  // Enforces the gap between sends, so this endpoint cannot be used to
  // post mail at somebody.
  resetOtpSentAt: { type: Date, select: false }
}, { timestamps: true });

adminSchema.pre('save', async function () {
  if (!this.isModified('password')) return;
  this.password = await bcrypt.hash(this.password, 10);
});

adminSchema.methods.matchPassword = function (entered) {
  return bcrypt.compare(entered, this.password);
};

module.exports = mongoose.model('Admin', adminSchema);
