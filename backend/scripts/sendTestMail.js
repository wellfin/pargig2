/**
 * Check that SMTP actually works, before a locked-out admin finds out
 * that it does not.
 *
 *   npm run mail:test                 # connect and authenticate only
 *   npm run mail:test you@example.com # also send one real message
 *
 * The forgot-password flow deliberately swallows mail failures — it
 * must answer identically whether or not an account exists, so it
 * cannot report that the mail server refused. That makes it the wrong
 * place to discover a wrong password or an unverified From address.
 * This is the right place.
 *
 * Never prints SMTP_PASS. The status line shows whether credentials
 * are present, not what they are.
 */
require('dotenv').config();

const mailer = require('../utils/mailer');

(async () => {
  const s = mailer.status();
  console.log('\nSMTP configuration');
  console.log('  host:        ', s.host || '(not set)');
  console.log('  port:        ', s.port, s.secure ? '(implicit TLS)' : '(STARTTLS)');
  console.log('  credentials: ', s.hasCredentials ? 'present' : 'none');
  console.log('  from:        ', s.from || '(not set)');

  if (!s.configured) {
    console.error(
      '\nNot configured. SMTP_HOST and MAIL_FROM are both required.\n' +
      'Until they are set, the admin reset code is not emailed — it comes\n' +
      'back in the API response, and only when NODE_ENV is not production.',
    );
    process.exit(1);
  }

  try {
    await mailer.verify();
    console.log('\n  + connection and login OK');
  } catch (err) {
    console.error('\n  - FAILED:', err.message);
    console.error(
      '\nUsual causes: wrong port for the TLS mode (587 vs 465), a\n' +
      'password that is the account password where the provider wants an\n' +
      'app-specific or SMTP-only one, or outbound 587/465 blocked by the\n' +
      'server firewall or security group.',
    );
    process.exit(1);
  }

  const to = (process.argv[2] || '').trim();
  if (!to) {
    console.log('\nPass an address to send a real test message:');
    console.log('  npm run mail:test you@example.com\n');
    return;
  }

  try {
    const info = await mailer.sendMail({
      to,
      subject: 'Pargig SMTP test',
      text:
        'This is a test from the Pargig backend.\n\n' +
        'If you are reading it, admin password reset codes will arrive.\n\n' +
        'Check that it landed in the inbox and not in spam — a reset code\n' +
        'in a spam folder is the same as no reset code.',
    });
    console.log(`\n  + sent to ${to}`);
    console.log('  messageId:', info.messageId);
    console.log('\nCheck the spam folder too, not just the inbox.\n');
  } catch (err) {
    console.error('\n  - send FAILED:', err.message);
    console.error(
      '\nLogin worked, so this is about the message rather than the\n' +
      'connection — most often a MAIL_FROM address the provider has not\n' +
      'verified, or a sending sandbox that only allows verified\n' +
      'recipients (Amazon SES does this until you ask to leave it).',
    );
    process.exit(1);
  }
})().catch((e) => {
  console.error('ERROR', e.message);
  process.exit(1);
});
