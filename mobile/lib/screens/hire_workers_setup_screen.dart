import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:provider/provider.dart';

import '../state/auth_state.dart';

/// "Enter Location" — job-giver setup screen. Reached from the role-chooser
/// when the user taps Hire Workers. Same Location + GPS + Search Radius
/// pattern as the Find Work screen, but without the Skills / Custom Skills /
/// Years of Experience sections (those are job-taker-only).
///
/// On Apply Location:
///   1. switchRole('jobgiver') if not already jobgiver
///   2. PUT /users/me/location with lat/lng (+ address text from the field)
///   3. PUT /users/me with searchRadiusKm
///   4. pushNamedAndRemoveUntil('/home')
class HireWorkersSetupScreen extends StatefulWidget {
  const HireWorkersSetupScreen({super.key});

  @override
  State<HireWorkersSetupScreen> createState() => _HireWorkersSetupScreenState();
}

class _HireWorkersSetupScreenState extends State<HireWorkersSetupScreen> {
  static const _radiusOptions = <({String label, int km})>[
    (label: '1-5 Kms', km: 5),
    (label: '5-10 Kms', km: 10),
    (label: '10-20 Kms', km: 20),
    (label: 'Above 20kms', km: 50),
  ];

  final _location = TextEditingController();
  int _radiusKm = 20;

  double? _lat;
  double? _lng;

  bool _gpsLoading = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthState>().user ?? const <String, dynamic>{};
    // Location field intentionally starts empty — the user picks a work
    // location explicitly via the GPS button. We do NOT pre-fill from the
    // profile address (user.location), since that's their home/billing
    // address and not necessarily where they want to find workers.
    final existingRadius = (user['searchRadiusKm'] as num?)?.toInt();
    if (existingRadius != null &&
        _radiusOptions.any((o) => o.km == existingRadius)) {
      _radiusKm = existingRadius;
    }
  }

  @override
  void dispose() {
    _location.dispose();
    super.dispose();
  }

  Future<void> _pickLocation() async {
    // Push the picker — the user can search a place by name OR use the
    // "Use Current Location" shortcut inside it. The picker pops with
    // {lat, lng, label}.
    if (_gpsLoading) return;
    setState(() {
      _gpsLoading = true;
      _error = null;
    });
    final picked = await Navigator.pushNamed<Object?>(
      context,
      '/pick-location',
    );
    if (!mounted) {
      _gpsLoading = false;
      return;
    }
    setState(() => _gpsLoading = false);
    if (picked is! Map) return;
    final lat = picked['lat'];
    final lng = picked['lng'];
    final label = picked['label'];
    if (lat is num && lng is num) {
      setState(() {
        _lat = lat.toDouble();
        _lng = lng.toDouble();
        if (label is String && label.trim().isNotEmpty) {
          _location.text = label;
        }
      });
    }
  }

  Future<void> _apply() async {
    if (_saving) return;
    // Two paths to workArea coords: GPS pick OR typed text + forward
    // geocode. Hard error only if both fail.
    if (_lat == null || _lng == null) {
      final typed = _location.text.trim();
      if (typed.isEmpty) {
        setState(
          () => _error = 'Type an area or tap GPS to pick your hire location',
        );
        return;
      }
      setState(() {
        _saving = true;
        _error = null;
      });
      try {
        final hits = await locationFromAddress(typed);
        if (hits.isNotEmpty) {
          _lat = hits.first.latitude;
          _lng = hits.first.longitude;
        }
      } catch (_) {
        // Forward geocoding can fail offline or for unknown text.
      }
      if (!mounted) return;
      if (_lat == null || _lng == null) {
        setState(() {
          _saving = false;
          _error =
              "Couldn't find that area. Tap GPS to pick a real location, "
              'or check the spelling.';
        });
        return;
      }
    } else {
      setState(() {
        _saving = true;
        _error = null;
      });
    }
    try {
      final auth = context.read<AuthState>();
      // Always replace — even if the user is currently "jobgiver" they
      // might still have both roles in their roles array from a prior
      // Switch Mode. Hire Workers means "I want to be a jobgiver only",
      // so we normalize the array to [jobgiver] every time.
      await auth.switchRole('jobgiver', mode: 'replace');
      // IMPORTANT: do NOT call updateLocation — that holds the user's
      // home/profile address. GPS here is for the WORK AREA only.
      final radiusLabel = _radiusOptions
          .firstWhere(
            (o) => o.km == _radiusKm,
            orElse: () => _radiusOptions.last,
          )
          .label;
      await auth.updateProfile({
        'searchRadiusKm': _radiusKm,
        'searchRadiusLabel': radiusLabel,
        'workArea': {
          'type': 'Point',
          // GeoJSON order is [lng, lat].
          'coordinates': [_lng!, _lat!],
        },
        'workAreaLabel': _location.text.trim(),
      });
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
    } catch (e) {
      if (!mounted) return;
      setState(
          () => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _IconHeader(),
                    const SizedBox(height: 16),
                    const Center(
                      child: Text(
                        'Enter Location',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF101828),
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'We need your location to show nearby workers in your area',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF64748B),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const _SectionLabel('Location'),
                    const SizedBox(height: 8),
                    _LocationRow(
                      controller: _location,
                      gpsLoading: _gpsLoading,
                      onGpsTap: _pickLocation,
                    ),
                    const SizedBox(height: 20),
                    const _SectionLabel('Search Radius'),
                    const SizedBox(height: 8),
                    _RadiusChips(
                      options: _radiusOptions,
                      selectedKm: _radiusKm,
                      onChanged: (km) => setState(() => _radiusKm = km),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFDC2626),
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: _ApplyButton(
                loading: _saving,
                onTap: _saving ? null : _apply,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconHeader extends StatelessWidget {
  const _IconHeader();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 64,
        height: 64,
        decoration: const BoxDecoration(
          color: Color(0xFF408EE0),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.location_on, color: Colors.white, size: 30),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Color(0xFF101828),
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  final TextEditingController controller;
  final bool gpsLoading;
  final VoidCallback onGpsTap;

  const _LocationRow({
    required this.controller,
    required this.gpsLoading,
    required this.onGpsTap,
  });

  @override
  Widget build(BuildContext context) {
    // Two-input row (Figma): typed text field + GPS button.
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: TextField(
              controller: controller,
              style: const TextStyle(fontSize: 14, color: Color(0xFF101828)),
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Noida, Sector 135',
                hintStyle: TextStyle(
                  color: Color(0x801A1A1A),
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: gpsLoading ? null : onGpsTap,
            icon: gpsLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.near_me, size: 16, color: Colors.white),
            label: const Text(
              'GPS',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF408EE0),
              disabledBackgroundColor: const Color(0xFF93C5FD),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RadiusChips extends StatelessWidget {
  final List<({String label, int km})> options;
  final int selectedKm;
  final ValueChanged<int> onChanged;

  const _RadiusChips({
    required this.options,
    required this.selectedKm,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((o) {
        final isSelected = o.km == selectedKm;
        return GestureDetector(
          onTap: () => onChanged(o.km),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF408EE0)
                  : Colors.white,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF408EE0)
                    : const Color(0xFFE5E7EB),
                width: 1,
              ),
            ),
            child: Text(
              o.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isSelected ? Colors.white : const Color(0xFF101828),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ApplyButton extends StatelessWidget {
  final bool loading;
  final VoidCallback? onTap;
  const _ApplyButton({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF408EE0),
          disabledBackgroundColor: const Color(0xFF93C5FD),
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                'Apply Location',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
