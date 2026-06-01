const mongoose = require('mongoose');

const ratingSchema = new mongoose.Schema({
  job: { type: mongoose.Schema.Types.ObjectId, ref: 'Job', required: true },
  rater: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  ratee: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  stars: { type: Number, min: 1, max: 5, required: true },
  review: String,
  tags: [String]
}, { timestamps: true });

ratingSchema.index({ job: 1, rater: 1 }, { unique: true });

module.exports = mongoose.model('Rating', ratingSchema);
