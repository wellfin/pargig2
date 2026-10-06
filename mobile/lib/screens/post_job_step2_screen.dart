import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../api/home_api.dart';

class PostJobStep2Screen extends StatefulWidget {
  const PostJobStep2Screen({super.key});

  @override
  State<PostJobStep2Screen> createState() => _PostJobStep2ScreenState();
}

class _PostJobStep2ScreenState extends State<PostJobStep2Screen> {
  bool _posting = false;
  String? _error;

  // Read-the-description-back preview. Same setup as Job Details' Play
  // pill, so a dictated description can be checked by ear before posting.
  final FlutterTts _tts = FlutterTts();
  bool _ttsSpeaking = false;
  bool _ttsReady = false;

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _ensureTts() async {
    if (_ttsReady) return;
    _ttsReady = true;
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _ttsSpeaking = false);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _ttsSpeaking = false);
    });
    _tts.setErrorHandler((_) {
      if (mounted) setState(() => _ttsSpeaking = false);
    });
  }

  Future<void> _toggleSpeak(String text) async {
    if (_ttsSpeaking) {
      await _tts.stop();
      if (mounted) setState(() => _ttsSpeaking = false);
      return;
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await _ensureTts();
    if (!mounted) return;
    setState(() => _ttsSpeaking = true);
    await _tts.stop();
    await _tts.speak(trimmed);
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  Map<String, dynamic> _readDraft(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) return args;
    return const {};
  }

  String _formatDateTime(DateTime dt) {
    final h12 = dt.hour == 0
        ? 12
        : dt.hour > 12
        ? dt.hour - 12
        : dt.hour;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${_months[dt.month - 1]} ${dt.day}, $h12:$mm $ampm';
  }

  String _priceText(Map<String, dynamic> draft) {
    final mode = draft['priceMode'] as String? ?? 'open';
    final amt = draft['proposedBudget'];
    if (mode == 'fixed' && amt is num && amt > 0) {
      return '₹${amt.toStringAsFixed(0)}';
    }
    return 'Open to offers';
  }

  // Keyword sets per category. Each list has ONLY category-specific nouns
  // / words — no generic verbs like "fit", "install", "fix", "service"
  // which appear in every category equally and would cause false matches
  // (e.g. "fan fitting" wrongly hitting Carpentry because of "fit").
  //
  // Scoring is word-boundary based, not substring: "fan" matches the word
  // "fan" or "fans" but not "fancy". Higher score wins; ties resolve in
  // declaration order — so Electrical is listed before Carpentry because a
  // "fan" / "switch" / "wire" mention is a much stronger signal than a
  // random "door" reference.
  static const Map<String, List<String>> _categoryKeywords = {
    'Electrical': [
      'electric',
      'electrician',
      'electrical',
      'fan',
      'fans',
      'ceiling fan',
      'exhaust fan',
      'pedestal fan',
      'light',
      'lights',
      'bulb',
      'tubelight',
      'led',
      'cfl',
      'switch',
      'switches',
      'socket',
      'plug point',
      'wire',
      'wires',
      'wiring',
      'rewiring',
      'rewire',
      'mcb',
      'fuse',
      'breaker',
      'circuit',
      'short circuit',
      'inverter',
      'ups',
      'stabilizer',
      'voltage',
      'meter',
      'chandelier',
      'extension',
      'earthing',
    ],
    'Plumbing': [
      'plumber',
      'plumbing',
      'pipe',
      'pipes',
      'piping',
      'tap',
      'taps',
      'faucet',
      'leak',
      'leakage',
      'dripping',
      'drip',
      'drain',
      'drainage',
      'sink',
      'basin',
      'wash basin',
      'flush',
      'toilet',
      'commode',
      'shower',
      'cistern',
      'geyser',
      'water heater',
      'water tank',
      'overhead tank',
      'motor',
      'pump',
      'sewage',
      'choke',
      'choked',
      'clog',
      'clogged',
      'blocked drain',
    ],
    'Carpentry': [
      'carpenter',
      'carpentry',
      'wood',
      'wooden',
      'plywood',
      'mdf',
      'teak',
      'sunmica',
      'door',
      'doors',
      'window frame',
      'cabinet',
      'cupboard',
      'almirah',
      'wardrobe',
      'shelf',
      'shelves',
      'rack',
      'bookshelf',
      'drawer',
      'drawers',
      'table',
      'chair',
      'chairs',
      'sofa frame',
      'bed frame',
      'furniture',
      'hinge',
      'latch',
      'handle',
      'polish',
      'polishing',
    ],
    'Painting': [
      'paint',
      'painting',
      'painter',
      'painters',
      'whitewash',
      'distemper',
      'enamel',
      'primer',
      'colour',
      'color',
      'wall paint',
      'wall painting',
      'putty',
      'texture',
      'roller',
      'spray paint',
    ],
    'Cleaning': [
      'clean',
      'cleaning',
      'cleaner',
      'deep clean',
      'deep cleaning',
      'sweep',
      'sweeping',
      'mop',
      'mopping',
      'dust',
      'dusting',
      'vacuum',
      'sanitize',
      'sanitise',
      'sanitization',
      'scrub',
      'kitchen clean',
      'bathroom clean',
      'sofa clean',
      'carpet clean',
      'maid clean',
    ],
    'Cooking': [
      'cook',
      'cooking',
      'cookbook',
      'chef',
      'kitchen help',
      'tiffin',
      'meal',
      'meals',
      'lunch',
      'dinner',
      'breakfast',
      'roti',
      'sabzi',
      'curry',
      'biryani',
      'cuisine',
      'rasoi',
    ],
    'Babysitting': [
      'babysit',
      'babysitter',
      'babysitting',
      'nanny',
      'child care',
      'childcare',
      'caretaker',
      'kid',
      'kids',
      'baby',
      'toddler',
      'infant',
    ],
    'Delivery': [
      'deliver',
      'delivery',
      'parcel',
      'courier',
      'grocery pickup',
      'food pickup',
    ],
    'Helper': [
      'helper',
      'household help',
      'maid',
      'servant',
      'shifting help',
      'moving help',
      'packing help',
      'loader',
      'labour',
      'labourer',
    ],
    'Repair': [
      'repair',
      'broken',
      'servicing',
      'maintenance',
      'mechanic',
      'ac service',
      'ac repair',
      'ac not cooling',
      'fridge',
      'refrigerator',
      'washing machine',
      'microwave',
      'oven repair',
      'tv repair',
    ],
    'Gardening': [
      'garden',
      'gardening',
      'gardener',
      'plant',
      'plants',
      'lawn',
      'grass',
      'mowing',
      'hedge',
      'mali',
    ],
    'Driving': ['driver', 'driving', 'car drive'],
  };

  // Pre-build regex per category so we don't recompile on every call.
  // Phrases (containing space) get a literal match; single words get a
  // word-boundary match.
  static final Map<String, List<RegExp>> _categoryPatterns = {
    for (final entry in _categoryKeywords.entries)
      entry.key: entry.value.map((kw) {
        final escaped = RegExp.escape(kw);
        if (kw.contains(' ')) {
          return RegExp(escaped, caseSensitive: false);
        }
        return RegExp('\\b$escaped\\b', caseSensitive: false);
      }).toList(),
  };

  /// Best-guess category from title + description. Caller may pass an
  /// explicit `category` on the draft, which wins over the heuristic.
  String _categoryText(Map<String, dynamic> draft) {
    final explicit = (draft['category'] ?? '').toString().trim();
    if (explicit.isNotEmpty) return explicit;

    final blob = '${draft['title'] ?? ''} ${draft['description'] ?? ''}';
    if (blob.trim().isEmpty) return 'General';

    String? bestCat;
    int bestScore = 0;
    _categoryPatterns.forEach((category, patterns) {
      var score = 0;
      for (final p in patterns) {
        if (p.hasMatch(blob)) score++;
      }
      if (score > bestScore) {
        bestScore = score;
        bestCat = category;
      }
    });
    return bestCat ?? 'General';
  }

  Future<void> _post() async {
    if (_posting) return;
    final draft = _readDraft(context);

    setState(() {
      _posting = true;
      _error = null;
    });

    try {
      final body = <String, dynamic>{
        'title': draft['title'],
        'description': draft['description'],
        'priceMode': draft['priceMode'],
        'isUrgent': draft['isUrgent'] ?? false,
        'isBoosted': false,
        'preference': draft['preference'],
        'scheduledAt': draft['scheduledAt'],
        'photos': draft['photos'] ?? const <String>[],
        if (draft['proposedBudget'] != null)
          'proposedBudget': draft['proposedBudget'],
        if (draft['location'] != null) 'location': draft['location'],
        if (draft['voiceNoteUrl'] is String &&
            (draft['voiceNoteUrl'] as String).isNotEmpty)
          'voiceNoteUrl': draft['voiceNoteUrl'],
        'category': _categoryText(draft),
      };

      // Edit mode: draft carries the id of the job being edited (set in
      // step 1 when opened from My Posted Jobs → pencil). Update that job
      // instead of creating a new one.
      final editId = (draft['_editJobId'] ?? '').toString();
      final isEdit = editId.isNotEmpty;
      if (isEdit) {
        await HomeApi.updateJob(editId, body);
      } else {
        await HomeApi.createJob(body);
      }
      if (!mounted) return;

      // Tiny delay so the user actually sees the "Posting…" state on fast
      // networks. Then pop with `true` — Step 1 sees that and itself pops
      // with `true`, which triggers the Hire-view _refresh() back home so
      // the just-posted/updated job appears with its new details.
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;

      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isEdit ? 'Job updated' : 'Job posted')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _posting = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = _readDraft(context);
    final title = (draft['title'] ?? '').toString();
    final isEdit = (draft['_editJobId'] ?? '').toString().isNotEmpty;
    final scheduled = draft['_displayDate'];
    final whenText = (draft['isUrgent'] == true)
        ? 'Immediate'
        : (scheduled is DateTime
              ? _formatDateTime(scheduled)
              : 'Not scheduled');

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Column(
            children: [
              _Step2Header(
                onBack: _posting ? null : () => Navigator.maybePop(context),
              ),
              Expanded(
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ReviewCard(
                          title: title.isEmpty ? '—' : title,
                          category: _categoryText(draft),
                          whenText: whenText,
                          priceText: _priceText(draft),
                          locationText:
                              (draft['_displayLocation'] ?? '')
                                  .toString()
                                  .isEmpty
                              ? '—'
                              : draft['_displayLocation'].toString(),
                          description: (draft['description'] ?? '').toString(),
                          speaking: _ttsSpeaking,
                          onSpeak: () => _toggleSpeak(
                            (draft['description'] ?? '').toString(),
                          ),
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
                          child: OutlinedButton.icon(
                            onPressed: _posting ? null : _post,
                            icon: const Icon(
                              Icons.file_upload_outlined,
                              size: 20,
                              color: Color(0xFFFF6900),
                            ),
                            label: Text(
                              isEdit ? 'Update Job' : 'Post Job',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFFFF6900),
                              ),
                            ),
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
          if (_posting) const _PostingOverlay(),
        ],
      ),
    );
  }
}

