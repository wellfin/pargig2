import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  // Compile-time default (set with --dart-define=API_BASE=...).
  // - Production APKs (no --dart-define): point at the live server below.
  // - Android emulator dev: build with --dart-define=API_BASE=http://10.0.2.2:5014
  // - iOS sim dev: --dart-define=API_BASE=http://127.0.0.1:5014
  // - Real phone on Wi-Fi (laptop backend): --dart-define=API_BASE=http://192.168.x.x:5014
  static const _defaultApiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://3.111.246.106',
  );

  static String _apiBase = _defaultApiBase;

  /// Current API base, e.g. "http://192.168.1.11:5014". No trailing slash.
  static String get apiBase => _apiBase;
  static String get apiUrl => '$_apiBase/api';
  static String get defaultApiBase => _defaultApiBase;

  /// Call once during app start, before any API calls, to load the
  /// user-configured value (if any) from SharedPreferences.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('api_base');
      if (saved != null && saved.trim().isNotEmpty) {
        _apiBase = _normalize(saved);
      }
    } catch (_) {
      // shared_preferences may not be ready in some test envs — non-fatal
    }
  }

  /// Persist a new API base. Pass an empty string to fall back to the
  /// compile-time default.
  static Future<void> setApiBase(String value) async {
    final normalized = _normalize(value);
    final prefs = await SharedPreferences.getInstance();
    if (normalized.isEmpty) {
      _apiBase = _defaultApiBase;
      await prefs.remove('api_base');
    } else {
      _apiBase = normalized;
      await prefs.setString('api_base', normalized);
    }
  }

  static String _normalize(String v) {
    var s = v.trim();
    s = s.replaceAll(RegExp(r'/+$'), ''); // strip trailing slashes
    return s;
  }
}

class AppColors {
  static const primary = Color(0xFFFF6B1A);
  static const primaryDark = Color(0xFFD9540A);
  static const text = Color(0xFF222222);
  static const muted = Color(0xFF707684);
  static const border = Color(0xFFE6E8EE);
  static const green = Color(0xFF16A34A);
  static const red = Color(0xFFDC2626);
}
