import 'package:flutter/material.dart';

import 'job_history_screen.dart' show WorkerAvatar, fmtDate, fmtTime;
import 'need_help_type_screen.dart' show NeedHelpArgs;

/// Job Details — one completed job, and the way into Need Help.
///
/// Takes the job map straight from Job History rather than re-fetching:
/// the list already joined both parties and the payment, and a second
/// round trip would only show the user a spinner for data in hand.
///
/// The middle section names the other party — the worker when a giver is
/// looking, the client when a worker is.
class JobHistoryDetailScreen extends StatefulWidget {
  const JobHistoryDetailScreen({super.key});

  @override
  State<JobHistoryDetailScreen> createState() => _JobHistoryDetailScreenState();
}

class _JobHistoryDetailScreenState extends State<JobHistoryDetailScreen> {
  Map<String, dynamic>? _job;

  /// Set by Job History when it pushes this screen. Defaults to the
  /// giver's view, which is what a direct push without the flag means.
  bool get _isGiver => _job?['_isGiver'] != false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_job != null) return;
    final raw = ModalRoute.of(context)?.settings.arguments;
    if (raw is Map) _job = Map<String, dynamic>.from(raw);
  }

  Future<void> _needHelp() async {
    final job = _job;
    if (job == null) return;
    final filed = await Navigator.pushNamed(
      context,
      '/need-help',
      arguments: NeedHelpArgs(
        jobId: (job['_id'] ?? '').toString(),
        jobTitle: (job['title'] ?? 'Job').toString(),
        isJobGiver: _isGiver,
      ),
    );
    // Submitting comes back `true`, so the button can flip to the
    // already-reported state without a round trip.
    if (filed == true && mounted) {
      setState(() {
        _job = {
          ...job,
          'issue': {'status': 'open', 'code': ''},
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = _job;
    if (job == null) {
      return const Scaffold(body: Center(child: Text('Job not found')));
    }

    final title = (job['title'] ?? 'Job').toString();
    final category = (job['category'] ?? '').toString();
    final description = (job['description'] ?? '').toString().trim();
    final otherKey = _isGiver ? 'selectedJobtaker' : 'jobgiver';
    final worker = job[otherKey] is Map ? job[otherKey] as Map : const {};
    final workerName = (worker['name'] ?? (_isGiver ? 'Worker' : 'Client'))
        .toString();
    final ratingRaw = worker['rating'];
    final rating = ratingRaw is Map
        ? (ratingRaw['average'] as num?)?.toDouble()
        : (ratingRaw as num?)?.toDouble();
    final jobsDone = (worker['jobsCompleted'] as num?)?.toInt();
    final verified = worker['isVerified'] == true;

    final loc = job['location'] is Map ? job['location'] as Map : const {};
    final address = [loc['address'], loc['city'], loc['state'], loc['pincode']]
        .map((s) => (s ?? '').toString().trim())
        .where((s) => s.isNotEmpty)
        .join(', ');

    final completedAt = DateTime.tryParse(
      (job['paymentReleasedAt'] ?? job['updatedAt'] ?? '').toString(),
    )?.toLocal();
    final scheduledAt = DateTime.tryParse(
      (job['scheduledAt'] ?? '').toString(),
    )?.toLocal();

    final issue = job['issue'] is Map ? job['issue'] as Map : null;
    final issueOpen =
        issue != null && !['resolved', 'rejected'].contains(issue['status']);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: const Color(0xFF101828),
        elevation: 0,
        scrolledUnderElevation: 0.5,
        title: const Text(
          'Job Details',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF101828),
          ),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 14),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 15,
                  color: Color(0xFF16A34A),
                ),
                SizedBox(width: 4),
                Text(
                  'Completed',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF16A34A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          _Section(
            icon: Icons.description_outlined,
            label: 'JOB INFORMATION',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF101828),
                  ),
                ),
                if (category.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      category,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _Tile(
                        label: 'Completed On',
                        icon: Icons.calendar_today_outlined,
                        value: completedAt == null ? '—' : fmtDate(completedAt),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Tile(
                        label: 'Scheduled At',
                        icon: Icons.schedule,
                        value: scheduledAt == null ? '—' : fmtTime(scheduledAt),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _Tile(
                  label: 'Service Location',
                  icon: Icons.place_outlined,
                  value: address.isEmpty ? 'Not recorded' : address,
                  full: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            icon: Icons.badge_outlined,
            label: _isGiver ? 'WORKER INFORMATION' : 'CLIENT INFORMATION',
            child: Row(
              children: [
                WorkerAvatar(
                  name: workerName,
                  photo: worker['photo']?.toString(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              workerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF101828),
                              ),
                            ),
                          ),
                          if (verified) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.verified,
                              size: 14,
                              color: Color(0xFF16A34A),
                            ),
                            const SizedBox(width: 2),
                            const Text(
                              'Verified',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF16A34A),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.star,
                            size: 13,
                            color: Color(0xFFF59E0B),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            (rating ?? 5.0).toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF364153),
                            ),
                          ),
                          if (jobsDone != null) ...[
                            const SizedBox(width: 10),
                            Text(
                              '$jobsDone jobs done',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF9CA3AF),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Section(
              icon: Icons.check_circle_outline,
              label: 'WORK DETAILS',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Job Description',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: Color(0xFF364153),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Work Completed',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    completedAt == null
                        ? 'Marked complete by the worker'
                        : 'Completed on ${fmtDate(completedAt)}',
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: Color(0xFF364153),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: issueOpen
                // Already reported: the backend would answer a second
                // attempt with a 409, so say so instead of walking them
                // through five steps to reach it.
                ? OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.hourglass_top_outlined, size: 17),
                    label: const Text(
                      'Issue reported — under review',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  )
                : OutlinedButton(
                    onPressed: _needHelp,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF364153),
                      side: const BorderSide(color: Color(0xFFD1D5DB)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Need Help',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- pieces

class _Section extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget child;
  const _Section({
    required this.icon,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDEFF3)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: const Color(0xFF2563EB)),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: Color(0xFF2563EB),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool full;
  const _Tile({
    required this.label,
    required this.value,
    required this.icon,
    this.full = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: full ? double.infinity : null,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
          ),
          const SizedBox(height: 5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, size: 13, color: const Color(0xFF6B7280)),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF364153),
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
