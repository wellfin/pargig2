import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

class ApiException implements Exception {
  final String message;
  final int? status;
  ApiException(this.message, [this.status]);
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
    return uri.replace(queryParameters: query.map(
      (k, v) => MapEntry(k, v?.toString() ?? ''),
    ));
  }

  static dynamic _decode(http.Response r) {
    final body = r.body.isEmpty ? null : jsonDecode(r.body);
    if (r.statusCode >= 200 && r.statusCode < 300) return body;
    final msg = body is Map && body['message'] != null
        ? body['message'].toString()
        : 'Request failed (${r.statusCode})';
    throw ApiException(msg, r.statusCode);
  }

  static Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    final r = await http.get(_uri(path, query), headers: _headers(json: false));
    return _decode(r);
  }

  static Future<dynamic> post(String path, Map<String, dynamic> body) async {
    final r = await http.post(_uri(path), headers: _headers(), body: jsonEncode(body));
    return _decode(r);
  }

  static Future<dynamic> put(String path, Map<String, dynamic> body) async {
    final r = await http.put(_uri(path), headers: _headers(), body: jsonEncode(body));
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