class _Step2Header extends StatelessWidget {
  final VoidCallback? onBack;
  const _Step2Header({required this.onBack});

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
              // Balances the back button so the title stays centred.
              const SizedBox(width: 40),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: List.generate(2, (i) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i == 1 ? 0 : 8),
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          const Text(
            'Step 2 of 2',
            style: TextStyle(fontSize: 14, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final String title;
  final String category;
  final String whenText;
  final String priceText;
  final String locationText;
  final String description;
  final bool speaking;
  final VoidCallback onSpeak;

  const _ReviewCard({
    required this.title,
    required this.category,
    required this.whenText,
    required this.priceText,
    required this.locationText,
    required this.description,
    required this.speaking,
    required this.onSpeak,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Review Your Job',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF101828),
            ),
          ),
          const SizedBox(height: 16),
          _ReviewRow(label: 'Title', value: title),
          const SizedBox(height: 12),
          _ReviewRow(label: 'Category', value: category),
          const SizedBox(height: 12),
          _ReviewRow(label: 'Location', value: locationText),
          const SizedBox(height: 12),
          _ReviewRow(label: 'Date & Time', value: whenText),
          const SizedBox(height: 12),
          _ReviewRow(
            label: 'Price',
            value: priceText,
            valueColor: const Color(0xFFFF6900),
            valueWeight: FontWeight.w600,
          ),
          // Description gets its own block rather than a one-line row: it's
          // the field most likely to be wrong (dictated, not typed), so it's
          // shown in full with a Play button to hear it back before posting.
          const SizedBox(height: 16),
          const Divider(height: 1, thickness: 0.8, color: Color(0xFFE5E7EB)),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Description',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF101828),
                  ),
                ),
              ),
              if (description.trim().isNotEmpty)
                _SpeakButton(speaking: speaking, onTap: onSpeak),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description.trim().isEmpty ? '—' : description.trim(),
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: description.trim().isEmpty
                  ? const Color(0xFF9CA3AF)
                  : const Color(0xFF374151),
            ),
          ),
        ],
      ),
    );
  }
}

