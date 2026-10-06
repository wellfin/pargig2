const mongoose = require('mongoose');

const interestedSchema = new mongoose.Schema({
  jobtaker: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  proposedPrice: Number,
  message: String,
  // When this worker says they can do the job. Distinct from the job's
  // own `scheduledAt`, which is the giver's preferred slot: the worker
  // may offer a different one, and the giver decides on the applicants
  // screen whether that suits them.
  availableAt: Date,
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
  // Optional tip the job giver adds on top of the job price. Kept separate
  // from finalPrice/proposedBudget — it is NOT part of the working price,
  // just an extra incentive shown to the worker.
  tip: { type: Number, default: 0 },
  isUrgent: { type: Boolean, default: false },
  isBoosted: { type: Boolean, default: false },

  interested: [interestedSchema],
  selectedJobtaker: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },

  // Workers who claimed-then-cancelled this job. When the jobtaker
  // cancels we push their _id here AND reopen the post so other workers
  // can claim it. browseJobs / browseCategories filter out any job
  // whose blockedJobtakers contains the calling user, so the canceller
  // never sees this post again in the feed / urgent popup.
  blockedJobtakers: [{ type: mongoose.Schema.Types.ObjectId, ref: 'User', index: true }],

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
  completionPhotos: [String],
  completionNote: String,
  // Payout method the worker requested via /payments/request from
  // the Payment Request screen — used by the jobgiver's payment flow
  // to render the matching pay-by-X UI.
  payoutMethod: { type: String, enum: ['cash', 'upi', 'card'] },
  payoutRequestedAt: Date,

  cancellation: {
    by: { type: String, enum: ['jobgiver', 'jobtaker', 'admin'] },
    reason: String,
    at: Date
  },

  startedAt: Date,
  completedAt: Date,
  // Stamped when the jobgiver taps "Release Payment" on the
  // completed-job card. Used by the mobile My Posted Jobs Completed
  // tab to render "Payment Released" disabled instead of an active
  // Release Payment button.
  paymentReleasedAt: Date
}, { timestamps: true });

jobSchema.index({ location: '2dsphere' });
jobSchema.index({ status: 1, createdAt: -1 });

module.exports = mongoose.model('Job', jobSchema);
