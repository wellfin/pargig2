/**
 * Outbound email over SMTP.
 *
 * Built the same way as utils/sms.js, and for the same reasons: the
 * code is generated and checked here, and this module is only the
 * thing that carries it. An outage at the mail provider can delay a
 * password reset; it can never approve one.
 *
 * SMTP rather than a provider's own API because SMTP is the superset —
 * Amazon SES, Zoho, Brevo, Gmail and a plain company mail server all
 * hand out SMTP credentials, so one set of environment variables
 * covers whichever is chosen without another dependency.
 *
 * Environment:
 *   SMTP_HOST      e.g. email-smtp.ap-south-1.amazonaws.com
 *   SMTP_PORT      587 (STARTTLS) or 465 (implicit TLS). Default 587.
 *   SMTP_USER      the SMTP username
 *   SMTP_PASS      the SMTP password
 *   MAIL_FROM      what the recipient sees, e.g. "Pargig <no-reply@pargig.in>"
 *                  Must be an address the provider has verified, or it
 *                  will be rejected or silently filed as spam.
 *
 * Nothing is cached: config is read per call, so a restart is the only
 * thing needed to change providers, and tests can point it at a stub.
 */

const nodemailer = require('nodemailer');

function config() {
  const port = parseInt(process.env.SMTP_PORT || '587', 10);
  return {
    host: (process.env.SMTP_HOST || '').trim(),
    port,
    // 465 is TLS from the first byte; 587 opens plain and upgrades
    // with STARTTLS. Getting this backwards is the usual cause of a
    // connection that hangs instead of failing.
    secure: port === 465,
    user: (process.env.SMTP_USER || '').trim(),
    pass: process.env.SMTP_PASS || '',
    from: (process.env.MAIL_FROM || '').trim(),
    timeoutMs: parseInt(process.env.SMTP_TIMEOUT_MS || '15000', 10),
  };
}

/**
 * A host and a From address are the minimum. Credentials are not
 * required — a mail server on the same network may accept relay from
 * this host without them — but a missing From is always a failure,
 * reported per message, which looks like flaky delivery rather than
 * the configuration mistake it is.
 */
function isConfigured() {
  const c = config();
  return Boolean(c.host && c.from);
}

/** What ops can be shown without leaking the password. */
function status() {
  const c = config();
  return {
    transport: 'smtp',
    configured: isConfigured(),
    host: c.host || null,
    port: c.port,
    secure: c.secure,
    hasCredentials: Boolean(c.user && c.pass),
    from: c.from || null,
  };
}

class MailNotConfiguredError extends Error {
  constructor() {
    super('Email is not configured on this server');
    this.name = 'MailNotConfiguredError';
  }
}

class MailSendError extends Error {
  constructor(message) {
    super(message);
    this.name = 'MailSendError';
  }
}

function transport() {
  const c = config();
  return nodemailer.createTransport({
    host: c.host,
    port: c.port,
    secure: c.secure,
    auth: c.user ? { user: c.user, pass: c.pass } : undefined,
    connectionTimeout: c.timeoutMs,
    greetingTimeout: c.timeoutMs,
    socketTimeout: c.timeoutMs,
  });
}

/**
 * Send one message. Throws MailNotConfiguredError when there is no
 * server to send through, and MailSendError when there is one and it
 * refused — the caller distinguishes them, because the first is a
 * development machine behaving normally and the second is a fault.
 */
async function sendMail({ to, subject, text, html }) {
  if (!isConfigured()) throw new MailNotConfiguredError();
  const c = config();
  try {
    const info = await transport().sendMail({
      from: c.from,
      to,
      subject,
      text,
      html,
    });
    return { messageId: info.messageId, accepted: info.accepted || [] };
  } catch (err) {
    throw new MailSendError(err.message || 'Mail server refused the message');
  }
}

/** Opens a connection and authenticates, without sending anything. */
async function verify() {
  if (!isConfigured()) throw new MailNotConfiguredError();
  await transport().verify();
  return true;
}

module.exports = {
  sendMail,
  verify,
  isConfigured,
  status,
  MailNotConfiguredError,
  MailSendError,
};
