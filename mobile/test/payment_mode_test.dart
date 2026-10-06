import 'package:flutter_test/flutter_test.dart';
import 'package:pargig/utils/payment_mode.dart';

Map<String, dynamic> job({
  String priceMode = 'fixed',
  num? finalPrice,
  num? proposedBudget,
  Map<String, dynamic>? payment,
}) => {
  'priceMode': priceMode,
  'finalPrice': ?finalPrice,
  'proposedBudget': ?proposedBudget,
  'payment': payment,
};

void main() {
  group('payment mode label', () {
    test('reads the canonical mode', () {
      expect(paymentModeLabel(job(payment: {'mode': 'upi'})), 'UPI');
      expect(paymentModeLabel(job(payment: {'mode': 'card'})), 'Card');
      expect(
        paymentModeLabel(job(payment: {'mode': 'netbanking'})),
        'Net Banking',
      );
      expect(paymentModeLabel(job(payment: {'mode': 'wallet'})), 'Wallet');
      expect(paymentModeLabel(job(payment: {'mode': 'cash'})), 'COD');
    });

    test('cash is COD however it is flagged', () {
      expect(paymentModeLabel(job(payment: {'isCod': true})), 'COD');
      expect(
        paymentModeLabel(job(payment: {'mode': 'other', 'isCod': true})),
        'COD',
      );
    });

    test('falls back to the printed label for older payments', () {
      expect(
        paymentModeLabel(job(payment: {'method': 'HDFC Debit Card ****9232'})),
        'Card',
      );
      expect(paymentModeLabel(job(payment: {'method': 'PhonePe'})), 'UPI');
      expect(paymentModeLabel(job(payment: {'method': 'Online'})), 'UPI');
    });

    test('no payment means no mode to name', () {
      expect(paymentModeLabel(job()), isNull);
      expect(paymentModeLabel(job(payment: {'mode': 'other'})), isNull);
    });
  });

  group('amount shown on a card', () {
    test('prefers what was actually paid', () {
      expect(jobAmount(job(finalPrice: 500, payment: {'amount': 850})), 850);
    });

    test('an OPEN-price job that settled shows the amount, not "Open"', () {
      // The bug this fixes: the card read "Open" on a finished job.
      final settled = job(
        priceMode: 'open',
        payment: {'amount': 850, 'isCod': true},
      );
      expect(jobAmount(settled), 850);
      expect(priceSubtitle(settled), 'Open · COD');
    });

    test('falls back to the agreed price, then the opening budget', () {
      expect(jobAmount(job(finalPrice: 12)), 12);
      expect(jobAmount(job(proposedBudget: 300)), 300);
    });

    test('adds the tip and boost fee to an unpaid job only', () {
      expect(jobAmount(job(finalPrice: 100), extra: 30), 130);
      // Already paid: the payment is the whole total, so nothing is
      // added on top or the tip would be counted twice.
      expect(
        jobAmount(job(finalPrice: 100, payment: {'amount': 130}), extra: 30),
        130,
      );
    });

    test('an open job with no budget has no amount', () {
      expect(jobAmount(job(priceMode: 'open')), isNull);
      expect(jobAmount(job(finalPrice: 0)), isNull);
    });
  });

  group('the line under the amount', () {
    test('states how the price was agreed before payment', () {
      expect(priceSubtitle(job()), 'Fixed');
      expect(priceSubtitle(job(priceMode: 'open')), 'Open');
    });

    test('adds how it was settled once paid', () {
      expect(priceSubtitle(job(payment: {'mode': 'upi'})), 'Fixed · UPI');
      expect(
        priceSubtitle(job(priceMode: 'open', payment: {'mode': 'card'})),
        'Open · Card',
      );
    });

    test('never prints a bare separator', () {
      expect(priceSubtitle(job()).contains('·'), isFalse);
    });
  });
}
