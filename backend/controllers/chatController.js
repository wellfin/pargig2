const asyncHandler = require('express-async-handler');
const ChatRoom = require('../models/chatModel');
const Job = require('../models/jobModel');
const { pushToUser } = require('../utils/notify');

const openOrGetRoom = asyncHandler(async (req, res) => {
  const { jobId } = req.params;
  const job = await Job.findById(jobId);
  if (!job) { res.status(404); throw new Error('Job not found'); }
  const giver = job.jobgiver.toString();
  const me = req.user._id.toString();
  // who is the counterparty?
  let other;
  if (me === giver) {
    other = req.body.jobtakerId || (job.selectedJobtaker && job.selectedJobtaker.toString());
    if (!other) { res.status(400); throw new Error('jobtakerId required'); }
  } else {
    other = giver;
  }
  let room = await ChatRoom.findOne({ job: jobId, participants: { $all: [me, other] } });
  if (!room) {
    room = await ChatRoom.create({ job: jobId, participants: [me, other], messages: [] });
  }
  res.json(room);
});

const sendMessage = asyncHandler(async (req, res) => {
  const { roomId } = req.params;
  const room = await ChatRoom.findById(roomId);
  if (!room) { res.status(404); throw new Error('Room not found'); }
  if (!room.participants.map(String).includes(req.user._id.toString())) {
    res.status(403); throw new Error('Not a participant');
  }
  const msg = {
    sender: req.user._id,
    body: req.body.body,
    attachmentUrl: req.body.attachmentUrl,
    type: req.body.type || 'text',
    proposedPrice: req.body.proposedPrice,
    readBy: [req.user._id]
  };
  room.messages.push(msg);
  room.lastMessageAt = new Date();
  await room.save();

  const fresh = room.messages[room.messages.length - 1];
  const io = global._io;
  if (io) io.to(`room:${room._id}`).emit('chat:message', { roomId: room._id, message: fresh });

  // notify the other side
  room.participants
    .map(String)
    .filter((p) => p !== req.user._id.toString())
    .forEach((p) =>
      pushToUser(p, {
        type: 'chat',
        title: 'New message',
        body: req.body.body || '[attachment]',
        data: { roomId: room._id, jobId: room.job }
      })
    );

  res.json(fresh);
});

const myRooms = asyncHandler(async (req, res) => {
  const rooms = await ChatRoom.find({ participants: req.user._id })
    .populate('participants', 'name photo')
    .populate('job', 'title status')
    .sort('-lastMessageAt');
  res.json(rooms);
});

const getRoom = asyncHandler(async (req, res) => {
  const room = await ChatRoom.findById(req.params.roomId)
    .populate('participants', 'name photo')
    .populate('job', 'title status');
  if (!room) { res.status(404); throw new Error('Room not found'); }
  if (!room.participants.map((p) => p._id.toString()).includes(req.user._id.toString())) {
    res.status(403); throw new Error('Not a participant');
  }
  res.json(room);
});

/**
 * Mobile calls this after writing a Firestore chat message so the recipient
 * gets an FCM push (works even when their app is closed). The backend never
 * sees the message body itself unless mobile sends it here for the
 * notification preview — which is fine; the source of truth stays in Firestore.
 */
const notifyChatMessage = asyncHandler(async (req, res) => {
  const { recipientUserId, jobTitle, body, roomId, jobId } = req.body;
  if (!recipientUserId) {
    res.status(400);
    throw new Error('recipientUserId required');
  }
  const senderName = req.user.name || 'Someone';
  const previewBody = (body && body.length > 80 ? `${body.slice(0, 80)}…` : body) || 'sent you a message';
  const title = jobTitle ? `${senderName} · ${jobTitle}` : senderName;

  const { pushToUser } = require('../utils/notify');
  const notif = await pushToUser(recipientUserId, {
    type: 'chat',
    title,
    body: previewBody,
    data: { roomId: roomId || '', jobId: jobId || '', senderId: req.user._id.toString() }
  });
  res.json({ ok: true, notificationId: notif._id });
});

module.exports = { openOrGetRoom, sendMessage, myRooms, getRoom, notifyChatMessage };
