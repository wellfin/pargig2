import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/home_api.dart';
import '../config.dart';
import '../state/auth_state.dart';
import 'chat_screen.dart';
import 'complete_job_screen.dart';
import 'job_status_screen.dart';
import 'start_job_verification_screen.dart';

/// Picks the best route + args to resume a job at the step the user
/// last left off. Used by both the card tap and the action buttons
/// on My Jobs so accidentally closing the app mid-flow doesn't lose
/// the user's place.
({String route, Object? args}) resumeRouteForJob({
  required String jobId,
  required String status,
  required bool iAmSelected,
}) {
  switch (status) {
    case 'reached':
      // OTP issued, awaiting verify → resume the OTP-entry stage.
      return (
        route: '/start-job-verification',
        args: StartJobVerificationArgs(jobId: jobId),
      );
    case 'in_progress':
    case 'confirmed':
      // Confirmed for me OR running → Job Status timeline screen.
      if (iAmSelected || status == 'in_progress') {
        return (
          route: '/job-status',
          args: JobStatusArgs(jobId: jobId),
        );
      }
      return (route: '/job-details', args: jobId);
    case 'completed':
    case 'cancelled':
      return (route: '/job-details', args: jobId);
    case 'open':
    default:
      // Still open / not yet picked — show the full job details so
      // the user can read the description, re-message, etc.
      return (route: '/job-details', args: jobId);
  }
}

/// "My Work" screen for jobtakers — lists jobs the user has applied
/// to and is working on, grouped by status. Reached from the bottom-
/// nav Jobs tab (which is labelled "My Jobs" in work mode).
class MyJobsScreen extends StatefulWidget {
  const MyJobsScreen({super.key});

  @override
  State<MyJobsScreen> createState() => _MyJobsScreenState();
}

enum _Bucket { applied, accepted, ongoing, completed }

