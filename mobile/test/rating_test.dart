import 'package:flutter_test/flutter_test.dart';
import 'package:pargig/utils/rating.dart';

void main() {
  group('displayRating', () {
    test('a brand-new user shows 5.0, not 0.0', () {
      // What the backend actually stores for someone never rated.
      expect(displayRating({'average': 0, 'count': 0}), '5.0');
      expect(displayRating(null), '5.0');
      expect(displayRating({}), '5.0');
      expect(displayRating(0), '5.0');
    });

    test('a rated user shows their real average, never the default', () {
      expect(displayRating({'average': 4.6, 'count': 24}), '4.6');
      expect(displayRating({'average': 3.0, 'count': 2}), '3.0');
      expect(displayRating({'average': 5.0, 'count': 9}), '5.0');
    });

    test('a genuinely poor rating is not flattered upward', () {
      // The default must never mask real feedback: 1.2 stays 1.2.
      expect(displayRating({'average': 1.2, 'count': 7}), '1.2');
      expect(displayRating({'average': 2.5, 'count': 1}), '2.5');
    });

    test('accepts the flattened numeric shape some endpoints return', () {
      expect(displayRating(4.2), '4.2');
      expect(displayRating(5), '5.0');
    });

    test('rounds to one decimal', () {
      expect(displayRating({'average': 4.6666, 'count': 3}), '4.7');
      expect(displayRating({'average': 3.44, 'count': 3}), '3.4');
    });

    test('an average with no count is treated as never-rated', () {
      // Defensive: stale rows where average was written but count wasn't.
      expect(displayRating({'average': 4.5, 'count': 0}), '5.0');
    });
  });

  group('ratingCountValue / hasRatings', () {
    test('reports the real number of reviews', () {
      expect(ratingCountValue({'average': 4.6, 'count': 24}), 24);
      expect(ratingCountValue({'average': 0, 'count': 0}), 0);
      expect(ratingCountValue(null), 0);
      expect(hasRatings({'average': 4.6, 'count': 24}), isTrue);
      expect(hasRatings({'average': 0, 'count': 0}), isFalse);
    });
  });

  group('ratingCountLabel', () {
    test('stays empty while unrated so nobody advertises (0)', () {
      expect(ratingCountLabel({'average': 0, 'count': 0}), '');
      expect(ratingCountLabel({'average': 4.6, 'count': 24}), '(24)');
    });
  });
}
