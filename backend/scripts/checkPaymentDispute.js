/**
 * End-to-end check of the payment + dispute/refund module.
 *
 *   npm run check:payments
 *
 * Runs the real Express app against a THROWAWAY database, exercises every
 * path with HTTP calls, then drops that database. It never touches the
 * configured MONGO_URI, and it forces the gateway into simulated mode so
 * it can be run safely at any time, including with live keys in .env.
 *
 * What it covers:
 *   1  payment mode is recorded against each payment
 *   2  disputes are refused on cash-paid jobs
 *   3  full refund: money, gateway reference, audit trail
 *   4  a dispute cannot be resolved twice
 *   5  partial refund
 *   6  refunds beyond the remaining balance are refused
 *   7  no refund leaves the payment settled
 *   8  wallet-mode refunds credit the wallet
 *   9  the older `outcome` vocabulary still works
 *  10  refund webhooks, including signature verification
 *  11  live/simulated is decided by .env alone
 *  12  the admin decision screen gets the numbers it needs
 */
process.env.MONGO_URI =
  process.env.CHECK_MONGO_URI ||
  'mongodb://127.0.0.1:27017/pargig_paymentcheck_tmp';
process.env.JWT_SECRET = process.env.JWT_SECRET || 'testsecret';
process.env.NODE_ENV = 'test';
// Simulated gateway regardless of what .env holds: this script must never
// move real money.
delete process.env.RAZORPAY_KEY_ID;
delete process.env.RAZORPAY_KEY_SECRET;
delete process.env.RAZORPAY_WEBHOOK_SECRET;

const mongoose = require('mongoose');
const http = require('http');
const crypto = require('crypto');
const app = require('../app');
const User = require('../models/userModel');
const Admin = require('../models/adminModel');
const Job = require('../models/jobModel');
const Payment = require('../models/paymentModel');
const Dispute = require('../models/disputeModel');
const Transaction = require('../models/transactionModel');
const generateToken = require('../utils/generateToken');

const results = [];
const ck = (label, cond, detail) =>
  results.push(
    (cond ? '  + ' : '  - FAIL ') +
      label +
      (detail !== undefined ? ' -> ' + detail : '')
  );

function call(port, method, path, token, body, extraHeaders) {
  return new Promise((resolve) => {
    const data = body === undefined ? null : JSON.stringify(body);
    const headers = { ...(extraHeaders || {}) };
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
          let parsed = {};
          try {
            parsed = JSON.parse(b || '{}');
          } catch {
            parsed = { raw: b };
          }
          resolve({ status: res.statusCode, body: parsed });
        });
      }
    );
    if (data) req.write(data);
    req.end();
  });
}

const makeJob = ({ giver, taker, title, price }) =>
  Job.create({
    title,
    category: 'cleaning',
    description: 'x',
    jobgiver: giver._id,
    selectedJobtaker: taker._id,
    status: 'completed',
    finalPrice: price,
    location: { type: 'Point', coordinates: [77.5, 12.9] },
  });

