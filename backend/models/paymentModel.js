const mongoose = require('mongoose');

const paymentSchema = new mongoose.Schema({
  job: { type: mongoose.Schema.Types.ObjectId, ref: 'Job', required: true, index: true },
  jobgiver: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  jobtaker: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
  amount: { type: Number, required: true },
  platformFee: { type: Number, default: 0 },
  payoutAmount: { type: Number, default: 0 },
  gateway: { type: String, enum: ['razorpay', 'stripe', 'wallet', 'manual'], default: 'razorpay' },
  gatewayOrderId: String,
  gatewayPaymentId: String,
  gatewaySignature: String,
  status: {
    type: String,
    enum: ['initiated', 'paid', 'on_hold', 'released', 'refunded', 'failed'],
    default: 'initiated',
    index: true
  },
  heldAt: Date,
  releasedAt: Date,
  refundedAt: Date,
  refundReason: String
}, { timestamps: true });

module.exports = mongoose.model('Payment', paymentSchema);
