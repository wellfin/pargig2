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

  // Per-field validation errors shown directly under each input. Cleared
  // as the user types in that field so the error doesn't stick around
  // after they've fixed it. The top-level `_error` is reserved for
  // non-field errors (network failure, server reject, GPS denied).
  String? _addressError;
  String? _cityError;
  String? _stateError;
  String? _pincodeError;

  bool _detecting = false;
  bool _saving = false;
  String? _error;

  double? _lat;
  double? _lng;

  // Validators — each returns null if valid, otherwise the message to
  // render under the field. Kept simple on purpose: the goal is to stop
  // obvious bad data (empty / wrong length / wrong character set)
  // before we hit the backend, not to enforce locale-specific rules.
  String? _validateAddress(String v) {
    final t = v.trim();
    if (t.isEmpty) return 'Address is required';
    if (t.length < 5) return 'Enter at least 5 characters';
    return null;
  }

  String? _validateCity(String v) {
    final t = v.trim();
    if (t.isEmpty) return 'City is required';
    if (t.length < 2) return 'City is too short';
    // All-numeric input is invalid (e.g. "12345"); mixed input like
    // "Sector 5" or "Phase II" is allowed.
    if (RegExp(r'^\d+$').hasMatch(t)) {
      return 'City cannot be only numbers';
    }
    return null;
  }

  String? _validateState(String v) {
    final t = v.trim();
    if (t.isEmpty) return 'State is required';
    if (t.length < 2) return 'State is too short';
    if (RegExp(r'^\d+$').hasMatch(t)) {
      return 'State cannot be only numbers';
    }
    return null;
  }

  String? _validatePincode(String v) {
    final t = v.trim();
    if (t.isEmpty) return 'Pincode is required';
    if (!RegExp(r'^\d{6}$').hasMatch(t)) {
      return 'Must be exactly 6 digits';
    }
    return null;
  }

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

  // Sets _lat/_lng from forward-geocoding `query` if it returns at least
  // one hit. Silent on failure — callers decide whether to try a
  // simpler query next.
  Future<void> _tryGeocode(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    try {
      final results = await locationFromAddress(q);
      if (results.isNotEmpty) {
        _lat = results.first.latitude;
        _lng = results.first.longitude;
      }
    } catch (_) {
      // Forward geocoding can fail offline or for an unknown address.
    }
  }

  // Last-resort fallback: read device GPS once. The user is almost
  // always physically at the address they're typing, so this is
  // usually within 10-30m of the real home. Silent on permission
  // denied / services off — Next still proceeds with whatever coords
  // (or no coords) we have.
  Future<void> _tryDeviceGps() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      _lat = pos.latitude;
      _lng = pos.longitude;
    } catch (_) {
      // Best-effort — silent.
    }
  }

  Future<void> _next() async {
    final addr = _address.text.trim();
    final city = _city.text.trim();
    final st = _state.text.trim();
    final pin = _pincode.text.trim();

    final addrErr = _validateAddress(addr);
    final cityErr = _validateCity(city);
    final stateErr = _validateState(st);
    final pinErr = _validatePincode(pin);

    if (addrErr != null ||
        cityErr != null ||
        stateErr != null ||
        pinErr != null) {
      setState(() {
        _addressError = addrErr;
        _cityError = cityErr;
        _stateError = stateErr;
        _pincodeError = pinErr;
        _error = null;
      });
      return;
    }

    setState(() {
      _addressError = null;
      _cityError = null;
      _stateError = null;
      _pincodeError = null;
      _saving = true;
      _error = null;
    });

    // If the user typed the address manually (no "Use Current Location"
    // tap), try every angle we can think of to capture *some*
    // coordinates within ~300m of the user. Order matters — full
    // address gives the best precision, fall-backs trade precision for
    // success rate. Next must always proceed once the four fields are
    // filled; coordinates are a bonus, not a gate.
    if (_lat == null || _lng == null) {
      // Try 1 — full address. Best case: street-level (10-100m).
      await _tryGeocode([addr, city, st, pin].where((s) => s.isNotEmpty).join(', '));

      // Try 2 — drop the street number, keep "area, city, state, pincode".
      // Helps when the geocoder doesn't know the house number but knows
      // the locality.
      if (_lat == null || _lng == null) {
        await _tryGeocode([city, st, pin].where((s) => s.isNotEmpty).join(', '));
      }

      // Try 3 — pincode + state alone. Indian pincodes resolve to a
      // small sub-locality area (usually 200-500m radius), which fits
      // the user's "even near 300m" requirement.
      if (_lat == null || _lng == null) {
        await _tryGeocode([pin, st].where((s) => s.isNotEmpty).join(', '));
      }

      // Try 4 — device GPS as a last resort. The user is most likely
      // sitting AT the address they're typing, so live GPS is usually
      // within 10-30m of the real home location. Asks permission if
      // not granted; silent if denied.
      if (_lat == null || _lng == null) {
        await _tryDeviceGps();
      }
    }

    if (!mounted) return;
    try {
      final auth = context.read<AuthState>();
      await auth.updateLocation(
        _lat,
        _lng,
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
        // Jobgivers finish the wizard here — drop them on the role-chooser
        // screen so they can confirm "Hire Workers" before landing on home.
        Navigator.pushReplacementNamed(context, '/role-chooser');
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
                      errorText: _addressError,
                      onChanged: (_) {
                        if (_addressError != null) {
                          setState(() => _addressError = null);
                        }
                      },
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
                                errorText: _cityError,
                                onChanged: (_) {
                                  if (_cityError != null) {
                                    setState(() => _cityError = null);
                                  }
                                },
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
                                errorText: _stateError,
                                onChanged: (_) {
                                  if (_stateError != null) {
                                    setState(() => _stateError = null);
                                  }
                                },
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
                      maxLength: 6,
                      errorText: _pincodeError,
                      onChanged: (_) {
                        if (_pincodeError != null) {
                          setState(() => _pincodeError = null);
                        }
                      },
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
                    onTap: () {
                      if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      } else {
                        Navigator.pushReplacementNamed(
                          context,
                          '/onboarding',
                        );
                      }
                    },
                    child: const Icon(
                      Icons.arrow_back,
                      size: 24,
                      color: Color(0xFF101828),
                    ),
                  ),
                ),
              ),
              const Expanded(
                child: Text(
                  'Setup Profile',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF101828),
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: 40),
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
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final int? maxLength;

  const _FilledInput({
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.errorText,
    this.onChanged,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasError
                  ? const Color(0xFFDC2626)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            onChanged: onChanged,
            maxLength: maxLength,
            style: const TextStyle(
              fontSize: 16,
              color: Color(0xFF1A1A1A),
              height: 1.5,
            ),
            decoration: InputDecoration(
              isCollapsed: true,
              counterText: '',
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
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Text(
              errorText!,
              style: const TextStyle(
                color: Color(0xFFDC2626),
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ),
      ],
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
