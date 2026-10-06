import 'package:flutter/material.dart';

import '../api/api_client.dart';
import 'rating_thanks_screen.dart';

/// Args for Navigator.pushNamed('/rate-experience', ...).
class RateExperienceArgs {
  final String jobId;
  final String? jobTitle;
  final String? clientName;
  // Where to land once the rating is submitted or skipped. The worker
  // flow leaves this null and keeps its Rating Thanks → Payment Request
  // hand-off; the giver flow passes '/my-posted-jobs'.
  final String? nextRoute;

  /// When true the rating must be given before leaving: no skip link, no
  /// back button, and the system back gesture is blocked. Set on the job
  /// giver's flow, where rating the worker is required.
  final bool mandatory;

  const RateExperienceArgs({
    required this.jobId,
    this.jobTitle,
    this.clientName,
    this.nextRoute,
    this.mandatory = false,
  });
}

/// Figma "Rate Experience" — the worker rates the client after the
/// job wraps. 1-5 star tap-to-set rating, multi-select tag chips
/// (Professional, Quality Work, Friendly, Clean, Affordable),
/// optional freeform review, and a Submit Rating button that POSTs
/// to /ratings.
///
/// When [RateExperienceArgs.mandatory] is set — the job giver rating the
/// worker — there is no way past this screen without a star: the skip
/// link and back button are gone and the system back gesture is blocked.
/// Otherwise an "Optional" link skips, so a worker who would rather not
/// rate the client is not held up.
class RateExperienceScreen extends StatefulWidget {
  const RateExperienceScreen({super.key});

  @override
  State<RateExperienceScreen> createState() => _RateExperienceScreenState();
}

class _RateExperienceScreenState extends State<RateExperienceScreen> {
  static const List<String> _allTags = [
    'Professional',
    'On Time',
    'Quality Work',
    'Friendly',
    'Clean',
    'Affordable',
  ];

  RateExperienceArgs? _args;
  int _stars = 0;
  final Set<String> _tags = {};
  final _reviewCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_args != null) return;
    final raw = ModalRoute.of(context)?.settings.arguments;
    if (raw is RateExperienceArgs) {
      setState(() => _args = raw);
    }
  }

  @override
  void dispose() {
    _reviewCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final id = _args?.jobId;
    if (id == null || _stars < 1 || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ApiClient.post('/ratings', {
        'jobId': id,
        'stars': _stars,
        'review': _reviewCtrl.text.trim(),
        'tags': _tags.toList(),
      });
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/rating-thanks',
        (_) => false,
        arguments: RatingThanksArgs(
          jobId: id,
          jobTitle: _args?.jobTitle,
          clientName: _args?.clientName,
          nextRoute: _args?.nextRoute,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e is ApiException ? e.message : e.toString();
      });
    }
  }

  bool get _mandatory => _args?.mandatory ?? false;

  // Skipping lands the user wherever the caller said the flow ends. Not
  // reachable at all in the mandatory flow — the guard is belt-and-braces
  // in case a route is ever wired straight to it.
  void _skip() {
    if (_mandatory) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      _args?.nextRoute ?? '/home',
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = (_args?.jobTitle ?? '').trim();
    final clientLabel = (_args?.clientName ?? '').trim();
    final canSubmit = !_submitting && _stars >= 1;
    return PopScope(
      // Blocks the hardware/gesture back, which would otherwise walk
      // around a hidden back button.
      canPop: !_mandatory,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _topBar(
                mandatory: _mandatory,
                onBack: () {
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  } else {
                    Navigator.pushReplacementNamed(context, '/home');
                  }
                },
                onSkip: _skip,
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        title.isEmpty ? 'Rate Experience' : title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF101828),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        clientLabel.isEmpty
                            ? 'How was your experience?'
                            : 'How was your experience with $clientLabel?',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _starsRow(),
                    const SizedBox(height: 22),
                    const Text(
                      'Select tags',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF101828),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _tagsWrap(),
                    const SizedBox(height: 22),
                    const Text(
                      'Write a review (Optional)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF101828),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _reviewField(),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _bottomBar(canSubmit),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar({
    required bool mandatory,
    required VoidCallback onBack,
    required VoidCallback onSkip,
  }) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB), width: 0.8),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      child: Row(
        children: [
          if (mandatory)
            // Keeps the title centred where the back button was.
            const SizedBox(width: 48)
          else
            IconButton(
              onPressed: onBack,
              icon: const Icon(
                Icons.arrow_back,
                size: 22,
                color: Color(0xFF101828),
              ),
            ),
          const Expanded(
            child: Center(
              child: Text(
                'Rate Experience',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF101828),
                ),
              ),
            ),
          ),
          if (mandatory)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Required',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFFF6900),
                ),
              ),
            )
          else
            TextButton(
              onPressed: onSkip,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Optional',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _starsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        final filled = i < _stars;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              setState(() {
                // Tapping the currently-set top star clears it.
                _stars = (_stars == i + 1) ? 0 : i + 1;
                _error = null;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(
                filled ? Icons.star : Icons.star_border,
                size: 36,
                color: filled
                    ? const Color(0xFFFFB400)
                    : const Color(0xFFD1D5DB),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _tagsWrap() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _allTags.map((t) {
        final selected = _tags.contains(t);
        return InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () {
            setState(() {
              if (selected) {
                _tags.remove(t);
              } else {
                _tags.add(t);
              }
            });
          },
          child: Container(
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFFFEDD4) : Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected
                    ? const Color(0xFFFF6900)
                    : const Color(0xFFE5E7EB),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              t,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected
                    ? const Color(0xFFFF6900)
                    : const Color(0xFF374151),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _reviewField() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: TextField(
        controller: _reviewCtrl,
        minLines: 3,
        maxLines: 5,
        maxLength: 1000,
        style: const TextStyle(fontSize: 13.5, color: Color(0xFF101828)),
        decoration: const InputDecoration(
          isCollapsed: true,
          counterText: '',
          border: InputBorder.none,
          hintText: 'Share your experience...',
          hintStyle: TextStyle(fontSize: 13.5, color: Color(0xFF9CA3AF)),
        ),
      ),
    );
  }

  Widget _bottomBar(bool canSubmit) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE5E7EB), width: 0.8)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: SizedBox(
          height: 48,
          width: double.infinity,
          child: OutlinedButton(
            onPressed: canSubmit ? _submit : null,
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              side: BorderSide(
                color: canSubmit
                    ? const Color(0xFFFF6900)
                    : const Color(0xFFE5E7EB),
                width: 1.4,
              ),
              foregroundColor: const Color(0xFFFF6900),
              disabledForegroundColor: const Color(0xFF9CA3AF),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFFFF6900),
                      ),
                    ),
                  )
                : const Text(
                    'Submit Rating',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ),
    );
  }
}
