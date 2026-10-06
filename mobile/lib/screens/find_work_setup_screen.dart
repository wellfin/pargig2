import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:provider/provider.dart';

import '../state/auth_state.dart';

/// "Enter Location" — job-taker setup screen. Reached from the role-chooser
/// when the user taps Find Work. Collects:
///   - city/area text + GPS coords (tap GPS to auto-fill)
///   - search radius (1-5 / 5-10 / 10-20 / Above 20 km)
///   - skills (chips) + custom skills (comma-separated text)
///   - years of experience
/// On Apply Location:
///   1. switchRole('jobtaker') if not already jobtaker
///   2. PUT /users/me/location with lat/lng (+ address text from the field)
///   3. PUT /users/me with skills, yearsOfExperience, searchRadiusKm
///   4. pushNamedAndRemoveUntil('/home')
class FindWorkSetupScreen extends StatefulWidget {
  const FindWorkSetupScreen({super.key});

  @override
  State<FindWorkSetupScreen> createState() => _FindWorkSetupScreenState();
}

class _FindWorkSetupScreenState extends State<FindWorkSetupScreen> {
  static const _skillOptions = <String>[
    'Cleaning',
    'Plumbing',
    'Electrical',
    'Painting',
    'Carpentry',
    'Gardening',
    'AC Repair',
    'Appliance Repair',
    'Others',
  ];

  static const _experienceOptions = <String>[
    'Less than 1 year',
    '1-2 years',
    '3-5 years',
    '5-10 years',
    '10+ years',
  ];

  // Search-radius buckets — value is the upper-bound in km used when querying
  // nearby jobs.
  static const _radiusOptions = <({String label, int km})>[
    (label: '1-5 Kms', km: 5),
    (label: '5-10 Kms', km: 10),
    (label: '10-20 Kms', km: 20),
    (label: 'Above 20kms', km: 50),
  ];

