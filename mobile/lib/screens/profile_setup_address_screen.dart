import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../state/auth_state.dart';

class ProfileSetupAddressScreen extends StatefulWidget {
  const ProfileSetupAddressScreen({super.key});

  @override
  State<ProfileSetupAddressScreen> createState() =>
      _ProfileSetupAddressScreenState();
}

class _ProfileSetupAddressScreenState
    extends State<ProfileSetupAddressScreen> {
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _pincode = TextEditingController();

  bool _detecting = false;
  bool _saving = false;
  String? _error;

  double? _lat;
  double? _lng;

  @override
  void initState() {
    super.initState();
    final loc = (context.read<AuthState>().user?['location'] ?? {}) as Map?;
    _address.text = (loc?['address'] ?? '').toString();
    _city.text = (loc?['city'] ?? '').toString();
    _state.text = (loc?['state'] ?? '').toString();
    _pincode.text = (loc?['pincode'] ?? '').toString();
    final coords = loc?['coordinates'];
    if (coords is List && coords.length == 2) {
      _lng = (coords[0] as num?)?.toDouble();
      _lat = (coords[1] as num?)?.toDouble();
    }
  }

  @override
  void dispose() {
    _address.dispose();
    _city.dispose();
    _state.dispose();
    _pincode.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    if (_detecting) return;
    setState(() {
      _detecting = true;
      _error = null;
    });
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        throw 'Turn on location services to detect your address';
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw 'Location permission denied';
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _lat = pos.latitude;
      _lng = pos.longitude;
      try {
        final placemarks =
            await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          _address.text = [
            p.street,
            p.subLocality,
            p.locality,
          ].whereType<String>().where((s) => s.trim().isNotEmpty).join(', ');
          _city.text = p.locality ?? p.subAdministrativeArea ?? '';
          _state.text = p.administrativeArea ?? '';
          _pincode.text = p.postalCode ?? '';
        }
      } catch (_) {
        // Reverse-geocoding optional; coordinates were captured.
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  Future<void> _next() async {
    final addr = _address.text.trim();
    final city = _city.text.trim();
    final st = _state.text.trim();
    final pin = _pincode.text.trim();
    if (addr.isEmpty || city.isEmpty || st.isEmpty || pin.isEmpty) {
      setState(() => _error = 'Fill in all address fields to continue');
      return;
    }
    if (_lat == null || _lng == null) {
      setState(() => _error =
          'Tap "Use Current Location" so we can capture your coordinates');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthState>();
      await auth.updateLocation(
        _lat!,
        _lng!,
        address: addr,
        city: city,
        state: st,
        pincode: pin,
      );
      if (!mounted) return;
      // Skills are only for job takers. The role is threaded explicitly
      // through the wizard via route arguments so the decision doesn't
      // depend on whether the switchRole API round-trip succeeded.
      final args = ModalRoute.of(context)?.settings.arguments;
      final wizardRole = args is Map ? args['role'] as String? : null;
      final isJobTaker =
          wizardRole == 'jobtaker' || auth.activeRole == 'jobtaker';
      if (isJobTaker) {
        Navigator.pushReplacementNamed(context, '/profile-setup/skills');
      } else {
        Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
      }
    } catch (e) {
      setState(() => _error = e.toString());
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
            _Header(currentStep: 2, totalSteps: 3),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Label('Address'),
                    const SizedBox(height: 8),
                    _FilledInput(
                      controller: _address,
                      hint: 'House no, Street, Area',
                    ),
                    const SizedBox(height: 24),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _Label('City'),
                              const SizedBox(height: 8),
                              _FilledInput(
                                controller: _city,
                                hint: 'City',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _Label('State'),
                              const SizedBox(height: 8),
                              _FilledInput(
                                controller: _state,
                                hint: 'State',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _Label('Pincode'),
                    const SizedBox(height: 8),
                    _FilledInput(
                      controller: _pincode,
                      hint: '560001',
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 24),
                    _UseCurrentLocationCard(
                      loading: _detecting,
                      onTap: _detecting ? null : _useCurrentLocation,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFDC2626),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _NextButton(
                loading: _saving,
                onTap: _saving ? null : _next,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  const _Header({required this.currentStep, required this.totalSteps});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => Navigator.maybePop(context),
                    child: const Icon(
                      Icons.arrow_back,
                      size: 24,
                      color: Color(0xFF101828),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Setup Profile',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF101828),
                  height: 1.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: List.generate(totalSteps, (i) {
              final filled = i < currentStep;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i == totalSteps - 1 ? 0 : 8),
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: filled
                          ? const Color(0xFFFF6900)
                          : const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: Color(0xFF364153),
        height: 1.5,
      ),
    );
  }
}

class _FilledInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;

  const _FilledInput({
    required this.controller,
    required this.hint,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(16),
      ),
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(
          fontSize: 16,
          color: Color(0xFF1A1A1A),
          height: 1.5,
        ),
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          hintText: hint,
          hintStyle: const TextStyle(
            color: Color(0x801A1A1A),
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

class _UseCurrentLocationCard extends StatelessWidget {
  final bool loading;
  final VoidCallback? onTap;
  const _UseCurrentLocationCard({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFF7ED),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Color(0xFF7E2A0C)),
                      ),
                    )
                  : const Icon(
                      Icons.location_on,
                      size: 20,
                      color: Color(0xFF7E2A0C),
                    ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Use Current Location',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF7E2A0C),
                        height: 1.42,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      loading
                          ? 'Detecting your location…'
                          : "We'll detect your location automatically",
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFCA3500),
                        height: 1.33,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NextButton extends StatelessWidget {
  final bool loading;
  final VoidCallback? onTap;
  const _NextButton({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFF6900), width: 1),
          ),
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Color(0xFFFF6900)),
                  ),
                )
              : const Text(
                  'Next',
                  style: TextStyle(
                    color: Color(0xFFFF6900),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                  ),
                ),
        ),
      ),
    );
  }
}
