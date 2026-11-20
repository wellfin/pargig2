/**
 * End-to-end check that the third-party settings actually take effect.
 *
 *   npm run check:integrations
 *
 * Runs the real Express app against a THROWAWAY database and drops it
 * afterwards. It never touches the configured MONGO_URI.
 *
 * The one that matters is section 2. Saving an MSG91 key in the panel
 * has to do two things in the same act: start sending real messages,
 * and stop returning the development code at sign-in. Two separate
 * switches could disagree, and the state where both are on is one
 * where a code is on the handset AND in an HTTP response.
 *
 * It is asserted through the real sign-in endpoint against a stub
 * MSG91, not by reading the setting back, because what is being
 * tested is the behaviour and not the row.
 */
process.env.MONGO_URI =
  process.env.CHECK_MONGO_URI ||
  'mongodb://127.0.0.1:27017/pargig_integrcheck_tmp';
process.env.JWT_SECRET = process.env.JWT_SECRET || 'testsecret';
process.env.NODE_ENV = 'test';
// Nothing from the environment, so the panel is the only source.
delete process.env.MSG91_AUTH_KEY;
delete process.env.MSG91_TEMPLATE_ID;
delete process.env.OSRM_BASE_URL;

const http = require('http');

const Admin = require('../models/adminModel');
const mongoose = Admin.base;
const app = require('../app');
const User = require('../models/userModel');
const Setting = require('../models/settingModel');
const smsConfig = require('../utils/smsConfig');
const routingConfig = require('../utils/routingConfig');
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
        let j = {};
        try { j = JSON.parse(b || '{}'); } catch { j = { raw: b }; }
        resolve({ status: res.statusCode, body: j });
      });
    });
    if (data) req.write(data);
    req.end();
  });
}

/** A stand-in MSG91 that records what it was asked to send. */
function msg91Stub() {
  const seen = [];
  const server = http.createServer((req, res) => {
    seen.push({ url: req.url, authkey: req.headers.authkey });
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ type: 'success', request_id: 'stub-1' }));
  });
  return { server, seen };
}

const MOB = '9700000001';

