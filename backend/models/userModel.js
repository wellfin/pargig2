const mongoose = require('mongoose');

const documentSchema = new mongoose.Schema({
  type: { type: String, enum: ['aadhaar', 'pan', 'license', 'certification', 'other'], required: true },
  url: { type: String, required: true },
  status: { type: String, enum: ['pending', 'approved', 'rejected'], default: 'pending' },
  remark: String,
  uploadedAt: { type: Date, default: Date.now }
}, { _id: true });

const userSchema = new mongoose.Schema({
  mobile: { type: String, required: true, unique: true, index: true },
  name: String,
  photo: String,
  email: String,
  bio: String,
  skills: [{ type: String }],
  yearsOfExperience: String,
  roles: [{ type: String, enum: ['jobgiver', 'jobtaker'], default: 'jobgiver' }],
  activeRole: { type: String, enum: ['jobgiver', 'jobtaker'], default: 'jobgiver' },
  preference: { type: String, enum: ['anyone', 'experienced'] },
  location: {
    type: { type: String, enum: ['Point'], default: 'Point' },
    coordinates: { type: [Number], default: [0, 0] },
    address: String,
    city: String,
    state: String,
    pincode: String
  },
  documents: [documentSchema],
  isVerifiedProfessional: { type: Boolean, default: false },
  badge: { type: String, enum: ['none', 'verified', 'pro'], default: 'none' },
  rating: {
    average: { type: Number, default: 0 },
    count: { type: Number, default: 0 }
  },
  jobsCompleted: { type: Number, default: 0 },
  jobsCancelled: { type: Number, default: 0 },
  walletBalance: { type: Number, default: 0 },
  freeJobsRemaining: { type: Number, default: 3 },
  isActive: { type: Boolean, default: true },
  isBlocked: { type: Boolean, default: false },
  blockReason: String,
  fcmToken: String,
  acceptedTermsAt: Date,
  otp: {
    code: String,
    expiresAt: Date,
    attempts: { type: Number, default: 0 }
  },
  lastLoginAt: Date
}, { timestamps: true });

userSchema.index({ location: '2dsphere' });

module.exports = mongoose.model('User', userSchema);
