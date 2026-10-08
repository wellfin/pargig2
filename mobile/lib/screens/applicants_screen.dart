import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/home_api.dart';
import '../config.dart';
import 'apply_for_job_screen.dart' show formatSlot;
import 'chat_screen.dart';
import '../utils/rating.dart';

class ApplicantsScreen extends StatefulWidget {
  const ApplicantsScreen({super.key});

  @override
  State<ApplicantsScreen> createState() => _ApplicantsScreenState();
}

class _ApplicantsScreenState extends State<ApplicantsScreen> {
  Map<String, dynamic>? _job;
  bool _loading = true;
  bool _accepted = false;
  String? _error;
  String? _jobId;
  final Set<String> _busyIds = {};
  final Set<String> _rejectedIds = {};

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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  double? _haversineKm(List<num>? a, List<num>? b) {
    if (a == null || b == null || a.length < 2 || b.length < 2) return null;
    final lng1 = a[0].toDouble();
    final lat1 = a[1].toDouble();
    final lng2 = b[0].toDouble();
    final lat2 = b[1].toDouble();
    if (lat1 == 0 && lng1 == 0) return null;
    if (lat2 == 0 && lng2 == 0) return null;
    const r = 6371.0;
    double rad(double v) => v * math.pi / 180.0;
    final dLat = rad(lat2 - lat1);
    final dLng = rad(lng2 - lng1);
    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.asin(math.min(1, math.sqrt(h)));
  }

  /// Tip the giver added when posting. It is paid on top of whatever
  /// the worker asked for, so every figure the giver is shown here has
  /// to include it — otherwise they agree to one number and are charged
  /// a larger one.
  num get _tip {
    final t = _job?['tip'];
    return t is num && t > 0 ? t : 0;
  }

