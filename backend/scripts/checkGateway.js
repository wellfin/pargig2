/**
 * End-to-end check of the payment gateway module.
 *
 *   npm run check:gateway
 *
 * Runs the real Express app against a THROWAWAY database and drops it
 * afterwards. It never touches the configured MONGO_URI, and it never
 * calls Razorpay with real credentials — the signature maths is checked
 * against the same HMAC Razorpay computes, which is the part that has
 * to be right.
 */
process.env.MONGO_URI =
  process.env.CHECK_MONGO_URI ||
  'mongodb://127.0.0.1:27017/pargig_gatewaycheck_tmp';
process.env.JWT_SECRET = process.env.JWT_SECRET || 'testsecret';
process.env.NODE_ENV = 'test';
// Keep the env path out of the way: these checks are about what the
// admin panel saves, and an env credential would outrank nothing but
// would still change which branch runs.
delete process.env.RAZORPAY_KEY_ID;
delete process.env.RAZORPAY_KEY_SECRET;

const mongoose = require('mongoose');
const http = require('http');
const crypto = require('crypto');
const app = require('../app');
const User = require('../models/userModel');
const Admin = require('../models/adminModel');
const Job = require('../models/jobModel');
const Setting = require('../models/settingModel');
const GatewayOrder = require('../models/gatewayOrderModel');
const Payment = require('../models/paymentModel');
const Transaction = require('../models/transactionModel');
const generateToken = require('../utils/generateToken');
const secretBox = require('../utils/secretBox');
const razorpay = require('../utils/razorpay');
const gatewayConfig = require('../utils/gatewayConfig');

const out = [];
const ck = (l, c, d) =>
  out.push((c ? '  + ' : '  - FAIL ') + l + (d !== undefined ? ' -> ' + d : ''));

function call(port, method, path, token, body, headers = {}) {
  return new Promise((resolve) => {
    const data = body === undefined ? null : JSON.stringify(body);
    const h = { ...headers };
    if (token) h.Authorization = `Bearer ${token}`;
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
          resolve({ status: res.statusCode, body: p });
        });
      },
    );
    if (data) req.write(data);
    req.end();
  });
}

const TEST_KEY_ID = 'rzp_test_1234567890abcd';
const TEST_SECRET = 'abcdefghijklmnopqrstuvwx';
const WEBHOOK_SECRET = 'whsec_pargig_check';

