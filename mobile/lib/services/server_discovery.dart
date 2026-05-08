import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config.dart';

/// Auto-detects the Pargig backend's URL on the local network.
///
/// Probes (in parallel) a curated list of candidates plus the device's own
/// /24 subnet, looking for a host that answers `/api/health` with the right
/// signature (`{ok: true, app: 'pargig'}`). The first match is persisted to
/// [AppConfig] so subsequent launches skip the scan.
class ServerDiscovery {
  ServerDiscovery._();

  static const int _backendPort = 5014;
  static const Duration _probeTimeout = Duration(milliseconds: 1500);
  static const Duration _totalTimeout = Duration(seconds: 8);
  static const int _batchSize = 32;

  static bool _running = false;
  static bool get isRunning => _running;

  /// Try the saved URL first (longer timeout, single probe). If it responds,
  /// nothing else needs to happen.
  static Future<bool> verifyCurrent() async {
    return _probe(AppConfig.apiBase, timeout: const Duration(seconds: 3));
  }

  /// Full discovery: tries saved URL, common dev addresses, and every IP in
  /// the device's wireless /24 subnet. Returns true if a backend was found.
  static Future<bool> discover() async {
    if (_running) return false;
    _running = true;
    try {
      // 1. Saved value first — fast path, no scan needed if it still works.
      if (await verifyCurrent()) return true;

      // 2. Build the broader candidate list and probe in parallel batches.
      final candidates = await _buildCandidates();
      final found = await _firstResponder(candidates);
      if (found != null) {
        if (found != AppConfig.apiBase) {
          await AppConfig.setApiBase(found);
        }
        return true;
      }
      return false;
    } finally {
      _running = false;
    }
  }

  static Future<List<String>> _buildCandidates() async {
    final candidates = <String>{};

    // Common dev hosts.
    candidates.add('http://10.0.2.2:$_backendPort'); // Android emulator
    candidates.add('http://127.0.0.1:$_backendPort'); // iOS simulator / desktop

    // Device's own /24 subnet — by far the most likely place the dev PC is.
    final deviceIp = await _deviceIPv4();
    if (deviceIp != null) {
      final parts = deviceIp.split('.');
      if (parts.length == 4) {
        final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
        for (int i = 1; i <= 254; i++) {
          final ip = '$subnet.$i';
          if (ip == deviceIp) continue;
          candidates.add('http://$ip:$_backendPort');
        }
      }
    }

    return candidates.toList(growable: false);
  }

  static Future<String?> _deviceIPv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      // Prefer wlan/wifi-style interfaces over rmnet/cellular.
      InternetAddress? best;
      for (final iface in interfaces) {
        final lower = iface.name.toLowerCase();
        for (final addr in iface.addresses) {
          if (addr.isLoopback || addr.isLinkLocal) continue;
          if (lower.contains('wlan') || lower.contains('wi') || lower.contains('en')) {
            return addr.address;
          }
          best ??= addr;
        }
      }
      return best?.address;
    } catch (_) {
      return null;
    }
  }

  /// Returns the first candidate URL that responds with our health signature.
  /// Probes in batches so we don't open hundreds of sockets at once on mobile.
  static Future<String?> _firstResponder(List<String> candidates) async {
    final completer = Completer<String?>();
    final stopwatch = Stopwatch()..start();
    int index = 0;

    Future<void> runBatch() async {
      while (index < candidates.length && !completer.isCompleted) {
        if (stopwatch.elapsed > _totalTimeout) break;
        final batch = candidates.skip(index).take(_batchSize).toList();
        index += batch.length;
        await Future.wait(batch.map((url) async {
          if (completer.isCompleted) return;
          if (await _probe(url)) {
            if (!completer.isCompleted) completer.complete(url);
          }
        }));
      }
      if (!completer.isCompleted) completer.complete(null);
    }

    unawaited(runBatch());
    return completer.future.timeout(
      _totalTimeout,
      onTimeout: () => null,
    );
  }

  static Future<bool> _probe(
    String baseUrl, {
    Duration timeout = _probeTimeout,
  }) async {
    if (baseUrl.isEmpty) return false;
    try {
      final resp = await http
          .get(Uri.parse('$baseUrl/api/health'))
          .timeout(timeout);
      if (resp.statusCode != 200) return false;
      final body = jsonDecode(resp.body);
      return body is Map && body['ok'] == true && body['app'] == 'pargig';
    } catch (_) {
      return false;
    }
  }
}