  Future<void> _accept(String applicantId, num? proposedPrice) async {
    if (_jobId == null || _busyIds.contains(applicantId)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Accept this applicant?'),
        content: Text(
          proposedPrice == null
              ? 'You will agree to this applicant for the job.'
              : _tip > 0
              ? 'You will be charged ₹${(proposedPrice + _tip).toInt()} on '
                    'completion — ₹${proposedPrice.toInt()} agreed plus the '
                    '₹${_tip.toInt()} tip you added.'
              : 'You will be charged ₹${proposedPrice.toInt()} on completion.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFF6900),
            ),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busyIds.add(applicantId));
    try {
      await HomeApi.confirmApplicant(
        _jobId!,
        jobtakerId: applicantId,
        finalPrice: proposedPrice,
      );
      if (!mounted) return;
      setState(() {
        _busyIds.remove(applicantId);
        _accepted = true;
      });
      // Hold the success overlay long enough to be readable, then jump
      // straight to a fresh /home — the `pushNamedAndRemoveUntil` clears
      // job-details and applicants from the stack, and the new home
      // instance re-runs initState/_refresh so the just-confirmed job
      // shows up under "Active Jobs" with its updated status.
      await Future.delayed(const Duration(milliseconds: 1400));
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyIds.remove(applicantId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not accept: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    }
  }

  void _message(String name, String userId) {
    Navigator.pushNamed(
      context,
      '/chat',
      arguments: ChatArgs(name: name, userId: userId.isEmpty ? null : userId),
    );
  }

  Future<void> _reject(String applicantId, String name) async {
    if (applicantId.isEmpty || _jobId == null) return;
    if (_busyIds.contains(applicantId)) return;
    // Optimistically hide the card, but keep the id busy so the buttons
    // don't fire twice while the request is in flight.
    setState(() {
      _busyIds.add(applicantId);
      _rejectedIds.add(applicantId);
    });
    try {
      await HomeApi.rejectApplicant(_jobId!, jobtakerId: applicantId);
      if (!mounted) return;
      setState(() => _busyIds.remove(applicantId));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Rejected $name')));
    } catch (e) {
      if (!mounted) return;
      // Roll back the optimistic hide so the applicant reappears — the
      // rejection didn't actually persist.
      setState(() {
        _busyIds.remove(applicantId);
        _rejectedIds.remove(applicantId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not reject: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = _job;
    final title = (job?['title'] ?? 'Job').toString();
    final interested = job?['interested'] is List
        ? (job!['interested'] as List)
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .where((m) {
                final t = m['jobtaker'];
                final id = (t is Map ? t['_id'] : '').toString();
                return id.isEmpty || !_rejectedIds.contains(id);
              })
              .toList()
        : <Map<String, dynamic>>[];

    final jobLoc = job?['location'] is Map ? job!['location'] as Map : const {};
    final jobCoords = jobLoc['coordinates'] is List
        ? (jobLoc['coordinates'] as List).whereType<num>().toList()
        : <num>[];

    // The applicant the giver already accepted (job.selectedJobtaker). Used
    // to mark that card "Accepted" and disable accepting another one.
    final sel = job?['selectedJobtaker'];
    final selectedTakerId = sel is Map
        ? (sel['_id'] ?? '').toString()
        : (sel ?? '').toString();

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Column(
            children: [
              _Header(
                title: title,
                count: interested.length,
                onBack: () => Navigator.maybePop(context),
              ),
              Expanded(
                child: _buildBody(interested, jobCoords, selectedTakerId),
              ),
            ],
          ),
          if (_accepted) const _AcceptedOverlay(),
        ],
      ),
    );
  }

  Widget _buildBody(
    List<Map<String, dynamic>> applicants,
    List<num> jobCoords,
    String selectedTakerId,
  ) {
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
    if (applicants.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.group_outlined, size: 48, color: Color(0xFF9CA3AF)),
              SizedBox(height: 12),
              Text(
                'No applicants yet',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF101828),
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Workers will appear here once they apply.',
                style: TextStyle(fontSize: 14, color: Color(0xFF6A7282)),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      itemCount: applicants.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (_, i) {
        final a = applicants[i];
        final taker = a['jobtaker'] is Map
            ? Map<String, dynamic>.from(a['jobtaker'] as Map)
            : <String, dynamic>{};
        final id = (taker['_id'] ?? '').toString();
        final takerLoc = taker['location'] is Map
            ? taker['location'] as Map
            : const {};
        final takerCoords = takerLoc['coordinates'] is List
            ? (takerLoc['coordinates'] as List).whereType<num>().toList()
            : <num>[];
        final km = _haversineKm(jobCoords, takerCoords);
        final isSelected = id.isNotEmpty && id == selectedTakerId;
        final hasSelection = selectedTakerId.isNotEmpty;

        return _ApplicantCard(
          name: (taker['name'] ?? 'Worker').toString(),
          photo: (taker['photo'] ?? '').toString(),
          // Same `is num` mismatch as Job Details: real worker ratings
          // were being discarded in favour of a flat 5.0.
          rating: displayRating(taker['rating']),
          jobsCompleted: taker['jobsCompleted'] is num
              ? (taker['jobsCompleted'] as num).toInt()
              : 0,
          distanceKm: km,
          proposedPrice: a['proposedPrice'] is num
              ? (a['proposedPrice'] as num)
              : null,
          tip: _tip,
          message: (a['message'] ?? '').toString(),
          // The agreed slot. The worker sets it on "Choose your arrival
          // type" once accepted, which writes it onto the job — so there
          // is one schedule per job rather than one per applicant.
          jobScheduledAt: DateTime.tryParse(
            (_job?['scheduledAt'] ?? '').toString(),
          )?.toLocal(),
          busy: id.isNotEmpty && _busyIds.contains(id),
          accepted: isSelected,
          // Once one applicant is accepted, the rest can't be accepted.
          onAccept: id.isEmpty || hasSelection
              ? null
              : () => _accept(
                  id,
                  a['proposedPrice'] is num ? a['proposedPrice'] as num : null,
                ),
          onMessage: () => _message(
            (taker['name'] ?? 'Worker').toString(),
            (taker['_id'] ?? '').toString(),
          ),
          onReject: () => _reject(id, (taker['name'] ?? 'Worker').toString()),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final int count;
  final VoidCallback onBack;

  const _Header({
    required this.title,
    required this.count,
    required this.onBack,
  });

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
                child: const Icon(
                  Icons.arrow_back,
                  size: 24,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$count Applicant${count == 1 ? '' : 's'}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _ApplicantCard extends StatelessWidget {
  final String name;
  final String photo;
  final String rating;
  final int jobsCompleted;
  final double? distanceKm;

  /// The job's agreed arrival slot, once the worker has chosen one.
  final DateTime? jobScheduledAt;

  /// What this worker asked for, and the tip the giver already added on
  /// top. The card shows the total of the two, because that is what the
  /// giver actually pays.
  final num? proposedPrice;
  final num tip;
  final String message;
  final bool busy;
  final bool accepted;
  final VoidCallback? onAccept;
  final VoidCallback onMessage;
  final VoidCallback onReject;

  const _ApplicantCard({
    required this.name,
    required this.photo,
    required this.rating,
    required this.jobsCompleted,
    required this.distanceKm,
    this.jobScheduledAt,
    required this.proposedPrice,
    this.tip = 0,
    required this.message,
    required this.busy,
    this.accepted = false,
    required this.onAccept,
    required this.onMessage,
    required this.onReject,
  });

  /// The schedule line, or null before a slot has been agreed.
  ///
  /// Empty until the worker picks an arrival time after being accepted,
  /// so an applicant who has not been chosen yet simply shows no line
  /// rather than a time nobody has committed to.
  ({String label, DateTime at})? _slot() {
    final at = jobScheduledAt;
    return at == null ? null : (label: 'Scheduled', at: at);
  }

  String _distanceText() {
    final km = distanceKm;
    if (km == null) return 'Distance unknown';
    if (km < 1) return '${(km * 1000).round()} m away';
    return '${km.toStringAsFixed(1)} km away';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(photo: photo),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF101828),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(
                          Icons.star,
                          size: 16,
                          color: Color(0xFFFFB300),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$rating • $jobsCompleted jobs',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF4A5565),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 16,
                          color: Color(0xFF6A7282),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _distanceText(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF6A7282),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (proposedPrice != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹${(proposedPrice! + tip).toInt()}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF101828),
                      ),
                    ),
                    // Only when there is a tip: on a job without one the
                    // breakdown would just repeat the number above.
                    if (tip > 0)
                      Text(
                        '₹${proposedPrice!.toInt()} + ₹${tip.toInt()} tip',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF6A7282),
                        ),
                      ),
                  ],
                ),
            ],
          ),
          // Full card width, below the name/price row rather than inside
          // the column beside the price — a date and time does not fit
          // in what is left over there, and was being cut to
          // "Scheduled: 7 Oct ...". Wraps to a second line rather than
          // truncating, because a half-shown time is worse than none.
          if (_slot() != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.event_outlined,
                    size: 16,
                    color: Color(0xFF6A7282),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${_slot()!.label}: ${formatSlot(_slot()!.at)}',
                    maxLines: 2,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      color: Color(0xFF6A7282),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (message.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF364153),
                height: 1.43,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: accepted
                      ? OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(
                            Icons.check_circle,
                            size: 20,
                            color: Color(0xFF16A34A),
                          ),
                          label: const Text(
                            'Accepted',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF16A34A),
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: const Color(0xFFF0FDF4),
                            disabledForegroundColor: const Color(0xFF16A34A),
                            side: const BorderSide(
                              color: Color(0xFF16A34A),
                              width: 1,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        )
                      : OutlinedButton.icon(
                          onPressed: busy ? null : onAccept,
                          icon: busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFFFF6900),
                                    ),
                                  ),
                                )
                              : const Icon(
                                  Icons.check_circle_outline,
                                  size: 20,
                                  color: Color(0xFFFF6900),
                                ),
                          label: Text(
                            busy ? 'Accepting…' : 'Accept',
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
              ),
              const SizedBox(width: 8),
              _SquareIconButton(
                icon: Icons.chat_bubble_outline,
                onTap: busy ? null : onMessage,
              ),
              if (!accepted) ...[
                const SizedBox(width: 8),
                _SquareIconButton(
                  icon: Icons.close,
                  onTap: busy ? null : onReject,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String photo;
  const _Avatar({required this.photo});

  @override
  Widget build(BuildContext context) {
    final src = photo.isEmpty
        ? null
        : photo.startsWith('http')
        ? photo
        : '${AppConfig.apiBase}$photo';
    return Container(
      width: 48,
      height: 48,
      decoration: const BoxDecoration(
        color: Color(0xFFE5E7EB),
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: src == null
          ? const Icon(Icons.person, color: Color(0xFF9CA3AF))
          : Image.network(
              src,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.person, color: Color(0xFF9CA3AF)),
            ),
    );
  }
}

class _AcceptedOverlay extends StatelessWidget {
  const _AcceptedOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.white,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 128,
              height: 128,
              decoration: const BoxDecoration(
                color: Color(0xFFDCFCE7),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_outline,
                size: 80,
                color: Color(0xFF00A63E),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Applicant Accepted!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Color(0xFF101828),
                height: 1.33,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Worker has been notified',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Color(0xFF4A5565),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SquareIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _SquareIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Center(
            child: Icon(icon, size: 20, color: const Color(0xFF364153)),
          ),
        ),
      ),
    );
  }
}
