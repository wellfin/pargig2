import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  // One-time fee (₹) the job giver pays to boost a post for 3x visibility.
  // Must match the Boost card / review on the Post Job screen.
  static const int boostFee = 50;

  // Production EC2 backend — what the app uses when no --dart-define is
  // passed at build/run time (normal release builds, or `flutter run`
  // without extra flags).
  static const _prodApiBase = 'http://52.66.245.202';

  // Compile-time default (set with --dart-define=API_BASE=...).
  // - Production APKs (no --dart-define): point at the live server above.
  // - Android emulator dev: build with --dart-define=API_BASE=http://10.0.2.2:5014
  // - iOS sim dev: --dart-define=API_BASE=http://127.0.0.1:5014
  // - Real phone on Wi-Fi (laptop backend): --dart-define=API_BASE=http://192.168.x.x:5014
  static const _defaultApiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: _prodApiBase,
  );

  // Whether this run/build explicitly passed --dart-define=API_BASE=...
  // rather than falling through to the hardcoded production default.
  static const _hasExplicitDartDefine = _defaultApiBase != _prodApiBase;

  static String _apiBase = _defaultApiBase;

  /// Current API base, e.g. "http://192.168.1.11:5014". No trailing slash.
  static String get apiBase => _apiBase;
  static String get apiUrl => '$_apiBase/api';
  static String get defaultApiBase => _defaultApiBase;

  // Addresses that only resolve on the machine running the backend. A
  // real handset can never reach these, so a leftover dev override
  // pointing at one would brick a production install with no obvious
  // cause — see [load].
  static const _devOnlyHosts = ['10.0.2.2', '127.0.0.1', 'localhost'];

  static bool _isDevOnly(String base) {
    final host = Uri.tryParse(base)?.host ?? '';
    return _devOnlyHosts.contains(host);
  }

  /// Call once during app start, before any API calls, to load the
  /// user-configured value (if any) from SharedPreferences.
  ///
  /// An explicit --dart-define=API_BASE=... (e.g. a USB dev `flutter run`
  /// pointed at a laptop's LAN IP) always wins over whatever was
  /// previously saved via the in-app Server Settings screen — otherwise a
  /// saved override would silently swallow the --dart-define on every
  /// dev run.
  ///
  /// With nothing saved, the production default is written to disk on
  /// first launch, so a fresh install is already pointed at the live
  /// backend without anyone opening Server Settings.
  static Future<void> load() async {
    if (_hasExplicitDartDefine) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('api_base');
      if (saved == null || saved.trim().isEmpty) {
        // Fresh install: persist the default so "Currently saved" on the
        // Server Settings screen is the truth, not just a fallback.
        _apiBase = _defaultApiBase;
        await prefs.setString('api_base', _defaultApiBase);
        return;
      }
      final normalized = _normalize(saved);
      // A release APK on a real phone can't reach an emulator or loopback
      // address, so drop that override rather than failing every request.
      // Debug builds keep it — that's where it's deliberately set.
      if (kReleaseMode && _isDevOnly(normalized)) {
        _apiBase = _defaultApiBase;
        await prefs.setString('api_base', _defaultApiBase);
        return;
      }
      _apiBase = normalized;
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
