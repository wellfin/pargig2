const asyncHandler = require('express-async-handler');
const User = require('../models/userModel');

/** The search box takes whatever is typed; '(' is not an empty result,
 *  it is an invalid regular expression and a 500. */
const escapeRegex = (v) => String(v).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const ChatRoom = require('../models/chatModel');
const { pushToUser } = require('../utils/notify');

/**
 * Live chat between one user and the Pargig support desk.
 *
 * Deliberately NOT the Issue model. An issue is raised against a job
 * and carries that job, the other party and the money with it — which
 * is the right shape for a dispute and the wrong shape for "how do I
 * change my number". Those questions have no job to attach to, and
 * forcing one made the Help Center's Chat tile send people to a list
 * of jobs and hope they picked the right one.
 *
 * It reuses ChatRoom rather than a new collection because a support
 * thread IS a conversation: same messages, same read tracking, same
 * socket room, same unread badge the user already understands. The
 * only structural difference is that one side is an admin, which the
 * model handles with senderAdmin.
 *
 * What this is not: it is not staffed. Nothing here promises a reply
 * time, and nothing pages anybody. The admin panel shows the queue and
 * a human has to open it. The app's copy says exactly that.
 */

const MAX_BODY = 2000;

/** The caller's single support thread, created on first use. */
const openSupport = asyncHandler(async (req, res) => {
  const me = req.user._id;

  // One thread per person, forever. A new room per question would
  // scatter their history across rows the desk has to piece together,
  // and would lose the context of what we already told them.
  let room = await ChatRoom.findOne({ kind: 'support', participants: me });
  if (!room) {
    room = await ChatRoom.create({
      kind: 'support',
      participants: [me],
      messages: [],
    });
  }

  // Opening the thread marks the desk's replies as read for the user,
  // the same way GET /chat/rooms/:id does — otherwise the unread dot
  // would survive the user reading the answer.
  let touched = false;
  for (const m of room.messages) {
    if (m.sender && m.sender.toString() === me.toString()) continue;
    const readBy = (m.readBy || []).map(String);
    if (!readBy.includes(me.toString())) {
      m.readBy.push(me);
      touched = true;
    }
  }
  if (touched) await room.save();

  const populated = await ChatRoom.findById(room._id)
    .populate('messages.senderAdmin', 'name');
  res.json(populated);
});

// ------------------------------------------------------------ admin

/**
 * The support queue.
 *
 * Ordered by most recent activity, not by longest wait — the opposite
 * of the verification queue, and for a reason: a chat is a live
 * conversation. Someone typing right now is still at their phone and
 * can be helped in one exchange; a thread from last Tuesday is a
 * follow-up either way. Unanswered threads are counted separately and
 * badged, so newest-first does not let them disappear.
 */
