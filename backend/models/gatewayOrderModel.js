const mongoose = require('mongoose');

/**
 * An order we opened with the payment gateway, as we understood it.
 *
 * This exists so that confirming a payment never has to trust the
 * client for the one thing that matters. Before it, wallet top-ups
 * verified a signature and then credited whatever amount the request
 * body claimed — pay ₹1, say ₹10,000, and the wallet believed it. Now
 * the amount is read back from the order the server itself opened.
 *
 * It also gives webhooks something to land on: Razorpay tells us an
 * order was paid and nothing else, so the order has to remember what it
 * was for.
 */
const gatewayOrderSchema = new mongoose.Schema(
  {
    // The provider's order id ("order_xxx"), or the stand-in's.
    orderId: { type: String, required: true, unique: true, index: true },
    provider: { type: String, default: 'dummy' },
    // 'job' settles a completed job; 'wallet' tops up a balance.
    purpose: { type: String, enum: ['job', 'wallet'], required: true },
    // Rupees, as the server computed them. The only amount anything
    // downstream is allowed to believe.
    amount: { type: Number, required: true },
    currency: { type: String, default: 'INR' },
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    job: { type: mongoose.Schema.Types.ObjectId, ref: 'Job', index: true },
    status: {
      type: String,
      enum: ['created', 'paid', 'failed', 'expired'],
      default: 'created',
      index: true,
    },
    paymentId: String,
    signature: String,
    // Set the moment an order is settled, and checked before settling,
    // so a double-tap and a retried webhook racing each other cannot
    // both credit the same money.
    settledAt: Date,
    failureReason: String,
    notes: { type: mongoose.Schema.Types.Mixed },
  },
  { timestamps: true },
);

// Orders nobody ever paid are noise after a day. Mongo's TTL monitor
// removes them; paid ones are kept, since they are the audit trail.
gatewayOrderSchema.index(
  { createdAt: 1 },
  {
    expireAfterSeconds: 24 * 60 * 60,
    partialFilterExpression: { status: 'created' },
  },
);

module.exports = mongoose.model('GatewayOrder', gatewayOrderSchema);
