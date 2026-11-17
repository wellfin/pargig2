const mongoose = require('mongoose');

/**
 * A dispute raised from My Services against a completed / paid job.
 *
 * Shapes the support flow the app walks the user through: what went
 * wrong, when, what evidence they attached, and what outcome they asked
 * for. Admin resolution then decides what actually happens to the money.
 */

// One entry per state change, so the app's tracking timeline is read from
// the record rather than inferred from `status` (which only ever holds the
// latest value and can't show when each step happened).
const timelineSchema = new mongoose.Schema({
  label: { type: String, required: true },
  note: String,
  at: { type: Date, default: Date.now },
}, { _id: false });

const disputeSchema = new mongoose.Schema({
  // Human-readable reference shown in the app and quoted to support
  // ("#DSP-10482"). ObjectIds are unusable over a phone call.
  code: { type: String, unique: true, index: true },

  job: { type: mongoose.Schema.Types.ObjectId, ref: 'Job', required: true, index: true },
  raisedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  against: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },

  // Category picked on the "What went wrong?" step.
  reason: { type: String, required: true },
  details: String,

  // "When did the issue occur?" — optional in the UI, so no default.
  occurredWhen: { type: String, enum: ['during', 'after', 'other'] },

  // Photos / videos / documents. Same upload pipeline as job photos, so
  // these are S3 URLs when S3 is configured.
  attachments: [String],

  // What the user asked for on the resolution step. Distinct from
  // `resolution.outcome`, which is what admin actually decided — the two
  // disagreeing is the normal case, not an error.
  requestedResolution: {
    type: String,
    enum: ['refund', 'correction', 'support_decide'],
    default: 'support_decide'
  },
  // Amount the user is claiming back, when they asked for a refund.
  amountRequested: { type: Number, default: 0 },

  status: {
    type: String,
    enum: ['open', 'under_review', 'resolved', 'rejected'],
    default: 'open'
  },

  // How the job was paid, copied in when the dispute is raised. Stored
  // rather than looked up so the case file still reads correctly if the
  // payment is later amended, and so disputes can be reported on by mode
  // without a join. Cash never gets this far — see raiseDispute.
  paymentMode: {
    type: String,
    enum: ['upi', 'card', 'netbanking', 'wallet', 'cash', 'other']
  },

  timeline: [timelineSchema],

  resolution: {
    decidedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'Admin' },

    // The decision in the business's own words — Full Refund / Partial
    // Refund / No Refund. `outcome` below is the older money-movement
    // vocabulary, kept in step with this and still written so existing
    // records and screens keep working.
    decision: {
      type: String,
      enum: ['full_refund', 'partial_refund', 'no_refund']
    },
    outcome: { type: String, enum: ['refund_giver', 'release_taker', 'split', 'no_action'] },
    note: String,
    decidedAt: Date,

    // Filled on resolution so the app can render the payment breakdown
    // ("Refund ₹500 / Released to provider ₹350") without recomputing it.
    refundAmount: { type: Number, default: 0 },
    releasedAmount: { type: Number, default: 0 },

    // ------------------------------------------------- audit trail
    // What the money actually did, as opposed to what was decided. The
    // two differ whenever a gateway declines or a refund is still in
    // flight, and reconciliation cares about the difference.
    refundStatus: {
      type: String,
      enum: ['not_applicable', 'pending', 'processed', 'failed'],
      default: 'not_applicable'
    },
    // Gateway refund id (`rfnd_...`), or null for a wallet credit.
    refundReference: String,
    refundProvider: String,
    // Settlement state of the payments behind this job after the
    // decision was carried out.
    settlementStatus: String,
    recoveredFromWorker: { type: Number, default: 0 },
    platformAbsorbed: { type: Number, default: 0 },
    error: String
  }
}, { timestamps: true });

// Short numeric reference, derived from how many disputes exist.
//
// An async pre-hook is promise-based — Mongoose passes it no `next`, and
// calling one throws "next is not a function" on every save.
//
// The count alone can collide (two disputes filed at once both read the
// same number, and `code` is uniquely indexed), so the candidate is probed
// and stepped until it is free. Disputes are low-volume, so the extra
// lookups cost nothing; the loop is bounded and falls back to an
// id-derived suffix, which cannot collide because ObjectIds do not.
disputeSchema.pre('validate', async function assignCode() {
  if (this.code) return;
  const Model = mongoose.model('Dispute');
  const base = 10000 + (await Model.estimatedDocumentCount()) + 1;
  for (let i = 0; i < 25; i += 1) {
    const candidate = `DSP-${base + i}`;
    const taken = await Model.exists({ code: candidate });
    if (!taken) {
      this.code = candidate;
      return;
    }
  }
  this.code = `DSP-${this._id.toString().slice(-6).toUpperCase()}`;
});

module.exports = mongoose.model('Dispute', disputeSchema);