const listSupportChats = asyncHandler(async (req, res) => {
  const page = Math.max(1, parseInt(req.query.page, 10) || 1);
  const limit = Math.min(100, Math.max(1, parseInt(req.query.limit, 10) || 30));

  const filter = { kind: 'support' };
  // ?unread=1 — only threads the desk has not answered since the
  // person last wrote.
  if (req.query.unread === '1') {
    filter.$expr = { $gt: ['$lastUserMessageAt', '$supportReadAt'] };
  }

  // ?q= — by the person's name or number.
  //
  // Done here rather than in the panel because this list is paged:
  // filtering the thirty rows already on screen would quietly fail to
  // find anybody who is thirty-first, which is exactly when somebody
  // reaches for a search box.
  //
  // The name lives on the User, so the term is resolved to ids first
  // and matched with $in. An empty match must still produce an empty
  // result, so the $in is set unconditionally.
  const term = String(req.query.q || '').trim();
  if (term) {
    const rx = { $regex: escapeRegex(term), $options: 'i' };
    const people = await User.find({ $or: [{ name: rx }, { mobile: rx }] })
      .select('_id')
      .lean();
    filter.participants = { $in: people.map((u) => u._id) };
  }

  // ?days= — threads with activity in the last N days. Counted from
  // lastMessageAt, so a long-running conversation stays in "today"
  // for as long as it is still going.
  const days = parseInt(req.query.days, 10);
  if (Number.isFinite(days) && days > 0) {
    filter.lastMessageAt = {
      $gte: new Date(Date.now() - days * 24 * 60 * 60 * 1000),
    };
  }

  const [rooms, total] = await Promise.all([
    ChatRoom.find(filter)
      .populate('participants', 'name photo mobile isBlocked')
      .sort('-lastMessageAt')
      .skip((page - 1) * limit)
      .limit(limit)
      .lean(),
    ChatRoom.countDocuments(filter),
  ]);

  const out = rooms.map((room) => {
    const msgs = Array.isArray(room.messages) ? room.messages : [];
    const last = msgs[msgs.length - 1] || null;
    const readAt = room.supportReadAt ? new Date(room.supportReadAt) : null;
    // Unread for the desk: written by the person, after the last time
    // anyone here opened the thread.
    const unread = msgs.filter(
      (m) => m && m.sender && (!readAt || new Date(m.createdAt) > readAt),
    ).length;
    return {
      _id: room._id,
      user: room.participants?.[0] || null,
      lastMessage: (last && last.body) || '',
      lastFromUser: !!(last && last.sender),
      lastMessageAt: last?.createdAt || room.lastMessageAt,
      messageCount: msgs.length,
      unread,
    };
  });

  res.json({ chats: out, total });
});

/** One thread, in full. Opening it is what marks it answered-for-now. */
const getSupportChat = asyncHandler(async (req, res) => {
  const room = await ChatRoom.findById(req.params.roomId);
  if (!room || room.kind !== 'support') {
    res.status(404);
    throw new Error('Support chat not found');
  }

  // Reading clears the badge. This is honest only because the panel
  // opens a thread when an admin clicks it, never in the background.
  room.supportReadAt = new Date();
  await room.save();

  const populated = await ChatRoom.findById(room._id)
    .populate('participants', 'name photo mobile isBlocked createdAt')
    .populate('messages.senderAdmin', 'name role')
    .lean();
  res.json(populated);
});

/** A reply from the desk. */
const replySupportChat = asyncHandler(async (req, res) => {
  const body = (req.body.body || '').toString().trim();
  if (!body) {
    res.status(400);
    throw new Error('Message is empty');
  }
  if (body.length > MAX_BODY) {
    res.status(400);
    throw new Error(`Message is too long (max ${MAX_BODY} characters)`);
  }

  const room = await ChatRoom.findById(req.params.roomId);
  if (!room || room.kind !== 'support') {
    res.status(404);
    throw new Error('Support chat not found');
  }

  room.messages.push({
    senderAdmin: req.admin._id,
    body,
    type: 'text',
    readBy: [],
  });
  room.lastMessageAt = new Date();
  room.supportReadAt = room.lastMessageAt;
  await room.save();

  const fresh = room.messages[room.messages.length - 1];

  const io = global._io;
  if (io) {
    io.to(`room:${room._id}`).emit('chat:message', {
      roomId: room._id,
      message: fresh,
    });
  }

  // The person is almost certainly not holding the app open waiting,
  // so the push is the only thing that brings them back to the answer.
  const userId = room.participants?.[0];
  if (userId) {
    await pushToUser(userId.toString(), {
      type: 'chat',
      title: 'Pargig Support',
      body: body.length > 80 ? `${body.slice(0, 80)}…` : body,
      data: { roomId: room._id.toString(), support: '1' },
    });
  }

  const populated = await ChatRoom.findById(room._id)
    .populate('messages.senderAdmin', 'name role')
    .lean();
  const out = populated.messages[populated.messages.length - 1];
  res.json(out);
});

module.exports = {
  openSupport,
  listSupportChats,
  getSupportChat,
  replySupportChat,
};
