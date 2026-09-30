const mongoose = require('mongoose');

const transactionSchema = new mongoose.Schema({
  user: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  type: {
    type: String,
    enum: ['wallet_topup', 'wallet_deduct', 'payment', 'payout', 'refund', 'fee'],
    required: true
  },
  amount: { type: Number, required: true },
  balanceAfter: Number,
  reference: { type: mongoose.Schema.Types.ObjectId },
  referenceModel: { type: String, enum: ['Job', 'Payment'] },
  note: String,
  // A payout the worker received in cash, hand to hand. Kept as a
  // 'payout' so earnings totals still count it, but it never touched the
  // wallet balance — the worker already has the money. The app uses this
  // to show "Cash received" instead of a wallet credit.
  isCash: { type: Boolean, default: false }
}, { timestamps: true });

module.exports = mongoose.model('Transaction', transactionSchema);
