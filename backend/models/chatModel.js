const mongoose = require('mongoose');

const messageSchema = new mongoose.Schema({
  sender: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  body: String,
  attachmentUrl: String,
  type: { type: String, enum: ['text', 'image', 'price_proposal', 'system'], default: 'text' },
  proposedPrice: Number,
  readBy: [{ type: mongoose.Schema.Types.ObjectId, ref: 'User' }],
  createdAt: { type: Date, default: Date.now }
}, { _id: true });

const chatRoomSchema = new mongoose.Schema({
  // job-scoped rooms still link back; 1:1 "direct" rooms (opened from
  // the applicants screen / nearby-workers / posted-jobs in-progress
  // card) leave this null. App-level uniqueness is enforced by the
  // findOne-before-create in chatController.openOrGetRoom and
  // chatController.openOrGetDirect — no DB unique index is needed,
  // and we explicitly avoid one because a compound unique on
  // (participants, job) blows up when job is null and the same user
  // appears in multiple direct rooms (the multi-key index entry
  // (userId, null) duplicates across pairs).
  job: { type: mongoose.Schema.Types.ObjectId, ref: 'Job', index: true },
  participants: [{ type: mongoose.Schema.Types.ObjectId, ref: 'User' }],
  messages: [messageSchema],
  lastMessageAt: { type: Date, default: Date.now }
}, { timestamps: true });

module.exports = mongoose.model('ChatRoom', chatRoomSchema);