(async () => {
  await mongoose.connect(process.env.MONGO_URI);
  await mongoose.connection.dropDatabase();

  const giver = await User.create({
    name: 'Rohan', mobile: '9600000001', roles: ['jobgiver'],
  });
  const worker = await User.create({
    name: 'Rahul', mobile: '9600000002', roles: ['jobtaker'],
  });
  const superadmin = await Admin.create({
    name: 'Boss', email: 'boss@pargig.test', password: 'secret123',
    role: 'superadmin',
  });
  const support = await Admin.create({
    name: 'Helper', email: 'help@pargig.test', password: 'secret123',
    role: 'support',
  });

  const giverToken = generateToken(giver._id);
  const adminToken = generateToken(superadmin._id, 'admin');
  const supportToken = generateToken(support._id, 'admin');

  const server = http.createServer(app).listen(0);
  await new Promise((r) => server.on('listening', r));
  const port = server.address().port;

  const newJob = async () =>
    Job.create({
      jobgiver: giver._id,
      selectedJobtaker: worker._id,
      title: 'Home cleaning',
      category: 'General',
      description: 'Clean the flat',
      finalPrice: 2000,
      tip: 100,
      status: 'completed',
      location: { type: 'Point', coordinates: [77.3, 28.5] },
    });

  // ------------------------------------------------- secrets at rest
  out.push('\nSecrets at rest');
  {
    const ct = secretBox.encrypt(TEST_SECRET);
    ck('encrypts to something that is not the plaintext',
      ct && !ct.includes(TEST_SECRET));
    ck('round-trips', secretBox.decrypt(ct) === TEST_SECRET);
    ck('two encryptions of the same secret differ (random IV)',
      secretBox.encrypt(TEST_SECRET) !== ct);
    const tampered = ct.slice(0, -2) + (ct.slice(-2) === 'AA' ? 'BB' : 'AA');
    ck('tampered ciphertext does not decrypt', secretBox.decrypt(tampered) === '');
    ck('garbage reads as no secret', secretBox.decrypt('nonsense') === '');
    ck('mask hides the middle',
      !secretBox.mask(TEST_SECRET).includes(TEST_SECRET.slice(4, 12)),
      secretBox.mask(TEST_SECRET));
  }

  // ------------------------------------------------ signature maths
  out.push('\nSignature verification');
  {
    const orderId = 'order_ABC123';
    const paymentId = 'pay_XYZ789';
    // Exactly how Razorpay computes it, from their docs.
    const good = crypto
      .createHmac('sha256', TEST_SECRET)
      .update(`${orderId}|${paymentId}`)
      .digest('hex');
    ck('accepts a correct checkout signature',
      razorpay.verifyCheckoutSignature({
        keySecret: TEST_SECRET, orderId, paymentId, signature: good,
      }));
    ck('rejects a wrong signature',
      !razorpay.verifyCheckoutSignature({
        keySecret: TEST_SECRET, orderId, paymentId, signature: good.replace(/.$/, '0'),
      }));
    ck('rejects a signature for a different order',
      !razorpay.verifyCheckoutSignature({
        keySecret: TEST_SECRET, orderId: 'order_OTHER', paymentId, signature: good,
      }));
    ck('rejects a signature made with the wrong secret',
      !razorpay.verifyCheckoutSignature({
        keySecret: 'not-the-secret', orderId, paymentId, signature: good,
      }));
    ck('rejects missing pieces',
      !razorpay.verifyCheckoutSignature({ keySecret: TEST_SECRET, orderId }));

    const body = JSON.stringify({ event: 'payment.captured' });
    const wh = crypto
      .createHmac('sha256', WEBHOOK_SECRET).update(body).digest('hex');
    ck('accepts a correct webhook signature',
      razorpay.verifyWebhookSignature({
        webhookSecret: WEBHOOK_SECRET, rawBody: body, signature: wh,
      }));
    ck('webhook signature works on a Buffer body',
      razorpay.verifyWebhookSignature({
        webhookSecret: WEBHOOK_SECRET, rawBody: Buffer.from(body), signature: wh,
      }));
    ck('rejects a webhook signed with the key secret instead',
      !razorpay.verifyWebhookSignature({
        webhookSecret: WEBHOOK_SECRET,
        rawBody: body,
        signature: crypto.createHmac('sha256', TEST_SECRET).update(body).digest('hex'),
      }));
    ck('rupees convert to paise without drift',
      razorpay.toPaise(2099.99) === 209999 && razorpay.toPaise(0.1) === 10);
    ck('reads test/live from the key id',
      razorpay.modeOfKeyId('rzp_live_x') === 'live' &&
      razorpay.modeOfKeyId('rzp_test_x') === 'test' &&
      razorpay.modeOfKeyId('nonsense') === null);
  }

  // --------------------------------------------------- admin settings
  out.push('\nAdmin settings API');
  {
    let r = await call(port, 'GET', '/admin/settings/payment', supportToken);
    ck('support admin cannot read payment settings', r.status === 403, r.status);

    r = await call(port, 'GET', '/admin/settings/payment', adminToken);
    ck('superadmin can read them', r.status === 200, r.status);
    ck('starts on the stand-in gateway', r.body.provider === 'dummy', r.body.provider);
    ck('offers a webhook url to paste into Razorpay',
      /\/api\/payments\/webhook\/razorpay$/.test(r.body.webhookUrl || ''),
      r.body.webhookUrl);

    r = await call(port, 'PUT', '/admin/settings/payment', adminToken, {
      provider: 'razorpay', keyId: 'not-a-key', keySecret: TEST_SECRET,
    });
    ck('rejects a key id that is not a Razorpay key', r.status === 400, r.body.message);

    r = await call(port, 'PUT', '/admin/settings/payment', adminToken, {
      provider: 'razorpay', keyId: TEST_KEY_ID,
    });
    ck('rejects saving without a secret the first time', r.status === 400, r.body.message);

    // No provider field: the key is the switch.
    r = await call(port, 'PUT', '/admin/settings/payment', adminToken, {
      provider: 'razorpay', keyId: TEST_KEY_ID, keySecret: TEST_SECRET,
      webhookSecret: WEBHOOK_SECRET, enabled: true,
    });
    ck('saves a valid key pair', r.status === 200, r.body.message || r.status);
    ck('choosing Razorpay with a key pair turns it on',
      r.body.provider === 'razorpay', r.body.provider);
    ck('says the secret is held', r.body.hasKeySecret === true);
    ck('never returns the secret itself',
      JSON.stringify(r.body).indexOf(TEST_SECRET) === -1);
    ck('reports test mode from the key id', r.body.mode === 'test', r.body.mode);
    ck('records who saved it', !!r.body.updatedByName, r.body.updatedByName);

    const stored = await Setting.findOne({ key: Setting.PAYMENT_GATEWAY }).lean();
    ck('database holds no plaintext secret',
      JSON.stringify(stored.value).indexOf(TEST_SECRET) === -1);
    ck('database holds no plaintext webhook secret',
      JSON.stringify(stored.value).indexOf(WEBHOOK_SECRET) === -1);

    // Re-save with blank secrets: must keep what is already there.
    r = await call(port, 'PUT', '/admin/settings/payment', adminToken, {
      provider: 'razorpay', keyId: TEST_KEY_ID, keySecret: '', webhookSecret: '',
    });
    ck('a blank secret leaves the saved one alone', r.body.hasKeySecret === true);
    const after = await gatewayConfig.getConfig();
    ck('and the kept secret is still the right one',
      after.keySecret === TEST_SECRET);
    ck('webhook secret survives too', after.webhookSecret === WEBHOOK_SECRET);

    r = await call(port, 'GET', '/admin/settings/payment', adminToken);
    ck('config now reads as razorpay', r.body.provider === 'razorpay', r.body.provider);
    ck('and reports where it came from', r.body.source === 'admin', r.body.source);

    // The `enabled` tick is gone: choosing the stand-in is what it
    // meant, and two controls for one decision is a state where they
    // can disagree.
    r = await call(port, 'PUT', '/admin/settings/payment', adminToken, {
      provider: 'dummy',
    });
    ck('choosing the stand-in falls back from razorpay',
      (await gatewayConfig.getConfig()).provider === 'dummy');

    r = await call(port, 'POST', '/admin/settings/payment/test', adminToken);
    ck('Test Connection refuses while on the stand-in', r.status === 400,
      r.body.message);

    await call(port, 'PUT', '/admin/settings/payment', adminToken, {
      provider: 'razorpay',
    });
    ck('switching back restores razorpay, with no key retyped',
      (await gatewayConfig.getConfig()).provider === 'razorpay');
  }

  // --------------------------------------- wallet top-up amount safety
  out.push('\nWallet top-up cannot be over-claimed');
  {
    // Back to the stand-in so an order can be opened without calling
    // Razorpay: the check is about which amount is believed, and that
    // code path is identical for both providers.
    // Switching to the stand-in is the outage switch: it must keep
    // the key pair, or the way back is a trip to the Razorpay
    // dashboard at the worst possible moment.
    let back = await call(port, 'PUT', '/admin/settings/payment', adminToken, {
      provider: 'dummy',
    });
    ck('choosing the stand-in stops real payments',
      back.body.provider === 'dummy', back.body.provider);
    ck('and KEEPS the saved key pair',
      back.body.keyId === TEST_KEY_ID && back.body.hasKeySecret === true,
      `${back.body.keyId} / ${back.body.hasKeySecret}`);

    back = await call(port, 'PUT', '/admin/settings/payment', adminToken, {
      provider: 'razorpay',
    });
    ck('switching back needs no retyping', back.body.provider === 'razorpay',
      back.body.provider);

    // Razorpay with nothing to authenticate as would read as live and
    // take no money, so it is refused rather than accepted.
    const noKey = await call(port, 'PUT', '/admin/settings/payment', adminToken, {
      provider: 'razorpay', keyId: '',
    });
    ck('Razorpay without a Key ID is refused -> 400', noKey.status === 400,
      noKey.status);

    // Clearing the key while on the stand-in is the deliberate delete.
    back = await call(port, 'PUT', '/admin/settings/payment', adminToken, {
      provider: 'dummy', keyId: '',
    });
    ck('clearing the Key ID removes the stored secrets',
      back.body.hasKeySecret === false && back.body.hasWebhookSecret === false,
      `${back.body.hasKeySecret} / ${back.body.hasWebhookSecret}`);

    gatewayConfig.invalidate();

    let r = await call(port, 'POST', '/payments/wallet/order', giverToken, {
      amount: 100,
    });
    ck('opens a top-up order', r.status === 200, r.status);
    const orderId = r.body.orderId;
    const opened = await GatewayOrder.findOne({ orderId }).lean();
    ck('order is recorded server-side', !!opened);
    ck('with the amount the server was asked for', opened.amount === 100);
    // The mirror of "recording razorpay as the gateway" further down:
    // a payment taken while the stand-in is chosen has to be recorded
    // as the stand-in. Together they are the proof that the saved
    // radio is the one a real payment goes through, rather than only
    // the one the config reports.
    ck('and recording the stand-in as the gateway it went through',
      opened.provider === 'dummy' || opened.gateway === 'dummy',
      opened.provider || opened.gateway);

    r = await call(port, 'POST', '/payments/wallet/confirm', giverToken, {
      orderId, amount: 100000,
    });
    ck('confirm succeeds', r.status === 200, r.body.message || r.status);
    ck('but credits the ORDER amount, not the claimed one',
      r.body.walletBalance === 100, r.body.walletBalance);

    const fresh = await User.findById(giver._id).lean();
    ck('wallet really holds 100', fresh.walletBalance === 100, fresh.walletBalance);

    r = await call(port, 'POST', '/payments/wallet/confirm', giverToken, {
      orderId, amount: 100,
    });
    ck('the same order cannot be credited twice', r.status === 409, r.status);
    const stillOne = await Transaction.countDocuments({
      user: giver._id, type: 'wallet_topup',
    });
    ck('exactly one top-up transaction exists', stillOne === 1, stillOne);

    r = await call(port, 'POST', '/payments/wallet/confirm', giverToken, {
      orderId: 'order_madeup', amount: 50,
    });
    ck('an invented order id is refused', r.status === 400, r.status);

    const otherToken = generateToken(worker._id);
    const mine = await call(port, 'POST', '/payments/wallet/order', giverToken, {
      amount: 25,
    });
    r = await call(port, 'POST', '/payments/wallet/confirm', otherToken, {
      orderId: mine.body.orderId, amount: 25,
    });
    ck('another account cannot confirm my order', r.status === 403, r.status);
  }

  // ------------------------------------------------- job order/confirm
  out.push('\nJob payment');
  {
    const job = await newJob();
    let r = await call(port, 'POST', `/payments/jobs/${job._id}/order`, giverToken);
    ck('opens an order for a completed job', r.status === 200, r.status);
    ck('for price plus tip', r.body.amount === 2100, r.body.amount);
    ck('tells the app which gateway it is', r.body.provider === 'dummy', r.body.provider);
    const orderId = r.body.orderId;

    const other = await newJob();
    r = await call(port, 'POST', `/payments/jobs/${other._id}/confirm`, giverToken, {
      orderId,
    });
    ck("an order from another job is refused", r.status === 400, r.body.message);

    r = await call(port, 'POST', `/payments/jobs/${job._id}/confirm`, giverToken, {
      orderId, methodLabel: 'UPI',
    });
    ck('confirming settles the job', r.status === 200, r.body.message || r.status);
    ck('worker receives price less fee, plus tip',
      r.body.payoutAmount > 0, r.body.payoutAmount);

    r = await call(port, 'POST', `/payments/jobs/${job._id}/confirm`, giverToken, {
      orderId,
    });
    ck('a replayed confirm does not pay twice',
      r.status === 200 && r.body.alreadyPaid === true, r.status);
    const paid = await Payment.countDocuments({ job: job._id });
    ck('one payment record for the job', paid === 1, paid);
  }

  // ------------------------------------------------------- the webhook
  out.push('\nWebhook');
  {
    await call(port, 'PUT', '/admin/settings/payment', adminToken, {
      provider: 'razorpay', keyId: TEST_KEY_ID, keySecret: TEST_SECRET,
      webhookSecret: WEBHOOK_SECRET, enabled: true,
    });
    gatewayConfig.invalidate();

    const job = await newJob();
    const order = await GatewayOrder.create({
      orderId: 'order_WEBHOOK1', provider: 'razorpay', purpose: 'job',
      amount: 2100, user: giver._id, job: job._id,
    });

    const payload = {
      event: 'payment.captured',
      payload: {
        payment: {
          entity: {
            id: 'pay_WEBHOOK1', order_id: order.orderId,
            amount: 210000, method: 'card', status: 'captured',
          },
        },
      },
    };
    const body = JSON.stringify(payload);
    const sign = (secret) =>
      crypto.createHmac('sha256', secret).update(body).digest('hex');

    let r = await postRaw(port, '/api/payments/webhook/razorpay', body, {
      'x-razorpay-signature': sign('wrong-secret'),
    });
    ck('an unsigned / wrongly signed webhook is refused', r.status === 400, r.status);
    let after = await Job.findById(job._id).lean();
    ck('and settles nothing', !after.paymentReleasedAt);

    r = await postRaw(port, '/api/payments/webhook/razorpay', body, {
      'x-razorpay-signature': sign(WEBHOOK_SECRET),
    });
    ck('a correctly signed webhook is accepted', r.status === 200, r.status);
    after = await Job.findById(job._id).lean();
    ck('and settles the job', !!after.paymentReleasedAt);
    const pay = await Payment.findOne({ job: job._id }).lean();
    ck('recording razorpay as the gateway', pay.gateway === 'razorpay', pay.gateway);
    ck('and the method the payer actually used', pay.mode === 'card', pay.mode);

    r = await postRaw(port, '/api/payments/webhook/razorpay', body, {
      'x-razorpay-signature': sign(WEBHOOK_SECRET),
    });
    ck('a retried webhook does not settle twice',
      r.status === 200 && r.body.alreadySettled === true, JSON.stringify(r.body));
    const count = await Payment.countDocuments({ job: job._id });
    ck('still one payment record', count === 1, count);

    // A failure event must not settle anything.
    const failJob = await newJob();
    const failOrder = await GatewayOrder.create({
      orderId: 'order_WEBHOOK2', provider: 'razorpay', purpose: 'job',
      amount: 2100, user: giver._id, job: failJob._id,
    });
    const failBody = JSON.stringify({
      event: 'payment.failed',
      payload: {
        payment: {
          entity: {
            id: 'pay_F', order_id: failOrder.orderId,
            error_description: 'Card declined',
          },
        },
      },
    });
    r = await postRaw(port, '/api/payments/webhook/razorpay', failBody, {
      'x-razorpay-signature': crypto
        .createHmac('sha256', WEBHOOK_SECRET).update(failBody).digest('hex'),
    });
    ck('a failure event is accepted', r.status === 200, r.status);
    const failed = await GatewayOrder.findById(failOrder._id).lean();
    ck('and marks the order failed', failed.status === 'failed', failed.status);
    ck('with the reason', /declined/i.test(failed.failureReason || ''));
    const failedJob = await Job.findById(failJob._id).lean();
    ck('and never settles the job', !failedJob.paymentReleasedAt);
  }

  // ------------------------------------------------------------ report
  const failures = out.filter((l) => l.includes('FAIL'));
  console.log(out.join('\n'));
  console.log(
    `\n${out.filter((l) => l.startsWith('  ')).length - failures.length}/` +
      `${out.filter((l) => l.startsWith('  ')).length} checks passed`,
  );
  if (failures.length) console.log(`\n${failures.length} FAILED`);

  await mongoose.connection.dropDatabase();
  await mongoose.disconnect();
  server.close();
  process.exit(failures.length ? 1 : 0);
})().catch(async (err) => {
  console.error(err);
  try {
    await mongoose.connection.dropDatabase();
    await mongoose.disconnect();
  } catch (_) {}
  process.exit(1);
});

/** Posts an exact byte string, so webhook signatures line up. */
function postRaw(port, path, body, headers) {
  return new Promise((resolve) => {
    const req = http.request(
      {
        port,
        path,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(body),
          ...headers,
        },
      },
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
          resolve({ status: res.statusCode, body: p });
        });
      },
    );
    req.write(body);
    req.end();
  });
}
