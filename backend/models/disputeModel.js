const mongoose = require('mongoose');

const disputeSchema = new mongoose.Schema({
  job: { type: mongoose.Schema.Types.ObjectId, ref: 'Job', required: true, index: true },
  raisedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  against: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
  reason: { type: String, required: true },
  details: String,
  attachments: [String],
  status: {
    type: String,
    enum: ['open', 'under_review', 'resolved', 'rejected'],
    default: 'open'
  },
  resolution: {
    decidedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'Admin' },
    outcome: { type: String, enum: ['refund_giver', 'release_taker', 'split', 'no_action'] },
    note: String,
    decidedAt: Date
  }
}, { timestamps: true });

module.exports = mongoose.model('Dispute', disputeSchema);
