/**
 * End-to-end check of the Need Help issue module.
 *
 *   npm run check:issues
 *
 * Runs the real Express app against a THROWAWAY database and drops it
 * afterwards. It never touches the configured MONGO_URI.
 */
process.env.MONGO_URI =
  process.env.CHECK_MONGO_URI ||
  'mongodb://127.0.0.1:27017/pargig_issuecheck_tmp';
process.env.JWT_SECRET = process.env.JWT_SECRET || 'testsecret';
process.env.NODE_ENV = 'test';

const mongoose = require('mongoose');
const http = require('http');
const app = require('../app');
const User = require('../models/userModel');
const Admin = require('../models/adminModel');
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
    const req = http.request({ port, path: '/api' + path, method, headers }, (res) => {
      let b = '';
      res.on('data', (c) => (b += c));
      res.on('end', () => {
        let p = {};
        try { p = JSON.parse(b || '{}'); } catch { p = { raw: b }; }
        resolve({ status: res.statusCode, body: p });
      });
    });
    if (data) req.write(data);
    req.end();
  });
}

(async () => {
  await mongoose.connect(process.env.MONGO_URI);
  await mongoose.connection.dropDatabase();

  const giver = await User.create({ name: 'Rohan', mobile: '9500000001', roles: ['jobgiver'] });
  const other = await User.create({ name: 'Someone', mobile: '9500000003', roles: ['jobgiver'] });
  const worker = await User.create({
    name: 'Rahul Sharma', mobile: '9500000002', roles: ['jobtaker'],
    rating: { average: 4.9, count: 20 }, jobsCompleted: 142,
  });
  const admin = await Admin.create({ name: 'Admin', email: 'a@pargig.test', password: 'x'.repeat(12) });

  const mkJob = (title, status = 'completed') => Job.create({
    title, category: 'Cleaning', description: 'Deep clean the flat',
    jobgiver: giver._id, selectedJobtaker: worker._id, status,
    finalPrice: 850, location: { type: 'Point', coordinates: [72.5, 23.0], address: 'B-14, Satellite Road', city: 'Ahmedabad' },
  });

  const done = await mkJob('Home Deep Cleaning');
  const done2 = await mkJob('AC Repair & Service');
  const open = await mkJob('Not finished yet', 'open');

  const server = http.createServer(app).listen(0);
  await new Promise((r) => server.on('listening', r));
  const port = server.address().port;
  const gTok = generateToken(giver._id, 'user');
  const oTok = generateToken(other._id, 'user');
  const aTok = generateToken(admin._id, 'admin');

  // ------------------------------------------------------ 1. catalog
  const cat = await call(port, 'GET', '/issues/catalog');
  ck('1. catalog served', cat.status === 200, cat.status);
  ck('1. six issue types for a giver', cat.body.types?.length === 6, cat.body.types?.length);
  ck('1. service_quality sub-issues match the design',
    JSON.stringify(cat.body.subIssues?.service_quality) ===
      JSON.stringify(['Work Not Completed', 'Poor Quality Work', 'Property Damage']),
    JSON.stringify(cat.body.subIssues?.service_quality));

  const takerCat = await call(port, 'GET', '/issues/catalog?role=jobtaker');
  ck('1. seven issue types for a taker', takerCat.body.types?.length === 7,
    takerCat.body.types?.length);
  ck('1. the two catalogues share only "other"',
    cat.body.types.filter((t) => takerCat.body.types.includes(t)).join(',') === 'other',
    cat.body.types.filter((t) => takerCat.body.types.includes(t)).join(','));
  ck('1. taker sub-issues served',
    JSON.stringify(takerCat.body.subIssues?.payment_not_received) ===
      JSON.stringify(['Not Paid At All', 'Paid Less Than Agreed', 'Payment Still Pending']),
    JSON.stringify(takerCat.body.subIssues?.payment_not_received));

  // -------------------------------------------------- 2. job history
  const hist = await call(port, 'GET', '/issues/job-history', gTok);
  ck('2. job history served', hist.status === 200, hist.status);
  ck('2. completed jobs only', hist.body.jobs.length === 2, hist.body.jobs.length);
  ck('2. worker details joined for the card',
    hist.body.jobs[0].selectedJobtaker?.name === 'Rahul Sharma' &&
      hist.body.jobs[0].selectedJobtaker?.jobsCompleted === 142);
  ck('2. no issue attached yet', hist.body.jobs.every((j) => j.issue === null));
  ck('2. another user sees none of it',
    (await call(port, 'GET', '/issues/job-history', oTok)).body.jobs.length === 0);

  // ------------------------------------------------ 3. raising works
  const made = await call(port, 'POST', '/issues', gTok, {
    jobId: done._id,
    issueType: 'service_quality',
    subIssues: ['Poor Quality Work'],
    description: 'q3wertynmksacnmskn',
    photos: ['https://x/1.jpg', 'https://x/2.jpg'],
  });
  ck('3. issue created', made.status === 201, made.status + ' ' + (made.body.message || ''));
  ck('3. reference code assigned', /^ISS-\d+$/.test(made.body.code || ''), made.body.code);
  ck('3. sub-issue kept', JSON.stringify(made.body.subIssues) === '["Poor Quality Work"]');
  ck('3. photos kept', made.body.photos?.length === 2, made.body.photos?.length);
  ck('3. filed against the worker', String(made.body.against) === String(worker._id));
  ck('3. starts open', made.body.status === 'open', made.body.status);

  const hist2 = await call(port, 'GET', '/issues/job-history', gTok);
  const row = hist2.body.jobs.find((j) => j._id === String(done._id));
  ck('3. history now marks that job as reported',
    row.issue?.code === made.body.code && row.issue?.status === 'open', JSON.stringify(row.issue));

  // ------------------------------------------------- 4. the guards
  const dup = await call(port, 'POST', '/issues', gTok, {
    jobId: done._id, issueType: 'payment', description: 'again and again',
  });
  ck('4. second open issue on the same job refused', dup.status === 409, dup.status);

  const short = await call(port, 'POST', '/issues', gTok, {
    jobId: done2._id, issueType: 'other', description: 'too short',
  });
  ck('4. under 10 characters refused', short.status === 400, short.status);
  ck('4. and says why', /10 characters/i.test(short.body.message || ''), short.body.message);

  const long = await call(port, 'POST', '/issues', gTok, {
    jobId: done2._id, issueType: 'other', description: 'x'.repeat(501),
  });
  ck('4. over 500 characters refused', long.status === 400, long.status);

  const badType = await call(port, 'POST', '/issues', gTok, {
    jobId: done2._id, issueType: 'nonsense', description: 'a valid description',
  });
  ck('4. unknown issue type refused', badType.status === 400, badType.status);

  const notDone = await call(port, 'POST', '/issues', gTok, {
    jobId: open._id, issueType: 'other', description: 'a valid description',
  });
  ck('4. issue on an unfinished job refused', notDone.status === 400, notDone.status);

  const notMine = await call(port, 'POST', '/issues', oTok, {
    jobId: done2._id, issueType: 'other', description: 'a valid description',
  });
  ck("4. issue on someone else's job refused", notMine.status === 403, notMine.status);

  const strayed = await call(port, 'POST', '/issues', gTok, {
    jobId: done2._id, issueType: 'payment',
    subIssues: ['Poor Quality Work', 'Overcharged'], description: 'wrong amount charged',
  });
  ck('4. sub-issues from another type are dropped',
    JSON.stringify(strayed.body.subIssues) === '["Overcharged"]',
    JSON.stringify(strayed.body.subIssues));

  // ------------------------------------------------- 5. reading back
  const mine = await call(port, 'GET', '/issues/me', gTok);
  ck('5. my issues lists both', mine.body.issues?.length === 2, mine.body.issues?.length);
  const one = await call(port, 'GET', `/issues/${made.body._id}`, gTok);
  ck('5. single issue readable', one.status === 200, one.status);
  ck('5. job joined for display', one.body.job?.title === 'Home Deep Cleaning');
  const peek = await call(port, 'GET', `/issues/${made.body._id}`, oTok);
  ck("5. someone else cannot read it", peek.status === 403, peek.status);

  // ----------------------------------------------------- 6. admin
  const list = await call(port, 'GET', '/admin/issues', aTok);
  ck('6. admin list works', list.status === 200, list.status);
  ck('6. both issues listed', list.body.total === 2, list.body.total);
  ck('6. raiser and worker joined',
    list.body.issues[0].raisedBy?.name === 'Rohan' &&
      list.body.issues[0].against?.name === 'Rahul Sharma');
  const filtered = await call(port, 'GET', '/admin/issues?issueType=payment', aTok);
  ck('6. filter by type works', filtered.body.total === 1, filtered.body.total);
  const byStatus = await call(port, 'GET', '/admin/issues?status=open,under_review', aTok);
  ck('6. comma-separated status filter works', byStatus.body.total === 2, byStatus.body.total);

  const detail = await call(port, 'GET', `/admin/issues/${made.body._id}`, aTok);
  ck('6. admin detail works', detail.status === 200, detail.status);
  ck('6. counts this worker’s other issues', detail.body.issuesAgainstWorker === 2,
    detail.body.issuesAgainstWorker);

  const noNote = await call(port, 'PUT', `/admin/issues/${made.body._id}`, aTok, {
    status: 'resolved',
  });
  ck('6. closing without a note refused', noNote.status === 400, noNote.status);

  const review = await call(port, 'PUT', `/admin/issues/${made.body._id}`, aTok, {
    status: 'under_review', note: 'Looking into it',
  });
  ck('6. moving to under review works', review.status === 200, review.body.status);

  const resolved = await call(port, 'PUT', `/admin/issues/${made.body._id}`, aTok, {
    status: 'resolved', note: 'Re-clean arranged for Friday',
  });
  ck('6. resolving works', resolved.status === 200, resolved.status);
  ck('6. decision recorded', resolved.body.resolution?.note === 'Re-clean arranged for Friday');
  ck('6. decided-by recorded', String(resolved.body.resolution?.decidedBy) === String(admin._id));

  const twice = await call(port, 'PUT', `/admin/issues/${made.body._id}`, aTok, {
    status: 'rejected', note: 'changed my mind',
  });
  ck('6. a closed issue cannot be reopened by another decision', twice.status === 409, twice.status);

  // Raising again is allowed once the previous one is closed.
  const afterClose = await call(port, 'POST', '/issues', gTok, {
    jobId: done._id, issueType: 'safety', description: 'something else happened',
  });
  ck('6. a new issue can be raised after the last one closed',
    afterClose.status === 201, afterClose.status);

  // ------------------------------------------------- 7. dashboard
  const dash = await call(port, 'GET', '/admin/dashboard', aTok);
  ck('7. dashboard counts issues', dash.body.issues === 3, dash.body.issues);
  ck('7. dashboard counts open issues', dash.body.openIssues === 2, dash.body.openIssues);

  // ================================================ 8. job taker side
  const wTok = generateToken(worker._id, 'user');

  const wHist = await call(port, 'GET', '/issues/job-history?role=jobtaker', wTok);
  ck('8. worker job history served', wHist.status === 200, wHist.status);
  ck('8. worker sees the jobs they worked on', wHist.body.jobs.length === 2,
    wHist.body.jobs.length);
  ck('8. the client is joined for the card',
    wHist.body.jobs.every((j) => j.jobgiver?.name === 'Rohan'));
  ck("8. worker does not see the client's issues on those jobs",
    wHist.body.jobs.every((j) => j.issue === null),
    JSON.stringify(wHist.body.jobs.map((j) => j.issue)));

  const wIssue = await call(port, 'POST', '/issues', wTok, {
    jobId: done2._id,
    issueType: 'payment_not_received',
    subIssues: ['Paid Less Than Agreed'],
    description: 'Agreed 1200 but only 800 was released to me.',
  });
  ck('8. worker can raise an issue', wIssue.status === 201,
    wIssue.status + ' ' + (wIssue.body.message || ''));
  ck('8. filed as jobtaker', wIssue.body.raisedByRole === 'jobtaker',
    wIssue.body.raisedByRole);
  ck('8. filed against the client', String(wIssue.body.against) === String(giver._id));
  ck('8. worker sub-issue kept',
    JSON.stringify(wIssue.body.subIssues) === '["Paid Less Than Agreed"]');

  const wHist2 = await call(port, 'GET', '/issues/job-history?role=jobtaker', wTok);
  ck('8. worker history marks their own issue',
    wHist2.body.jobs.filter((j) => j.issue).length === 1,
    wHist2.body.jobs.filter((j) => j.issue).length);

  // Neither side may borrow the other's catalogue.
  const wrongWay = await call(port, 'POST', '/issues', wTok, {
    jobId: done._id, issueType: 'service_quality',
    description: 'a worker cannot file this',
  });
  ck("8. worker cannot use a giver-only type", wrongWay.status === 400, wrongWay.status);

  const giverWrong = await call(port, 'POST', '/issues', gTok, {
    jobId: done2._id, issueType: 'giver_unavailable',
    description: 'a giver cannot file this',
  });
  ck('8. giver cannot use a taker-only type', giverWrong.status === 400,
    giverWrong.status);

  // The role comes from the job, never from the request body.
  const spoof = await call(port, 'POST', '/issues', wTok, {
    jobId: done._id, issueType: 'giver_unavailable',
    role: 'jobgiver', raisedByRole: 'jobgiver',
    description: 'trying to file as the other side',
  });
  ck('8. a claimed role in the body is ignored',
    spoof.status !== 201 || spoof.body.raisedByRole === 'jobtaker',
    spoof.status + ' ' + (spoof.body.raisedByRole || ''));

  // Both sides can have an open issue on the same job at once.
  const bothSides = await call(port, 'GET', '/admin/issues', aTok);
  const onDone2 = bothSides.body.issues.filter(
    (i) => String(i.job?._id) === String(done2._id)
  );
  ck('8. both sides can report the same job',
    onDone2.length === 2 &&
      new Set(onDone2.map((i) => i.raisedByRole)).size === 2,
    onDone2.map((i) => i.raisedByRole).join(','));

  // Two by now: the payment complaint above, plus the one the spoof
  // attempt filed \u2014 which was refused its claimed role but is a valid
  // worker issue in its own right.
  const byRole = await call(port, 'GET', '/admin/issues?role=jobtaker', aTok);
  ck('8. admin can filter to worker-raised issues', byRole.body.total === 2,
    byRole.body.total);
  ck('8. and every one of them is a worker\u2019s',
    byRole.body.issues.every((i) => i.raisedByRole === 'jobtaker'));
  const byGiver = await call(port, 'GET', '/admin/issues?role=jobgiver', aTok);
  ck('8. the giver filter excludes them, and the two add up',
    byGiver.body.issues.every((i) => i.raisedByRole === 'jobgiver') &&
      byGiver.body.total + byRole.body.total === bothSides.body.total,
    `${byGiver.body.total} + ${byRole.body.total} = ${bothSides.body.total}`);

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
