import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../api/home_api.dart';
import '../config.dart';
import '../state/auth_state.dart';

class PostJobScreen extends StatefulWidget {
  const PostJobScreen({super.key});

  @override
  State<PostJobScreen> createState() => _PostJobScreenState();
}

class _PostJobScreenState extends State<PostJobScreen> {
  static const _maxPhotos = 6;

  final _title = TextEditingController();
  final _description = TextEditingController();
  final _location = TextEditingController();
  final _amount = TextEditingController();
  final _picker = ImagePicker();

  String _descriptionMode = 'text'; // 'text' or 'voice'
  bool _isRecording = false;
  DateTime? _date;
  TimeOfDay? _time;
  bool _urgent = false;
  String _priceMode = 'fixed'; // 'fixed' or 'open'
  String? _preference; // 'experienced' or 'anyone'
  final List<String> _photoUrls = [];
  bool _photoUploading = false;

  double? _lat;
  double? _lng;
  bool _gpsLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthState>();
    final loc = auth.user?['location'] is Map
        ? auth.user!['location'] as Map
        : const {};
    final coords = loc['coordinates'];
    if (coords is List && coords.length == 2) {
      final lng = (coords[0] as num?)?.toDouble();
      final lat = (coords[1] as num?)?.toDouble();
      if (lat != null && lng != null && (lat != 0 || lng != 0)) {
        _lat = lat;
        _lng = lng;
      }
    }
    final addr = (loc['address'] ?? '').toString();
    final city = (loc['city'] ?? '').toString();
    _location.text = [addr, city].where((s) => s.trim().isNotEmpty).join(', ');
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _location.dispose();
    _amount.dispose();
    super.dispose();
  }

  // The address string we pre-fill into _location in initState — used
  // on submit to detect whether the user edited the text. If they did,
  // we forward-geocode the new text so coords stay in sync.
  String _initialAddressFromProfile() {
    final auth = context.read<AuthState>();
    final loc =
        auth.user?['location'] is Map ? auth.user!['location'] as Map : const {};
    final addr = (loc['address'] ?? '').toString();
    final city = (loc['city'] ?? '').toString();
    return [addr, city].where((s) => s.trim().isNotEmpty).join(', ');
  }

  void _toggleRecording() {
    // Real audio capture + speech-to-text would replace this stub.
    // For now we flip the visual recording state and let the user
    // type the transcript manually below.
    setState(() => _isRecording = !_isRecording);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isRecording
              ? 'Recording… (real audio capture coming soon — type the transcript below)'
              : 'Recording stopped',
        ),
        duration: const Duration(milliseconds: 1600),
      ),
    );
  }

  Future<void> _useCurrentLocation() async {
    if (_gpsLoading) return;
    setState(() => _gpsLoading = true);
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
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _lat = pos.latitude;
      _lng = pos.longitude;
      try {
        final placemarks = await placemarkFromCoordinates(
          pos.latitude,
          pos.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          _location.text = [
            p.street,
            p.subLocality,
            p.locality,
          ].whereType<String>().where((s) => s.trim().isNotEmpty).join(', ');
        }
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: _date ?? DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.now(),
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _addPhoto() async {
    if (_photoUrls.length >= _maxPhotos) return;
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (picked == null) return;
    setState(() => _photoUploading = true);
    try {
      final url = await HomeApi.uploadJobPhoto(picked.path);
      if (url != null && mounted) {
        setState(() => _photoUrls.add(url));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Photo upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _photoUploading = false);
    }
  }

  Future<void> _continue() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Job title is required');
      return;
    }
    final desc = _description.text.trim();
    if (desc.isEmpty && _descriptionMode == 'text') {
      setState(() => _error = 'Description is required');
      return;
    }
    if (_location.text.trim().isEmpty) {
      setState(() => _error = 'Location is required');
      return;
    }
    if (_date == null || _time == null) {
      setState(() => _error = 'Pick a date and time');
      return;
    }
    if (_priceMode == 'fixed' &&
        (double.tryParse(_amount.text.trim()) ?? 0) <= 0) {
      setState(() => _error = 'Enter a fixed-price amount');
      return;
    }
    if (_preference == null) {
      setState(() => _error = 'Pick a worker preference');
      return;
    }

    setState(() => _error = null);

    final scheduled = DateTime(
      _date!.year,
      _date!.month,
      _date!.day,
      _time!.hour,
      _time!.minute,
    );
    final amount = double.tryParse(_amount.text.trim());
    final addr = _location.text.trim();

    // Forward-geocode the typed address whenever we DON'T have real
    // coords yet. This covers two cases:
    //   1. The user edited the address text after initState
    //      pre-filled it — inherited coords no longer match.
    //   2. The new user's profile has [0,0] coords (typed-only
    //      address during the wizard) — inherited coords are bogus,
    //      so the job would post with [0,0] and never match any
    //      real-location $near query.
    // Falls back silently to whatever coords we had if geocoding
    // fails (offline, unknown text).
    final inheritedAddr = _initialAddressFromProfile();
    final needsGeocode = addr.isNotEmpty &&
        (_lat == null ||
            _lng == null ||
            (_lat == 0 && _lng == 0) ||
            addr != inheritedAddr);
    if (needsGeocode) {
      try {
        final hits = await locationFromAddress(addr);
        if (hits.isNotEmpty) {
          _lat = hits.first.latitude;
          _lng = hits.first.longitude;
        }
      } catch (_) {
        // Offline / unknown text — keep whatever coords we had.
      }
    }
    if (!mounted) return;

    final draft = <String, dynamic>{
      'title': title,
      'description': desc,
      'priceMode': _priceMode,
      'isUrgent': _urgent,
      'preference': _preference,
      'scheduledAt': scheduled.toIso8601String(),
      'photos': _photoUrls,
      'location': _lat != null && _lng != null
          ? {'lat': _lat, 'lng': _lng, 'address': addr}
          : {'address': addr},
      // UI-only fields used by Step 2's review card.
      '_displayDate': scheduled,
      '_displayLocation': addr,
    };
    if (amount != null) {
      draft['proposedBudget'] = amount;
    }

    final result = await Navigator.pushNamed(
      context,
      '/post-job/step2',
      arguments: draft,
    );
    if (result == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _Header(
            currentStep: 1,
            totalSteps: 2,
            onBack: () => Navigator.maybePop(context),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Label('Job Title *'),
                    const SizedBox(height: 8),
                    _FilledInput(
                      controller: _title,
                      hint: 'e.g., Home Deep Cleaning',
                    ),
                    const SizedBox(height: 24),
                    _Label('Description *'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _DescriptionModeCard(
                            icon: Icons.edit,
                            label: 'Type Text',
                            selectedAccent: const Color(0xFFFF6900),
                            selected: _descriptionMode == 'text',
                            onTap: () =>
                                setState(() => _descriptionMode = 'text'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DescriptionModeCard(
                            icon: Icons.mic,
                            label: 'Voice Input',
                            selectedAccent: const Color(0xFF2B7FFF),
                            selected: _descriptionMode == 'voice',
                            onTap: () =>
                                setState(() => _descriptionMode = 'voice'),
                          ),
                        ),
                      ],
                    ),
                    if (_descriptionMode == 'text') ...[
                      const SizedBox(height: 12),
                      _FilledInput(
                        controller: _description,
                        hint: 'Describe what needs to be done in detail...',
                        maxLines: 5,
                        minHeight: 128,
                        maxLength: 500,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${_description.text.length}/500 characters',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF6A7282),
                          ),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      _VoiceInputPanel(
                        description: _description,
                        isRecording: _isRecording,
                        onMicTap: _toggleRecording,
                      ),
                    ],
                    const SizedBox(height: 24),
                    _Label('Location *'),
                    const SizedBox(height: 8),
                    _FilledInput(
                      controller: _location,
                      hint: 'Enter job location',
                      leading: const Icon(
                        Icons.location_on_outlined,
                        size: 20,
                        color: Color(0xFF6A7282),
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _gpsLoading ? null : _useCurrentLocation,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_gpsLoading)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFFFF6900),
                                ),
                              ),
                            )
                          else
                            const Icon(
                              Icons.near_me,
                              size: 16,
                              color: Color(0xFFFF6900),
                            ),
                          const SizedBox(width: 6),
                          const Text(
                            'Use current location',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFFFF6900),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _Label('Date *'),
                              const SizedBox(height: 8),
                              _PickerField(
                                icon: Icons.calendar_today,
                                text: _date == null
                                    ? 'DD / MM / YYYY'
                                    : '${_date!.day.toString().padLeft(2, '0')} / '
                                          '${_date!.month.toString().padLeft(2, '0')} / '
                                          '${_date!.year}',
                                isPlaceholder: _date == null,
                                onTap: _pickDate,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _Label('Time *'),
                              const SizedBox(height: 8),
                              _PickerField(
                                icon: Icons.access_time,
                                text: _time == null
                                    ? 'HH : MM'
                                    : _time!.format(context),
                                isPlaceholder: _time == null,
                                onTap: _pickTime,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _UrgentRow(
                      value: _urgent,
                      onChanged: (v) => setState(() => _urgent = v),
                    ),
                    const SizedBox(height: 24),
                    _Label('Pricing *'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _PriceModeCard(
                            title: 'Fixed Price',
                            subtitle: 'Set your budget',
                            selected: _priceMode == 'fixed',
                            onTap: () => setState(() => _priceMode = 'fixed'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _PriceModeCard(
                            title: 'Open to Offers',
                            subtitle: 'Get quotes',
                            selected: _priceMode == 'open',
                            onTap: () => setState(() => _priceMode = 'open'),
                          ),
                        ),
                      ],
                    ),
                    if (_priceMode == 'fixed') ...[
                      const SizedBox(height: 16),
                      _FilledInput(
                        controller: _amount,
                        hint: 'Enter amount',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        leading: const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Text(
                            '₹',
                            style: TextStyle(
                              fontSize: 18,
                              color: Color(0xFF6A7282),
                            ),
                          ),
                        ),
                        hintFontSize: 18,
                      ),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      children: const [
                        Text(
                          'Preferences * ',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF364153),
                          ),
                        ),
                        Text(
                          '(Required)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFFF54900),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _PreferenceCard(
                            title: 'Experienced',
                            subtitle: 'Skilled workers only',
                            selected: _preference == 'experienced',
                            onTap: () =>
                                setState(() => _preference = 'experienced'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _PreferenceCard(
                            title: 'Anyone',
                            subtitle: 'Open to all workers',
                            selected: _preference == 'anyone',
                            onTap: () => setState(() => _preference = 'anyone'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _Label('Add Photos (Optional)'),
                    const SizedBox(height: 4),
                    const Text(
                      'Photos help workers understand the job better',
                      style: TextStyle(fontSize: 14, color: Color(0xFF4A5565)),
                    ),
                    const SizedBox(height: 12),
                    _PhotosGrid(
                      photoUrls: _photoUrls,
                      uploading: _photoUploading,
                      onAdd: _addPhoto,
                      onRemove: (i) => setState(() => _photoUrls.removeAt(i)),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Maximum 6 images allowed. JPG, PNG up to 5MB each.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF6A7282)),
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
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton(
                        onPressed: _continue,
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          side: const BorderSide(
                            color: Color(0xFFFF6900),
                            width: 1,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Continue',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFFFF6900),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final VoidCallback onBack;
  const _Header({
    required this.currentStep,
    required this.totalSteps,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF408EE0),
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 16,
        16,
        16,
      ),
      child: Column(
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
                    onTap: onBack,
                    child: const Icon(
                      Icons.arrow_back,
                      size: 24,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              const Text(
                'Post a Job',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0x1AF3F4F6),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: const Text(
                  'Draft',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFE5E7EB),
                  ),
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
                      color: filled ? Colors.white : const Color(0x33E5E7EB),
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          Text(
            'Step $currentStep of $totalSteps',
            style: const TextStyle(fontSize: 14, color: Colors.white),
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
      ),
    );
  }
}

class _FilledInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final double? minHeight;
  final int? maxLength;
  final TextInputType? keyboardType;
  final Widget? leading;
  final ValueChanged<String>? onChanged;
  final double? hintFontSize;

  const _FilledInput({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.minHeight,
    this.maxLength,
    this.keyboardType,
    this.leading,
    this.onChanged,
    this.hintFontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(16),
      ),
      constraints: BoxConstraints(minHeight: minHeight ?? 56),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 8)],
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: maxLines,
              maxLength: maxLength,
              keyboardType: keyboardType,
              onChanged: onChanged,
              style: const TextStyle(fontSize: 16, color: Color(0xFF0F172A)),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                filled: false,
                fillColor: Colors.transparent,
                counterText: '',
                hintText: hint,
                hintStyle: TextStyle(
                  color: const Color(0x801A1A1A),
                  fontSize: hintFontSize ?? 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DescriptionModeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color selectedAccent;
  final VoidCallback onTap;

  const _DescriptionModeCard({
    required this.icon,
    required this.label,
    required this.selected,
    required this.selectedAccent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tint = selectedAccent == const Color(0xFFFF6900)
        ? const Color(0xFFFFF7ED)
        : const Color(0xFFEFF6FF);
    final labelColor = selectedAccent == const Color(0xFFFF6900)
        ? const Color(0xFFF54900)
        : const Color(0xFF155DFC);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: selected ? tint : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? selectedAccent : const Color(0xFFE5E7EB),
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 3,
                    offset: Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: selected ? selectedAccent : const Color(0xFFF3F4F6),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 22,
                color: selected ? Colors.white : const Color(0xFF6A7282),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? labelColor : const Color(0xFF364153),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceInputPanel extends StatelessWidget {
  final TextEditingController description;
  final bool isRecording;
  final VoidCallback onMicTap;

  const _VoiceInputPanel({
    required this.description,
    required this.isRecording,
    required this.onMicTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBEDBFF), width: 1.5),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: onMicTap,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: isRecording
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF2B7FFF),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color:
                        (isRecording
                                ? const Color(0xFFDC2626)
                                : const Color(0xFF2B7FFF))
                            .withAlpha(60),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                isRecording ? Icons.stop : Icons.mic,
                size: 40,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isRecording ? 'Recording…' : 'Tap to start recording',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF408EE0),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Describe your job requirements',
            style: TextStyle(fontSize: 14, color: Color(0xFF155DFC)),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFBEDBFF), width: 0.8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Transcribed Text:',
                  style: TextStyle(fontSize: 12, color: Color(0xFF408EE0)),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: description,
                  maxLines: 4,
                  minLines: 2,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF101828),
                    height: 1.43,
                  ),
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    contentPadding: EdgeInsets.zero,
                    hintText:
                        'Need complete deep cleaning of my 2BHK '
                        'apartment including kitchen and bathrooms.',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: Color(0x801A1A1A),
                      height: 1.43,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool isPlaceholder;
  final VoidCallback onTap;

  const _PickerField({
    required this.icon,
    required this.text,
    required this.isPlaceholder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: const Color(0xFF6A7282)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isPlaceholder
                      ? const Color(0xFF4A5565)
                      : const Color(0xFF0F172A),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UrgentRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _UrgentRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.flash_on, size: 20, color: Color(0xFFFF6900)),
          const SizedBox(width: 8),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mark as Urgent',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF101828),
                  ),
                ),
                Text(
                  'Get faster responses',
                  style: TextStyle(fontSize: 14, color: Color(0xFF4A5565)),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => onChanged(!value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 56,
              height: 32,
              decoration: BoxDecoration(
                color: value
                    ? const Color(0xFFFF6900)
                    : const Color(0xFFD1D5DC),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 180),
                    left: value ? 28 : 4,
                    top: 4,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _PriceModeCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF4F6F9) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? const Color(0xFF0F172A) : const Color(0xFFE5E7EB),
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: selected
                    ? const Color(0xFF0F172A)
                    : const Color(0xFF364153),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: selected
                    ? const Color(0xFF0F172A)
                    : const Color(0xFF364153),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreferenceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _PreferenceCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF7ED) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? const Color(0xFFFF6900) : const Color(0xFFE5E7EB),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFFFF6900)
                    : const Color(0xFFF3F4F6),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.star,
                size: 22,
                color: selected ? Colors.white : const Color(0xFF6A7282),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected
                    ? const Color(0xFFF54900)
                    : const Color(0xFF364153),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF4A5565),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotosGrid extends StatelessWidget {
  final List<String> photoUrls;
  final bool uploading;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  const _PhotosGrid({
    required this.photoUrls,
    required this.uploading,
    required this.onAdd,
    required this.onRemove,
  });

  static const _maxPhotos = 6;

  @override
  Widget build(BuildContext context) {
    final slots = <Widget>[
      ...photoUrls.asMap().entries.map(
        (e) => _Thumb(url: e.value, onRemove: () => onRemove(e.key)),
      ),
      if (photoUrls.length < _maxPhotos)
        _AddSlot(loading: uploading, onTap: onAdd),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: slots
          .map(
            (w) => SizedBox(
              width: (MediaQuery.of(context).size.width - 32 - 24) / 3,
              height: 112,
              child: w,
            ),
          )
          .toList(),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String url;
  final VoidCallback onRemove;
  const _Thumb({required this.url, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final src = url.startsWith('http') ? url : '${AppConfig.apiBase}$url';
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(
              src,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: const Color(0xFFF3F4F6),
                child: const Icon(Icons.broken_image, color: Color(0xFF94A3B8)),
              ),
            ),
          ),
        ),
        Positioned(
          top: 6,
          right: 6,
          child: Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onRemove,
              child: const SizedBox(
                width: 24,
                height: 24,
                child: Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddSlot extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;
  const _AddSlot({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: DottedBorder(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFF6A7282),
                    ),
                  ),
                )
              else
                const Icon(
                  Icons.add_a_photo_outlined,
                  size: 28,
                  color: Color(0xFF6A7282),
                ),
              const SizedBox(height: 4),
              const Text(
                'Add',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF6A7282),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DottedBorder extends StatelessWidget {
  final Widget child;
  const DottedBorder({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DottedBorderPainter(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(color: const Color(0xFFF3F4F6), child: child),
      ),
    );
  }
}

class _DottedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD1D5DC)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(16),
    );
    final path = Path()..addRRect(rrect);
    final dashed = _dashPath(path, dashLength: 6, gapLength: 4);
    canvas.drawPath(dashed, paint);
  }

  Path _dashPath(
    Path source, {
    required double dashLength,
    required double gapLength,
  }) {
    final dest = Path();
    for (final metric in source.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = distance + dashLength;
        dest.addPath(metric.extractPath(distance, next), Offset.zero);
        distance = next + gapLength;
      }
    }
    return dest;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
