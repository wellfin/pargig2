const mongoose = require('mongoose');

const interestedSchema = new mongoose.Schema({
  jobtaker: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  proposedPrice: Number,
  message: String,
  createdAt: { type: Date, default: Date.now }
}, { _id: true });

const jobSchema = new mongoose.Schema({
  jobgiver: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  title: { type: String, required: true },
  description: String,
  voiceNoteUrl: String,
  category: String,
  photos: [String],
  location: {
    type: { type: String, enum: ['Point'], default: 'Point' },
    coordinates: { type: [Number], default: [0, 0] },
    address: String,
    city: String,
    pincode: String
  },
  scheduledAt: Date,
  preference: { type: String, enum: ['anyone', 'experienced'], default: 'anyone' },
  priceMode: { type: String, enum: ['fixed', 'open'], default: 'open' },
  proposedBudget: Number,
  finalPrice: Number,
  isUrgent: { type: Boolean, default: false },
  isBoosted: { type: Boolean, default: false },

  interested: [interestedSchema],
  selectedJobtaker: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },

  status: {
    type: String,
    enum: [
      'open', 'confirmed', 'reached', 'in_progress',
      'completed', 'cancelled', 'disputed'
    ],
    default: 'open',
    index: true
  },

  startOtp: {
    code: String,
    issuedAt: Date,
    verifiedAt: Date
  },
  completeOtp: {
    code: String,
    issuedAt: Date,
    verifiedAt: Date
  },

  cancellation: {
    by: { type: String, enum: ['jobgiver', 'jobtaker', 'admin'] },
    reason: String,
    at: Date
  },

  startedAt: Date,
  completedAt: Date
}, { timestamps: true });

jobSchema.index({ location: '2dsphere' });
jobSchema.index({ status: 1, createdAt: -1 });

module.exports = mongoose.model('Job', jobSchema);