(async () => {
  await mongoose.connect(process.env.MONGO_URI);
  await mongoose.connection.dropDatabase();

  const giver = await User.create({
    name: 'Giver', mobile: '9300000001', roles: ['jobgiver'], freeJobsRemaining: 0,
  });
  const taker = await User.create({
    name: 'Taker', mobile: '9300000002', roles: ['jobtaker'], walletBalance: 0,
  });
  const admin = await Admin.create({
    name: 'Admin', email: 'a@pargig.test', password: 'x'.repeat(12),
  });

  const server = http.createServer(app).listen(0);
  await new Promise((r) => server.on('listening', r));
  const port = server.address().port;
  const gTok = generateToken(giver._id, 'user');
  const aTok = generateToken(admin._id, 'admin');

  // ------------------------------------------------- 1. payment modes
  const upiJob = await makeJob({ giver, taker, title: 'UPI job', price: 1000 });
  const upiRel = await call(port, 'POST', `/payments/jobs/${upiJob._id}/release`,
    gTok, { isCod: false, methodLabel: 'PhonePe' });
  ck('1. online release ok', upiRel.status === 200,
    upiRel.status + ' ' + (upiRel.body.message || ''));
  let upiPay = await Payment.findOne({ job: upiJob._id });
  ck('1. mode recorded as upi from "PhonePe"', upiPay.mode === 'upi', upiPay.mode);
  ck('1. settlementStatus = settled after release',
    upiPay.settlementStatus === 'settled', upiPay.settlementStatus);

  const cardJob = await makeJob({ giver, taker, title: 'Card job', price: 800 });
  await call(port, 'POST', `/payments/jobs/${cardJob._id}/release`, gTok,
    { isCod: false, methodLabel: 'HDFC Debit Card ****9232' });
  const cardPay = await Payment.findOne({ job: cardJob._id });
  ck('1. mode recorded as card', cardPay.mode === 'card', cardPay.mode);

  const cashJob = await makeJob({ giver, taker, title: 'Cash job', price: 500 });
  await call(port, 'POST', `/payments/jobs/${cashJob._id}/release`, gTok,
    { isCod: true, methodLabel: 'Cash on Delivery' });
  const cashPay = await Payment.findOne({ job: cashJob._id });
  ck('1. mode recorded as cash', cashPay.mode === 'cash', cashPay.mode);

  // ------------------------------------------ 2. cash disputes refused
  const cashDisp = await call(port, 'POST', '/disputes', gTok,
    { jobId: cashJob._id, reason: 'Poor quality', details: 'x' });
  ck('2. cash dispute rejected', cashDisp.status === 400, cashDisp.status);
  ck('2. rejection explains why', /cash/i.test(cashDisp.body.message || ''),
    JSON.stringify(cashDisp.body.message));
  ck('2. no dispute record created',
    (await Dispute.countDocuments({ job: cashJob._id })) === 0);
  const cashJobAfter = await Job.findById(cashJob._id);
  ck('2. cash job not flipped to disputed',
    cashJobAfter.status === 'completed', cashJobAfter.status);

  // ---------------------------------------------- 3. UPI full refund
  const d1 = await call(port, 'POST', '/disputes', gTok,
    { jobId: upiJob._id, reason: 'Work not done', requestedResolution: 'refund' });
  ck('3. upi dispute accepted', d1.status === 201,
    d1.status + ' ' + (d1.body.message || ''));
  ck('3. dispute records the payment mode', d1.body.paymentMode === 'upi',
    d1.body.paymentMode);

  const takerBefore = (await User.findById(taker._id)).walletBalance;
  const r1 = await call(port, 'PUT', `/admin/disputes/${d1.body._id}/resolve`,
    aTok, { decision: 'full_refund', note: 'Worker never arrived' });
  ck('3. full refund accepted', r1.status === 200,
    r1.status + ' ' + (r1.body.message || ''));
  const s1 = r1.body.settlement || {};
  upiPay = await Payment.findById(upiPay._id);
  ck('3. full amount refunded', s1.refundedAmount === upiPay.amount,
    `${s1.refundedAmount} of ${upiPay.amount}`);
  ck('3. gateway reference recorded',
    typeof s1.refundReference === 'string' && s1.refundReference.startsWith('rfnd_'),
    s1.refundReference);
  ck('3. provider recorded', s1.refundProvider === 'razorpay_dummy',
    s1.refundProvider);
  ck('3. settlementStatus = refunded', upiPay.settlementStatus === 'refunded',
    upiPay.settlementStatus);
  ck('3. payment status = refunded', upiPay.status === 'refunded', upiPay.status);
  ck('3. refund entry stored on payment',
    upiPay.refunds.length === 1 && upiPay.refunds[0].status === 'processed');
  ck('3. refund entry links to the dispute',
    String(upiPay.refunds[0].dispute) === String(d1.body._id));
  ck('3. refund entry records the deciding admin',
    String(upiPay.refunds[0].decidedBy) === String(admin._id));
  const takerAfter = (await User.findById(taker._id)).walletBalance;
  ck('3. recovered from worker wallet',
    takerBefore - takerAfter === s1.recoveredFromWorker && s1.recoveredFromWorker > 0,
    `worker ${takerBefore} -> ${takerAfter}, recovered ${s1.recoveredFromWorker}`);
  ck('3. shortfall recorded as platform absorbed', s1.platformAbsorbed >= 0,
    s1.platformAbsorbed);
  const clawback = await Transaction.findOne({ user: taker._id, type: 'wallet_deduct' });
  ck('3. clawback written to the ledger', !!clawback && clawback.amount < 0,
    clawback && clawback.amount);
  const d1doc = await Dispute.findById(d1.body._id);
  ck('3. decision recorded', d1doc.resolution.decision === 'full_refund',
    d1doc.resolution.decision);
  ck('3. legacy outcome kept in step',
    d1doc.resolution.outcome === 'refund_giver', d1doc.resolution.outcome);
  ck('3. dispute refundStatus processed',
    d1doc.resolution.refundStatus === 'processed', d1doc.resolution.refundStatus);
  ck('3. dispute stores settlementStatus',
    d1doc.resolution.settlementStatus === 'refunded',
    d1doc.resolution.settlementStatus);

  // ------------------------------------- 4. resolving twice is refused
  const again = await call(port, 'PUT', `/admin/disputes/${d1.body._id}/resolve`,
    aTok, { decision: 'full_refund' });
  ck('4. second resolve refused', again.status === 409, again.status);
  ck('4. no second refund recorded',
    (await Payment.findById(upiPay._id)).refunds.length === 1);

  // -------------------------------------------- 5. card partial refund
  const d2 = await call(port, 'POST', '/disputes', gTok,
    { jobId: cardJob._id, reason: 'Partly done', requestedResolution: 'refund' });
  ck('5. card dispute accepted', d2.status === 201, d2.status);
  const r2 = await call(port, 'PUT', `/admin/disputes/${d2.body._id}/resolve`,
    aTok, { decision: 'partial_refund', refundAmount: 300, note: 'Half was fine' });
  ck('5. partial refund accepted', r2.status === 200,
    r2.status + ' ' + (r2.body.message || ''));
  const cardAfter = await Payment.findById(cardPay._id);
  ck('5. only the approved amount refunded', cardAfter.refundedAmount === 300,
    cardAfter.refundedAmount);
  ck('5. settlementStatus = partially_refunded',
    cardAfter.settlementStatus === 'partially_refunded', cardAfter.settlementStatus);
  ck('5. payment not marked fully refunded', cardAfter.status !== 'refunded',
    cardAfter.status);
  const d2doc = await Dispute.findById(d2.body._id);
  ck('5. decision recorded as partial_refund',
    d2doc.resolution.decision === 'partial_refund', d2doc.resolution.decision);
  ck('5. approved amount recorded', d2doc.resolution.refundAmount === 300,
    d2doc.resolution.refundAmount);

  // ---------------------------- 6. over-refunding the rest is refused
  const dOver = await Dispute.create({
    job: cardJob._id, raisedBy: giver._id, against: taker._id, reason: 'again',
  });
  const rOver = await call(port, 'PUT', `/admin/disputes/${dOver._id}/resolve`,
    aTok, { decision: 'partial_refund', refundAmount: 9999 });
  ck('6. refund beyond the balance refused', rOver.status === 400, rOver.status);
  ck('6. refusal states what is left',
    /can still be refunded/i.test(rOver.body.message || ''), rOver.body.message);
  ck('6. nothing extra refunded',
    (await Payment.findById(cardPay._id)).refundedAmount === 300);
  const dOverDoc = await Dispute.findById(dOver._id);
  ck('6. failed attempt recorded', dOverDoc.resolution.refundStatus === 'failed',
    dOverDoc.resolution.refundStatus);
  ck('6. dispute left open for another attempt',
    !['resolved', 'rejected'].includes(dOverDoc.status), dOverDoc.status);

  // ------------------------------------------------------ 7. no refund
  const noJob = await makeJob({ giver, taker, title: 'Fine job', price: 400 });
  await call(port, 'POST', `/payments/jobs/${noJob._id}/release`, gTok,
    { isCod: false, methodLabel: 'UPI' });
  const d3 = await call(port, 'POST', '/disputes', gTok,
    { jobId: noJob._id, reason: 'Late' });
  const r3 = await call(port, 'PUT', `/admin/disputes/${d3.body._id}/resolve`,
    aTok, { decision: 'no_refund', note: 'Work was delivered as agreed' });
  ck('7. no-refund accepted', r3.status === 200, r3.status);
  const noPay = await Payment.findOne({ job: noJob._id });
  ck('7. nothing refunded', Number(noPay.refundedAmount) === 0, noPay.refundedAmount);
  ck('7. payment stays settled', noPay.settlementStatus === 'settled',
    noPay.settlementStatus);
  const d3doc = await Dispute.findById(d3.body._id);
  ck('7. decision recorded as no_refund', d3doc.resolution.decision === 'no_refund',
    d3doc.resolution.decision);
  ck('7. refundStatus not_applicable',
    d3doc.resolution.refundStatus === 'not_applicable', d3doc.resolution.refundStatus);

  // ------------------------------------------- 8. wallet mode refund
  const wJob = await makeJob({ giver, taker, title: 'Wallet job', price: 600 });
  await call(port, 'POST', `/payments/jobs/${wJob._id}/release`, gTok,
    { isCod: false, methodLabel: 'Pargig Wallet', mode: 'wallet' });
  const wPay = await Payment.findOne({ job: wJob._id });
  ck('8. mode recorded as wallet', wPay.mode === 'wallet', wPay.mode);
  const giverBefore = (await User.findById(giver._id)).walletBalance || 0;
  const d4 = await call(port, 'POST', '/disputes', gTok,
    { jobId: wJob._id, reason: 'Not done' });
  const r4 = await call(port, 'PUT', `/admin/disputes/${d4.body._id}/resolve`,
    aTok, { decision: 'full_refund', note: 'Refund to wallet' });
  ck('8. wallet refund accepted', r4.status === 200,
    r4.status + ' ' + (r4.body.message || ''));
  const giverAfter = (await User.findById(giver._id)).walletBalance || 0;
  ck('8. credited to the payer wallet', giverAfter - giverBefore === wPay.amount,
    `${giverBefore} -> ${giverAfter} (amount ${wPay.amount})`);
  const wRefundTxn = await Transaction.findOne({ user: giver._id, type: 'refund' });
  ck('8. wallet refund on the ledger',
    !!wRefundTxn && wRefundTxn.amount === wPay.amount, wRefundTxn && wRefundTxn.amount);
  ck('8. wallet refund has no gateway reference',
    (r4.body.settlement || {}).refundReference === null,
    (r4.body.settlement || {}).refundReference);

  // ---------------------------- 9. legacy `outcome` still understood
  const lJob = await makeJob({ giver, taker, title: 'Legacy job', price: 200 });
  await call(port, 'POST', `/payments/jobs/${lJob._id}/release`, gTok,
    { isCod: false, methodLabel: 'UPI' });
  const d5 = await call(port, 'POST', '/disputes', gTok, { jobId: lJob._id, reason: 'x' });
  const r5 = await call(port, 'PUT', `/admin/disputes/${d5.body._id}/resolve`,
    aTok, { outcome: 'refund_giver', note: 'old client' });
  ck('9. legacy outcome accepted', r5.status === 200,
    r5.status + ' ' + (r5.body.message || ''));
  ck('9. mapped to full_refund',
    (await Dispute.findById(d5.body._id)).resolution.decision === 'full_refund');

  // ------------------------------------------------- 10. refund webhook
  const wh = {
    event: 'refund.failed',
    payload: { refund: { entity: { id: upiPay.refunds[0].refundId, status: 'failed' } } },
  };
  const whRes = await call(port, 'POST', '/payments/webhooks/razorpay', null, wh);
  ck('10. webhook accepted in simulated mode', whRes.status === 200,
    whRes.status + ' ' + (whRes.body.message || ''));
  const afterWh = await Payment.findById(upiPay._id);
  ck('10. failed refund un-counted', Number(afterWh.refundedAmount) === 0,
    afterWh.refundedAmount);
  ck('10. settlementStatus = refund_failed',
    afterWh.settlementStatus === 'refund_failed', afterWh.settlementStatus);

  process.env.RAZORPAY_WEBHOOK_SECRET = 'whsec';
  const forged = await call(port, 'POST', '/payments/webhooks/razorpay', null, wh,
    { 'x-razorpay-signature': 'deadbeef' });
  ck('10. forged webhook rejected once a secret is set', forged.status === 400,
    forged.status);
  const sig = crypto.createHmac('sha256', 'whsec').update(JSON.stringify(wh)).digest('hex');
  const signed = await call(port, 'POST', '/payments/webhooks/razorpay', null, wh,
    { 'x-razorpay-signature': sig });
  ck('10. correctly signed webhook accepted', signed.status === 200, signed.status);
  delete process.env.RAZORPAY_WEBHOOK_SECRET;

  // ------------------------------- 11. live/simulated is env-only
  const rp = require('../utils/razorpay');
  ck('11. simulated while keys are absent',
    rp.isLive() === false && rp.providerName() === 'razorpay_dummy');
  process.env.RAZORPAY_KEY_ID = 'rzp_test_x';
  process.env.RAZORPAY_KEY_SECRET = 'secret';
  ck('11. live the moment keys appear, no redeploy',
    rp.isLive() === true && rp.providerName() === 'razorpay');
  delete process.env.RAZORPAY_KEY_ID;
  delete process.env.RAZORPAY_KEY_SECRET;

  // --------------------------- 12. admin screen gets what it needs
  const detail = await call(port, 'GET', `/admin/disputes/${d2.body._id}`, aTok);
  ck('12. admin dispute detail ok', detail.status === 200, detail.status);
  ck('12. refundable reflects the partial already given',
    detail.body.refundable === cardPay.amount - 300,
    `${detail.body.refundable} (paid ${cardPay.amount}, refunded 300)`);
  ck('12. already-refunded reported', detail.body.alreadyRefunded === 300,
    detail.body.alreadyRefunded);
  ck('12. payment mode reported', detail.body.paymentMode === 'card',
    detail.body.paymentMode);
  ck('12. gatewayLive flag reported', detail.body.gatewayLive === false,
    detail.body.gatewayLive);
  const cashDetail = await call(port, 'GET',
    `/admin/disputes/${(await Dispute.create({
      job: cashJob._id, raisedBy: giver._id, against: taker._id, reason: 'legacy cash',
    }))._id}`, aTok);
  ck('12. cash dispute reports why refunds are blocked',
    /cash/i.test(cashDetail.body.refundBlockedReason || ''),
    cashDetail.body.refundBlockedReason);

  console.log(results.join('\n'));
  server.close();
  await mongoose.connection.dropDatabase();
  await mongoose.disconnect();
  const failed = results.filter((r) => r.includes('FAIL'));
  console.log(`\n${results.length - failed.length}/${results.length} passed`);
  console.log(
    failed.length ? 'RESULT: FAILURES' : 'RESULT: all good (temp db dropped)'
  );
  process.exit(failed.length ? 1 : 0);
})().catch(async (e) => {
  console.error('ERROR', e);
  try {
    await mongoose.connection.dropDatabase();
    await mongoose.disconnect();
  } catch {
    /* already down */
  }
  process.exit(1);
});
