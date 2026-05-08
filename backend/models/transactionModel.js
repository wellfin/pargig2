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
  note: String
}, { timestamps: true });

module.exports = mongoose.model('Transaction', transactionSchema);
