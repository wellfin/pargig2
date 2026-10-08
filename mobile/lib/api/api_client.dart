import 'dart:convert';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

class ApiException implements Exception {
  final String message;
  final int? status;

  /// The whole error body, for the few cases where the server sends more
  /// than a sentence — the start PIN refused before its scheduled time
  /// returns that time so the app can name it rather than paraphrase.
  final Map<String, dynamic>? data;

  ApiException(this.message, [this.status, this.data]);
  @override
  String toString() => message;
}

class ApiClient {
  static String? _token;

  static Future<void> setToken(String? token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    if (token == null) {
      await prefs.remove('token');
    } else {
      await prefs.setString('token', token);
    }
  }

  static Future<String?> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    return _token;
  }

  static String? get token => _token;

  static Map<String, String> _headers({bool json = true}) {
    return {
      if (json) 'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    };
  }

  static Uri _uri(String path, [Map<String, dynamic>? query]) {
    final uri = Uri.parse('${AppConfig.apiUrl}$path');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(
      queryParameters: query.map((k, v) => MapEntry(k, v?.toString() ?? '')),
    );
  }

  /// Test-only entry point to [_decode], so response handling can be
  /// pinned without exposing it to the rest of the app.
  @visibleForTesting
  static dynamic decodeForTest(http.Response r) => _decode(r);

  static dynamic _decode(http.Response r) {
    // The API speaks JSON, but what comes back is not always the API.
    // A gateway error page, a captive portal sign-in page, or a proxy
    // notice all arrive as HTML, and decoding one threw a raw
    // "FormatException: Unexpected character (at character 1) <html>"
    // at the user — which names the problem in a language only a
    // developer reads, and points at the wrong layer entirely.
    dynamic body;
    if (r.body.isNotEmpty) {
      try {
        body = jsonDecode(r.body);
      } catch (_) {
        throw ApiException(_notJsonMessage(r), r.statusCode);
      }
    }

    if (r.statusCode >= 200 && r.statusCode < 300) return body;
    final msg = body is Map && body['message'] != null
        ? body['message'].toString()
        : 'Request failed (${r.statusCode})';
    throw ApiException(
      msg,
      r.statusCode,
      body is Map ? Map<String, dynamic>.from(body) : null,
    );
  }

  /// What to tell someone when the server answered with something other
  /// than JSON.
  ///
  /// The status code is the useful part: 502/503/504 from a reverse
  /// proxy means the API behind it is down or restarting, which is a
  /// wait-and-retry, not anything the user did wrong.
  static String _notJsonMessage(http.Response r) {
    switch (r.statusCode) {
      case 502:
      case 503:
      case 504:
        return 'The server is not responding right now. '
            'Please try again in a moment.';
      case 404:
        return 'Could not reach the Pargig service at this address. '
            'Check the server address in Settings.';
    }
    if (r.statusCode >= 500) {
      return 'The server ran into a problem. Please try again.';
    }
    // A 2xx that is not JSON usually means the address points at a web
    // page rather than the API — a wrong host, or a Wi-Fi login page.
    return 'Unexpected response from the server (${r.statusCode}). '
        'Check the server address in Settings.';
  }

  static Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    final r = await http.get(_uri(path, query), headers: _headers(json: false));
    return _decode(r);
  }

  static Future<dynamic> post(String path, Map<String, dynamic> body) async {
    final r = await http.post(
      _uri(path),
      headers: _headers(),
      body: jsonEncode(body),
    );
    return _decode(r);
  }

  static Future<dynamic> put(String path, Map<String, dynamic> body) async {
    final r = await http.put(
      _uri(path),
      headers: _headers(),
      body: jsonEncode(body),
    );
    return _decode(r);
  }

  static Future<dynamic> delete(String path) async {
    final r = await http.delete(_uri(path), headers: _headers(json: false));
    return _decode(r);
  }

  /// Multipart upload of a single file. Pass [field] = backend's expected
  /// field name (e.g. "photo" or "file"). [filePath] is the local path on
  /// disk. Returns the decoded JSON response.
  static Future<dynamic> postFile(
    String path, {
    required String field,
    required String filePath,
    Map<String, String>? fields,
  }) async {
    final req = http.MultipartRequest('POST', _uri(path));
    if (_token != null) {
      req.headers['Authorization'] = 'Bearer $_token';
    }
    if (fields != null) req.fields.addAll(fields);
    req.files.add(await http.MultipartFile.fromPath(field, filePath));
    final streamed = await req.send();
    final r = await http.Response.fromStream(streamed);
    return _decode(r);
  }
}
