const mongoose = require('mongoose');

const notificationSchema = new mongoose.Schema({
  user: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  type: {
    type: String,
    enum: ['job_alert', 'chat', 'payment', 'job_status', 'dispute', 'system'],
    required: true
  },
  title: { type: String, required: true },
  body: String,
  data: mongoose.Schema.Types.Mixed,
  isRead: { type: Boolean, default: false }
}, { timestamps: true });

module.exports = mongoose.model('Notification', notificationSchema);
