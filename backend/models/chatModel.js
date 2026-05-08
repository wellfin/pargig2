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
  job: { type: mongoose.Schema.Types.ObjectId, ref: 'Job', required: true, index: true },
  participants: [{ type: mongoose.Schema.Types.ObjectId, ref: 'User' }],
  messages: [messageSchema],
  lastMessageAt: { type: Date, default: Date.now }
}, { timestamps: true });

chatRoomSchema.index({ participants: 1, job: 1 }, { unique: true });

module.exports = mongoose.model('ChatRoom', chatRoomSchema);
