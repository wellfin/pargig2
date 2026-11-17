const mongoose = require('mongoose');

const messageSchema = new mongoose.Schema({
  // Exactly one of these is set. A support thread has the user on one
  // side and whichever admin picked it up on the other, and admins
  // live in their own collection — so the sender cannot always be a
  // User ref, and `required: true` on it would reject every reply the
  // support desk writes.
  sender: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required() {
      return !this.senderAdmin;
    }
  },
  // Set only on support replies. Populated for display so the person
  // sees a name rather than "Support" with nobody behind it.
  senderAdmin: { type: mongoose.Schema.Types.ObjectId, ref: 'Admin' },
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

  // 'direct'  — two users talking to each other (everything above).
  // 'support' — one user talking to the Pargig support desk. These
  //             rooms hold a SINGLE participant: the other side is the
  //             desk, which is not a User and is not stored here.
  //
  // The find-or-create in supportChatController keeps it to one
  // support room per user, so a person's history with us stays in one
  // thread instead of scattering across a new room per question.
  kind: {
    type: String,
    enum: ['direct', 'support'],
    default: 'direct',
    index: true
  },

  participants: [{ type: mongoose.Schema.Types.ObjectId, ref: 'User' }],
  messages: [messageSchema],
  lastMessageAt: { type: Date, default: Date.now },

  // Support rooms only.
  //
  // Unread-for-the-desk is a comparison of these two, rather than a
  // flag on each message: the desk is one shared inbox, so "has anyone
  // here read it yet" is a property of the thread. Walking every
  // message to count unread would also mean loading every message of
  // every thread just to badge the sidebar.
  lastUserMessageAt: { type: Date },
  supportReadAt: { type: Date }
}, { timestamps: true });

// The support queue reads newest-activity-first, every time.
chatRoomSchema.index({ kind: 1, lastMessageAt: -1 });

module.exports = mongoose.model('ChatRoom', chatRoomSchema);
