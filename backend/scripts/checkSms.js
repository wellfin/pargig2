/**
 * End-to-end check of OTP delivery over MSG91.
 *
 *   npm run check:sms
 *
 * Runs the real Express app against a THROWAWAY database and drops it
 * afterwards. MSG91 itself is replaced by a local stub server, so this
 * never sends a message, never spends credit, and needs no account —
 * what it proves is that we call them with the right number, the right
 * template and the code we actually stored, and that we behave sanely
 * when they say no.
 *
 * To check real credentials against the real MSG91, send yourself one
 * message instead:  npm run sms:test -- 9876543210
 */
process.env.MONGO_URI =
  process.env.CHECK_MONGO_URI ||
  'mongodb://127.0.0.1:27017/pargig_smscheck_tmp';
process.env.JWT_SECRET = process.env.JWT_SECRET || 'testsecret';
process.env.NODE_ENV = 'test';
process.env.OTP_TTL_SECONDS = '300';
process.env.OTP_RESEND_COOLDOWN_SECONDS = '30';
process.env.OTP_MAX_PER_DAY = '10';
process.env.OTP_MAX_PER_IP_PER_HOUR = '20';
// Whatever the developer has in their own .env must not decide which
// branch these checks take.
delete process.env.MSG91_AUTH_KEY;
delete process.env.MSG91_TEMPLATE_ID;
delete process.env.MSG91_SENDER_ID;

const mongoose = require('mongoose');
const http = require('http');
const app = require('../app');
const User = require('../models/userModel');
const sms = require('../utils/sms');
const throttle = require('../utils/otpThrottle');

const out = [];
const ck = (l, c, d) =>
  out.push((c ? '  + ' : '  - FAIL ') + l + (d !== undefined ? ' -> ' + d : ''));

function call(port, method, path, body, headers = {}) {
  return new Promise((resolve) => {
    const data = body === undefined ? null : JSON.stringify(body);
    const h = { ...headers };
    if (data) {
      h['Content-Type'] = 'application/json';
      h['Content-Length'] = Buffer.byteLength(data);
    }
    const req = http.request(
      { port, path: '/api' + path, method, headers: h },
      (res) => {
        let b = '';
        res.on('data', (c) => (b += c));
        res.on('end', () => {
          let p = {};
          try {
            p = JSON.parse(b || '{}');
          } catch {
            p = { raw: b };
          }
          resolve({ status: res.statusCode, headers: res.headers, body: p });
        });
      },
    );
    if (data) req.write(data);
    req.end();
  });
}

/** Stands in for control.msg91.com. `reply` decides what it answers. */
function stubMsg91() {
  const seen = [];
  let reply = { status: 200, body: { type: 'success', message: 'req-1' } };
  const server = http.createServer((req, res) => {
    let raw = '';
    req.on('data', (c) => (raw += c));
    req.on('end', () => {
      const url = new URL(req.url, 'http://stub');
      seen.push({
        path: url.pathname,
        query: Object.fromEntries(url.searchParams),
        headers: req.headers,
        body: raw,
      });
      if (reply === 'hang') return; // never answers: exercises the timeout
      res.writeHead(reply.status, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(reply.body));
    });
  });
  return {
    server,
    seen,
    last: () => seen[seen.length - 1],
    setReply: (r) => {
      reply = r;
    },
  };
}

/** Lets the next request through without waiting out the real cooldown. */
const clearCooldown = (mobile) =>
  User.updateOne({ mobile }, { $set: { otpSentAt: new Date(0) } });

