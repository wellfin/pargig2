const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const adminSchema = new mongoose.Schema({
  name: { type: String, required: true },
  email: { type: String, required: true, unique: true, lowercase: true },
  password: { type: String, required: true },
  /**
   * Which role this admin holds.
   *
   * No enum, deliberately. Roles are created and deleted from the
   * panel now, so a list fixed at schema-definition time would reject
   * every role made after the process started — and a role added on
   * one server would be invalid on another until both restarted.
   *
   * Validation moved to the one place that can do it correctly: the
   * controller, against the live list. Nothing else writes this
   * field, and the scripts read the same list.
   */
  role: { type: String, default: 'superadmin', index: true },
  isActive: { type: Boolean, default: true },

  /**
   * When this admin last opened the dispute queue.
   *
   * Drives the bell, and only the bell. The bell answers "has anything
   * arrived since I last looked", which is a question that stops being
   * true the moment you look — unlike "how many disputes are open",
   * which the sidebar count already answers and which stays true until
   * somebody decides them. Conflating the two is why the bell used to
   * sit on 3 forever.
   *
   * Whether a particular row has been read is a different thing again,
   * and is tracked per issue in Issue.readBy.
   */
  issuesSeenAt: Date,

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
