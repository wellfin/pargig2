import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../api/home_api.dart';
import '../config.dart';
// SPEECH-TO-TEXT — TEMPORARILY DISABLED (see _VoiceInputPanel below).
// The transcription layer is parked, not removed: Voice Input is back to
// plain record → upload → play-on-worker's-phone. Re-enable by restoring
// these imports and un-commenting the blocks marked "SPEECH-TO-TEXT".
// import '../services/offline_transcriber.dart';
// import '../services/speech_model.dart';
import '../state/auth_state.dart';
import '../widgets/voice_dictation_panel.dart';
import '../widgets/voice_recorder.dart';

// Job titles are ALPHABETIC ONLY — letters and spaces, nothing else.
//
// Requested explicitly after "2345567c ko poiijggyjhu" and "16161515151"
// were both posted as titles. Note the cost, which is real: "AC repair
// for 2BHK", "Fix 3 taps" and "Sofa shifting to 3rd floor" are now
// rejected too, and several seeded demo jobs would not pass. That is the
// intended trade — the rule is strict on purpose.
//
// Length is deliberately NOT constrained: the giver decides how long a
// title needs to be. The constant below is not a UX limit — it is a stop
// against a pasted novel or a scripted client writing megabytes into the
// database, set far beyond anything a person would ever type.
const int kTitleSafetyLimit = 2000;

final RegExp _lettersRe = RegExp(r'[A-Za-z]');
// Letters and spaces only. Digits, punctuation, emoji and symbols are all
// refused, at the keyboard as well as on submit.
final RegExp _titleCharsRe = RegExp(r'^[A-Za-z ]+$');

/// Returns an error message for [title], or null when it's acceptable.
String? validateJobTitle(String title) {
  final v = title.trim();
  if (v.isEmpty) return 'Job title is required';
  if (v.length < 3) return 'Job title must be at least 3 characters';
  // No upper bound the giver can feel. A title as long as they want to
  // type is their call; the only ceiling is the pathological-paste guard
  // below, which no human writing a title will ever reach.
  if (v.length > kTitleSafetyLimit) {
    return 'Job title is too long to save';
  }
  if (!_titleCharsRe.hasMatch(v)) {
    return 'Job title can only contain letters';
  }
  // Three letters, not one, so "a1" and "12x" don't slip through.
  if (_lettersRe.allMatches(v).length < 3) {
    return 'Job title must describe the work in words';
  }
  return null;
}

