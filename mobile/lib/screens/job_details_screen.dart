import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/home_api.dart';
import '../config.dart';
import '../services/routing.dart';
import '../state/auth_state.dart';
import 'apply_for_job_screen.dart';
import 'chat_screen.dart';

class JobDetailsScreen extends StatefulWidget {
  const JobDetailsScreen({super.key});

  @override
  State<JobDetailsScreen> createState() => _JobDetailsScreenState();
}

class _JobDetailsScreenState extends State<JobDetailsScreen> {
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  Map<String, dynamic>? _job;
  bool _loading = true;
  String? _error;
  String? _jobId;
  bool _isFav = false;
  // True while the POST/DELETE to /users/me/favorites/:jobId is in flight
  // so a double-tap can't fire two overlapping requests.
  bool _favSaving = false;
  // Road distance from OSRM (km) — null while pending or on failure.
  // When null, _distanceText falls back to the haversine estimate.
  double? _roadKm;
  bool _routingFetched = false; // ensures we only call OSRM once per job

  // Voice-note playback state. _voicePlayer streams the m4a directly
  // from the backend URL — no temp download. _voicePlaying tracks the
  // play/stop toggle; _voicePlayerSub flips it back to false on
  // playback completion.
  final AudioPlayer _voicePlayer = AudioPlayer();
  bool _voicePlaying = false;
  StreamSubscription<void>? _voicePlayerSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_jobId == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is String) {
        _jobId = args;
      } else if (args is Map && args['id'] is String) {
        _jobId = args['id'] as String;
      }
      _load();
    }
  }

  @override
  void dispose() {
    _voicePlayerSub?.cancel();
    _voicePlayer.dispose();
    super.dispose();
  }

  Future<void> _toggleVoicePlayback(String voiceUrl) async {
    final full = voiceUrl.startsWith('http')
        ? voiceUrl
        : '${AppConfig.apiBase}$voiceUrl';
    if (_voicePlaying) {
      await _voicePlayer.stop();
      if (!mounted) return;
      setState(() => _voicePlaying = false);
      return;
    }
    try {
      _voicePlayerSub?.cancel();
      _voicePlayerSub = _voicePlayer.onPlayerComplete.listen((_) {
        if (!mounted) return;
        setState(() => _voicePlaying = false);
      });
      await _voicePlayer.play(UrlSource(full));
      if (!mounted) return;
      setState(() => _voicePlaying = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not play voice note: $e')),
      );
    }
  }

  Future<void> _load() async {
    if (_jobId == null) {
      setState(() {
        _loading = false;
        _error = 'Missing job id';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final job = await HomeApi.jobById(_jobId!);
      if (!mounted) return;
      setState(() {
        _job = job;
        _loading = false;
      });
      // Fire-and-forget — figuring out whether this job is already in
      // the user's wishlist shouldn't block rendering the details.
      // ignore: unawaited_futures
      _loadFavoriteState();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // Resolves whether _jobId sits in the current user's favouriteJobs
  // list so the heart icon opens in the correct (filled vs outline)
  // state. Failures are silent — the heart just renders as "not
  // favourited" and the user can still tap to favourite normally.
  Future<void> _loadFavoriteState() async {
    if (_jobId == null) return;
    try {
      final res = await ApiClient.get('/users/me/favorites');
      if (!mounted) return;
      final items = (res is Map && res['items'] is List)
          ? res['items'] as List
          : const [];
      final isFav = items.any((j) {
        if (j is Map) {
          return (j['_id'] ?? '').toString() == _jobId;
        }
        return false;
      });
      if (isFav != _isFav) {
        setState(() => _isFav = isFav);
      }
    } catch (_) {
      // Silent — heart stays at default (outline) state.
    }
  }

  Future<void> _toggleFavorite() async {
    if (_jobId == null || _favSaving) return;
    final wasFav = _isFav;
    // Optimistic flip so the heart responds immediately. Roll back on
    // error so the user isn't lied to about what the server saved.
    setState(() {
      _isFav = !wasFav;
      _favSaving = true;
    });
    try {
      if (wasFav) {
        await ApiClient.delete('/users/me/favorites/$_jobId');
      } else {
        await ApiClient.post('/users/me/favorites/$_jobId', const {});
      }
      if (!mounted) return;
      setState(() => _favSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(wasFav ? 'Removed from wishlist' : 'Added to wishlist'),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isFav = wasFav;
        _favSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not update wishlist: '
            '${e.toString().replaceFirst('Exception: ', '')}',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _confirmCancel() async {
    if (_job == null || _jobId == null) return;
    final cancelled = await Navigator.pushNamed(
      context,
      '/cancel-job',
      arguments: {
        'id': _jobId,
        'title': (_job!['title'] ?? '').toString(),
      },
    );
    if (cancelled == true && mounted) {
      // The job-details view's status is now stale; bubble back to home
      // so its Active Jobs list re-fetches and the cancelled job drops out.
      Navigator.pop(context, true);
    }
  }

  Future<void> _viewApplicants() async {
    if (_jobId == null) return;
    final accepted = await Navigator.pushNamed(
      context,
      '/applicants',
      arguments: _jobId,
    );
    if (accepted == true && mounted) {
      // Status flipped from open -> confirmed; reload so the bottom action
      // bar disables Cancel/View correctly and the applicants count updates.
      _load();
      // Bubble back to the home Hire view so its Active Jobs list refreshes too.
      if (mounted) Navigator.pop(context, true);
    }
  }

  String _formatDate(DateTime dt) {
    return '${_months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _formatTime(DateTime dt) {
    final h12 = dt.hour == 0
        ? 12
        : dt.hour > 12
            ? dt.hour - 12
            : dt.hour;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$h12:$mm $ampm';
  }

  String _memberSince(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    return '${_months[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _Header(
            onBack: () => Navigator.maybePop(context),
            isFav: _isFav,
            onFavTap: _toggleFavorite,
          ),
          Expanded(child: _buildBody()),
          if (_job != null && !_loading) _buildBottomBar(),
        ],
      ),
    );
  }

  // Picks the right bottom bar based on whether the current user owns
  // this job: owners see Cancel / View Applicants, everyone else sees
  // Apply (and only when the job is still open).
  Widget _buildBottomBar() {
    final job = _job!;
    final me = context.read<AuthState>().user?['_id']?.toString();
    String? giverId;
    final g = job['jobgiver'];
    if (g is Map) {
      giverId = g['_id']?.toString();
    } else if (g != null) {
      giverId = g.toString();
    }
    final isOwner = me != null && giverId != null && me == giverId;
    final status = (job['status'] ?? '').toString();
    if (isOwner) {
      return _BottomActions(
        applicants: (job['interested'] is List)
            ? (job['interested'] as List).length
            : 0,
        cancelDisabled: ['completed', 'cancelled'].contains(status),
        onCancel: _confirmCancel,
        onViewApplicants: _viewApplicants,
      );
    }
    final alreadyApplied = _alreadyApplied(job, me);
    final canApply = status == 'open' && !alreadyApplied;
    return _ApplyBottomBar(
      disabled: !canApply,
      label: alreadyApplied
          ? 'Already Applied'
          : (status == 'open' ? 'Apply for Job' : 'Job Closed'),
      onTap: canApply ? () => _openApplyScreen(job) : null,
    );
  }

  bool _alreadyApplied(Map<String, dynamic> job, String? meId) {
    if (meId == null) return false;
    final list = job['interested'];
    if (list is! List) return false;
    for (final entry in list) {
      if (entry is! Map) continue;
      final jt = entry['jobtaker'];
      final jtId = jt is Map ? jt['_id']?.toString() : jt?.toString();
      if (jtId == meId) return true;
    }
    return false;
  }

  Future<void> _openApplyScreen(Map<String, dynamic> job) async {
    final id = (job['_id'] ?? _jobId ?? '').toString();
    if (id.isEmpty) return;
    final suggested =
        (job['proposedBudget'] ?? job['finalPrice'] ?? 0) as num;
    final title = (job['title'] ?? 'Job').toString();
    final result = await Navigator.pushNamed(
      context,
      '/apply-for-job',
      arguments: ApplyForJobArgs(
        jobId: id,
        jobTitle: title,
        suggestedPrice: suggested,
        priceMode: (job['priceMode'] ?? 'open').toString(),
      ),
    );
    if (result == true && mounted) {
      // Refresh so the "Already Applied" state shows + applicant count
      // bumps if we ever expose that to non-owners.
      _load();
    }
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6900)),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFDC2626)),
          ),
        ),
      );
    }
    final job = _job;
    if (job == null) return const SizedBox.shrink();

    final title = (job['title'] ?? '').toString();
    final category = (job['category'] ?? 'Other').toString();
    final isUrgent = job['isUrgent'] == true;
    final priceMode = (job['priceMode'] ?? 'open').toString();
    final price = (job['finalPrice'] ?? job['proposedBudget'] ?? 0) as num;
    final scheduledAt = job['scheduledAt']?.toString();
    final scheduledDt = scheduledAt != null
        ? DateTime.tryParse(scheduledAt)
        : null;
    final desc = (job['description'] ?? '').toString();
    final voiceUrl = (job['voiceNoteUrl'] ?? '').toString();
    final loc = job['location'] is Map
        ? job['location'] as Map
        : const {};
    final locText = [loc['address'], loc['city'], loc['pincode']]
        .map((s) => (s ?? '').toString())
        .where((s) => s.trim().isNotEmpty)
        .join(', ');
    final photos = (job['photos'] is List)
        ? (job['photos'] as List).whereType<String>().toList()
        : <String>[];
    final applicants = (job['interested'] is List)
        ? (job['interested'] as List).length
        : 0;
    final giver = job['jobgiver'] is Map
        ? job['jobgiver'] as Map
        : const {};
    final giverName = (giver['name'] ?? 'Job Giver').toString();
    final giverRating = giver['rating'] is num
        ? (giver['rating'] as num).toStringAsFixed(1)
        : '5.0';
    final giverSince = _memberSince(giver['createdAt']?.toString());

    // Surface the active 6-digit OTP — completion code takes priority
    // over the start code because it's only present at the later
    // hand-off. Verified codes are skipped so the card disappears
    // once the worker has typed it in.
    String? otpCode;
    String? otpHint;
    final completeOtp =
        job['completeOtp'] is Map ? job['completeOtp'] as Map : null;
    final startOtp =
        job['startOtp'] is Map ? job['startOtp'] as Map : null;
    if (completeOtp != null &&
        completeOtp['code'] != null &&
        completeOtp['verifiedAt'] == null) {
      otpCode = completeOtp['code'].toString();
      otpHint = 'Share this with the worker to release payment';
    } else if (startOtp != null &&
        startOtp['code'] != null &&
        startOtp['verifiedAt'] == null) {
      otpCode = startOtp['code'].toString();
      otpHint = 'Share this with the worker to start the job';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PhotoStrip(photos: photos, category: category),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.isEmpty ? '—' : title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF101828),
                          height: 1.33,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _Tag(
                            label: category,
                            bg: const Color(0xFFFFEDD4),
                            fg: const Color(0xFFF54900),
                          ),
                          if (isUrgent)
                            _Tag(
                              label: 'Urgent',
                              bg: const Color(0xFFFFE2E2),
                              fg: const Color(0xFFE7000B),
                            ),
                          _Tag(
                            label: 'One-time',
                            bg: const Color(0xFFDBEAFE),
                            fg: const Color(0xFF155DFC),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      price > 0 ? '₹${price.toInt()}' : 'Open',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF101828),
                      ),
                    ),
                    Text(
                      priceMode == 'fixed' ? 'fixed' : 'open',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF6A7282),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _OrangeInfoCard(
              distance: _distanceText(job),
              duration: _durationText(job),
              payment: 'Cash or Online',
            ),
          ),
          if (otpCode != null) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _OtpDisplayCard(
                code: otpCode,
                hint: otpHint ?? 'Share this with the worker',
              ),
            ),
          ],
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _InfoGrid(
              location: locText.isEmpty ? '—' : locText,
              date: scheduledDt != null ? _formatDate(scheduledDt) : '—',
              time: scheduledDt != null ? _formatTime(scheduledDt) : '—',
              applicants: '$applicants applied',
            ),
          ),
          const SizedBox(height: 24),
          if (voiceUrl.trim().isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _VoiceNoteCard(
                isPlaying: _voicePlaying,
                onTap: () => _toggleVoicePlayback(voiceUrl),
              ),
            ),
            const SizedBox(height: 24),
          ],
          if (desc.trim().isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Description',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF101828),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                desc,
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF364153),
                  height: 1.625,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Requirements',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF101828),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _requirementsFor(category)
                  .map((r) => _RequirementBullet(text: r))
                  .toList(),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Builder(builder: (context) {
              final giverId = (giver['_id'] ?? '').toString();
              final giverMobile = (giver['mobile'] ?? '').toString();
              final me = context.read<AuthState>().user?['_id']?.toString();
              // Hide the chat icon on the user's own posted job — you
              // can't chat with yourself.
              final showChat = giverId.isNotEmpty && giverId != me;
              return _PostedByCard(
                name: giverName,
                rating: giverRating,
                memberSince: giverSince,
                jobsPosted: giver['jobsPosted'] is num
                    ? (giver['jobsPosted'] as num).toInt()
                    : 1,
                onChatTap: showChat
                    ? () => Navigator.pushNamed(
                          context,
                          '/chat',
                          arguments: ChatArgs(
                            name: giverName,
                            userId: giverId,
                            mobile: giverMobile.isEmpty ? null : giverMobile,
                          ),
                        )
                    : null,
              );
            }),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Builder(builder: (context) {
              final user = context.read<AuthState>().user;
              final freeLeft = user?['freeJobsRemaining'] is num
                  ? (user!['freeJobsRemaining'] as num).toInt()
                  : 0;
              return _PlatformChargesCard(freeJobsRemaining: freeLeft);
            }),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _distanceText(Map<String, dynamic> job) {
    final jobLoc = job['location'];
    final jobCoords = (jobLoc is Map ? jobLoc['coordinates'] : null);
    if (jobCoords is! List ||
        jobCoords.length != 2 ||
        (jobCoords[0] == 0 && jobCoords[1] == 0)) {
      return '—';
    }
    final jobLng = (jobCoords[0] as num).toDouble();
    final jobLat = (jobCoords[1] as num).toDouble();

    // Reference point = the viewer's workArea (search center). Fall back
    // to the home address coords if workArea isn't set. Both are stored
    // as GeoJSON [lng, lat].
    final user = context.read<AuthState>().user ?? const <String, dynamic>{};
    List? refCoords;
    final wa = user['workArea'];
    if (wa is Map && wa['coordinates'] is List) {
      final c = wa['coordinates'] as List;
      if (c.length == 2 && !(c[0] == 0 && c[1] == 0)) refCoords = c;
    }
    if (refCoords == null) {
      final home = user['location'];
      if (home is Map && home['coordinates'] is List) {
        final c = home['coordinates'] as List;
        if (c.length == 2 && !(c[0] == 0 && c[1] == 0)) refCoords = c;
      }
    }
    if (refCoords == null) return 'Nearby';

    final refLng = (refCoords[0] as num).toDouble();
    final refLat = (refCoords[1] as num).toDouble();

    // Kick off the road-distance lookup once per job. While we wait we
    // display the haversine estimate so the UI never sits empty.
    if (!_routingFetched) {
      _routingFetched = true;
      Routing.roadDistanceKm(refLat, refLng, jobLat, jobLng).then((km) {
        if (km != null && mounted) setState(() => _roadKm = km);
      });
    }

    // Prefer OSRM road distance when we have it; haversine otherwise.
    final km = _roadKm ?? _haversineKm(refLat, refLng, jobLat, jobLng);
    if (km < 1) return '${(km * 1000).round()} m away';
    if (km < 10) return '${km.toStringAsFixed(1)} km away';
    return '${km.round()} km away';
  }

  // Haversine — great-circle distance between two lat/lng pairs in km.
  // Earth radius 6371 km (mean). Good to ~0.5% over typical job ranges.
  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLng = _deg2rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  double _deg2rad(double d) => d * math.pi / 180;

  String _durationText(Map<String, dynamic> job) {
    // Description-derived heuristic — backend doesn't store a duration field.
    final d = (job['description'] ?? '').toString().toLowerCase();
    final m = RegExp(r'(\d+)\s*-\s*(\d+)\s*hour').firstMatch(d);
    if (m != null) return '${m.group(1)}-${m.group(2)} hours';
    final s = RegExp(r'(\d+)\s*hour').firstMatch(d);
    if (s != null) return '${s.group(1)} hours';
    return '2-3 hours';
  }

  List<String> _requirementsFor(String category) {
    final lower = category.toLowerCase();
    if (lower.contains('clean')) {
      return const [
        'Own cleaning supplies',
        'Experience with deep cleaning',
        'Punctuality is important',
        'Respectful and professional',
      ];
    }
    if (lower.contains('plumb')) {
      return const [
        'Own plumbing tools',
        'Experience with leaks and pipes',
        'Punctuality is important',
        'Respectful and professional',
      ];
    }
    if (lower.contains('electric')) {
      return const [
        'Own electrical tools',
        'Certified electrician preferred',
        'Punctuality is important',
        'Respectful and professional',
      ];
    }
    if (lower.contains('carp') || lower.contains('wood')) {
      return const [
        'Own carpentry tools (drill, hammer, level)',
        'Experience with wooden doors, frames, and furniture',
        'Punctuality is important',
        'Respectful and professional',
      ];
    }
    if (lower.contains('paint')) {
      return const [
        'Own painting kit (brushes, roller, drop cloth)',
        'Experience with wall and surface preparation',
        'Punctuality is important',
        'Respectful and professional',
      ];
    }
    if (lower.contains('repair') || lower.contains('mechanic')) {
      return const [
        'Own basic toolkit',
        'Experience with the specific appliance/equipment',
        'Punctuality is important',
        'Respectful and professional',
      ];
    }
    if (lower.contains('cook')) {
      return const [
        'Experience with Indian home-style cooking',
        'Hygiene and clean handling',
        'Punctuality is important',
        'Respectful and professional',
      ];
    }
    if (lower.contains('baby') || lower.contains('child')) {
      return const [
        'Experience caring for children',
        'Patience and warm demeanor',
        'Punctuality is important',
        'Respectful and professional',
      ];
    }
    if (lower.contains('deliver')) {
      return const [
        'Own two-wheeler with valid licence',
        'Smartphone with active GPS',
        'Punctuality is important',
        'Respectful and professional',
      ];
    }
    if (lower.contains('helper') || lower.contains('shift')) {
      return const [
        'Able to lift moderate loads safely',
        'Available for the full booked window',
        'Punctuality is important',
        'Respectful and professional',
      ];
    }
    if (lower.contains('garden')) {
      return const [
        'Own gardening tools (trimmer, shears)',
        'Experience with lawn / plant care',
        'Punctuality is important',
        'Respectful and professional',
      ];
    }
    if (lower.contains('driv')) {
      return const [
        'Valid commercial driving licence',
        'Clean driving history',
        'Punctuality is important',
        'Respectful and professional',
      ];
    }
    return const [
      'Relevant experience',
      'Own tools where required',
      'Punctuality is important',
      'Respectful and professional',
    ];
  }
}

