/**
 * End-to-end check of the dispute bell and the unread rows.
 *
 *   npm run check:unread
 *
 * Runs the real Express app against a THROWAWAY database and drops it
 * afterwards. It never touches the configured MONGO_URI.
 *
 * Two separate states are being tested, and the point of the check is
 * that they really are separate:
 *
 *   the BELL counts what arrived since this admin last opened the
 *   queue. Opening it takes the bell to zero even though every
 *   dispute is still open and still waiting.
 *
 *   a ROW is unread until this admin opens that particular dispute.
 *   Visiting the list does not clear it; pressing Review does.
 *
 * And both are per admin: one admin reading a dispute must not mark
 * it read for everyone else, which is the failure mode a single
 * boolean on the issue would have had.
 */
process.env.MONGO_URI =
  process.env.CHECK_MONGO_URI ||
  'mongodb://127.0.0.1:27017/pargig_unreadcheck_tmp';
process.env.JWT_SECRET = process.env.JWT_SECRET || 'testsecret';
process.env.NODE_ENV = 'test';

const http = require('http');

const Admin = require('../models/adminModel');
// The models' own Mongoose instance — see scripts/checkAdminReset.js.
const mongoose = Admin.base;
const app = require('../app');
const User = require('../models/userModel');
const Job = require('../models/jobModel');
const Issue = require('../models/issueModel');
const generateToken = require('../utils/generateToken');

const out = [];
const ck = (l, c, d) =>
  out.push((c ? '  + ' : '  - FAIL ') + l + (d !== undefined ? ' -> ' + d : ''));

function call(port, method, path, token) {
  return new Promise((resolve) => {
    const req = http.request(
      { port, path: '/api' + path, method, headers: { Authorization: `Bearer ${token}` } },
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

const PW = 'x'.repeat(12);

(async () => {
  await mongoose.connect(process.env.MONGO_URI);
  await mongoose.connection.dropDatabase();

  const boss = await Admin.create({
    name: 'Boss', email: 'boss@t.test', password: PW, role: 'superadmin',
  });
  const desk = await Admin.create({
    name: 'Desk', email: 'desk@t.test', password: PW, role: 'superadmin',
  });

  const giver = await User.create({ name: 'G', mobile: '9100000001', roles: ['jobgiver'] });
  const taker = await User.create({ name: 'T', mobile: '9100000002', roles: ['jobtaker'] });

  const mkIssue = async (n) => {
    const job = await Job.create({
      title: `Job ${n}`, category: 'Cleaning', description: 'd',
      jobgiver: giver._id, selectedJobtaker: taker._id, status: 'completed',
      finalPrice: 500,
      location: { type: 'Point', coordinates: [72.5, 23], address: 'a', city: 'c' },
    });
    return Issue.create({
      job: job._id, raisedBy: giver._id, raisedByRole: 'jobgiver',
      against: taker._id, issueType: 'service_quality',
      subIssues: ['Poor Quality Work'], description: `issue ${n}`, status: 'open',
    });
  };

  const i1 = await mkIssue(1);
  await mkIssue(2);
  await mkIssue(3);

  const server = http.createServer(app).listen(0);
  await new Promise((r) => server.on('listening', r));
  const port = server.address().port;
  const bTok = generateToken(boss._id, 'admin');
  const dTok = generateToken(desk._id, 'admin');

  // ------------------------------------------------------ 1. bell
  const dash1 = await call(port, 'GET', '/admin/dashboard', bTok);
  ck('1. three disputes are open', dash1.body.openIssues === 3, dash1.body.openIssues);
  ck('1. and all three are new to this admin', dash1.body.newIssues === 3,
    dash1.body.newIssues);

  const seen = await call(port, 'POST', '/admin/issues/seen', bTok);
  ck('1. the queue can be marked seen', seen.status === 200, seen.status);

  const dash2 = await call(port, 'GET', '/admin/dashboard', bTok);
  ck('1. the bell goes to zero after looking', dash2.body.newIssues === 0,
    dash2.body.newIssues);
  ck('1. while the open count is untouched — nothing was decided',
    dash2.body.openIssues === 3, dash2.body.openIssues);

  // The other admin has not looked, so their bell is unaffected.
  const deskDash = await call(port, 'GET', '/admin/dashboard', dTok);
  ck('1. one admin looking does not clear another admin’s bell',
    deskDash.body.newIssues === 3, deskDash.body.newIssues);

  // A dispute raised after the stamp rings again.
  await mkIssue(4);
  const dash3 = await call(port, 'GET', '/admin/dashboard', bTok);
  ck('1. a dispute raised AFTER looking rings the bell again',
    dash3.body.newIssues === 1, dash3.body.newIssues);

  // ------------------------------------------------- 2. unread rows
  const list1 = await call(port, 'GET', '/admin/issues', bTok);
  ck('2. four rows', list1.body.issues.length === 4, list1.body.issues.length);
  ck('2. every row is unread, even after marking the queue seen',
    list1.body.issues.every((i) => i.unread === true),
    list1.body.issues.map((i) => i.unread).join(','));
  ck('2. the list never discloses who else has read a row',
    list1.body.issues.every((i) => i.readBy === undefined));

  await call(port, 'GET', `/admin/issues/${i1._id}`, bTok);

  const list2 = await call(port, 'GET', '/admin/issues', bTok);
  const row1 = list2.body.issues.find((i) => String(i._id) === String(i1._id));
  ck('2. opening one marks that one read', row1.unread === false, row1.unread);
  ck('2. and leaves the other three alone',
    list2.body.issues.filter((i) => i.unread).length === 3,
    list2.body.issues.filter((i) => i.unread).length);

  const deskList = await call(port, 'GET', '/admin/issues', dTok);
  ck('2. read is per admin, not per issue',
    deskList.body.issues.every((i) => i.unread === true),
    deskList.body.issues.map((i) => i.unread).join(','));

  await call(port, 'GET', `/admin/issues/${i1._id}`, bTok);
  const fresh = await Issue.findById(i1._id).lean();
  ck('2. opening it twice does not add a second entry',
    fresh.readBy.length === 1, fresh.readBy.length);

  // Reading a row is not the same as deciding it.
  const stillOpen = await call(port, 'GET', '/admin/dashboard', bTok);
  ck('2. reading a dispute does not reduce the open count',
    stillOpen.body.openIssues === 4, stillOpen.body.openIssues);

  // ------------------------------------------------ 3. permissions
  const nobody = await Admin.create({
    name: 'Fin', email: 'fin@t.test', password: PW, role: 'finance',
  });
  const fTok = generateToken(nobody._id, 'admin');
  ck('3. marking seen needs the disputes permission -> 403',
    (await call(port, 'POST', '/admin/issues/seen', fTok)).status === 403);

  console.log(out.join('\n'));
  server.close();
  await mongoose.connection.dropDatabase();
  await mongoose.disconnect();
  const bad = out.filter((r) => r.includes('FAIL'));
  console.log(`\n${out.length - bad.length}/${out.length} passed`);
  console.log(bad.length ? 'RESULT: FAILURES' : 'RESULT: all good (temp db dropped)');
  process.exit(bad.length ? 1 : 0);
})().catch(async (e) => {
  console.error('ERROR', e);
  try { await mongoose.connection.dropDatabase(); await mongoose.disconnect(); } catch { /* down */ }
  process.exit(1);
});