  final _location = TextEditingController();
  final _customSkills = TextEditingController();
  final Set<String> _selectedSkills = {};
  String? _experience;
  int _radiusKm = 20; // default selection matches the design (10-20 chip)

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
    // address and not necessarily where they want to find work.
    final existingSkills = user['skills'];
    if (existingSkills is List) {
      _selectedSkills.addAll(existingSkills.map((e) => e.toString()));
    }
    final existingExp = (user['yearsOfExperience'] ?? '').toString();
    if (_experienceOptions.contains(existingExp)) _experience = existingExp;
    final existingRadius = (user['searchRadiusKm'] as num?)?.toInt();
    if (existingRadius != null &&
        _radiusOptions.any((o) => o.km == existingRadius)) {
      _radiusKm = existingRadius;
    }
  }

  @override
  void dispose() {
    _location.dispose();
    _customSkills.dispose();
    super.dispose();
  }

  Future<void> _pickLocation() async {
    // Push the picker — the user can search a place by name OR use the
    // "Use Current Location" shortcut inside it. The picker pops with
    // {lat, lng, label}. We don't capture GPS directly from this screen
    // anymore: the user explicitly picks the work area they want.
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

  Future<void> _pickExperience() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Years of Experience',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF101828),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ..._experienceOptions.map(
                (e) => ListTile(
                  title: Text(e),
                  trailing: e == _experience
                      ? const Icon(Icons.check, color: Color(0xFF408EE0))
                      : null,
                  onTap: () => Navigator.pop(ctx, e),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _experience = picked);
  }

  Future<void> _apply() async {
    if (_saving) return;
    final allSkills = <String>{..._selectedSkills};
    for (final raw in _customSkills.text.split(',')) {
      final s = raw.trim();
      if (s.isNotEmpty) allSkills.add(s);
    }
    if (allSkills.isEmpty) {
      setState(() => _error = 'Pick at least one skill (or add a custom one)');
      return;
    }
    if (_experience == null) {
      setState(() => _error = 'Select your years of experience');
      return;
    }
    // Two paths to workArea coords:
    //   1. user tapped GPS → _lat/_lng set by the picker
    //   2. user typed in the Location field → forward-geocode the
    //      typed text here. Falls back to a hard error if neither
    //      worked (typed text empty AND no GPS pick).
    if (_lat == null || _lng == null) {
      final typed = _location.text.trim();
      if (typed.isEmpty) {
        setState(
          () => _error = 'Type an area or tap GPS to pick your work location',
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
      // Always replace — even if the user is currently "jobtaker" they
      // might still have both roles in their roles array from a prior
      // Switch Mode. Find Work means "I want to be a jobtaker only", so
      // we normalize the array to [jobtaker] every time.
      await auth.switchRole('jobtaker', mode: 'replace');
      // IMPORTANT: do NOT call updateLocation here — that field holds the
      // user's profile/home address (typed during the wizard's address
      // step) and must stay untouched. GPS on this screen is for the
      // WORK AREA, which is a separate field on the user record.
      final radiusLabel = _radiusOptions
          .firstWhere(
            (o) => o.km == _radiusKm,
            orElse: () => _radiusOptions.last,
          )
          .label;
      await auth.updateProfile({
        'skills': allSkills.toList(),
        'yearsOfExperience': _experience,
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
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
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
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        onPressed: () {
                          if (Navigator.canPop(context)) {
                            Navigator.pop(context);
                          } else {
                            // Reached here directly (role-chooser clears the
                            // stack before landing on this screen). Step
                            // back to role-chooser instead of doing nothing.
                            Navigator.pushReplacementNamed(
                              context,
                              '/role-chooser',
                            );
                          }
                        },
                        icon: const Icon(
                          Icons.arrow_back,
                          size: 22,
                          color: Color(0xFF101828),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
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
                          'We need your location to show nearby jobs in your area',
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
                    const _SectionLabel('Select location and radius'),
                    const SizedBox(height: 8),
                    _LocationRow(
                      controller: _location,
                      gpsLoading: _gpsLoading,
                      onGpsTap: _pickLocation,
                    ),
                    const SizedBox(height: 20),
                    const _SectionLabel('Search radius to job'),
                    const SizedBox(height: 8),
                    _RadiusChips(
                      options: _radiusOptions,
                      selectedKm: _radiusKm,
                      onChanged: (km) => setState(() => _radiusKm = km),
                    ),
                    const SizedBox(height: 20),
                    const _SectionLabel('Select Your Skills'),
                    const SizedBox(height: 8),
                    _SkillGrid(
                      options: _skillOptions,
                      selected: _selectedSkills,
                      onToggle: (s) {
                        setState(() {
                          if (_selectedSkills.contains(s)) {
                            _selectedSkills.remove(s);
                          } else {
                            _selectedSkills.add(s);
                          }
                          if (_error != null) _error = null;
                        });
                      },
                    ),
                    const SizedBox(height: 20),
                    const _SectionLabel('Enter Your Custom Skills'),
                    const SizedBox(height: 8),
                    _CustomSkillsField(controller: _customSkills),
                    const SizedBox(height: 6),
                    const Text(
                      'Separate multiple skills with commas',
                      style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                    ),
                    const SizedBox(height: 20),
                    const _SectionLabel('Years of Experience'),
                    const SizedBox(height: 8),
                    _ExperienceDropdown(
                      value: _experience,
                      onTap: _pickExperience,
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
    // Two-input row (Figma): a typed text field + a GPS button. User
    // can either type a place name OR tap GPS to open the location
    // picker (the picker overwrites the typed text with its label).
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
                hintStyle: TextStyle(color: Color(0x801A1A1A), fontSize: 14),
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
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF408EE0) : Colors.white,
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

class _SkillGrid extends StatelessWidget {
  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  const _SkillGrid({
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cellWidth = (c.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: options.map((s) {
            final isSelected = selected.contains(s);
            return SizedBox(
              width: cellWidth,
              child: GestureDetector(
                onTap: () => onToggle(s),
                child: Container(
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFFFF6900)
                          : const Color(0xFFD1D5DB),
                      width: isSelected ? 1.4 : 1,
                    ),
                  ),
                  child: Text(
                    s,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isSelected
                          ? const Color(0xFFFF6900)
                          : const Color(0xFF101828),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _CustomSkillsField extends StatelessWidget {
  final TextEditingController controller;
  const _CustomSkillsField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: TextField(
        controller: controller,
        minLines: 3,
        maxLines: 4,
        style: const TextStyle(fontSize: 14, color: Color(0xFF101828)),
        decoration: const InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText:
              'e.g., Photography, Video Editing, Web Development (comma separated)',
          hintStyle: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
        ),
      ),
    );
  }
}

class _ExperienceDropdown extends StatelessWidget {
  final String? value;
  final VoidCallback onTap;
  const _ExperienceDropdown({required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFD1D5DB), width: 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value ?? 'Select experience',
                style: TextStyle(
                  fontSize: 14,
                  color: value == null
                      ? const Color(0xFF9CA3AF)
                      : const Color(0xFF101828),
                ),
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down,
              color: Color(0xFF6B7280),
              size: 22,
            ),
          ],
        ),
      ),
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
      width: double.infinity,
      height: 56,
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
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
      ),
    );
  }
}