/// Returns an error message for a typed [description], or null.
String? validateJobDescription(String description) {
  final v = description.trim();
  if (v.isEmpty) return null; // Emptiness is handled by the caller.
  if (v.length < 10) return 'Description must be at least 10 characters';
  if (_lettersRe.allMatches(v).length < 5) {
    return 'Describe the work in words so workers understand the job';
  }
  return null;
}

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
  // Voice Input records the giver's real microphone audio to an .m4a and
  // uploads it; workers play back that exact file on Job Details. There
  // is no speech-to-text and no speech synthesis anywhere in the path, so
  // tone, accent, pauses, hesitation and background sound are preserved
  // as recorded. _voiceNoteUrl is the uploaded clip's server URL and is
  // what gets posted as the job's voiceNoteUrl.
  String? _voiceNoteUrl;
  // True while a clip is mid-record or mid-upload — blocks Continue so a
  // job can't be posted with a half-captured recording. Always false while
  // the simple dictation panel is in use (it records nothing); the
  // recording panel is what sets it.
  // ignore: prefer_final_fields
  bool _voiceBusy = false;
  // Last transcript auto-filled into the description. Kept so a re-record
  // can replace its own text without wiping wording the giver typed or
  // edited themselves.
  String? _autoDescription;
  // RECENT UI — HIDDEN (not deleted). The box used to lock once it held
  // speech-derived text. It stays editable now: the recogniser mishears
  // often enough that not being able to fix a word was worse than the
  // text drifting from the audio.
  // bool _descFromSpeech = false;
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

  // Set when this screen was opened in EDIT mode (from My Posted Jobs →
  // pencil). Holds the id of the job being edited; when non-null, step 2
  // updates that job instead of creating a new one.
  String? _editJobId;
  bool _prefilledFromEdit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilledFromEdit) return;
    final raw = ModalRoute.of(context)?.settings.arguments;
    // Edit mode: My Posted Jobs passes the whole job document. A plain
    // /post-job push (new job) has no arguments, so this is skipped.
    if (raw is Map && raw['_id'] != null) {
      _prefilledFromEdit = true;
      _prefillFromJob(Map<String, dynamic>.from(raw));
    }
  }

  // Load an existing job's fields into the form for editing.
  void _prefillFromJob(Map<String, dynamic> job) {
    _editJobId = (job['_id'] ?? '').toString();
    _title.text = (job['title'] ?? '').toString();
    _description.text = (job['description'] ?? '').toString();
    // A job posted with a recording reopens in Voice mode with that clip
    // loaded, so editing something else doesn't silently drop the audio.
    final voice = (job['voiceNoteUrl'] ?? '').toString();
    if (voice.trim().isNotEmpty) {
      _voiceNoteUrl = voice;
      _descriptionMode = 'voice';
    }

    final loc = job['location'] is Map ? job['location'] as Map : const {};
    final addr = (loc['address'] ?? '').toString();
    final city = (loc['city'] ?? '').toString();
    final locText = [addr, city].where((s) => s.trim().isNotEmpty).join(', ');
    if (locText.isNotEmpty) _location.text = locText;
    final coords = loc['coordinates'];
    if (coords is List && coords.length == 2) {
      final lng = (coords[0] as num?)?.toDouble();
      final lat = (coords[1] as num?)?.toDouble();
      if (lat != null && lng != null && (lat != 0 || lng != 0)) {
        _lat = lat;
        _lng = lng;
      }
    }

    _urgent = job['isUrgent'] == true;
    final mode = (job['priceMode'] ?? 'fixed').toString();
    if (mode == 'open' || mode == 'fixed') _priceMode = mode;
    final budget = job['proposedBudget'] ?? job['finalPrice'];
    if (budget is num && budget > 0) _amount.text = budget.toStringAsFixed(0);
    final pref = (job['preference'] ?? '').toString();
    if (pref == 'experienced' || pref == 'anyone') _preference = pref;
    final photos = job['photos'];
    if (photos is List) _photoUrls.addAll(photos.whereType<String>());

    // Scheduled slot (non-urgent only). Stored UTC → show as local wall
    // clock, then split back into the date + time pickers.
    final sched = job['scheduledAt'];
    if (!_urgent && sched != null) {
      final dt = DateTime.tryParse(sched.toString())?.toLocal();
      if (dt != null) {
        _date = DateTime(dt.year, dt.month, dt.day);
        _time = TimeOfDay(hour: dt.hour, minute: dt.minute);
      }
    }
    setState(() {});
  }

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

  // The phone transcribed the recording — write it into the Transcribed
  // Text box so the job is readable as well as playable.
  //
  // Only fills a box that's empty or still holds a previous transcript:
  // anything the giver typed or corrected by hand wins over the machine's
  // version, so re-recording can't silently discard their edits.
  //
  // Unused while the simple dictation panel is in place — that one writes
  // into the controller directly. Kept for the recording panel.
  // ignore: unused_element
  void _applyTranscript(String text) {
    final current = _description.text.trim();
    final previous = (_autoDescription ?? '').trim();
    if (current.isNotEmpty && current != previous) return;
    final capped = text.length > 500 ? text.substring(0, 500) : text;
    _autoDescription = capped;
    _description.value = TextEditingValue(
      text: capped,
      selection: TextSelection.collapsed(offset: capped.length),
    );
    setState(() {});
  }

  // RECENT UI — HIDDEN (not deleted). Paired with the locked-text state.
  // // Drops the spoken text so the giver can type their own instead.
  // void _clearSpokenDescription() {
  //   _description.clear();
  //   _autoDescription = null;
  //   setState(() => _descFromSpeech = false);
  // }

  // The address string we pre-fill into _location in initState — used
  // on submit to detect whether the user edited the text. If they did,
  // we forward-geocode the new text so coords stay in sync.
  String _initialAddressFromProfile() {
    final auth = context.read<AuthState>();
    final loc = auth.user?['location'] is Map
        ? auth.user!['location'] as Map
        : const {};
    final addr = (loc['address'] ?? '').toString();
    final city = (loc['city'] ?? '').toString();
    return [addr, city].where((s) => s.trim().isNotEmpty).join(', ');
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
    // Ask the user where the photo should come from — Camera or
    // Gallery. Bottom-sheet result: ImageSource (or null if dismissed).
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Add a job photo',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF101828),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(
                Icons.camera_alt_outlined,
                color: Color(0xFFFF6900),
              ),
              title: const Text(
                'Take a photo',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF101828),
                ),
              ),
              subtitle: const Text('Use your camera right now'),
              onTap: () => Navigator.pop(sheetCtx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
                color: Color(0xFFFF6900),
              ),
              title: const Text(
                'Choose from gallery',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF101828),
                ),
              ),
              subtitle: const Text('Pick from your saved photos'),
              onTap: () => Navigator.pop(sheetCtx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 80,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            source == ImageSource.camera
                ? 'Could not open camera: $e'
                : 'Could not open gallery: $e',
          ),
        ),
      );
      return;
    }
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
    final titleError = validateJobTitle(title);
    if (titleError != null) {
      setState(() => _error = titleError);
      return;
    }
    final desc = _description.text.trim();
    final hasVoice = (_voiceNoteUrl ?? '').isNotEmpty;
    // A recorded voice note IS the description — workers hear it on Job
    // Details — so text is only mandatory when there's no recording.
    if (desc.isEmpty && !hasVoice) {
      setState(
        () => _error = _descriptionMode == 'voice'
            ? 'Record a voice description, or type one instead'
            : 'Description is required',
      );
      return;
    }
    // Typed text still has to say something. Skipped when it's blank and
    // a recording is carrying the description instead.
    if (desc.isNotEmpty) {
      final descError = validateJobDescription(desc);
      if (descError != null) {
        setState(() => _error = descError);
        return;
      }
    }
    if (_voiceBusy) {
      setState(() => _error = 'Finish the voice recording before continuing');
      return;
    }
    if (_location.text.trim().isEmpty) {
      setState(() => _error = 'Location is required');
      return;
    }
    if (!_urgent && (_date == null || _time == null)) {
      setState(() => _error = 'Pick a date and time');
      return;
    }
    if ((double.tryParse(_amount.text.trim()) ?? 0) <= 0) {
      setState(
        () => _error = _priceMode == 'fixed'
            ? 'Enter a fixed-price amount'
            : 'Enter a starting price',
      );
      return;
    }
    if (_preference == null) {
      setState(() => _error = 'Pick a worker preference');
      return;
    }

    setState(() => _error = null);

    DateTime? scheduled;
    if (!_urgent) {
      scheduled = DateTime(
        _date!.year,
        _date!.month,
        _date!.day,
        _time!.hour,
        _time!.minute,
      );
    }
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
    final needsGeocode =
        addr.isNotEmpty &&
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
      // Serialize as UTC (toUtc → trailing 'Z') so the instant is
      // unambiguous. Sending the naive local string ("…T16:23:00.000" with
      // no zone) let a UTC server store it as 16:23 UTC; the app then
      // .toLocal()'d that to 21:53 IST — the schedule showed +5:30 off.
      if (scheduled != null) 'scheduledAt': scheduled.toUtc().toIso8601String(),
      'photos': _photoUrls,
      // Uploaded recording of the giver's voice, played back as-is on the
      // worker's Job Details. Step 2 forwards it to createJob/updateJob.
      if ((_voiceNoteUrl ?? '').isNotEmpty) 'voiceNoteUrl': _voiceNoteUrl,
      'location': _lat != null && _lng != null
          ? {'lat': _lat, 'lng': _lng, 'address': addr}
          : {'address': addr},
      // UI-only fields used by Step 2's review card.
      '_displayDate': scheduled,
      '_displayLocation': addr,
      // When editing, step 2 updates this job instead of creating one.
      if (_editJobId != null && _editJobId!.isNotEmpty)
        '_editJobId': _editJobId,
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
            title: _editJobId != null ? 'Edit Job' : 'Post a Job',
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
                      // Reject disallowed characters at the keyboard, so
                      // the giver sees nothing appear rather than typing a
                      // whole title and being refused at Continue.
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z ]')),
                      ],
                      onChanged: (_) => setState(() {}),
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
                            // Switching to text keeps any recording that's
                            // already uploaded — the recorder unmounts, but
                            // _voiceNoteUrl survives and is still posted.
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
                      // Simple Voice Input: speak, and the words go into
                      // the Transcribed Text box. See the widget's own doc
                      // for what this gives up versus the recorder below.
                      VoiceDictationPanel(
                        description: _description,
                        onChanged: () => setState(() {}),
                      ),
                      // RECORDING PANEL — HIDDEN (not deleted). Captures
                      // the giver's actual voice, uploads it, and lets the
                      // worker play it on Job Details; it also transcribes
                      // the finished file into the same box. Swap the two
                      // blocks to bring it back.
                      // _VoiceInputPanel(
                      //   initialUrl: _voiceNoteUrl,
                      //   onUploaded: (url) =>
                      //       setState(() => _voiceNoteUrl = url),
                      //   onBusyChanged: (busy) =>
                      //       setState(() => _voiceBusy = busy),
                      //   description: _description,
                      //   onChanged: () => setState(() {}),
                      //   onTranscript: _applyTranscript,
                      //   // textLocked: _descFromSpeech,
                      //   // onClearText: _clearSpokenDescription,
                      // ),
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
                    // Date / Time pickers only for scheduled jobs. When the
                    // job is marked urgent, scheduling is disabled and this
                    // whole section is simply hidden (no banner shown).
                    if (!_urgent) ...[
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
                    ],
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
                    if (_priceMode == 'open') ...[
                      const SizedBox(height: 6),
                      const Text(
                        'Shown to workers as a starting point — they can '
                        'still offer their own price.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6A7282),
                        ),
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
  final String title;
  const _Header({
    required this.currentStep,
    required this.totalSteps,
    required this.onBack,
    this.title = 'Post a Job',
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
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              // Balances the back button so the title stays centred.
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
  final List<TextInputFormatter>? inputFormatters;

  const _FilledInput({
    required this.controller,
    required this.hint,
    this.inputFormatters,
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
              inputFormatters: inputFormatters,
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

// Voice Input panel: records the giver's actual microphone audio and
// hands the uploaded clip's URL back to the form. Playback on the
// worker's Job Details streams that same file, so what they hear is the
// giver's real voice — no transcription or synthesis in between.
//
// The typed description sits underneath the recorder rather than being
// replaced by it: the two are independent and both are posted, so Job
// Details can show the written text AND play the recording. Either one
// on its own is enough to submit.
class _VoiceInputPanel extends StatefulWidget {
  final String? initialUrl;
  final ValueChanged<String?> onUploaded;
  final ValueChanged<bool> onBusyChanged;
  final TextEditingController description;
  final VoidCallback onChanged;
  // SPEECH-TO-TEXT — TEMPORARILY DISABLED. Kept optional so the call site
  // can simply stop passing them; make them `required` again when the
  // transcription flow comes back.
  final ValueChanged<String>? onTranscript;
  // Speech-derived text is shown locked — see _descFromSpeech.
  final bool textLocked;
  final VoidCallback? onClearText;

  const _VoiceInputPanel({
    required this.initialUrl,
    required this.onUploaded,
    required this.onBusyChanged,
    required this.description,
    required this.onChanged,
    // ignore: unused_element_parameter
    this.onTranscript,
    // ignore: unused_element_parameter
    this.textLocked = false,
    // ignore: unused_element_parameter
    this.onClearText,
  });

  @override
  State<_VoiceInputPanel> createState() => _VoiceInputPanelState();
}

class _VoiceInputPanelState extends State<_VoiceInputPanel> {
  // SPEECH-TO-TEXT — TEMPORARILY DISABLED.
  // // Null until checked; false while the speech pack is still arriving.
  // bool? _ready;
  // double _progress = 0;
  //
  // @override
  // void initState() {
  //   super.initState();
  //   _prepare();
  // }
  //
  // /// Fetches the speech pack before showing the recorder, so the first
  // /// recording can produce text rather than silently falling back. If the
  // /// download can't complete (no network, say), the panel opens anyway —
  // /// recording and typing must never be blocked by it.
  // Future<void> _prepare() async {
  //   if (await SpeechModel.isReady()) {
  //     if (!mounted) return;
  //     setState(() => _ready = true);
  //     OfflineTranscriber.ensureLoaded();
  //     return;
  //   }
  //   if (!mounted) return;
  //   setState(() => _ready = false);
  //   final ok = await SpeechModel.download(
  //     onProgress: (p) {
  //       if (mounted) setState(() => _progress = p);
  //     },
  //   );
  //   if (!mounted) return;
  //   // Open the panel either way. A failed download only costs automatic
  //   // text — the recorder still works, and its own fallback covers it.
  //   setState(() => _ready = true);
  //   if (ok) await OfflineTranscriber.ensureLoaded();
  // }

  // No speech pack to fetch any more, so the recorder shows immediately —
  // no "Setting up voice input…" wait on first open.
  @override
  Widget build(BuildContext context) {
    // if (_ready != true) return _loadingPanel();
    return _contentPanel();
  }

  // SPEECH-TO-TEXT — TEMPORARILY DISABLED.
  // /// Shown in place of the mic and description box while the pack loads.
  // Widget _loadingPanel() {
  //   final pct = (_progress * 100).round();
  //   return Container(
  //     width: double.infinity,
  //     padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
  //     decoration: BoxDecoration(
  //       color: const Color(0xFFEFF6FF),
  //       borderRadius: BorderRadius.circular(16),
  //       border: Border.all(color: const Color(0xFFBEDBFF), width: 1.5),
  //     ),
  //     child: Column(
  //       children: [
  //         SizedBox(
  //           width: 46,
  //           height: 46,
  //           child: CircularProgressIndicator(
  //             // Indeterminate until the first bytes land, so it doesn't
  //             // sit frozen at 0% while the request is still connecting.
  //             value: _progress > 0 ? _progress : null,
  //             strokeWidth: 3.2,
  //             backgroundColor: const Color(0xFFDBEAFE),
  //             valueColor:
  //                 const AlwaysStoppedAnimation<Color>(Color(0xFF2B7FFF)),
  //           ),
  //         ),
  //         const SizedBox(height: 18),
  //         Text(
  //           _progress > 0 ? 'Loading… $pct%' : 'Loading…',
  //           style: const TextStyle(
  //             fontSize: 16,
  //             fontWeight: FontWeight.w700,
  //             color: Color(0xFF408EE0),
  //           ),
  //         ),
  //         const SizedBox(height: 6),
  //         const Text(
  //           'Setting up voice input for the first time. This happens once.',
  //           textAlign: TextAlign.center,
  //           style: TextStyle(fontSize: 13, color: Color(0xFF155DFC)),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  Widget _contentPanel() {
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
          VoiceRecorder(
            initialUrl: widget.initialUrl,
            onUploaded: widget.onUploaded,
            onBusyChanged: widget.onBusyChanged,
            onTranscript: widget.onTranscript,
          ),
          // RECENT UI — HIDDEN (not deleted). The original design runs the
          // mic straight into the text card with no rule between them.
          // const SizedBox(height: 18),
          // const Divider(height: 1, thickness: 0.8, color: Color(0xFFBEDBFF)),
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
                // RECENT UI — HIDDEN (not deleted). The "(optional if you
                // recorded)" / "(from your voice — locked)" header and its
                // Clear action belong to the speech-to-text flow, which is
                // off — the box is plain typed text again.
                // Row(
                //   children: [
                //     const Text(
                //       'Description',
                //       style: TextStyle(
                //         fontSize: 12,
                //         fontWeight: FontWeight.w700,
                //         color: Color(0xFF408EE0),
                //       ),
                //     ),
                //     const SizedBox(width: 6),
                //     Expanded(
                //       child: Text(
                //         widget.textLocked
                //             ? '(from your voice — locked)'
                //             : '(optional if you recorded)',
                //         style: const TextStyle(
                //           fontSize: 11,
                //           color: Color(0xFF6A7282),
                //         ),
                //       ),
                //     ),
                //     if (widget.textLocked)
                //       GestureDetector(
                //         onTap: widget.onClearText,
                //         child: const Text(
                //           'Clear',
                //           style: TextStyle(
                //             fontSize: 12,
                //             fontWeight: FontWeight.w700,
                //             color: Color(0xFFDC2626),
                //           ),
                //         ),
                //       ),
                //   ],
                // ),
                const SizedBox(height: 8),
                TextField(
                  controller: widget.description,
                  maxLines: 4,
                  minLines: 2,
                  maxLength: 500,
                  // Always editable now — with speech-to-text off there is
                  // no machine transcript for typing to contradict.
                  // RECENT UI — HIDDEN (not deleted):
                  // readOnly: widget.textLocked,
                  onChanged: (_) => widget.onChanged(),
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF101828),
                    height: 1.43,
                  ),
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    contentPadding: EdgeInsets.zero,
                    counterText: '',
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
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${widget.description.text.length}/500 characters',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6A7282),
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