(async () => {
  await mongoose.connect(process.env.MONGO_URI);
  await mongoose.connection.dropDatabase();

  const stub = stubMsg91();
  await new Promise((r) => stub.server.listen(0, '127.0.0.1', r));
  const stubPort = stub.server.address().port;

  const server = app.listen(0);
  await new Promise((r) => server.on('listening', r));
  const port = server.address().port;

  const MOB = '9811100011';

  // --- normalising the number MSG91 is given ------------------------
  out.push('\nnumber formatting');
  ck('ten digits gain the country code', sms.toMsisdn('9811100011', '91') === '919811100011', sms.toMsisdn('9811100011', '91'));
  ck('an existing 91 is not doubled', sms.toMsisdn('919811100011', '91') === '919811100011');
  ck('+91 and spaces are stripped', sms.toMsisdn('+91 98111 00011', '91') === '919811100011');
  ck('a leading 0 is dropped', sms.toMsisdn('09811100011', '91') === '919811100011');

  // --- no gateway configured ----------------------------------------
  out.push('\nwith no SMS gateway configured');
  ck('isConfigured is false', (await sms.isConfigured()) === false);

  let r = await call(port, 'POST', '/auth/otp/request', { mobile: MOB });
  ck('request succeeds', r.status === 200, r.status);
  ck('the code comes back for development', /^\d{4}$/.test(r.body.devOtp || ''), r.body.devOtp);
  ck('the resend window is published', r.body.resendAfter === 30, r.body.resendAfter);
  ck('nothing was sent to MSG91', stub.seen.length === 0, stub.seen.length);

  const devCode = r.body.devOtp;
  r = await call(port, 'POST', '/auth/otp/verify', { mobile: MOB, otp: devCode });
  ck('that code logs in', r.status === 200 && !!r.body.token, r.status);

  // The daily cap exists to bound an SMS bill. With nothing sending
  // there is no bill, and a tester logging in all afternoon should not
  // be cut off at ten — this is the path the project ran on before
  // MSG91 and the one it falls back to whenever the key is blank.
  const DEVMOB = '9811100099';
  await User.create({ mobile: DEVMOB, roles: ['jobgiver'] });
  await User.updateOne(
    { mobile: DEVMOB },
    { $set: { otpSentCount: 500, otpSentDay: throttle.dayKey() } },
  );
  r = await call(port, 'POST', '/auth/otp/request', { mobile: DEVMOB });
  ck('the daily cap does not apply with no gateway', r.status === 200, r.status);
  ck('and the code still comes back', /^\d{4}$/.test(r.body.devOtp || ''), r.body.devOtp);
  r = await call(port, 'POST', '/auth/otp/request', { mobile: DEVMOB });
  ck('but the cooldown still does', r.status === 429, r.status);

  // --- gateway configured -------------------------------------------
  process.env.MSG91_AUTH_KEY = 'authkey-for-tests';
  process.env.MSG91_TEMPLATE_ID = 'tmpl_123';
  process.env.MSG91_SENDER_ID = 'PARGIG';
  process.env.MSG91_BASE_URL = `http://127.0.0.1:${stubPort}`;
  process.env.MSG91_TIMEOUT_MS = '1500';
  // The config is cached for thirty seconds, which is right in
  // production — the environment does not change under a running
  // process — and wrong here, where the whole point is that it just
  // did. Dropping the cache is also what saving in the panel does.
  require('../utils/smsConfig').invalidate();

  out.push('\nwith MSG91 configured');
  ck('isConfigured is true', (await sms.isConfigured()) === true);

  await clearCooldown(MOB);
  r = await call(port, 'POST', '/auth/otp/request', { mobile: MOB });
  ck('request succeeds', r.status === 200, r.status);
  ck('the code is NOT returned to the caller', r.body.devOtp === undefined, r.body.devOtp);
  ck('one message was sent', stub.seen.length === 1, stub.seen.length);

  let sent = stub.last();
  ck('it hit the OTP endpoint', sent.path === '/otp', sent.path);
  ck('the auth key travels in the header', sent.headers.authkey === 'authkey-for-tests');
  ck('the auth key is NOT in the query string', sent.query.authkey === undefined);
  ck('the template id is passed', sent.query.template_id === 'tmpl_123', sent.query.template_id);
  ck('the number carries the country code', sent.query.mobile === '91' + MOB, sent.query.mobile);
  ck('the sender id is passed', sent.query.sender === 'PARGIG', sent.query.sender);
  ck('a real-time answer is demanded', sent.query.realTimeResponse === '1');
  ck('expiry is sent in minutes', sent.query.otp_expiry === '5', sent.query.otp_expiry);

  let dbUser = await User.findOne({ mobile: MOB });
  ck('the code sent is the code stored', sent.query.otp === dbUser.otp.code, sent.query.otp);
  ck("MSG91's request id is kept for support", dbUser.otp.requestId === 'req-1', dbUser.otp.requestId);

  r = await call(port, 'POST', '/auth/otp/verify', { mobile: MOB, otp: sent.query.otp });
  ck('the texted code logs in', r.status === 200 && !!r.body.token, r.status);

  r = await call(port, 'POST', '/auth/otp/verify', { mobile: MOB, otp: sent.query.otp });
  ck('and cannot be replayed', r.status === 400, r.status);
  stub.setReply({ status: 200, body: { type: 'success', message: 'req-live' } });

  // --- MSG91 says no -------------------------------------------------
  out.push('\nwhen MSG91 refuses');
  // Put a good code on the record first, so "the failed send did not
  // overwrite it" is a claim about something that exists.
  await clearCooldown(MOB);
  await call(port, 'POST', '/auth/otp/request', { mobile: MOB });
  const before = (await User.findOne({ mobile: MOB })).otp;
  const spentBefore = (await User.findOne({ mobile: MOB })).otpSentCount;
  ck('a live code is on the record to protect', /^\d{4}$/.test(before?.code || ''), before?.code);

  await clearCooldown(MOB);
  // Their own failures arrive as HTTP 200 with type:error — the status
  // code alone is not the verdict.
  stub.setReply({ status: 200, body: { type: 'error', message: 'Template not found' } });
  r = await call(port, 'POST', '/auth/otp/request', { mobile: MOB });
  ck('a 200-with-type-error is treated as a failure', r.status === 502, r.status);
  ck('the reason is passed through outside production', /Template not found/.test(r.body.message || ''), r.body.message);

  dbUser = await User.findOne({ mobile: MOB });
  ck(
    'the undelivered code is not stored',
    String(dbUser.otp?.code || '') === String(before?.code || ''),
    `${before?.code || 'none'} -> ${dbUser.otp?.code || 'none'}`,
  );
  ck('the daily allowance is not spent on it', dbUser.otpSentCount === spentBefore, spentBefore + ' -> ' + dbUser.otpSentCount);
  ck('but the cooldown still applies', !!dbUser.otpSentAt && dbUser.otpSentAt.getTime() > Date.now() - 10000);

  process.env.NODE_ENV = 'production';
  await clearCooldown(MOB);
  r = await call(port, 'POST', '/auth/otp/request', { mobile: MOB });
  ck('production hides the gateway wording', r.status === 502 && !/Template/.test(r.body.message || ''), r.body.message);
  process.env.NODE_ENV = 'test';

  out.push('\nwhen MSG91 does not answer at all');
  stub.setReply('hang');
  await clearCooldown(MOB);
  const t0 = Date.now();
  r = await call(port, 'POST', '/auth/otp/request', { mobile: MOB });
  ck('the request is not left hanging', r.status === 502, r.status);
  ck('it gives up on the configured timeout', Date.now() - t0 < 5000, `${Date.now() - t0}ms`);
  stub.setReply({ status: 200, body: { type: 'success', message: 'req-2' } });

  // --- throttling ----------------------------------------------------
  out.push('\nrate limits');
  const MOB2 = '9811100022';
  r = await call(port, 'POST', '/auth/otp/request', { mobile: MOB2 });
  ck('first request for a new number goes through', r.status === 200, r.status);
  const sentCount = stub.seen.length;

  r = await call(port, 'POST', '/auth/otp/request', { mobile: MOB2 });
  ck('an immediate retry is refused', r.status === 429, r.status);
  ck('with a Retry-After header', Number(r.headers['retry-after']) > 0, r.headers['retry-after']);
  ck('and no SMS was spent on it', stub.seen.length === sentCount, stub.seen.length - sentCount);

  await User.updateOne(
    { mobile: MOB2 },
    { $set: { otpSentAt: new Date(0), otpSentCount: 10, otpSentDay: throttle.dayKey() } },
  );
  r = await call(port, 'POST', '/auth/otp/request', { mobile: MOB2 });
  ck('the daily cap stops the eleventh code', r.status === 429, r.status);
  ck('and says to try tomorrow', /tomorrow|support/i.test(r.body.message || ''), r.body.message);
  ck('still no SMS spent', stub.seen.length === sentCount, stub.seen.length - sentCount);

  await User.updateOne(
    { mobile: MOB2 },
    { $set: { otpSentAt: new Date(0), otpSentDay: 'yesterday' } },
  );
  r = await call(port, 'POST', '/auth/otp/request', { mobile: MOB2 });
  ck('a new day starts the count over', r.status === 200, r.status);
  dbUser = await User.findOne({ mobile: MOB2 });
  ck('and the counter restarted at one', dbUser.otpSentCount === 1, dbUser.otpSentCount);

  // --- throttle unit checks -----------------------------------------
  out.push('\nthrottle rules in isolation');
  throttle._reset();
  ck('loopback is never IP-limited (proxy may not forward the client)', (() => {
    for (let i = 0; i < 50; i++) throttle.noteIp('127.0.0.1');
    return throttle.checkIp('127.0.0.1').ok === true;
  })());
  ck('a real address is capped at 20/hour', (() => {
    for (let i = 0; i < 20; i++) throttle.noteIp('203.0.113.7');
    return throttle.checkIp('203.0.113.7').ok === false;
  })());
  ck('a different address is unaffected', throttle.checkIp('203.0.113.8').ok === true);
  ck('the day key rolls over at midnight IST, not UTC',
    throttle.dayKey(new Date('2026-03-01T18:45:00Z')) === '2026-03-02',
    throttle.dayKey(new Date('2026-03-01T18:45:00Z')));
  ck('and 18:15 UTC is still the day before',
    throttle.dayKey(new Date('2026-03-01T18:15:00Z')) === '2026-03-01');

  const u = { otpSentAt: new Date(Date.now() - 5000) };
  const verdict = throttle.checkMobile(u);
  ck('a 5s-old send leaves ~25s to wait', !verdict.ok && verdict.retryAfter >= 24 && verdict.retryAfter <= 26, verdict.retryAfter);

  // --- report --------------------------------------------------------
  const fails = out.filter((l) => l.startsWith('  - FAIL')).length;
  const passes = out.filter((l) => l.startsWith('  + ')).length;
  console.log(out.join('\n'));
  console.log(`\n${passes}/${passes + fails} checks passed`);

  await mongoose.connection.dropDatabase();
  await mongoose.disconnect();
  server.close();
  stub.server.close();
  process.exit(fails ? 1 : 0);
})().catch(async (err) => {
  console.log(out.join('\n'));
  console.error(err);
  try {
    await mongoose.connection.dropDatabase();
    await mongoose.disconnect();
  } catch (_) {}
  process.exit(1);
});
