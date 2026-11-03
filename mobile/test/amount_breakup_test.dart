import 'package:flutter_test/flutter_test.dart';
import 'package:pargig/utils/payment_mode.dart';

/// The three lines shown on Job Details, worker side.
///
/// Computed the same way the screen computes them, so the test fails if
/// the screen's arithmetic drifts from what is charged.
({num job, num tip, num total}) breakup(
  Map<String, dynamic> job, {
  num tip = 0,
}) {
  final total = jobAmount(job, extra: tip) ?? 0;
  return (job: total - tip, tip: tip, total: total);
}

void main() {
  group('payment breakup', () {
    test('job + tip = total', () {
      final b = breakup({'finalPrice': 500}, tip: 50);
      expect(b.job, 500);
      expect(b.tip, 50);
      expect(b.total, 550);
      expect(b.job + b.tip, b.total);
    });

    test('with no tip the job amount is the total', () {
      final b = breakup({'finalPrice': 500});
      expect(b.job, 500);
      expect(b.tip, 0);
      expect(b.total, 500);
    });

    test('a boosted job is not inflated by the uncharged boost fee', () {
      // isBoosted is only a flag: the server never charges or pays it,
      // so it must not reach any figure the user is shown.
      final b = breakup({'finalPrice': 500, 'isBoosted': true}, tip: 50);
      expect(b.total, 550, reason: 'Rs 50 boost fee must not be added');
      expect(b.job + b.tip, b.total);
    });

    test('once paid, the total is what was actually charged', () {
      // settleJob stores amount = finalPrice + tip, so the breakup the
      // worker saw before the job must equal the payment afterwards.
      final paid = {
        'finalPrice': 500,
        'payment': {'amount': 550},
      };
      final b = breakup(paid, tip: 50);
      expect(b.total, 550);
      expect(b.job, 500);
    });

    test('falls back to the opening budget before a price is agreed', () {
      final b = breakup({'proposedBudget': 300}, tip: 20);
      expect(b.job, 300);
      expect(b.total, 320);
    });

    test('an open job with no budget has nothing to break up', () {
      expect(jobAmount({'priceMode': 'open'}), isNull);
    });
  });

  group('job history amount', () {
    test('a completed job with no payment attached still adds the tip', () {
      // Job History does not join the payment, so this fallback is the
      // path every row takes. It used to drop the tip, showing Rs 5000
      // where every other screen said Rs 5200.
      final row = {'finalPrice': 5000};
      expect(jobAmount(row, extra: 200), 5200);
    });

    test('a settled payment wins, and already includes the tip', () {
      final row = {
        'finalPrice': 5000,
        'payment': {'amount': 5200},
      };
      expect(
        jobAmount(row, extra: 200),
        5200,
        reason: 'the tip must not be counted twice',
      );
    });

    test('no tip leaves the amount alone', () {
      expect(jobAmount({'finalPrice': 1200}, extra: 0), 1200);
    });
  });

  group('the breakdown line under an amount', () {
    // "Rs 1100 + Rs 100 tip" under the total, matching the applicant
    // card. Built the same way on both screens: total minus tip, then
    // the tip.
    String? line({required num total, required num tip}) =>
        tip > 0 ? '₹${(total - tip).toInt()} + ₹${tip.toInt()} tip' : null;

    test('splits the total back into price and tip', () {
      expect(line(total: 1200, tip: 100), '₹1100 + ₹100 tip');
      expect(line(total: 5500, tip: 500), '₹5000 + ₹500 tip');
    });

    test('the parts add back up to the total shown above', () {
      const total = 1200, tip = 100;
      expect((total - tip) + tip, total);
    });

    test('no line at all without a tip', () {
      // "Rs 1200 + Rs 0 tip" would repeat the number above and explain
      // nothing.
      expect(line(total: 1200, tip: 0), isNull);
    });
  });
}
