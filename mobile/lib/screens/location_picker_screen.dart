import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// A simple text + GPS picker used by Find Work / Hire Workers setup.
///
/// Pops with a `Map<String, dynamic>` of `{lat: double, lng: double,
/// label: String}` when the user makes a selection. Pops with `null` if
/// the user backs out.
///
/// No map widget — the project doesn't bundle a maps SDK. The user can:
///   - type a place name → forward-geocoded into one or more candidates
///   - tap "Use Current Location" → GPS + reverse-geocoded label
/// Either path returns coords + a human-readable label.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;

  List<_PickResult> _results = const [];
  bool _searching = false;
  bool _gpsLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 3) {
      setState(() {
        _results = const [];
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final matches = await locationFromAddress(q);
      if (!mounted) return;
      // Reverse-geocode each match to get a friendly label (best effort).
      final results = <_PickResult>[];
      for (final m in matches.take(6)) {
        String label = q;
        try {
          final placemarks = await placemarkFromCoordinates(
              m.latitude, m.longitude);
          if (placemarks.isNotEmpty) {
            final p = placemarks.first;
            label = [
              p.name,
              p.subLocality,
              p.locality,
              p.administrativeArea,
              p.country,
            ]
                .whereType<String>()
                .where((s) => s.trim().isNotEmpty)
                .toSet()
                .join(', ');
            if (label.isEmpty) label = q;
          }
        } catch (_) {
          // Reverse-geocode failed for this candidate; fall back to query.
        }
        results.add(_PickResult(m.latitude, m.longitude, label));
      }
      setState(() => _results = results);
    } catch (e) {
      setState(() => _error = 'No matches found');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    if (_gpsLoading) return;
    setState(() {
      _gpsLoading = true;
      _error = null;
    });
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) throw 'Turn on location services';
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw 'Location permission denied';
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      String label = 'My current location';
      try {
        final placemarks = await placemarkFromCoordinates(
            pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final l = [
            p.subLocality,
            p.locality,
            p.administrativeArea,
          ]
              .whereType<String>()
              .where((s) => s.trim().isNotEmpty)
              .toSet()
              .join(', ');
          if (l.isNotEmpty) label = l;
        }
      } catch (_) {
        // Reverse-geocode best effort.
      }
      if (!mounted) return;
      Navigator.pop(context, {
        'lat': pos.latitude,
        'lng': pos.longitude,
        'label': label,
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  void _selectResult(_PickResult r) {
    Navigator.pop(context, {
      'lat': r.lat,
      'lng': r.lng,
      'label': r.label,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(onClose: () => Navigator.pop(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _SearchInput(
                controller: _query,
                focusNode: _focus,
                onChanged: _onQueryChanged,
                onSubmitted: (v) => _search(v.trim()),
                isLoading: _searching,
              ),
            ),
            _CurrentLocationTile(
              loading: _gpsLoading,
              onTap: _useCurrentLocation,
            ),
            const Divider(height: 1, color: Color(0xFFEAECEF)),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontSize: 13,
                  ),
                ),
              ),
            Expanded(
              child: _results.isEmpty
                  ? _EmptyHint(
                      query: _query.text,
                      searching: _searching,
                    )
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, _) => const Divider(
                        height: 1,
                        color: Color(0xFFF3F4F6),
                      ),
                      itemBuilder: (_, i) => _ResultTile(
                        result: _results[i],
                        onTap: () => _selectResult(_results[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickResult {
  final double lat;
  final double lng;
  final String label;
  _PickResult(this.lat, this.lng, this.label);
}

class _TopBar extends StatelessWidget {
  final VoidCallback onClose;
  const _TopBar({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back,
                color: Color(0xFF101828), size: 22),
            onPressed: onClose,
          ),
          const SizedBox(width: 4),
          const Text(
            'Pick Work Location',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF101828),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final bool isLoading;

  const _SearchInput({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.search, color: Color(0xFF6B7280), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 14, color: Color(0xFF101828)),
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
                hintText: 'Search area, city, pincode…',
                hintStyle: TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 14,
                ),
              ),
            ),
          ),
          if (isLoading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor:
                    AlwaysStoppedAnimation<Color>(Color(0xFF408EE0)),
              ),
            ),
        ],
      ),
    );
  }
}

class _CurrentLocationTile extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;
  const _CurrentLocationTile({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: loading ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFDBEAFE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: loading
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF408EE0)),
                      ),
                    )
                  : const Icon(Icons.my_location,
                      color: Color(0xFF408EE0), size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Use Current Location',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF408EE0),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Pick the spot where you are now',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: Color(0xFF9CA3AF), size: 20),
          ],
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  final _PickResult result;
  final VoidCallback onTap;
  const _ResultTile({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const Icon(Icons.location_on_outlined,
                color: Color(0xFF6B7280), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF101828),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${result.lat.toStringAsFixed(5)}, ${result.lng.toStringAsFixed(5)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: Color(0xFF9CA3AF), size: 20),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String query;
  final bool searching;
  const _EmptyHint({required this.query, required this.searching});

  @override
  Widget build(BuildContext context) {
    if (searching) return const SizedBox.shrink();
    final q = query.trim();
    final hint = q.isEmpty
        ? 'Start typing to search, or tap "Use Current Location" above.'
        : (q.length < 3
            ? 'Keep typing — at least 3 characters.'
            : 'No matches found. Try a city or pincode.');
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        hint,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 13,
          color: Color(0xFF6B7280),
        ),
      ),
    );
  }
}