class _Header extends StatelessWidget {
  final VoidCallback? onBack;
  final bool isFav;
  final VoidCallback? onFavTap;
  const _Header({required this.onBack, this.isFav = false, this.onFavTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF408EE0),
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 1.5,
            offset: Offset(0, 1),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 16,
        16,
        16,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: onBack,
                child: const Icon(Icons.arrow_back,
                    size: 24, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Text(
              'Job Details',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          SizedBox(
            width: 40,
            height: 40,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: onFavTap,
                child: Icon(
                  isFav ? Icons.favorite : Icons.favorite_border,
                  size: 22,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoStrip extends StatelessWidget {
  final List<String> photos;
  final String category;
  const _PhotoStrip({required this.photos, required this.category});

  @override
  Widget build(BuildContext context) {
    // Figma layout: two square-ish images side-by-side at the top of
    // job details. Always renders — when the job has fewer than 2
    // photos, the empty slots show a category-tinted placeholder so the
    // page doesn't collapse and the user knows photos *can* live here.
    Widget slot(int i) {
      final hasPhoto = i < photos.length && photos[i].trim().isNotEmpty;
      final src = hasPhoto
          ? (photos[i].startsWith('http')
              ? photos[i]
              : '${AppConfig.apiBase}${photos[i]}')
          : null;
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 1,
          child: src != null
              ? Image.network(
                  src,
                  fit: BoxFit.cover,
                  loadingBuilder: (ctx, child, prog) {
                    if (prog == null) return child;
                    return _placeholder(category);
                  },
                  errorBuilder: (_, _, _) => _placeholder(category),
                )
              : _placeholder(category),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: slot(0)),
          const SizedBox(width: 10),
          Expanded(child: slot(1)),
        ],
      ),
    );
  }

  Widget _placeholder(String cat) {
    return Container(
      color: const Color(0xFFFFF7ED),
      child: Center(
        child: Icon(
          _iconForCategory(cat),
          size: 36,
          color: const Color(0xFFFFA34D),
        ),
      ),
    );
  }

  IconData _iconForCategory(String cat) {
    switch (cat.toLowerCase()) {
      case 'cleaning':
        return Icons.cleaning_services;
      case 'plumbing':
        return Icons.plumbing;
      case 'electrical':
        return Icons.electrical_services;
      case 'painting':
        return Icons.format_paint;
      case 'carpentry':
        return Icons.handyman;
      case 'gardening':
        return Icons.grass;
      case 'ac repair':
      case 'appliance repair':
        return Icons.build_circle;
      default:
        return Icons.image_outlined;
    }
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const _Tag({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 14, color: fg),
      ),
    );
  }
}

/// Inline OTP display rendered on Job Details when the job has an
/// unverified start or completion OTP. Six rounded digit boxes
/// matching the Figma + a Copy OTP outlined button below. The code
/// itself comes through the regular /jobs/:id payload — no extra
/// fetch — so it stays in sync with whatever the latest
/// /reach or /complete call generated on the worker side.
class _OtpDisplayCard extends StatelessWidget {
  final String code;
  final String hint;

  const _OtpDisplayCard({required this.code, required this.hint});

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('OTP $code copied'),
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Pad / truncate to 6 boxes so the widget renders cleanly even
    // if the backend ever emits a different length.
    final chars = code.padRight(6).split('').take(6).toList();
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD9B3), width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        children: [
          const Text(
            'Your One-Time Password',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF7E2A0C),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: chars
                .map((d) => _OtpDigitBox(digit: d.trim()))
                .toList(),
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF7E2A0C),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: OutlinedButton.icon(
              onPressed: () => _copy(context),
              icon: const Icon(Icons.copy_outlined,
                  size: 14, color: Color(0xFFFF6900)),
              label: const Text(
                'Copy OTP',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFFF6900),
                ),
              ),
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFFFF6900), width: 1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OtpDigitBox extends StatelessWidget {
  final String digit;
  const _OtpDigitBox({required this.digit});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFD9B3), width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        digit,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: Color(0xFF101828),
        ),
      ),
    );
  }
}

