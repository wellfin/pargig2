import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/home_api.dart';
import '../state/auth_state.dart';
import 'chat_screen.dart';
import 'job_completed_screen.dart';
import 'job_status_screen.dart';
import 'release_payment_screen.dart';

/// Figma "Notifications" — reached from the bell icon in the home header.
/// Fetches the live feed from the backend (GET /notifications). Each row is
/// typed (job alert / chat / payment / job status / dispute / system);
/// unread rows get a peach background + orange dot. Tapping a row marks it
/// read (POST /notifications/read) and deep-links to wherever that alert
/// actually happened — see _onTap for the destination table.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;
  String? _error;
  List<_Notification> _items = const [];
  // True while a tapped row's job is being fetched to pick the destination.
  // Blocks a second tap from racing a first one into two pushes.
  bool _opening = false;

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
      final raw = await HomeApi.notifications();
      if (!mounted) return;
      final items = raw.map(_Notification.fromJson).toList();
      setState(() {
        _items = items;
        _loading = false;
      });
      _markSeen(items);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  // Opening this list counts as seeing everything in it, so the unread
  // count clears the moment the screen loads — the bell badge is a "there's
  // something new" signal, not a to-do list. The rows keep their unread
  // highlight for this visit so it's still obvious what arrived recently;
  // they come back plain on the next open.
  Future<void> _markSeen(List<_Notification> items) async {
    if (!items.any((n) => n.unread)) return;
    try {
      // Mark-all rather than the fetched ids: the feed only returns the
      // most recent 50, so id-by-id would strand older unread rows and
      // leave a permanent number on the bell.
      await HomeApi.markAllNotificationsRead();
    } catch (_) {
      // Non-fatal — the badge just clears on a later read instead.
      return;
    }
    if (!mounted) return;
    context.read<AuthState>().refreshUnreadNotifications();
  }

  // Every row is a deep link. Where it lands depends on the alert type and,
  // for job alerts, on whether the reader is the giver or the worker and how
  // far the job has got — the same notification text means different screens
  // to the two sides:
  //
  //   chat                     → the thread with the sender
  //   job_alert (new interest) → that job's applicants list
  //   payment, giver           → Release Payment for that job
  //   payment, worker          → wallet / earnings
  //   job in confirmed..in_progress → Job Status (track / act)
  //   job completed, worker    → Job Completed summary
  //   anything else with a job → Job Details
  Future<void> _onTap(_Notification n) async {
    if (_opening) return;
    if (n.unread) {
      setState(() {
        _items = _items
            .map((x) => x.id == n.id ? x.asRead() : x)
            .toList(growable: false);
      });
      // Fire-and-forget — a failed read-receipt shouldn't block navigation.
      HomeApi.markNotificationsRead([n.id]);
    }
    if (!mounted) return;

    if (n.type == 'chat') {
      _openChat(n);
      return;
    }

    final jobId = n.jobId;
    if (jobId == null) {
      // "Payment released" only carries a paymentId — the wallet is where
      // that credit shows up. Nothing else is actionable without a job.
      if (n.type == 'payment') {
        Navigator.pushNamed(context, '/wallet');
      }
      return;
    }

    // Which screen is right depends on live job state (status, who the
    // worker is, whether payment already went out), not on the wording of
    // an alert that may be days old — so read the job first.
    setState(() => _opening = true);
    Map<String, dynamic> job;
    try {
      job = await HomeApi.jobById(jobId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _opening = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException ? e.message : "Couldn't open that job",
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _opening = false);
    if (job.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That job is no longer available')),
      );
      return;
    }
    _routeToJob(n, jobId, job);
  }

  void _openChat(_Notification n) {
    // Direct-chat pushes carry the sender; room pushes (legacy) don't, so
    // those fall back to the thread list. Title is "Sender · Job title".
    final senderId = n.senderId;
    if (senderId == null || senderId.isEmpty) {
      Navigator.pushNamed(context, '/messages');
      return;
    }
    final name = n.title.split('·').first.trim();
    Navigator.pushNamed(
      context,
      '/chat',
      arguments: ChatArgs(name: name.isEmpty ? 'Chat' : name, userId: senderId),
    );
  }

  void _routeToJob(_Notification n, String jobId, Map<String, dynamic> job) {
    final me = context.read<AuthState>().user?['_id']?.toString();
    final amGiver = me != null && me.isNotEmpty && _idOf(job['jobgiver']) == me;
    final amWorker =
        me != null && me.isNotEmpty && _idOf(job['selectedJobtaker']) == me;
    final status = (job['status'] ?? '').toString();
    const live = ['confirmed', 'reached', 'in_progress'];

    if (n.type == 'job_alert' && amGiver) {
      Navigator.pushNamed(context, '/applicants', arguments: jobId);
      return;
    }
    if (n.type == 'payment') {
      if (amGiver) {
        _openRelease(jobId, job, status);
      } else {
        Navigator.pushNamed(context, '/wallet');
      }
      return;
    }
    if (live.contains(status) && (amGiver || amWorker)) {
      Navigator.pushNamed(
        context,
        '/job-status',
        arguments: JobStatusArgs(jobId: jobId),
      );
      return;
    }
    if (status == 'completed' && amWorker) {
      Navigator.pushNamed(
        context,
        '/job-completed',
        arguments: JobCompletedArgs(jobId: jobId),
      );
      return;
    }
    // Everything else — an open post, a job the reader only applied for, a
    // cancelled one — reads fine as plain job details.
    Navigator.pushNamed(context, '/job-details', arguments: jobId);
  }

  // "Worker is requesting payment" should drop the giver on the actual
  // payout confirmation. If there's nothing left to release (already paid,
  // or the job hasn't completed), the job page is the honest destination.
  void _openRelease(String jobId, Map<String, dynamic> job, String status) {
    final taker = job['selectedJobtaker'] is Map
        ? job['selectedJobtaker'] as Map
        : const {};
    final base =
        (job['finalPrice'] as num?)?.toDouble() ??
        (job['proposedBudget'] as num?)?.toDouble() ??
        0;
    final amount = base + ((job['tip'] as num?)?.toDouble() ?? 0);
    if (status != 'completed' ||
        job['paymentReleasedAt'] != null ||
        amount <= 0) {
      Navigator.pushNamed(context, '/job-details', arguments: jobId);
      return;
    }
    Navigator.pushNamed(
      context,
      '/release-payment',
      arguments: ReleasePaymentArgs(
        jobId: jobId,
        jobTitle: (job['title'] ?? 'Job').toString(),
        workerName: (taker['name'] ?? 'Worker').toString(),
        amount: amount,
      ),
    );
  }

  static String _idOf(dynamic v) {
    if (v is Map) return (v['_id'] ?? '').toString();
    return (v ?? '').toString();
  }

  Future<void> _clearAll() async {
    if (_items.isEmpty) return;
    final ids = _items.map((n) => n.id).where((s) => s.isNotEmpty).toList();
    setState(() => _items = const []);
    await HomeApi.markNotificationsRead(ids).catchError((_) {});
    if (!mounted) return;
    context.read<AuthState>().refreshUnreadNotifications();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All notifications cleared'),
        duration: Duration(milliseconds: 900),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Column(
            children: [
              _Header(
                onBack: () => Navigator.maybePop(context),
                onClearAll: _items.isEmpty ? null : _clearAll,
              ),
              Expanded(child: _body()),
            ],
          ),
          // Covers the list while the tapped job loads, so the row doesn't
          // just sit there looking dead for the length of the round-trip.
          if (_opening)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x33FFFFFF),
                child: Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFFFF6900),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body() {
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
              const Icon(
                Icons.error_outline,
                size: 40,
                color: Color(0xFFDC2626),
              ),
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 14),
              OutlinedButton(onPressed: _fetch, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) return const _EmptyState();
    return RefreshIndicator(
      color: const Color(0xFFFF6900),
      onRefresh: _fetch,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _items.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, thickness: 0.6, color: Color(0xFFF1F5F9)),
        itemBuilder: (_, i) {
          final n = _items[i];
          return _NotificationRow(notification: n, onTap: () => _onTap(n));
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback? onClearAll;

  const _Header({required this.onBack, required this.onClearAll});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB), width: 0.6),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        4,
        MediaQuery.of(context).padding.top + 6,
        12,
        12,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.arrow_back,
              color: Color(0xFF101828),
              size: 22,
            ),
            onPressed: onBack,
          ),
          const Expanded(
            child: Center(
              child: Text(
                'Notifications',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF101828),
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: onClearAll,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFF6900),
              disabledForegroundColor: const Color(0xFFD1D5DB),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text(
              'Clear All',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  final _Notification notification;
  final VoidCallback onTap;

  const _NotificationRow({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final unread = notification.unread;
    final bg = unread ? const Color(0xFFFFF7ED) : Colors.white;
    final style = _styleForType(notification.type);
    return Material(
      color: bg,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: style.iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(style.icon, size: 16, color: style.iconFg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Weight carries the read state: unread is bold and
                    // near-black, read drops to medium and greys back so
                    // the two are tellable apart at a glance.
                    Text(
                      notification.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                        color: unread
                            ? const Color(0xFF101828)
                            : const Color(0xFF4A5565),
                      ),
                    ),
                    if (notification.body.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        notification.body,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: unread
                              ? FontWeight.w500
                              : FontWeight.w400,
                          color: unread
                              ? const Color(0xFF4A5565)
                              : const Color(0xFF9CA3AF),
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      _relativeTime(notification.createdAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              ),
              if (unread)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF6900),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

({IconData icon, Color iconBg, Color iconFg}) _styleForType(String type) {
  switch (type) {
    case 'job_alert':
      return (
        icon: Icons.work_outline,
        iconBg: const Color(0xFFDBEAFE),
        iconFg: const Color(0xFF408EE0),
      );
    case 'chat':
      return (
        icon: Icons.chat_bubble_outline,
        iconBg: const Color(0xFFDCFCE7),
        iconFg: const Color(0xFF16A34A),
      );
    case 'payment':
      return (
        icon: Icons.currency_rupee,
        iconBg: const Color(0xFFFFEDD4),
        iconFg: const Color(0xFFFF6900),
      );
    case 'job_status':
      return (
        icon: Icons.task_alt,
        iconBg: const Color(0xFFFEF3C7),
        iconFg: const Color(0xFFD97706),
      );
    case 'dispute':
      return (
        icon: Icons.report_problem_outlined,
        iconBg: const Color(0xFFFEE2E2),
        iconFg: const Color(0xFFDC2626),
      );
    case 'system':
    default:
      return (
        icon: Icons.notifications_none,
        iconBg: const Color(0xFFF3F4F6),
        iconFg: const Color(0xFF6B7280),
      );
  }
}

String _relativeTime(DateTime? dt) {
  if (dt == null) return '';
  final d = DateTime.now().difference(dt);
  if (d.inSeconds < 60) return 'Just now';
  if (d.inMinutes < 60) {
    return '${d.inMinutes} min${d.inMinutes == 1 ? '' : 's'} ago';
  }
  if (d.inHours < 24) {
    return '${d.inHours} hour${d.inHours == 1 ? '' : 's'} ago';
  }
  if (d.inDays < 7) {
    return '${d.inDays} day${d.inDays == 1 ? '' : 's'} ago';
  }
  return '${dt.day}/${dt.month}/${dt.year}';
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.notifications_none, size: 44, color: Color(0xFF9CA3AF)),
            SizedBox(height: 12),
            Text(
              'No notifications',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF101828),
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Job alerts, messages and payment updates will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF6B7280),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notification {
  final String id;
  final String type;
  final String title;
  final String body;
  final DateTime? createdAt;
  final bool unread;
  final String? jobId;
  // Set on chat alerts — the other party in the thread to open.
  final String? senderId;

  const _Notification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.unread,
    this.jobId,
    this.senderId,
  });

  factory _Notification.fromJson(Map<String, dynamic> m) {
    final data = m['data'] is Map ? m['data'] as Map : const {};
    final rawJobId = (data['jobId'] ?? '').toString();
    final rawSenderId = (data['senderId'] ?? '').toString();
    return _Notification(
      id: (m['_id'] ?? '').toString(),
      type: (m['type'] ?? 'system').toString(),
      title: (m['title'] ?? '').toString(),
      body: (m['body'] ?? '').toString(),
      createdAt: DateTime.tryParse(
        (m['createdAt'] ?? '').toString(),
      )?.toLocal(),
      unread: m['isRead'] != true,
      jobId: rawJobId.isEmpty ? null : rawJobId,
      senderId: rawSenderId.isEmpty ? null : rawSenderId,
    );
  }

  _Notification asRead() => _Notification(
    id: id,
    type: type,
    title: title,
    body: body,
    createdAt: createdAt,
    unread: false,
    jobId: jobId,
    senderId: senderId,
  );
}
