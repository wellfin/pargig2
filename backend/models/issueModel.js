const mongoose = require('mongoose');

/**
 * An issue either side raises against a completed job.
 *
 * Mirrors the Need Help flow exactly: pick an issue type, tick what
 * specifically happened, describe it, optionally attach photos. Nothing
 * more is asked of the user — what the money should do about it is the
 * admin's decision, recorded here when they resolve it.
 *
 * Both roles use this one record, because a complaint is the same object
 * whichever direction it points. What differs is the catalogue of types
 * on offer: a giver complains about the work, a worker about the client,
 * and neither list makes sense filed under the other's name.
 */

// The six types a JOB GIVER can choose. Machine values; the app and the
// admin panel own the display copy.
const GIVER_ISSUE_TYPES = [
  'service_quality',
  'payment',
  'worker_behavior',
  'wrong_service',
  'safety',
  'other'
];

// The seven a JOB TAKER can choose. 'other' is deliberately shared: it
// means the same thing from either side, and splitting it would produce
// two codes for one idea.
const TAKER_ISSUE_TYPES = [
  'payment_not_received',
  'requirement_changed',
  'additional_work',
  'access_not_provided',
  'giver_unavailable',
  'giver_behaviour',
  'other'
];

const ISSUE_TYPES = [
  ...GIVER_ISSUE_TYPES,
  ...TAKER_ISSUE_TYPES.filter((t) => !GIVER_ISSUE_TYPES.includes(t))
];

/**
 * Sub-issues offered under each type, on the "What specifically happened?"
 * step. Kept server-side so the app and the admin panel agree on what a
 * ticked box means, and so the list can change without shipping a build.
 */
const SUB_ISSUES = {
  // ---- job giver ----
  service_quality: ['Work Not Completed', 'Poor Quality Work', 'Property Damage'],
  payment: ['Overcharged', 'Charged Twice', 'Refund Not Received', 'Extra Charges Demanded'],
  worker_behavior: ['Rude Behaviour', 'Arrived Late', 'Did Not Arrive', 'Unprofessional Conduct'],
  wrong_service: ['Different Service Performed', 'Incomplete Scope', 'Wrong Address Attended'],
  safety: ['Unsafe Work Practice', 'Damage Risk Ignored', 'Felt Unsafe', 'No Safety Equipment'],

  // ---- job taker ----
  payment_not_received: ['Not Paid At All', 'Paid Less Than Agreed', 'Payment Still Pending'],
  requirement_changed: ['Different Work On Arrival', 'Scope Increased', 'Location Changed'],
  additional_work: ['Extra Work Without Pay', 'Asked To Stay Longer', 'Work Outside Agreement'],
  access_not_provided: ['No Materials Provided', 'Could Not Enter Property', 'No Power Or Water'],
  giver_unavailable: ['Nobody At The Location', 'Not Reachable On Call', 'Cancelled On Arrival'],
  giver_behaviour: ['Rude Behaviour', 'Unsafe Conditions', 'Felt Unsafe', 'Threatened Or Harassed'],

  // ---- shared ----
  other: []
};

/** The types one role may file under. */
const typesForRole = (role) =>
  role === 'jobtaker' ? TAKER_ISSUE_TYPES : GIVER_ISSUE_TYPES;

const issueSchema = new mongoose.Schema({
  // Human reference shown in the app and quoted to support ("#ISS-10042").
  // ObjectIds are unusable over a phone call.
  code: { type: String, unique: true, index: true },

  job: { type: mongoose.Schema.Types.ObjectId, ref: 'Job', required: true, index: true },
  raisedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  // Which side filed it, recorded rather than derived: it decides which
  // catalogue the type belongs to, and support reads a complaint very
  // differently depending on who is making it.
  raisedByRole: {
    type: String,
    enum: ['jobgiver', 'jobtaker'],
    default: 'jobgiver',
    index: true
  },
  // The other party on the job, captured at raise time.
  against: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },

  issueType: { type: String, enum: ISSUE_TYPES, required: true },
  // Ticked boxes from the sub-issue step. Free-form strings rather than an
  // enum so SUB_ISSUES above can grow without a migration.
  subIssues: [String],

  // "Tell us what happened". The 10-character floor is enforced in the
  // controller so the message can explain itself; 500 matches the counter
  // the app shows.
  description: { type: String, required: true, maxlength: 500 },

  // Optional evidence, uploaded through the same pipeline as job photos.
  photos: [String],

  status: {
    type: String,
    enum: ['open', 'under_review', 'resolved', 'rejected'],
    default: 'open',
    index: true
  },

  // Filled by admin when they close it out.
  resolution: {
    note: String,
    decidedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'Admin' },
    decidedAt: Date
  }
}, { timestamps: true });

// Newest-first listing per user is the only list query, so index for it.
issueSchema.index({ raisedBy: 1, createdAt: -1 });

/**
 * Short numeric reference.
 *
 * An async pre-hook is promise-based — Mongoose passes it no `next`, and
 * calling one throws "next is not a function" on every save.
 *
 * A count alone can collide (two issues filed at once read the same
 * number, and `code` is uniquely indexed), so the candidate is probed and
 * stepped until it is free. The loop is bounded and falls back to an
 * id-derived suffix, which cannot collide because ObjectIds do not.
 */
issueSchema.pre('validate', async function assignCode() {
  if (this.code) return;
  const Model = this.constructor;
  const base = await Model.estimatedDocumentCount();
  for (let i = 0; i < 25; i += 1) {
    const candidate = `ISS-${10001 + base + i}`;
    const taken = await Model.exists({ code: candidate });
    if (!taken) {
      this.code = candidate;
      return;
    }
  }
  this.code = `ISS-${this._id.toString().slice(-6).toUpperCase()}`;
});

const Issue = mongoose.model('Issue', issueSchema);

Issue.ISSUE_TYPES = ISSUE_TYPES;
Issue.GIVER_ISSUE_TYPES = GIVER_ISSUE_TYPES;
Issue.TAKER_ISSUE_TYPES = TAKER_ISSUE_TYPES;
Issue.SUB_ISSUES = SUB_ISSUES;
Issue.typesForRole = typesForRole;

module.exports = Issue;
