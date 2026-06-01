import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Routing helper — returns ROAD distance between two points (km),
/// matching what Google Maps shows. Uses OSRM's public demo server
/// (https://project-osrm.org) which is free and requires no API key.
///
/// IMPORTANT caveats of the public OSRM instance:
///   - Fair-use rate limit (~1 req/sec per IP). Don't hammer it.
///   - No SLA — occasional 502s.
///   - For production at scale, swap in Google Distance Matrix
///     (requires API key + billing) or self-host OSRM.
///
/// Falls back to `null` on any failure — callers should display
/// haversine as the fallback in that case.
class Routing {
  static const _base = 'https://router.project-osrm.org/route/v1/driving';

  // In-memory cache so we don't re-call the API for the same pair while
  // the user scrolls. Keyed on rounded coords to absorb minor jitter
  // (the rounding gives ~10m bucket size, which is fine for routing).
  static final Map<String, double> _cache = {};

  static String _key(double aLat, double aLng, double bLat, double bLng) =>
      '${aLat.toStringAsFixed(4)},${aLng.toStringAsFixed(4)}'
      '|${bLat.toStringAsFixed(4)},${bLng.toStringAsFixed(4)}';

  /// Returns the road distance in kilometres, or null if the routing
  /// service failed / timed out. Times out at 6s so we never block the
  /// UI for long.
  static Future<double?> roadDistanceKm(
    double aLat,
    double aLng,
    double bLat,
    double bLng,
  ) async {
    final cacheKey = _key(aLat, aLng, bLat, bLng);
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    final uri = Uri.parse(
      '$_base/$aLng,$aLat;$bLng,$bLat?overview=false&alternatives=false',
    );
    try {
      final res = await http.get(uri, headers: {
        // OSRM's demo server asks for an identifying User-Agent.
        'User-Agent': 'Pargig/1.0 (dev)',
      }).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body);
      if (json is! Map) return null;
      final routes = json['routes'];
      if (routes is! List || routes.isEmpty) return null;
      final first = routes.first;
      if (first is! Map) return null;
      final meters = first['distance'];
      if (meters is! num) return null;
      final km = meters / 1000.0;
      _cache[cacheKey] = km;
      return km;
    } catch (_) {
      return null;
    }
  }
}