class _OrangeInfoCard extends StatelessWidget {
  final String distance;
  final String duration;
  final String payment;
  const _OrangeInfoCard({
    required this.distance,
    required this.duration,
    required this.payment,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD6A8), width: 0.8),
      ),
      child: Row(
        children: [
          Expanded(
            child: _OrangeStat(label: 'Distance', value: distance),
          ),
          Container(
            width: 1,
            height: 36,
            color: const Color(0xFFFFD6A8),
          ),
          Expanded(
            child: _OrangeStat(label: 'Duration', value: duration),
          ),
          Container(
            width: 1,
            height: 36,
            color: const Color(0xFFFFD6A8),
          ),
          Expanded(
            child: _OrangeStat(label: 'Payment', value: payment),
          ),
        ],
      ),
    );
  }
}

class _OrangeStat extends StatelessWidget {
  final String label;
  final String value;
  const _OrangeStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF9F2D00),
            height: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF7E2A0C),
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

class _InfoGrid extends StatelessWidget {
  final String location;
  final String date;
  final String time;
  final String applicants;

  const _InfoGrid({
    required this.location,
    required this.date,
    required this.time,
    required this.applicants,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _InfoTile(
                icon: Icons.location_on_outlined,
                label: 'Location',
                value: location,
                multiline: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _InfoTile(
                icon: Icons.calendar_today_outlined,
                label: 'Date',
                value: date,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _InfoTile(
                icon: Icons.access_time,
                label: 'Time',
                value: time,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _InfoTile(
                icon: Icons.group_outlined,
                label: 'Applicants',
                value: applicants,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool multiline;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.multiline = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD1D5DB), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: const Color(0xFF4A5565)),
              const Spacer(),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF364153),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: multiline ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Color(0xFF101828),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _RequirementBullet extends StatelessWidget {
  final String text;
  const _RequirementBullet({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 9, right: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFFF6900),
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF364153),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlatformChargesCard extends StatelessWidget {
  // How many free jobs the current user still has. While > 0 the card
  // suppresses the "₹10 or 5%" commission line and shows a positive
  // "first 3 jobs are FREE" message instead. backend's User schema
  // already exposes freeJobsRemaining (default 3 on signup), so this
  // only requires reading the field — no migration.
  final int freeJobsRemaining;
  const _PlatformChargesCard({required this.freeJobsRemaining});

  @override
  Widget build(BuildContext context) {
    final hasFreeQuota = freeJobsRemaining > 0;
    // Switch to a green/positive palette while the user is still in
    // their free tier so it reads as a perk, not a fee notice.
    final bg = hasFreeQuota
        ? const Color(0xFFECFDF5) // mint-50
        : const Color(0xFFEFF6FF); // blue-50
    final border = hasFreeQuota
        ? const Color(0xFFA7F3D0) // mint-200
        : const Color(0xFFDBEAFE); // blue-100
    final accent = hasFreeQuota
        ? const Color(0xFF059669) // emerald-600
        : const Color(0xFF408EE0);
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            hasFreeQuota
                ? Icons.celebration_outlined
                : Icons.info_outline,
            size: 18,
            color: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Platform Charges',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 2),
                if (hasFreeQuota)
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF065F46),
                        height: 1.4,
                      ),
                      children: [
                        const TextSpan(
                          text: 'FREE ',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const TextSpan(text: 'for your first 3 jobs — '),
                        TextSpan(
                          text: freeJobsRemaining == 1
                              ? '1 free job left'
                              : '$freeJobsRemaining free jobs left',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF1E3A8A),
                        height: 1.4,
                      ),
                      children: [
                        TextSpan(text: '₹10 or 5% commission '),
                        TextSpan(
                          text: '(higher will be applicable)',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
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

class _PostedByCard extends StatelessWidget {
  final String name;
  final String rating;
  final String memberSince;
  final int jobsPosted;
  // null = hide the chat icon (e.g. on jobs the user posted themselves).
  // When set, the icon is rendered on the right of the row and tapping
  // it pushes /chat with the jobgiver's details.
  final VoidCallback? onChatTap;

  const _PostedByCard({
    required this.name,
    required this.rating,
    required this.memberSince,
    required this.jobsPosted,
    this.onChatTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Posted By',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF101828),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE5E7EB),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person,
                      size: 24,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00C950),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.check,
                          size: 12, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF101828),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star,
                            size: 16, color: Color(0xFFFFB300)),
                        const SizedBox(width: 4),
                        Text(
                          '$rating rating',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF4A5565),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      memberSince.isEmpty
                          ? 'Member since recently'
                          : 'Member since $memberSince',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6A7282),
                      ),
                    ),
                  ],
                ),
              ),
              if (onChatTap != null) ...[
                const SizedBox(width: 8),
                _PostedByChatButton(onTap: onChatTap!),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Color(0xFFE5E7EB), width: 0.8),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _Stat(value: '$jobsPosted', label: 'Jobs Posted'),
                ),
                Expanded(
                  child: _Stat(value: '95%', label: 'Response Rate'),
                ),
                Expanded(
                  child: _Stat(value: '2 hours', label: 'Avg Response'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF101828),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF4A5565),
          ),
        ),
      ],
    );
  }
}

