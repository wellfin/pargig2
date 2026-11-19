/**
 * End-to-end check of the dispute bell and the unread rows.
 *
 *   npm run check:unread
 *
 * Runs the real Express app against a THROWAWAY database and drops it
 * afterwards. It never touches the configured MONGO_URI.
 *
 * The thing being tested is that ONE definition drives both marks.
 * The bell and the dots count the same set: disputes this admin has
 * not opened that are still waiting on a decision. An earlier version
 * had the bell count "arrived since I last looked" while the dots
 * counted "never opened", which put three dotted rows under a bell
 * reading zero — and a screen where two marks disagree teaches people
 * to believe neither.
 *
 * Status is part of it so the count stays bounded. Without it, every
 * dispute ever filed is unread to a newly created admin, and a bell
 * showing two hundred on someone's first day is noise, not a queue.
 *
 * And it is per admin: one admin reading a dispute must not clear it
 * for everyone else, which is the failure a single flag on the issue
 * would have had.
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

function call(port, method, path, token, body) {
  return new Promise((resolve) => {
    const data = body === undefined ? null : JSON.stringify(body);
    const headers = {};
    if (token) headers.Authorization = `Bearer ${token}`;
    if (data) {
      headers['Content-Type'] = 'application/json';
      headers['Content-Length'] = Buffer.byteLength(data);
    }
    const req = http.request(
      { port, path: '/api' + path, method, headers },
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
    if (data) req.write(data);
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

  const mkIssue = async (n, status = 'open') => {
    const job = await Job.create({
      title: `Job ${n}`, category: 'Cleaning', description: 'd',
      jobgiver: giver._id, selectedJobtaker: taker._id, status: 'completed',
      finalPrice: 500,
      location: { type: 'Point', coordinates: [72.5, 23], address: 'a', city: 'c' },
    });
    return Issue.create({
      job: job._id, raisedBy: giver._id, raisedByRole: 'jobgiver',
      against: taker._id, issueType: 'service_quality',
      subIssues: ['Poor Quality Work'], description: `issue ${n}`, status,
    });
  };

  const i1 = await mkIssue(1);
  const i2 = await mkIssue(2);
  await mkIssue(3);
  const done = await mkIssue(4, 'resolved');

  const server = http.createServer(app).listen(0);
  await new Promise((r) => server.on('listening', r));
  const port = server.address().port;
  const bTok = generateToken(boss._id, 'admin');
  const dTok = generateToken(desk._id, 'admin');

  const bell = async (tok) =>
    (await call(port, 'GET', '/admin/dashboard', tok)).body.unreadIssues;
  const rows = async (tok) =>
    (await call(port, 'GET', '/admin/issues', tok)).body.issues;

  // ------------------------------------- 1. the two marks agree
  ck('1. four disputes exist, three of them open',
    (await call(port, 'GET', '/admin/dashboard', bTok)).body.openIssues === 3,
    (await call(port, 'GET', '/admin/dashboard', bTok)).body.openIssues);

  const r0 = await rows(bTok);
  ck('1. the bell counts three', (await bell(bTok)) === 3, await bell(bTok));
  ck('1. and the list dots exactly three',
    r0.filter((i) => i.unread).length === 3,
    r0.filter((i) => i.unread).length);
  ck('1. the resolved one is not dotted — nothing is waiting on it',
    r0.find((i) => String(i._id) === String(done._id)).unread === false);
  ck('1. the list never discloses who else has read a row',
    r0.every((i) => i.readBy === undefined));

  // --------------------------------- 2. reading one drops both
  await call(port, 'GET', `/admin/issues/${i1._id}`, bTok);
  const r1 = await rows(bTok);
  ck('2. that one loses its dot',
    r1.find((i) => String(i._id) === String(i1._id)).unread === false);
  ck('2. and the bell falls with it', (await bell(bTok)) === 2, await bell(bTok));
  ck('2. the two still agree',
    (await bell(bTok)) === r1.filter((i) => i.unread).length);

  await call(port, 'GET', `/admin/issues/${i2._id}`, bTok);
  ck('2. reading another drops it again', (await bell(bTok)) === 1, await bell(bTok));

  // Merely listing the queue must not clear anything: looking at a
  // row is not reading it.
  await rows(bTok);
  await rows(bTok);
  ck('2. listing the queue clears nothing', (await bell(bTok)) === 1, await bell(bTok));

  await call(port, 'GET', `/admin/issues/${i1._id}`, bTok);
  const fresh = await Issue.findById(i1._id).lean();
  ck('2. opening the same one twice does not add a second entry',
    fresh.readBy.length === 1, fresh.readBy.length);

  // ---------------------------------------- 3. per admin, not global
  ck('3. the other admin still has all three',
    (await bell(dTok)) === 3, await bell(dTok));
  const dRows = await rows(dTok);
  ck('3. and sees all three dotted',
    dRows.filter((i) => i.unread).length === 3,
    dRows.filter((i) => i.unread).length);

  // --------------------------------- 4. deciding one also clears it
  //
  // An unread dispute that somebody else resolves stops being work,
  // so it stops counting — without this the bell would hold a number
  // the admin can do nothing about.
  const beforeDecide = await bell(dTok);
  await call(port, 'PUT', `/admin/issues/${i1._id}`, bTok, {
    status: 'resolved', note: 'Refunded in full.',
  });
  ck('4. resolving a dispute the other admin never read drops their count',
    (await bell(dTok)) === beforeDecide - 1,
    `${beforeDecide} -> ${await bell(dTok)}`);
  const dRows2 = await rows(dTok);
  ck('4. and its dot goes with it',
    dRows2.find((i) => String(i._id) === String(i1._id)).unread === false);

  // --------------------------------------------- 5. a new one rings
  //
  // Asserted as a delta rather than a fixed number: whatever the
  // admin has left unread at this point, one more arriving must add
  // exactly one.
  const beforeNew = await bell(bTok);
  await mkIssue(5);
  ck('5. a newly raised dispute adds exactly one',
    (await bell(bTok)) === beforeNew + 1,
    `${beforeNew} -> ${await bell(bTok)}`);
  const r5 = await rows(bTok);
  ck('5. and the dots still match the bell',
    r5.filter((i) => i.unread).length === (await bell(bTok)),
    `${r5.filter((i) => i.unread).length} dots / ${await bell(bTok)} on the bell`);

  // ---------------------------------------------- 6. permissions
  const fin = await Admin.create({
    name: 'Fin', email: 'fin@t.test', password: PW, role: 'finance',
  });
  const fTok = generateToken(fin._id, 'admin');
  ck('6. a role without disputes cannot read the queue -> 403',
    (await call(port, 'GET', '/admin/issues', fTok)).status === 403);

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
