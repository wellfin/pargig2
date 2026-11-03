/**
 * Sends one real OTP SMS with the credentials in .env.
 *
 *   npm run sms:test -- 9876543210
 *
 * This spends one message. It is the only way to prove the whole chain
 * — auth key, DLT template, sender id, your MSG91 balance — because
 * every one of those can be wrong in a way that only shows up when a
 * handset is waiting for the message.
 *
 * It touches no database and creates no user. The code it sends is
 * random and will not log anyone in.
 */
require('dotenv').config();
const sms = require('../utils/sms');

const mobile = process.argv[2];

(async () => {
  if (!mobile || !/^\d{10}$/.test(mobile)) {
    console.error('Usage: npm run sms:test -- 9876543210');
    process.exit(2);
  }

  const s = sms.status();
  if (!s.configured) {
    console.error('MSG91 is not configured. Set these in backend/.env:');
    if (!s.hasAuthKey) console.error('  MSG91_AUTH_KEY');
    if (!s.hasTemplateId) console.error('  MSG91_TEMPLATE_ID');
    console.error('\nSee backend/MSG91_SETUP.md');
    process.exit(2);
  }

  const code = String(Math.floor(1000 + Math.random() * 9000));
  console.log(`Sending ${code} to ${sms.toMsisdn(mobile, s.countryCode)}`);
  console.log(`sender: ${s.senderId || '(from template)'}`);

  try {
    const { requestId } = await sms.sendOtp({ mobile, otp: code, ttlSeconds: 300 });
    console.log(`\nMSG91 accepted it. Request id: ${requestId}`);
    console.log('If nothing arrives within a minute, that id is what their');
    console.log('support needs — the message left here successfully.');
  } catch (err) {
    console.error(`\nMSG91 refused: ${err.message}`);
    if (err.body) console.error(JSON.stringify(err.body, null, 2));
    process.exit(1);
  }
})();
