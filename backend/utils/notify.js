const Notification = require('../models/notificationModel');
const { sendPushToUserId } = require('./firebaseAdmin');

const pushToUser = async (userId, payload) => {
  const notif = await Notification.create({
    user: userId,
    type: payload.type,
    title: payload.title,
    body: payload.body,
    data: payload.data || {}
  });
  const io = global._io;
  if (io) io.to(`user:${userId}`).emit('notification', notif);

  // Best-effort FCM push — won't fail the request if it errors
  try {
    await sendPushToUserId(userId, {
      title: payload.title,
      body: payload.body,
      data: { type: payload.type || 'system', ...(payload.data || {}) }
    });
  } catch (e) {
    console.warn('FCM push failed:', e.message);
  }
  return notif;
};

module.exports = { pushToUser };
