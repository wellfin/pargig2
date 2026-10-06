import 'package:flutter_test/flutter_test.dart';
import 'package:pargig/screens/post_job_screen.dart';

void main() {
  group('validateJobTitle — letters and spaces only', () {
    test('rejects the reported cases', () {
      // Both of these were posted as real job titles.
      expect(validateJobTitle('2345567c ko poiijggyjhu'), isNotNull);
      expect(validateJobTitle('16161515151'), isNotNull);
      expect(validateJobTitle('171717171771'), isNotNull);
    });

    test('rejects any digit, even inside a sensible phrase', () {
      // The strict rule bites here on purpose — these read fine but are
      // refused because the title must be alphabetic.
      expect(validateJobTitle('AC repair for 2BHK'), isNotNull);
      expect(validateJobTitle('Fix 3 taps'), isNotNull);
      expect(validateJobTitle('Sofa shifting to 3rd floor'), isNotNull);
    });

    test('rejects punctuation, symbols and emoji', () {
      expect(validateJobTitle('Plumbing - kitchen sink'), isNotNull);
      expect(validateJobTitle("Painter's help needed"), isNotNull);
      expect(validateJobTitle('Wiring & socket work'), isNotNull);
      expect(validateJobTitle('Repair (urgent)'), isNotNull);
      expect(validateJobTitle('@#\$%^&*'), isNotNull);
      expect(validateJobTitle('Cleaning 🧹'), isNotNull);
    });

    test('rejects empty and too short', () {
      expect(validateJobTitle(''), isNotNull);
      expect(validateJobTitle('   '), isNotNull);
      expect(validateJobTitle('ab'), isNotNull);
    });

    test('accepts plain alphabetic titles', () {
      expect(validateJobTitle('Home Deep Cleaning'), isNull);
      expect(validateJobTitle('Plumber needed'), isNull);
      expect(validateJobTitle('Need a driver for the day'), isNull);
      expect(validateJobTitle('Cleaning'), isNull);
    });

    test('puts no practical ceiling on length', () {
      expect(validateJobTitle('a' * 81), isNull);
      expect(validateJobTitle('a' * 2000), isNull);
    });

    test('still stops a pathological paste', () {
      expect(validateJobTitle('a' * 2001), isNotNull);
    });

    test('trims before judging', () {
      expect(validateJobTitle('  Home Cleaning  '), isNull);
      expect(validateJobTitle('  12345  '), isNotNull);
    });
  });

  group('validateJobDescription', () {
    test('empty is the caller\'s problem, not this function\'s', () {
      // A recorded voice note can stand in for typed text, so blank is
      // valid here and handled by the screen instead.
      expect(validateJobDescription(''), isNull);
      expect(validateJobDescription('   '), isNull);
    });

    test('rejects numeric mash and too-short text', () {
      expect(validateJobDescription('171717171771'), isNotNull);
      expect(validateJobDescription('short'), isNotNull);
    });

    test('still allows digits and punctuation — titles only are strict', () {
      expect(
        validateJobDescription('Need complete deep cleaning of my 2BHK '
            'apartment including kitchen and bathrooms.'),
        isNull,
      );
    });
  });
}
