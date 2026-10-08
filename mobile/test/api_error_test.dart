import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pargig/api/api_client.dart';

/// Runs a response through the same decoding the client uses, by calling
/// the public surface with a stubbed response.
///
/// `_decode` is private, so this exercises it the way every request does:
/// through `decodeForTest`, which exists only so this behaviour can be
/// pinned without loosening the real API.
void main() {
  group('non-JSON responses', () {
    test('an nginx 502 page reads as a server problem, not a parse error', () {
      // The exact failure seen on the phone: the gateway was up, the API
      // behind it was not, and the user was shown
      // "FormatException: Unexpected character (at character 1) <html>".
      final html =
          '<html>\n<head><title>502 Bad Gateway</title></head>\n'
          '<body><center><h1>502 Bad Gateway</h1></center></body>\n</html>';

      expect(
        () => ApiClient.decodeForTest(http.Response(html, 502)),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', contains('not responding'))
              .having((e) => e.message, 'message', isNot(contains('html')))
              .having((e) => e.status, 'status', 502),
        ),
      );
    });

    test('503 and 504 read the same way', () {
      for (final code in [503, 504]) {
        expect(
          () => ApiClient.decodeForTest(http.Response('<html></html>', code)),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              contains('not responding'),
            ),
          ),
          reason: '$code should read as the server being unavailable',
        );
      }
    });

    test('an HTML 404 points at the server address', () {
      expect(
        () => ApiClient.decodeForTest(http.Response('<html>nope</html>', 404)),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('server address'),
          ),
        ),
      );
    });

    test('an HTML page returned with 200 is still an error', () {
      // A Wi-Fi sign-in page, or an address pointing at a website rather
      // than the API. Returning it as success would fail further in with
      // a stranger message.
      expect(
        () => ApiClient.decodeForTest(http.Response('<html>login</html>', 200)),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('JSON responses still behave', () {
    test('a successful body is returned as decoded JSON', () {
      final res = ApiClient.decodeForTest(
        http.Response(jsonEncode({'ok': true, 'n': 3}), 200),
      );
      expect(res['ok'], isTrue);
      expect(res['n'], 3);
    });

    test('an empty 200 body is null, not an error', () {
      expect(ApiClient.decodeForTest(http.Response('', 200)), isNull);
    });

    test("the server's own message is preserved", () {
      expect(
        () => ApiClient.decodeForTest(
          http.Response(jsonEncode({'message': 'Invalid PIN'}), 400),
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', 'Invalid PIN')
              .having((e) => e.status, 'status', 400),
        ),
      );
    });

    test('extra fields on an error body survive for the caller', () {
      // The start-PIN gate sends back the scheduled time this way.
      expect(
        () => ApiClient.decodeForTest(
          http.Response(
            jsonEncode({'message': 'Too early', 'scheduledAt': '2026-10-09'}),
            425,
          ),
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.data?['scheduledAt'],
            'scheduledAt',
            '2026-10-09',
          ),
        ),
      );
    });
  });
}
