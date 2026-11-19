/**
 * End-to-end check of the support-desk list filters.
 *
 *   npm run check:support-search
 *
 * Runs the real Express app against a THROWAWAY database and drops it
 * afterwards. It never touches the configured MONGO_URI.
 *
 * The list is paged, so these filters have to run in the database
 * rather than over the rows already on screen — narrowing thirty
 * loaded rows would quietly fail to find the thirty-first, which is
 * exactly the moment somebody reaches for a search box. The
 * assertions below are therefore about rows the page would never have
 * had.
 */
process.env.MONGO_URI =
  process.env.CHECK_MONGO_URI ||
  'mongodb://127.0.0.1:27017/pargig_supportcheck_tmp';
process.env.JWT_SECRET = process.env.JWT_SECRET || 'testsecret';
process.env.NODE_ENV = 'test';

const http = require('http');

const Admin = require('../models/adminModel');
// The models' own Mongoose instance — see scripts/checkAdminReset.js.
const mongoose = Admin.base;
const app = require('../app');
const User = require('../models/userModel');
const ChatRoom = require('../models/chatModel');
const generateToken = require('../utils/generateToken');

const out = [];
const ck = (l, c, d) =>
  out.push((c ? '  + ' : '  - FAIL ') + l + (d !== undefined ? ' -> ' + d : ''));

function call(port, path, token) {
  return new Promise((resolve) => {
    const req = http.request(
      { port, path: '/api' + path, method: 'GET', headers: { Authorization: `Bearer ${token}` } },
      (res) => {
        let b = '';
        res.on('data', (c) => (b += c));
        res.on('end', () => {
          let j = {};
          try { j = JSON.parse(b || '{}'); } catch { j = { raw: b }; }
          resolve({ status: res.statusCode, body: j });
        });
      },
    );
    req.end();
  });
}

const ago = (d) => new Date(Date.now() - d * 24 * 60 * 60 * 1000);

(async () => {
  await mongoose.connect(process.env.MONGO_URI);
  await mongoose.connection.dropDatabase();

  const boss = await Admin.create({
    name: 'Boss', email: 'boss@t.test', password: 'x'.repeat(12), role: 'superadmin',
  });

  const mk = async (name, mobile, whenDays, body) => {
    const u = await User.create({ name, mobile, roles: ['jobgiver'] });
    const at = ago(whenDays);
    return ChatRoom.create({
      kind: 'support',
      participants: [u._id],
      messages: [{ sender: u._id, body, createdAt: at }],
      lastMessage: body,
      lastMessageAt: at,
      lastUserMessageAt: at,
    });
  };

  await mk('Rekha Sharma', '9300000001', 0, 'payment schedule?');
  await mk('saanvitha', '9300000002', 3, 'hello');
  await mk('Ravi Kumar', '9300000003', 20, 'old question');
  await mk('Rekha Verma', '9300000004', 200, 'very old');

  const server = http.createServer(app).listen(0);
  await new Promise((r) => server.on('listening', r));
  const port = server.address().port;
  const tok = generateToken(boss._id, 'admin');

  const list = async (qs) =>
    (await call(port, '/admin/support/chats' + qs, tok)).body;

  const all = await list('');
  ck('baseline: four conversations', all.chats.length === 4, all.chats.length);

  const byName = await list('?q=rekha');
  ck('by name, case insensitive, matches both Rekhas',
    byName.chats.length === 2, byName.chats.length);

  const byFull = await list('?q=' + encodeURIComponent('Rekha Sharma'));
  ck('a fuller name narrows it to one', byFull.chats.length === 1,
    byFull.chats.length);

  const byMobile = await list('?q=9300000002');
  ck('by mobile', byMobile.chats.length === 1 &&
    byMobile.chats[0].user?.name === 'saanvitha',
    byMobile.chats[0]?.user?.name);

  const noMatch = await list('?q=zzzznobody');
  ck('no match is empty, not everything', noMatch.chats.length === 0,
    noMatch.chats.length);

  const nasty = await call(port, '/admin/support/chats?q=' + encodeURIComponent('('), tok);
  ck('an unbalanced "(" is a clean 200, not a 500', nasty.status === 200,
    nasty.status);
  const wild = await list('?q=' + encodeURIComponent('.*'));
  ck('".*" is matched as text, not as a wildcard', wild.chats.length === 0,
    wild.chats.length);

  const today = await list('?days=1');
  ck('today only', today.chats.length === 1, today.chats.length);
  const week = await list('?days=7');
  ck('last 7 days', week.chats.length === 2, week.chats.length);
  const month = await list('?days=30');
  ck('last 30 days', month.chats.length === 3, month.chats.length);

  const both = await list('?q=rekha&days=30');
  ck('search and date range combine', both.chats.length === 1,
    both.chats.length);

  const bad = await list('?days=notanumber');
  ck('a nonsense range is ignored rather than emptying the list',
    bad.chats.length === 4, bad.chats.length);

  const unread = await list('?unread=1&q=rekha');
  ck('the unanswered filter still stacks with search',
    unread.chats.length === 2, unread.chats.length);

  console.log(out.join('\n'));
  server.close();
  await mongoose.connection.dropDatabase();
  await mongoose.disconnect();
  const fails = out.filter((r) => r.includes('FAIL'));
  console.log(`\n${out.length - fails.length}/${out.length} passed`);
  console.log(fails.length ? 'RESULT: FAILURES' : 'RESULT: all good (temp db dropped)');
  process.exit(fails.length ? 1 : 0);
})().catch(async (e) => {
  console.error('ERROR', e);
  try { await mongoose.connection.dropDatabase(); await mongoose.disconnect(); } catch { /* down */ }
  process.exit(1);
});
