const mongoose = require('mongoose');

const paymentSchema = new mongoose.Schema({
  job: { type: mongoose.Schema.Types.ObjectId, ref: 'Job', required: true, index: true },
  jobgiver: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  jobtaker: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
  amount: { type: Number, required: true },
  platformFee: { type: Number, default: 0 },
  tipAmount: { type: Number, default: 0 },
  payoutAmount: { type: Number, default: 0 },
  gateway: { type: String, enum: ['razorpay', 'stripe', 'wallet', 'manual'], default: 'razorpay' },
  gatewayOrderId: String,
  gatewayPaymentId: String,
  gatewaySignature: String,
  // How the jobgiver actually settled up, as picked on Select Payment
  // Method: a human label ("Cash on Delivery", "PhonePe", "HDFC Debit
  // Card ****9232"). isCod splits the receipt: cash settlements have no
  // transaction reference to show, online ones do.
  method: String,
  // Canonical mode behind that label: what the refund router switches on
  // and what reconciliation groups by. See utils/paymentMode.js.
  mode: {
    type: String,
    enum: ['upi', 'card', 'netbanking', 'wallet', 'cash', 'other'],
    default: 'other',
    index: true
  },
  isCod: { type: Boolean, default: false },
  transactionId: { type: String, index: true },
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
