/**
 * End-to-end check of the payment ledger search.
 *
 *   npm run check:payment-search
 *
 * Runs the real Express app against a THROWAWAY database and drops it
 * afterwards. It never touches the configured MONGO_URI.
 *
 * Worth its own check for two reasons. Most of what the box searches
 * is not stored on the payment at all — the job title and both
 * parties live in other collections, so the terms are resolved to ids
 * first, and a mistake there returns the WRONG money rather than no
 * money. And the box takes whatever is typed: the last three
 * assertions are about a regex metacharacter being treated as text,
 * which it was not before this.
 */
process.env.MONGO_URI =
  process.env.CHECK_MONGO_URI ||
  'mongodb://127.0.0.1:27017/pargig_paysearch_tmp';
process.env.JWT_SECRET = process.env.JWT_SECRET || 'testsecret';
process.env.NODE_ENV = 'test';

const http = require('http');

const Admin = require('../models/adminModel');
// The models' own Mongoose instance — see scripts/checkAdminReset.js.
const mongoose = Admin.base;
const app = require('../app');
const User = require('../models/userModel');
const Job = require('../models/jobModel');
const Payment = require('../models/paymentModel');
const generateToken = require('../utils/generateToken');

const out = [];
const ck = (l, c, d) =>
  out.push((c ? '  + ' : '  - FAIL ') + l + (d !== undefined ? ' -> ' + d : ''));

function call(port, p, token) {
  return new Promise((resolve) => {
    const r = http.request(
      { port, path: '/api' + p, method: 'GET', headers: { Authorization: `Bearer ${token}` } },
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
    r.end();
  });
}

(async () => {
  await mongoose.connect(process.env.MONGO_URI);
  await mongoose.connection.dropDatabase();

  const admin = await Admin.create({
    name: 'A', email: 'a@t.test', password: 'x'.repeat(12), role: 'superadmin',
  });
  const jyothish = await User.create({ name: 'jyothish', mobile: '9000000011', roles: ['jobgiver'] });
  const edu = await User.create({ name: 'Edukondalu', mobile: '9000000022', roles: ['jobtaker'] });
  const suresh = await User.create({ name: 'suresh Reddy', mobile: '9000000033', roles: ['jobgiver'] });

  const mk = (title, giver, taker) =>
    Job.create({
      title, category: 'Cleaning', description: 'd', jobgiver: giver._id,
      selectedJobtaker: taker._id, status: 'completed', finalPrice: 600,
      location: { type: 'Point', coordinates: [79.4, 13.6], address: 'x', city: 'Tirupati' },
    });

  const j1 = await mk('Documents collection', jyothish, edu);
  const j2 = await mk('pet walking', suresh, edu);
  const j3 = await mk('Home cleaning', jyothish, suresh);

  await Payment.create({
    job: j1._id, jobgiver: jyothish._id, jobtaker: edu._id,
    amount: 600, platformFee: 30, status: 'released', isCod: true,
  });
  await Payment.create({
    job: j2._id, jobgiver: suresh._id, jobtaker: edu._id,
    amount: 600, platformFee: 25, status: 'released',
    transactionId: 'pay_952VYMNUABCD',
  });
  await Payment.create({
    job: j3._id, jobgiver: jyothish._id, jobtaker: suresh._id,
    amount: 600, platformFee: 25, status: 'refunded',
    transactionId: 'pay_QZEKP6D3XYZ',
  });

  const server = http.createServer(app).listen(0);
  await new Promise((r) => server.on('listening', r));
  const port = server.address().port;
  const tok = generateToken(admin._id, 'admin');

  const all = await call(port, '/admin/payments', tok);
  ck('baseline: three payments', all.body.total === 3, all.body.total);

  const byJob = await call(port, '/admin/payments?q=pet', tok);
  ck('by job title', byJob.body.total === 1 && byJob.body.payments[0].job.title === 'pet walking',
    `${byJob.body.total} / ${byJob.body.payments[0]?.job?.title}`);

  const byGiver = await call(port, '/admin/payments?q=jyothish', tok);
  ck('by giver name -> both their payments', byGiver.body.total === 2, byGiver.body.total);

  const byTaker = await call(port, '/admin/payments?q=Edukondalu', tok);
  ck('by taker name', byTaker.body.total === 2, byTaker.body.total);

  const bothSides = await call(port, '/admin/payments?q=suresh', tok);
  // suresh is the GIVER on j2 and the TAKER on j3, so one search term
  // has to match two different fields on two different rows.
  ck('a name matches whichever side it is on', bothSides.body.total === 2,
    bothSides.body.total);

  const byMobile = await call(port, '/admin/payments?q=9000000022', tok);
  ck('by mobile', byMobile.body.total === 2, byMobile.body.total);

  const byTxn = await call(port, '/admin/payments?q=952VYMNU', tok);
  ck('by transaction id fragment', byTxn.body.total === 1, byTxn.body.total);

  const caseless = await call(port, '/admin/payments?q=DOCUMENTS', tok);
  ck('case insensitive', caseless.body.total === 1, caseless.body.total);

  const withStatus = await call(port, '/admin/payments?q=jyothish&status=refunded', tok);
  ck('search AND status combine', withStatus.body.total === 1, withStatus.body.total);

  const none = await call(port, '/admin/payments?q=zzzznothing', tok);
  ck('no match -> empty, not everything', none.body.total === 0, none.body.total);

  // The reason escapeRegex matters.
  const nasty = await call(port, '/admin/payments?q=' + encodeURIComponent('('), tok);
  ck('an unbalanced "(" is a clean 200, not a 500', nasty.status === 200, nasty.status);
  const nasty2 = await call(port, '/admin/payments?q=' + encodeURIComponent('.*'), tok);
  ck('".*" is treated as text, not as a wildcard', nasty2.body.total === 0, nasty2.body.total);

  const users = await call(port, '/admin/users?q=' + encodeURIComponent('('), tok);
  ck('and the users search survives it too -> 200', users.status === 200, users.status);

  console.log(out.join('\n'));
  server.close();
  await mongoose.connection.dropDatabase();
  await mongoose.disconnect();
  const bad = out.filter((r) => r.includes('FAIL'));
  console.log(`\n${out.length - bad.length}/${out.length} passed`);
  process.exit(bad.length ? 1 : 0);
})().catch(async (e) => {
  console.error('ERROR', e);
  try { await mongoose.connection.dropDatabase(); await mongoose.disconnect(); } catch { /* down */ }
  process.exit(1);
});
