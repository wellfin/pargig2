/**
 * Canonical payment modes.
 *
 * `Payment.method` is a human label chosen for the receipt ("PhonePe",
 * "HDFC Debit Card ****9232"). It is fine to print and useless to branch
 * on. `Payment.mode` is the machine value the refund router switches on,
 * and the field reconciliation groups by.
 *
 * Refundability is a property of the mode, which is why it lives here
 * rather than being re-derived at each call site:
 *   upi / card / netbanking -> back through the gateway
 *   wallet                  -> credited straight to the payer's wallet
 *   cash                    -> not refundable by the platform; the money
 *                              never passed through it
 */
const PAYMENT_MODES = ['upi', 'card', 'netbanking', 'wallet', 'cash', 'other'];

const GATEWAY_MODES = ['upi', 'card', 'netbanking'];

/** Modes the platform can refund on its own. */
const REFUNDABLE_MODES = [...GATEWAY_MODES, 'wallet'];

const MODE_LABELS = {
  upi: 'UPI',
  card: 'Card',
  netbanking: 'Net Banking',
  wallet: 'Pargig Wallet',
  cash: 'Cash',
  other: 'Other',
};

/**
 * Works out the mode of a payment.
 *
 * Prefers an explicit mode from the caller, then the cash flag, then
 * sniffs the human label — older payments predate the `mode` field and
 * still have to reconcile, so the label is the fallback rather than a
 * shrug.
 */
function resolvePaymentMode({ mode, isCod, method } = {}) {
  const explicit = String(mode || '').trim().toLowerCase();
  if (PAYMENT_MODES.includes(explicit)) return explicit;
  if (explicit === 'cod') return 'cash';

  if (isCod === true) return 'cash';

  const label = String(method || '').trim().toLowerCase();
  if (!label) return isCod === false ? 'other' : 'other';

  if (/\b(cash|cod|hand)\b/.test(label)) return 'cash';
  if (/wallet/.test(label) && !/phonepe|paytm|gpay|amazon/.test(label)) {
    return 'wallet';
  }
  if (/card|visa|master|rupay|maestro|amex|debit|credit/.test(label)) {
    return 'card';
  }
  if (/upi|vpa|phonepe|gpay|google ?pay|paytm|bhim|@/.test(label)) return 'upi';
  if (/net ?banking|neft|imps|rtgs|bank transfer/.test(label)) {
    return 'netbanking';
  }
  // "Online" with nothing more specific: treat as UPI, which is what the
  // app's online flow actually uses, so it stays refundable.
  if (/online/.test(label)) return 'upi';
  return 'other';
}

const isRefundableMode = (mode) => REFUNDABLE_MODES.includes(mode);
const isGatewayMode = (mode) => GATEWAY_MODES.includes(mode);
const modeLabel = (mode) => MODE_LABELS[mode] || 'Other';

module.exports = {
  PAYMENT_MODES,
  GATEWAY_MODES,
  REFUNDABLE_MODES,
  MODE_LABELS,
  resolvePaymentMode,
  isRefundableMode,
  isGatewayMode,
  modeLabel,
};
