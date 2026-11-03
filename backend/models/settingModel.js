const mongoose = require('mongoose');

/**
 * Operational settings an admin can change without a deploy.
 *
 * One document per `key`, with a free-form `value`. The payment gateway
 * credentials are the first and main occupant: Razorpay hands them over
 * after registration, and they have to be enterable from the admin panel
 * rather than shipped in a file, because the people who hold them are
 * not the people who deploy.
 *
 * Secrets inside `value` are stored encrypted — see utils/secretBox.js.
 * The schema does not try to enforce that; the settings controller is
 * the only writer and it encrypts before it gets here.
 */
const settingSchema = new mongoose.Schema(
  {
    key: { type: String, required: true, unique: true, index: true },
    value: { type: mongoose.Schema.Types.Mixed, default: {} },
    // Who last touched it. Payment credentials are the kind of thing
    // that needs an answer to "who changed this and when".
    updatedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'Admin' },
    updatedByName: String,
  },
  { timestamps: true },
);

/** The one settings key that exists today. */
settingSchema.statics.PAYMENT_GATEWAY = 'payment_gateway';

module.exports = mongoose.model('Setting', settingSchema);
