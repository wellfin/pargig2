/// How a job was actually paid, in the two or three letters people use.
///
/// Reads the payment summary the backend attaches to a job. Returns null
/// when the job has not been paid yet: there is no mode to name before
/// money moves, and guessing one from what the job *allows* ("Cash or
/// Online") would state a fact that is not yet true.
String? paymentModeLabel(Map<String, dynamic> job) {
  final payment = job['payment'];
  if (payment is! Map) return null;

  // Cash is the one whose common name is not its machine value: the app
  // and the receipts call it COD throughout.
  if (payment['isCod'] == true) return 'COD';

  switch ((payment['mode'] ?? '').toString()) {
    case 'upi':
      return 'UPI';
    case 'card':
      return 'Card';
    case 'netbanking':
      return 'Net Banking';
    case 'wallet':
      return 'Wallet';
    case 'cash':
      return 'COD';
  }

  // Older payments predate the `mode` field. Falling back to the printed
  // label keeps them showing something true rather than nothing.
  final method = (payment['method'] ?? '').toString().toLowerCase();
  if (method.isEmpty) return null;
  if (method.contains('cash') || method.contains('cod')) return 'COD';
  if (method.contains('card')) return 'Card';
  if (method.contains('net') || method.contains('bank')) return 'Net Banking';
  if (method.contains('wallet')) return 'Wallet';
  if (method.contains('upi') ||
      method.contains('phonepe') ||
      method.contains('gpay') ||
      method.contains('paytm') ||
      method.contains('online')) {
    return 'UPI';
  }
  return null;
}

/// The amount to print for [job], or null when there is genuinely no
/// number yet.
///
/// Prefers what was actually paid over what was asked: an open-price job
/// settled at Rs 850 should read 850, not "Open". Falls back to the
/// agreed price, then the giver's opening budget.
///
/// [extra] carries anything the caller adds on top — the tip, and the
/// boost fee — so one screen's total does not silently differ from
/// another's.
num? jobAmount(Map<String, dynamic> job, {num extra = 0}) {
  final payment = job['payment'];
  if (payment is Map) {
    final paid = payment['amount'];
    if (paid is num && paid > 0) return paid;
  }
  for (final key in ['finalPrice', 'proposedBudget']) {
    final v = job[key];
    if (v is num && v > 0) return v + extra;
  }
  return null;
}

/// "Fixed - COD", "Open - UPI", or just "Fixed" before payment.
///
/// One line under the amount, the same on every screen: how the price
/// was agreed, and how it was settled. The mode half only appears once
/// money has actually moved.
String priceSubtitle(Map<String, dynamic> job) {
  final mode = (job['priceMode'] ?? 'open').toString();
  final agreed = mode == 'fixed' ? 'Fixed' : 'Open';
  final paid = paymentModeLabel(job);
  return paid == null ? agreed : '$agreed · $paid';
}