// Voice description playback card, shown above the typed description
// when the jobgiver attached a voice note on the Post Job screen. Tap
// the play icon to stream the .m4a from the backend; tap again to
// stop. State (isPlaying) is owned by the parent so it stays in sync
// with the AudioPlayer's onPlayerComplete event.
class _VoiceNoteCard extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onTap;
  const _VoiceNoteCard({required this.isPlaying, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFEFF6FF),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFBEDBFF), width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Color(0xFF2B7FFF),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  isPlaying ? Icons.stop : Icons.play_arrow,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Voice description',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF101828),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isPlaying
                          ? 'Playing… tap to stop'
                          : 'Tap to listen to the jobgiver\'s description',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF4A5565),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                isPlaying ? Icons.graphic_eq : Icons.headphones_outlined,
                color: const Color(0xFF2B7FFF),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Square 44×44 chat icon shown on the right of the Posted By row. Tap
// pushes /chat with the jobgiver pre-populated so the worker can ask
// questions before applying / after accepting.
class _PostedByChatButton extends StatelessWidget {
  final VoidCallback onTap;
  const _PostedByChatButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
          ),
          child: const Icon(
            Icons.chat_bubble_outline,
            size: 20,
            color: Color(0xFF101828),
          ),
        ),
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  final int applicants;
  final bool cancelDisabled;
  final VoidCallback onCancel;
  final VoidCallback onViewApplicants;

  const _BottomActions({
    required this.applicants,
    required this.cancelDisabled,
    required this.onCancel,
    required this.onViewApplicants,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Color(0xFFE5E7EB), width: 0.8),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 56,
                child: OutlinedButton(
                  onPressed: cancelDisabled ? null : onCancel,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFFFEF2F2),
                    side: const BorderSide(
                      color: Color(0xFFFFC9C9),
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Cancel Job',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFE7000B),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 56,
                child: OutlinedButton(
                  onPressed: onViewApplicants,
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
                  child: Text(
                    'View Applicants ($applicants)',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFFF6900),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApplyBottomBar extends StatelessWidget {
  final bool disabled;
  final String label;
  final VoidCallback? onTap;

  const _ApplyBottomBar({
    required this.disabled,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Color(0xFFE5E7EB), width: 0.8),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: SizedBox(
          height: 56,
          child: OutlinedButton(
            onPressed: disabled ? null : onTap,
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              side: BorderSide(
                color: disabled
                    ? const Color(0xFFFFC9A6)
                    : const Color(0xFFFF6900),
                width: 1.4,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: disabled
                    ? const Color(0xFFFFC9A6)
                    : const Color(0xFFFF6900),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