class _MyJobsScreenState extends State<MyJobsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _jobs = const [];
  _Bucket _tab = _Bucket.applied;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await HomeApi.myAppliedJobs();
      if (!mounted) return;
      setState(() {
        _jobs = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  // Bucket a job into one of the four tabs based on its status field
  // + whether the current user was selected as the chosen jobtaker.
  _Bucket _bucketFor(Map<String, dynamic> job) {
    final status = (job['status'] ?? '').toString();
    final me = context.read<AuthState>().user?['_id']?.toString();
    String? selectedId;
    final sel = job['selectedJobtaker'];
    if (sel is Map) {
      selectedId = sel['_id']?.toString();
    } else if (sel != null) {
      selectedId = sel.toString();
    }
    final iAmSelected = me != null && selectedId == me;
    switch (status) {
      case 'open':
        // Job is still open. If the giver selected me, I'm "accepted"
        // waiting on me to start; otherwise still in "applied" stage.
        return iAmSelected ? _Bucket.accepted : _Bucket.applied;
      case 'confirmed':
        return iAmSelected ? _Bucket.accepted : _Bucket.applied;
      case 'reached':
      case 'in_progress':
        return _Bucket.ongoing;
      case 'completed':
        return _Bucket.completed;
      case 'cancelled':
        // Treat cancelled like completed for the list — the user can
        // still see it, but it's not actionable.
        return _Bucket.completed;
      default:
        return _Bucket.applied;
    }
  }

  num _myProposedPrice(Map<String, dynamic> job) {
    final me = context.read<AuthState>().user?['_id']?.toString();
    final list = job['interested'];
    if (list is List) {
      for (final entry in list) {
        if (entry is! Map) continue;
        final jt = entry['jobtaker'];
        final jtId = jt is Map ? jt['_id']?.toString() : jt?.toString();
        if (jtId == me) {
          return (entry['proposedPrice'] ??
                  job['finalPrice'] ??
                  job['proposedBudget'] ??
                  0) as num;
        }
      }
    }
    return (job['finalPrice'] ?? job['proposedBudget'] ?? 0) as num;
  }

  num _totalEarned() {
    // Sum of finalPrice / proposedBudget for completed jobs where the
    // current user was selected as the worker. (Rough estimate — the
    // backend doesn't track per-jobtaker payouts separately yet.)
    final me = context.read<AuthState>().user?['_id']?.toString();
    num total = 0;
    for (final j in _jobs) {
      if ((j['status'] ?? '').toString() != 'completed') continue;
      String? selectedId;
      final sel = j['selectedJobtaker'];
      if (sel is Map) {
        selectedId = sel['_id']?.toString();
      } else if (sel != null) {
        selectedId = sel.toString();
      }
      if (selectedId == me) {
        total += _myProposedPrice(j);
      }
    }
    return total;
  }

  int _countFor(_Bucket b) => _jobs.where((j) => _bucketFor(j) == b).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: Column(
        children: [
          _Header(
            onBack: () => Navigator.maybePop(context),
            totalEarned: _totalEarned(),
            jobsCount: _jobs.length,
          ),
          _TabBar(
            current: _tab,
            counts: {
              _Bucket.applied: _countFor(_Bucket.applied),
              _Bucket.accepted: _countFor(_Bucket.accepted),
              _Bucket.ongoing: _countFor(_Bucket.ongoing),
              _Bucket.completed: _countFor(_Bucket.completed),
            },
            onChanged: (b) => setState(() => _tab = b),
          ),
          Expanded(child: _list()),
        ],
      ),
    );
  }

  Widget _list() {
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 40, color: Color(0xFFDC2626)),
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton(onPressed: _fetch, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final filtered = _jobs.where((j) => _bucketFor(j) == _tab).toList();
    if (filtered.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No jobs in this tab yet.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: const Color(0xFFFF6900),
      onRefresh: _fetch,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: filtered.length,
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (_, i) => _JobCard(
          job: filtered[i],
          bucket: _tab,
          proposedPrice: _myProposedPrice(filtered[i]),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onBack;
  final num totalEarned;
  final int jobsCount;

  const _Header({
    required this.onBack,
    required this.totalEarned,
    required this.jobsCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF408EE0),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        12,
        MediaQuery.of(context).padding.top + 12,
        16,
        18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 36,
                height: 36,
                child: Material(
                  color: const Color(0x33FFFFFF),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onBack,
                    child: const Icon(Icons.arrow_back,
                        size: 18, color: Colors.white),
                  ),
                ),
              ),
              const Expanded(
                child: Column(
                  children: [
                    Text(
                      'My Work',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      "Jobs you've applied to and working on",
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xCCFFFFFF),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 36),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: const Color(0x33FFFFFF),
              borderRadius: BorderRadius.circular(14),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total Earned',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xCCFFFFFF),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '₹${totalEarned.toInt()}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0x33FFFFFF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.trending_up,
                          size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        '$jobsCount jobs',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
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

class _TabBar extends StatelessWidget {
  final _Bucket current;
  final Map<_Bucket, int> counts;
  final ValueChanged<_Bucket> onChanged;

  const _TabBar({
    required this.current,
    required this.counts,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    Widget chip(_Bucket b, String label) {
      final n = counts[b] ?? 0;
      final selected = b == current;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: selected ? const Color(0xFF408EE0) : Colors.white,
          borderRadius: BorderRadius.circular(100),
          child: InkWell(
            onTap: () => onChanged(b),
            borderRadius: BorderRadius.circular(100),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: selected
                      ? const Color(0xFF408EE0)
                      : const Color(0xFFE5E7EB),
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              child: Text(
                '$label ($n)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : const Color(0xFF101828),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            chip(_Bucket.applied, 'Applied'),
            chip(_Bucket.accepted, 'Accepted'),
            chip(_Bucket.ongoing, 'Ongoing'),
            chip(_Bucket.completed, 'Completed'),
          ],
        ),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final _Bucket bucket;
  final num proposedPrice;

  const _JobCard({
    required this.job,
    required this.bucket,
    required this.proposedPrice,
  });

  String? _photoUrl() {
    final photos = job['photos'];
    if (photos is List && photos.isNotEmpty) {
      final raw = photos.first?.toString() ?? '';
      if (raw.isEmpty) return null;
      return raw.startsWith('http') ? raw : '${AppConfig.apiBase}$raw';
    }
    return null;
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _formatTime(DateTime dt) {
    final h12 = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final mm = dt.minute.toString().padLeft(2, '0');
    final ap = dt.hour < 12 ? 'AM' : 'PM';
    return '$h12:$mm $ap';
  }

  @override
  Widget build(BuildContext context) {
    final title = (job['title'] ?? '').toString();
    final desc = (job['description'] ?? '').toString();
    final giver = job['jobgiver'] is Map ? job['jobgiver'] as Map : const {};
    final giverName = (giver['name'] ?? 'Client').toString();
    final giverId = (giver['_id'] ?? '').toString();
    double? giverRating;
    final r = giver['rating'];
    if (r is Map) {
      final v = r['average'];
      if (v is num) giverRating = v.toDouble();
    } else if (r is num) {
      giverRating = r.toDouble();
    }
    final scheduledAt = job['scheduledAt']?.toString();
    final scheduledDt =
        scheduledAt != null ? DateTime.tryParse(scheduledAt)?.toLocal() : null;
    final loc = job['location'] is Map ? job['location'] as Map : const {};
    final locText = [loc['address'], loc['city']]
        .map((s) => (s ?? '').toString())
        .where((s) => s.trim().isNotEmpty)
        .join(', ');
    final photo = _photoUrl();
    final id = (job['_id'] ?? '').toString();

    // Compute the resume route ONCE here so both the card tap and
    // any inner widgets share the same target. iAmSelected is true
    // only when this user is the chosen jobtaker on this job.
    final me =
        context.read<AuthState>().user?['_id']?.toString();
    String? selectedId;
    final sel = job['selectedJobtaker'];
    if (sel is Map) {
      selectedId = sel['_id']?.toString();
    } else if (sel != null) {
      selectedId = sel.toString();
    }
    final iAmSelected = me != null && selectedId == me;
    final resume = id.isEmpty
        ? null
        : resumeRouteForJob(
            jobId: id,
            status: (job['status'] ?? '').toString(),
            iAmSelected: iAmSelected,
          );

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: resume == null
            ? null
            : () => Navigator.pushNamed(context, resume.route,
                arguments: resume.args),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                    child: SizedBox(
                      height: 150,
                      width: double.infinity,
                      child: photo != null
                          ? Image.network(
                              photo,
                              fit: BoxFit.cover,
                              loadingBuilder: (_, c, p) =>
                                  p == null ? c : _placeholder(),
                              errorBuilder: (_, _, _) => _placeholder(),
                            )
                          : _placeholder(),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: _StatusBadge(bucket: bucket),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF101828),
                      ),
                    ),
                    if (desc.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        desc,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    _ClientRow(name: giverName, rating: giverRating),
                    const SizedBox(height: 10),
                    _MetaRow(
                      date: scheduledDt != null
                          ? _formatDate(scheduledDt)
                          : null,
                      time: scheduledDt != null
                          ? _formatTime(scheduledDt)
                          : null,
                      locText: locText.isEmpty ? null : locText,
                      price: proposedPrice,
                    ),
                    if (bucket == _Bucket.accepted) ...[
                      const SizedBox(height: 12),
                      _AcceptedBanner(),
                    ],
                    const SizedBox(height: 12),
                    _PrimaryButton(
                      bucket: bucket,
                      jobId: id,
                      status: (job['status'] ?? '').toString(),
                      jobTitle: title,
                      clientName: giverName,
                      clientId: giverId,
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

  Widget _placeholder() => Container(
        color: const Color(0xFFE5E7EB),
        child: const Center(
          child: Icon(Icons.image_outlined,
              size: 36, color: Color(0xFF9CA3AF)),
        ),
      );
}

class _StatusBadge extends StatelessWidget {
  final _Bucket bucket;
  const _StatusBadge({required this.bucket});

  @override
  Widget build(BuildContext context) {
    late final String label;
    late final IconData icon;
    late final Color bg;
    late final Color fg;
    switch (bucket) {
      case _Bucket.applied:
        label = 'Applied';
        icon = Icons.access_time;
        bg = const Color(0xFFFFEDD4);
        fg = const Color(0xFFF54900);
        break;
      case _Bucket.accepted:
        label = 'Accepted';
        icon = Icons.check_circle_outline;
        bg = const Color(0xFFF3E8FF);
        fg = const Color(0xFF7C3AED);
        break;
      case _Bucket.ongoing:
        label = 'Ongoing';
        icon = Icons.play_circle_outline;
        bg = const Color(0xFFDBEAFE);
        fg = const Color(0xFF408EE0);
        break;
      case _Bucket.completed:
        label = 'Completed';
        icon = Icons.task_alt;
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF16A34A);
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientRow extends StatelessWidget {
  final String name;
  final double? rating;
  const _ClientRow({required this.name, required this.rating});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.person_outline,
              size: 16, color: Color(0xFF6B7280)),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Client',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6B7280),
                  ),
                ),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF101828),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (rating != null && rating! > 0)
            Row(
              children: [
                const Icon(Icons.check_circle,
                    size: 14, color: Color(0xFF16A34A)),
                const SizedBox(width: 4),
                Text(
                  rating!.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF16A34A),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String? date;
  final String? time;
  final String? locText;
  final num price;

  const _MetaRow({
    required this.date,
    required this.time,
    required this.locText,
    required this.price,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.calendar_today_outlined,
                size: 14, color: Color(0xFF6B7280)),
            const SizedBox(width: 6),
            Text(
              date ?? '—',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF4A5565),
              ),
            ),
            const SizedBox(width: 16),
            const Icon(Icons.access_time,
                size: 14, color: Color(0xFF6B7280)),
            const SizedBox(width: 6),
            Text(
              time ?? '—',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF4A5565),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Icon(Icons.location_on_outlined,
                size: 14, color: Color(0xFF6B7280)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                locText ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF4A5565),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '\$',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '₹${price.toInt()}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF16A34A),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AcceptedBanner extends StatelessWidget {
  const _AcceptedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF3E8FF),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.check_circle,
              size: 16, color: Color(0xFF7C3AED)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Client accepted your application!',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B21A8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final _Bucket bucket;
  final String jobId;
  final String status;
  final String jobTitle;
  final String clientName;
  final String clientId;
  const _PrimaryButton({
    required this.bucket,
    required this.jobId,
    required this.status,
    required this.jobTitle,
    required this.clientName,
    required this.clientId,
  });

  void _openChat(BuildContext context) {
    Navigator.pushNamed(
      context,
      '/chat',
      arguments: ChatArgs(
        name: clientName,
        userId: clientId.isEmpty ? null : clientId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (bucket) {
      case _Bucket.applied:
        return SizedBox(
          height: 48,
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _openChat(context),
            icon: const Icon(Icons.chat_bubble_outline,
                size: 18, color: Colors.white),
            label: const Text(
              'Chat with Client',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6900),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        );
      case _Bucket.accepted:
        return Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: jobId.isEmpty
                      ? null
                      : () => Navigator.pushNamed(
                            context,
                            '/start-job-verification',
                            arguments:
                                StartJobVerificationArgs(jobId: jobId),
                          ),
                  icon: const Icon(Icons.play_circle_outline,
                      size: 18, color: Colors.white),
                  label: const Text(
                    'Start Job',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF408EE0),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _ChatIconWithBadge(
              partnerId: clientId,
              onTap: () => _openChat(context),
            ),
          ],
        );
      case _Bucket.ongoing:
        // Resume at the right step:
        //   status=reached → OTP exchange not yet finished → push
        //     the verification screen (auto-jumps to OTP entry).
        //   status=in_progress → job is actually running → tap pushes
        //     /complete-job (proof upload + Submit Completion) so a
        //     worker who closed the app mid-job can still finish.
        final isReached = status == 'reached';
        return SizedBox(
          height: 48,
          width: double.infinity,
          child: ElevatedButton(
            onPressed: jobId.isEmpty
                ? null
                : () => Navigator.pushNamed(
                      context,
                      isReached ? '/start-job-verification' : '/complete-job',
                      arguments: isReached
                          ? StartJobVerificationArgs(jobId: jobId)
                          : CompleteJobArgs(
                              jobId: jobId,
                              jobTitle: jobTitle,
                            ),
                    ),
            style: ElevatedButton.styleFrom(
              backgroundColor: isReached
                  ? const Color(0xFF408EE0)
                  : const Color(0xFF16A34A),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              isReached ? 'Resume Verification' : 'Mark as Complete',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        );
      case _Bucket.completed:
        return SizedBox(
          height: 48,
          width: double.infinity,
          child: OutlinedButton(
            onPressed: jobId.isEmpty
                ? null
                : () => Navigator.pushNamed(context, '/job-details',
                    arguments: jobId),
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              side: const BorderSide(
                color: Color(0xFFE5E7EB),
                width: 0.8,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'View Details',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
        );
    }
  }
}

/// Square chat icon button used next to "Start Job" on Accepted
/// cards. Wears a red unread dot top-right when the client (partnerId)
/// has sent the worker an unread message — driven by
/// AuthState.unreadPartnerIds which the home screen polls.
class _ChatIconWithBadge extends StatelessWidget {
  final String partnerId;
  final VoidCallback onTap;

  const _ChatIconWithBadge({
    required this.partnerId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final unread = partnerId.isNotEmpty &&
        context.watch<AuthState>().unreadPartnerIds.contains(partnerId);
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFE5E7EB),
                width: 0.8,
              ),
            ),
            child: IconButton(
              onPressed: onTap,
              icon: const Icon(Icons.chat_bubble_outline,
                  size: 18, color: Color(0xFF6B7280)),
            ),
          ),
          if (unread)
            Positioned(
              right: 2,
              top: 2,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFFE7000B),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.4),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
