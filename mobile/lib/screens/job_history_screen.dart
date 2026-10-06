import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/home_api.dart';
import '../api/issues_api.dart';
import '../state/auth_state.dart';

/// Job History — this user's completed jobs.
///
/// Serves both sides from one screen. A giver sees the jobs they paid
/// for and the worker who did them; a worker sees the jobs they worked
/// on and the client who booked them. The layout is identical because
/// the card says the same thing either way — only the counterparty and
/// the money's direction swap.
///
/// Reached from My Services (giver) or Job History (worker) on the
/// profile. Each card leads to Job Details and from there into Need
/// Help, so this is the entry point of the whole issue flow.
class JobHistoryScreen extends StatefulWidget {
  const JobHistoryScreen({super.key});

  @override
  State<JobHistoryScreen> createState() => _JobHistoryScreenState();
}

class _JobHistoryScreenState extends State<JobHistoryScreen> {
  List<Map<String, dynamic>> _jobs = const [];
  bool _loading = true;
  String? _error;

  /// Which side of these jobs the signed-in user is on.
  bool get _isGiver => context.read<AuthState>().isJobGiver;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final jobs = await IssuesApi.jobHistory(isJobGiver: _isGiver);
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : e.toString();
      });
    }
  }

  Future<void> _openJob(Map<String, dynamic> job) async {
    await Navigator.pushNamed(
      context,
      '/job-history-detail',
      arguments: {...job, '_isGiver': _isGiver},
    );
    // An issue may have been raised while away, which changes the card.
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: const Color(0xFF101828),
        elevation: 0,
        scrolledUnderElevation: 0.5,
        title: const Text(
          'Job History',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF101828),
          ),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 14),
            child: Icon(
              Icons.assignment_outlined,
              size: 21,
              color: Color(0xFF2563EB),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _error != null
                  ? _message(_error!, isError: true)
                  : _jobs.isEmpty
                  ? _message(
                      _isGiver
                          ? 'No completed jobs yet.\nJobs you post appear '
                                'here once the work is done.'
                          : 'No completed jobs yet.\nJobs you finish appear '
                                'here once the work is done.',
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 2, bottom: 10),
                          child: Text(
                            '${_jobs.length} COMPLETED '
                            '${_jobs.length == 1 ? 'JOB' : 'JOBS'}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                        ),
                        for (final job in _jobs) ...[
                          _JobCard(
                            job: job,
                            isGiver: _isGiver,
                            onTap: () => _openJob(job),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
            ),
    );
  }

  // Scrollable so pull-to-retry still works with nothing in the list.
  Widget _message(String text, {bool isError = false}) => ListView(
    children: [
      const SizedBox(height: 150),
      Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.assignment_outlined,
                size: 42,
                color: isError ? const Color(0xFFDC2626) : Colors.grey.shade400,
              ),
              const SizedBox(height: 12),
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: isError
                      ? const Color(0xFFDC2626)
                      : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _JobCard extends StatelessWidget {
  final Map<String, dynamic> job;

  /// Whose side of the job this card is on. Decides which party is named
  /// on it: showing people their own name back says nothing.
  final bool isGiver;
  final VoidCallback onTap;
  const _JobCard({
    required this.job,
    required this.isGiver,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = (job['title'] ?? 'Job').toString();
    final category = (job['category'] ?? '').toString();
    final otherKey = isGiver ? 'selectedJobtaker' : 'jobgiver';
    final other = job[otherKey] is Map ? job[otherKey] as Map : const {};
    final otherName = (other['name'] ?? '').toString();
    final loc = job['location'] is Map ? job['location'] as Map : const {};
    final city = [loc['city'], loc['address']]
        .map((s) => (s ?? '').toString().trim())
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');
    final when = DateTime.tryParse(
      (job['paymentReleasedAt'] ?? job['updatedAt'] ?? job['createdAt'] ?? '')
          .toString(),
    )?.toLocal();
    final amount = job['payment'] is Map
        ? (job['payment']['amount'] as num?)
        : null;
    final paid = amount ?? (job['finalPrice'] as num?) ?? 0;
    final issue = job['issue'] is Map ? job['issue'] as Map : null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDEFF3)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF101828),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const _CompletedChip(),
            ],
          ),
          if (category.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            _CategoryChip(label: category),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _Avatar(name: otherName, photo: other['photo']?.toString()),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  otherName.isEmpty
                      ? (isGiver ? 'Worker' : 'Client')
                      : (isGiver ? 'by $otherName' : 'for $otherName'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: Color(0xFF364153),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (when != null)
            _MetaLine(
              icon: Icons.calendar_today_outlined,
              text: 'Completed: ${fmtDate(when)}',
            ),
          if (city.isNotEmpty) ...[
            const SizedBox(height: 4),
            _MetaLine(icon: Icons.place_outlined, text: city),
          ],
          if (issue != null) ...[
            const SizedBox(height: 10),
            _IssueChip(
              code: (issue['code'] ?? '').toString(),
              status: (issue['status'] ?? '').toString(),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isGiver ? 'Amount Paid' : 'You Earned',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '₹${paid.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF101828),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 38,
                child: FilledButton(
                  onPressed: onTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View Details',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.chevron_right, size: 17),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- pieces

class _CompletedChip extends StatelessWidget {
  const _CompletedChip();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle_outline, size: 14, color: Color(0xFF16A34A)),
        SizedBox(width: 4),
        Text(
          'Completed',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF16A34A),
          ),
        ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  const _CategoryChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: Color(0xFF2563EB),
        ),
      ),
    );
  }
}

/// Marks a job the user has already reported, so they do not walk back
/// into Need Help expecting a fresh start.
class _IssueChip extends StatelessWidget {
  final String code;
  final String status;
  const _IssueChip({required this.code, required this.status});

  @override
  Widget build(BuildContext context) {
    final closed = status == 'resolved' || status == 'rejected';
    final color = closed ? const Color(0xFF16A34A) : const Color(0xFFB45309);
    final bg = closed ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            closed ? Icons.check_circle_outline : Icons.hourglass_top_outlined,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            closed
                ? 'Issue $code ${status == 'resolved' ? 'resolved' : 'reviewed'}'
                : 'Issue $code under review',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MetaLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 13, color: const Color(0xFF9CA3AF)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: Color(0xFF6B7280),
            ),
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final String? photo;
  final double size;
  const _Avatar({required this.name, this.photo, this.size = 28});

  @override
  Widget build(BuildContext context) {
    final url = (photo ?? '').trim();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: const Color(0xFF2563EB),
      backgroundImage: url.isEmpty
          ? null
          : NetworkImage(HomeApi.absoluteUrl(url)),
      child: url.isEmpty
          ? Text(
              initials(name),
              style: TextStyle(
                fontSize: size * 0.36,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            )
          : null,
    );
  }
}

/// Shared by Job History and Job Details.
class WorkerAvatar extends StatelessWidget {
  final String name;
  final String? photo;
  final double size;
  const WorkerAvatar({
    super.key,
    required this.name,
    this.photo,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) =>
      _Avatar(name: name, photo: photo, size: size);
}

/// "RS" from "Rahul Sharma"; first letter only for a single word.
String initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String fmtDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

String fmtTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}
