const asyncHandler = require('express-async-handler');
const ChatRoom = require('../models/chatModel');
const Job = require('../models/jobModel');
const { pushToUser } = require('../utils/notify');

// Find-or-create a 1:1 direct chat room between the current user and
// :userId (no job context). Used by the mobile Chat screen when it's
// opened from places like the applicants screen, nearby-workers, or
// My Posted Jobs — those entry points have a partner userId but no
// canonical Job to bind the conversation to.
const openOrGetDirect = asyncHandler(async (req, res) => {
  const other = req.params.userId;
  const me = req.user._id.toString();
  if (!other || other === me) {
    res.status(400); throw new Error('Invalid userId');
  }
  // $size+all together pin the room to exactly these two participants
  // and only matches rooms with no job field (direct rooms).
  let room = await ChatRoom.findOne({
    job: { $exists: false },
    participants: { $all: [me, other], $size: 2 },
  });
  if (!room) {
    room = await ChatRoom.create({
      participants: [me, other],
      messages: [],
    });
  }
  const populated = await ChatRoom.findById(room._id)
    .populate('participants', 'name photo');
  res.json(populated);
});

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

// Tally of messages addressed to the caller that they haven't read
// yet. Powers the small red dot on the mobile bottom-nav Messages
// icon. A message counts as "unread" when:
//   1. sender !== caller (own messages are always "read")
//   2. caller is not in message.readBy
// We cap the iteration at the most recent 50 messages per room so a
// noisy room can't push the response time up — the dot just signals
// "you have unread"; the actual list reads from /chat/rooms.
const unreadCount = asyncHandler(async (req, res) => {
  const me = req.user._id.toString();
  const rooms = await ChatRoom.find({ participants: req.user._id })
    .select('messages participants')
    .lean();
  let count = 0;
  const roomsWithUnread = [];
  // Set of partner userIds (as strings) that have at least one
  // unread message to the caller. Used by the mobile badging on
  // per-partner chat icons (in-progress card / nearby workers /
  // applicants screen) so each icon can light up independently.
  const partnerIds = new Set();
  for (const room of rooms) {
    let roomUnread = 0;
    const recent = (room.messages || []).slice(-50);
    for (const m of recent) {
      if (!m || !m.sender) continue;
      if (m.sender.toString() === me) continue;
      const readBy = Array.isArray(m.readBy) ? m.readBy.map(String) : [];
      if (!readBy.includes(me)) roomUnread += 1;
    }
    if (roomUnread > 0) {
      count += roomUnread;
      const partner = (room.participants || [])
        .map(String)
        .find((p) => p !== me);
      if (partner) partnerIds.add(partner);
      roomsWithUnread.push({
        roomId: room._id,
        partnerId: partner || null,
        unread: roomUnread,
      });
    }
  }
  res.json({
    count,
    partnerIds: Array.from(partnerIds),
    rooms: roomsWithUnread,
  });
});

const myRooms = asyncHandler(async (req, res) => {
  const rooms = await ChatRoom.find({ participants: req.user._id })
    .populate('participants', 'name photo')
    .populate('job', 'title status')
    .sort('-lastMessageAt')
    .lean();
  const me = req.user._id.toString();
  // Flatten each room into the shape the mobile Messages screen
  // actually renders — partner (the other participant), last message
  // preview, lastMessageAt, and unread count for the caller. Rooms
  // with no messages are kept (so freshly-opened-but-empty chats
  // still appear) but get an empty lastMessage.
  const out = rooms.map((room) => {
    const partner = (room.participants || []).find(
      (p) => p && p._id && p._id.toString() !== me
    );
    let unread = 0;
    let lastBody = '';
    let lastAt = room.lastMessageAt;
    if (Array.isArray(room.messages) && room.messages.length > 0) {
      const recent = room.messages.slice(-50);
      for (const m of recent) {
        if (!m || !m.sender) continue;
        if (m.sender.toString() === me) continue;
        const readBy = Array.isArray(m.readBy) ? m.readBy.map(String) : [];
        if (!readBy.includes(me)) unread += 1;
      }
      const last = room.messages[room.messages.length - 1];
      lastBody = (last && (last.body || '')) || '';
      lastAt = (last && last.createdAt) || room.lastMessageAt;
    }
    return {
      _id: room._id,
      job: room.job || null,
      partner: partner || null,
      lastMessage: lastBody,
      lastMessageAt: lastAt,
      unread,
    };
  });
  res.json(out);
});

const getRoom = asyncHandler(async (req, res) => {
  const room = await ChatRoom.findById(req.params.roomId)
    .populate('participants', 'name photo')
    .populate('job', 'title status');
  if (!room) { res.status(404); throw new Error('Room not found'); }
  if (!room.participants.map((p) => p._id.toString()).includes(req.user._id.toString())) {
    res.status(403); throw new Error('Not a participant');
  }
  // Mark messages from the OTHER side as read for the caller. Own
  // messages are already in their own readBy from sendMessage(). This
  // is what clears the bottom-nav red dot once the user opens the
  // chat — otherwise polling would re-fetch the same unread messages
  // forever.
  const me = req.user._id.toString();
  let touched = false;
  for (const m of room.messages) {
    if (!m.sender) continue;
    if (m.sender.toString() === me) continue;
    const readBy = (m.readBy || []).map(String);
    if (!readBy.includes(me)) {
      m.readBy.push(req.user._id);
      touched = true;
    }
  }
  if (touched) await room.save();
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

module.exports = {
  openOrGetRoom,
  openOrGetDirect,
  sendMessage,
  myRooms,
  getRoom,
  notifyChatMessage,
  unreadCount,
};
