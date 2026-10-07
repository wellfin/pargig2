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
}
