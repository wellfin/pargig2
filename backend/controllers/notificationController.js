const asyncHandler = require('express-async-handler');
const Notification = require('../models/notificationModel');

const myNotifications = asyncHandler(async (req, res) => {
  const list = await Notification.find({ user: req.user._id })
    .sort('-createdAt')
    .limit(parseInt(req.query.limit || '50'));
  res.json(list);
});

// `{ all: true }` clears every unread notification for the caller, not
// just the ids passed. The list screen needs that: it only renders the
// most recent 50, so marking the fetched ids alone would leave older
// unread rows behind and the bell badge could never reach zero.
const markRead = asyncHandler(async (req, res) => {
  const filter = req.body.all === true
    ? { user: req.user._id, isRead: false }
    : { user: req.user._id, _id: { $in: req.body.ids || [] } };
  await Notification.updateMany(filter, { $set: { isRead: true } });
  res.json({ ok: true });
});

const unreadCount = asyncHandler(async (req, res) => {
  const count = await Notification.countDocuments({ user: req.user._id, isRead: false });
  res.json({ count });
});

module.exports = { myNotifications, markRead, unreadCount };
