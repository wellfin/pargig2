const asyncHandler = require('express-async-handler');
const Notification = require('../models/notificationModel');

const myNotifications = asyncHandler(async (req, res) => {
  const list = await Notification.find({ user: req.user._id })
    .sort('-createdAt')
    .limit(parseInt(req.query.limit || '50'));
  res.json(list);
});

const markRead = asyncHandler(async (req, res) => {
  await Notification.updateMany(
    { user: req.user._id, _id: { $in: req.body.ids || [] } },
    { $set: { isRead: true } }
  );
  res.json({ ok: true });
});

const unreadCount = asyncHandler(async (req, res) => {
  const count = await Notification.countDocuments({ user: req.user._id, isRead: false });
  res.json({ count });
});

module.exports = { myNotifications, markRead, unreadCount };
