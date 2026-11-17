/**
 * End-to-end check of the admin forgot-password flow.
 *
 *   npm run check:admin-reset
 *
 * Runs the real Express app against a THROWAWAY database and drops it
 * afterwards. It never touches the configured MONGO_URI, and it never
 * sends mail — with no SMTP configured and NODE_ENV=test, the code is
 * returned in the response, which is the development path the flow is
 * built to support.
 *
 * What is worth checking here is almost entirely the refusals. A reset
 * endpoint that works is easy; one that cannot be used to enumerate
 * admin accounts, replay a code, or guess six digits is the point.
 */
process.env.MONGO_URI =
  process.env.CHECK_MONGO_URI ||
  'mongodb://127.0.0.1:27017/pargig_adminreset_tmp';
process.env.JWT_SECRET = process.env.JWT_SECRET || 'testsecret';
process.env.NODE_ENV = 'test';
// Make sure no real mail server is picked up from a developer's .env.
delete process.env.SMTP_HOST;
delete process.env.MAIL_FROM;

const http = require('http');
const app = require('../app');
const Admin = require('../models/adminModel');

// Connect through the Mongoose instance the MODELS are built on,
// rather than whatever `require('mongoose')` resolves to from this
// folder. Those are normally the same object. They are not when a
// stray node_modules has been installed further down the tree — then
// `mongoose.connect()` opens a pool the models cannot see, and every
// query sits in the buffer until it times out, which reads like a
// dead database rather than a duplicated library.
const mongoose = Admin.base;

const out = [];
const ck = (l, c, d) =>
  out.push((c ? '  + ' : '  - FAIL ') + l + (d !== undefined ? ' -> ' + d : ''));

function call(port, method, path, body) {
  return new Promise((resolve) => {
    const data = body === undefined ? null : JSON.stringify(body);
    const headers = {};
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
          let p = {};
          try { p = JSON.parse(b || '{}'); } catch { p = { raw: b }; }
          resolve({ status: res.statusCode, body: p });
        });
      },
    );
    if (data) req.write(data);
    req.end();
  });
}

/** Clears the resend cooldown so the next step does not wait 60s. */
const allowResend = (email) =>
  Admin.updateOne({ email }, { $unset: { resetOtpSentAt: 1 } });

(async () => {
  await mongoose.connect(process.env.MONGO_URI);
  await mongoose.connection.dropDatabase();

  const EMAIL = 'boss@pargig.test';
  const OLD = 'originalPassword1';
  const NEW = 'a-much-better-one-9';
  await Admin.create({ name: 'Boss', email: EMAIL, password: OLD });
  await Admin.create({
    name: 'Retired', email: 'gone@pargig.test', password: OLD, isActive: false,
  });

  const server = http.createServer(app).listen(0);
  await new Promise((r) => server.on('listening', r));
  const port = server.address().port;

  const forgot = (email) =>
    call(port, 'POST', '/auth/admin/forgot-password', { email });
  const reset = (email, otp, password) =>
    call(port, 'POST', '/auth/admin/reset-password', { email, otp, password });
  const login = (email, password) =>
    call(port, 'POST', '/auth/admin/login', { email, password });

  // ---------------------------------------------- 1. no enumeration
  const ghost = await forgot('nobody@pargig.test');
  ck('1. unknown email still answers 200', ghost.status === 200, ghost.status);
  ck('1. and hands out no code', !ghost.body.devCode);

  const disabled = await forgot('gone@pargig.test');
  ck('1. a disabled admin is treated as no admin',
    disabled.status === 200 && !disabled.body.devCode);
  ck('1. all three replies are word-for-word identical',
    ghost.body.message === disabled.body.message);

  // ------------------------------------------------- 2. the real one
  const asked = await forgot(EMAIL);
  const code = asked.body.devCode;
  ck('2. a real admin gets a code', asked.status === 200 && !!code);
  ck('2. it is six digits', /^\d{6}$/.test(code || ''), code);
  ck('2. the reply is the same sentence as for a stranger',
    asked.body.message === ghost.body.message);

  const stored = await Admin.findOne({ email: EMAIL }).select('+resetOtpHash');
  ck('2. the database holds a hash, not the code',
    !!stored.resetOtpHash && !String(stored.resetOtpHash).includes(code),
    String(stored.resetOtpHash).slice(0, 12) + '…');

  // -------------------------------------------------- 3. resend gate
  const again = await forgot(EMAIL);
  ck('3. asking again immediately is refused', again.status === 429, again.status);

  // --------------------------------------------------- 4. bad input
  await allowResend(EMAIL);
  const wrongCode = await reset(EMAIL, '000000', NEW);
  ck('4. a wrong code is refused', wrongCode.status === 400, wrongCode.status);
  const short = await reset(EMAIL, code, 'short1');
  ck('4. a short password is refused', short.status === 400, short.status);
  const wrongEmail = await reset('nobody@pargig.test', code, NEW);
  ck('4. the code does not work on another address',
    wrongEmail.status === 400, wrongEmail.status);
  ck('4. and that refusal reads the same as a wrong code',
    wrongEmail.body.message === wrongCode.body.message);

  const afterMisses = await Admin.findOne({ email: EMAIL })
    .select('+resetOtpAttempts');
  ck('4. wrong guesses are counted', afterMisses.resetOtpAttempts >= 1,
    afterMisses.resetOtpAttempts);

  // ------------------------------------------------- 5. the happy path
  const done = await reset(EMAIL, code, NEW);
  ck('5. the right code changes the password', done.status === 200, done.status);

  const newLogin = await login(EMAIL, NEW);
  ck('5. the new password signs in', newLogin.status === 200 && !!newLogin.body.token,
    newLogin.status);
  const oldLogin = await login(EMAIL, OLD);
  ck('5. the old password no longer does', oldLogin.status === 401, oldLogin.status);

  // ------------------------------------------------ 6. one use only
  const replay = await reset(EMAIL, code, 'yet-another-one-1');
  ck('6. the same code cannot be used twice', replay.status === 400, replay.status);
  ck('6. and the password it tried to set does not work',
    (await login(EMAIL, 'yet-another-one-1')).status === 401);

  // ------------------------------------------ 7. guessing burns it
  await allowResend(EMAIL);
  const second = await forgot(EMAIL);
  const code2 = second.body.devCode;
  for (let i = 0; i < 5; i += 1) await reset(EMAIL, '111111', NEW);
  const burned = await reset(EMAIL, code2, 'legitimate-change-2');
  ck('7. five wrong guesses destroy the code, even for the right one',
    burned.status === 400, burned.status);
  ck('7. so the password is unchanged',
    (await login(EMAIL, NEW)).status === 200);

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