(async () => {
  await mongoose.connect(process.env.MONGO_URI);
  await mongoose.connection.dropDatabase();

  const boss = await Admin.create({
    name: 'Boss', email: 'boss@t.test', password: 'x'.repeat(12), role: 'superadmin',
  });
  const desk = await Admin.create({
    name: 'Desk', email: 'desk@t.test', password: 'x'.repeat(12), role: 'support',
  });

  const stub = msg91Stub();
  stub.server.listen(0);
  await new Promise((r) => stub.server.on('listening', r));
  const stubPort = stub.server.address().port;

  const server = http.createServer(app).listen(0);
  await new Promise((r) => server.on('listening', r));
  const port = server.address().port;
  const bTok = generateToken(boss._id, 'admin');
  const dTok = generateToken(desk._id, 'admin');

  const askOtp = () =>
    call(port, 'POST', '/auth/otp/request', null, { mobile: MOB });
  // The field the resend gate reads — see authController. Set to the
  // epoch rather than unset, so the gate sees an old send instead of
  // no send at all.
  const clearCooldown = () =>
    User.updateOne({ mobile: MOB }, { $set: { otpSentAt: new Date(0) } });

  // --------------------------------------------- 1. who may look
  ck('1. support is refused the SMS settings -> 403',
    (await call(port, 'GET', '/admin/settings/sms', dTok)).status === 403);
  ck('1. support is refused the distance settings -> 403',
    (await call(port, 'GET', '/admin/settings/routing', dTok)).status === 403);
  ck('1. superadmin can read them',
    (await call(port, 'GET', '/admin/settings/sms', bTok)).status === 200);

  // ------------------------- 2. the key is the switch, both ways
  const before = await call(port, 'GET', '/admin/settings/sms', bTok);
  ck('2. starts unconfigured', before.body.configured === false,
    before.body.configured);
  ck('2. and says the dev code is in use', before.body.devCodeInUse === true);

  let r = await askOtp();
  ck('2. so the code comes back in the response',
    /^\d{4,6}$/.test(String(r.body.devOtp || '')), r.body.devOtp);
  ck('2. and nothing was sent', stub.seen.length === 0, stub.seen.length);

  const saved = await call(port, 'PUT', '/admin/settings/sms', bTok, {
    enabled: true,
    authKey: 'panel-auth-key',
    templateId: 'tmpl_panel',
    senderId: 'PARGIG',
    countryCode: '91',
    baseUrl: `http://127.0.0.1:${stubPort}`,
  });
  ck('2. the key saves', saved.status === 200, saved.status);
  ck('2. and reads back configured', saved.body.configured === true);
  ck('2. the auth key is never returned, only masked',
    saved.body.authKey === undefined && Boolean(saved.body.authKeyMasked),
    saved.body.authKeyMasked);

  await clearCooldown();
  r = await askOtp();
  ck('2. now a real message goes out', stub.seen.length === 1, stub.seen.length);
  ck('2. with the auth key from the panel, in the header',
    stub.seen[0].authkey === 'panel-auth-key', stub.seen[0].authkey);
  ck('2. AND the dev code stops coming back',
    r.body.devOtp === undefined, r.body.devOtp);

  // Half a configuration is worse than none.
  const half = await call(port, 'PUT', '/admin/settings/sms', bTok, {
    enabled: true, authKey: 'another-key', templateId: '',
  });
  ck('2. a key without a template id is refused -> 400', half.status === 400,
    half.status);
  ck('2. and the refusal explains why',
    /template/i.test(half.body.message || ''), half.body.message);

  // Switching it off has to put the dev code back, or there is no way
  // to keep working when MSG91 has a bad day.
  await call(port, 'PUT', '/admin/settings/sms', bTok, {
    enabled: false, templateId: 'tmpl_panel',
  });
  await clearCooldown();
  const sentBefore = stub.seen.length;
  r = await askOtp();
  ck('2. switching it off returns the dev code',
    /^\d{4,6}$/.test(String(r.body.devOtp || '')), r.body.devOtp);
  ck('2. and sends nothing', stub.seen.length === sentBefore,
    stub.seen.length - sentBefore);

  // ------------------------------------------------- 3. distance
  const dist = await call(port, 'GET', '/admin/settings/routing', bTok);
  ck('3. defaults to the public OSRM server',
    dist.body.baseUrl === routingConfig.DEFAULT_BASE, dist.body.baseUrl);
  ck('3. with the built-in detour factor',
    dist.body.detourFactor === routingConfig.DEFAULT_FACTOR,
    dist.body.detourFactor);

  const badUrl = await call(port, 'PUT', '/admin/settings/routing', bTok, {
    baseUrl: 'not a url',
  });
  ck('3. a non-URL is refused -> 400', badUrl.status === 400, badUrl.status);

  const clamped = await call(port, 'PUT', '/admin/settings/routing', bTok, {
    baseUrl: 'https://osrm.example.test', detourFactor: 99,
  });
  ck('3. an absurd detour factor is clamped, not stored',
    clamped.body.detourFactor === 3, clamped.body.detourFactor);

  const low = await call(port, 'PUT', '/admin/settings/routing', bTok, {
    baseUrl: 'https://osrm.example.test', detourFactor: 0.2,
  });
  ck('3. and a factor under 1 too — a road is never shorter than the line',
    low.body.detourFactor === 1, low.body.detourFactor);

  // ------------------------------------- 4. the panel beats env
  process.env.MSG91_AUTH_KEY = 'env-key';
  process.env.MSG91_TEMPLATE_ID = 'tmpl_env';
  smsConfig.invalidate();
  await Setting.deleteOne({ key: smsConfig.KEY });
  smsConfig.invalidate();
  const envOnly = await call(port, 'GET', '/admin/settings/sms', bTok);
  ck('4. with nothing saved, the environment is used',
    envOnly.body.source === 'env', envOnly.body.source);

  await call(port, 'PUT', '/admin/settings/sms', bTok, {
    enabled: true,
    authKey: 'panel-wins',
    templateId: 'tmpl_panel',
    baseUrl: `http://127.0.0.1:${stubPort}`,
  });
  const panelWins = await call(port, 'GET', '/admin/settings/sms', bTok);
  ck('4. once saved, the panel outranks the environment',
    panelWins.body.source === 'admin', panelWins.body.source);

  await clearCooldown();
  const n = stub.seen.length;
  await askOtp();
  ck('4. and the panel key is the one used',
    stub.seen[n]?.authkey === 'panel-wins', stub.seen[n]?.authkey);

  console.log(out.join('\n'));

  // Awaited, not fired and forgotten. process.exit() while a handle is
  // still closing aborts the process on Windows with a libuv
  // assertion — which turned a passing run into exit code 127, and a
  // test that passes and then exits non-zero is a failing test.
  const closed = (srv) => new Promise((r) => srv.close(r));
  await Promise.all([closed(server), closed(stub.server)]);
  await mongoose.connection.dropDatabase();
  await mongoose.disconnect();

  const bad = out.filter((x) => x.includes('FAIL'));
  console.log(`\n${out.length - bad.length}/${out.length} passed`);
  console.log(bad.length ? 'RESULT: FAILURES' : 'RESULT: all good (temp db dropped)');
  // Set rather than exit(): everything above is closed, so node ends
  // on its own and nothing is torn out mid-flight.
  process.exitCode = bad.length ? 1 : 0;
})().catch(async (e) => {
  console.error('ERROR', e);
  try { await mongoose.connection.dropDatabase(); await mongoose.disconnect(); } catch { /* down */ }
  process.exit(1);
});