// "Play" pill on the description preview — mirrors the one on Job Details
// so hearing a job back reads the same before and after posting.
class _SpeakButton extends StatelessWidget {
  final bool speaking;
  final VoidCallback onTap;
  const _SpeakButton({required this.speaking, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: speaking ? const Color(0xFFFF6900) : const Color(0xFFFFEDD4),
      borderRadius: BorderRadius.circular(100),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                speaking ? Icons.pause : Icons.play_arrow,
                size: 16,
                color: speaking ? Colors.white : const Color(0xFFF54900),
              ),
              const SizedBox(width: 6),
              Text(
                speaking ? 'Pause' : 'Play',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: speaking ? Colors.white : const Color(0xFFF54900),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final FontWeight? valueWeight;

  const _ReviewRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.valueWeight,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, color: Color(0xFF6A7282)),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 14,
              fontWeight: valueWeight ?? FontWeight.w500,
              color: valueColor ?? const Color(0xFF101828),
            ),
          ),
        ),
      ],
    );
  }
}

class _PostingOverlay extends StatelessWidget {
  const _PostingOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.white,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            SizedBox(
              width: 64,
              height: 64,
              child: CircularProgressIndicator(
                strokeWidth: 4,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6900)),
              ),
            ),
            SizedBox(height: 24),
            Text(
              'Posting your job...',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Color(0xFF101828),
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Please wait',
              style: TextStyle(fontSize: 16, color: Color(0xFF4A5565)),
            ),
          ],
        ),
      ),
    );
  }
}
