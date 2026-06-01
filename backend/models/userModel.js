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
  // Job-taker search preference: only surface jobs within this many km of
  // the user's saved location. Set on the Find Work setup screen.
  searchRadiusKm: { type: Number, default: 10 },
  // Human-readable label of the chosen radius bucket — e.g. "1-5 Kms",
  // "5-10 Kms", "10-20 Kms", "Above 20kms". Stored alongside
  // searchRadiusKm so the admin panel can show the original choice
  // (a "10-20 Kms" pick shouldn't read back as just "20 km").
  searchRadiusLabel: String,
  roles: [{ type: String, enum: ['jobgiver', 'jobtaker'], default: 'jobgiver' }],
  activeRole: { type: String, enum: ['jobgiver', 'jobtaker'], default: 'jobgiver' },
  preference: { type: String, enum: ['anyone', 'experienced'] },
  // Home / profile address. Source of truth: the wizard's address step.
  location: {
    type: { type: String, enum: ['Point'], default: 'Point' },
    coordinates: { type: [Number], default: [0, 0] },
    address: String,
    city: String,
    state: String,
    pincode: String,
    label: String
  },
  // Work area = the area the user wants to search for nearby jobs
  // (job-taker) or workers (job-giver) FROM. Distinct from `location`,
  // which is the user's home/profile address. The Find Work / Hire
  // Workers setup screens capture GPS into this field so that tapping
  // GPS there does NOT clobber the wizard's home address.
  // Same sub-fields as `location` so the admin sees a consistent shape.
  workArea: {
    type: { type: String, enum: ['Point'], default: 'Point' },
    coordinates: { type: [Number], default: [0, 0] },
    address: String,
    city: String,
    state: String,
    pincode: String,
    label: String
  },
  // Where the user is RIGHT NOW. Set by the home-header "Current
  // Location" toggle — captures GPS once and writes coordinates +
  // address parts + a label + timestamp here. Distinct from
  // `location` (home address) and `workArea` (search center).
  currentLocation: {
    type: { type: String, enum: ['Point'], default: 'Point' },
    coordinates: { type: [Number], default: [0, 0] },
    address: String,
    city: String,
    state: String,
    pincode: String,
    label: String,
    updatedAt: Date
  },
  // DEPRECATED — kept temporarily so old client builds that send these
  // top-level fields don't crash the controller. New writes should put
  // the label INSIDE the corresponding subdoc (workArea.label /
  // currentLocation.label). updateProfile mirrors top-level → subdoc
  // on save so old clients still work during the migration window.
  workAreaLabel: String,
  currentLocationLabel: String,
  currentLocationUpdatedAt: Date,
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
  lastLoginAt: Date,

  // Real-time availability for job-takers. Mobile flips this true when the
  // user turns on "Online" mode, then sends location updates every ~30s while
  // it stays true. nearby-workers query filters by isAvailable=true AND a
  // fresh lastLocationAt so stale ghosts don't show up to job-givers.
  isAvailable: { type: Boolean, default: false, index: true },
  lastLocationAt: Date
}, {
  timestamps: true,
  // minimize:false keeps empty subdocs (workArea at [0,0], otp shell)
  // present in the document instead of stripping them on save. Without
  // this, Mongoose treats a subdoc that's all at default/empty values
  // as "empty enough" and removes the field, which is what caused
  // workArea / currentLocation to disappear on suresh's record when an
  // older server build saved his doc.
  minimize: false,
});

userSchema.index({ location: '2dsphere' });

module.exports = mongoose.model('User', userSchema);
