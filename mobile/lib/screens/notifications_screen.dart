import 'package:flutter/material.dart';

/// Figma "Notifications" — reached from the bell icon in the home
/// header. Each row is typed (job alert / message / payment / rating
/// / job-completed / reminder); unread rows get a peach background
/// + orange dot, read rows are plain white. "Clear All" wipes the
/// list locally.
///
/// Backend notification feed isn't wired yet — the seed below mirrors
/// the Figma exactly. When a notifications service exists, swap the
/// seed for an API call; the per-row rendering already binds to a
/// generic _Notification shape.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<_Notification> _items = const [
    _Notification(
      kind: _Kind.jobAlert,
      title: 'New job nearby',
      body: 'Home Cleaning in Koramangala',
      timeLabel: '2 mins ago',
      unread: true,
    ),
    _Notification(
      kind: _Kind.message,
      title: 'New message',
      body: 'Raj Kumar sent you a message',
      timeLabel: '10 mins ago',
      unread: true,
    ),
    _Notification(
      kind: _Kind.payment,
      title: 'Payment received',
      body: '₹500 credited to your wallet',
      timeLabel: '1 hour ago',
      unread: false,
    ),
    _Notification(
      kind: _Kind.rating,
      title: 'New rating',
      body: 'Priya Sharma rated you 5 stars',
      timeLabel: '2 hours ago',
      unread: false,
    ),
    _Notification(
      kind: _Kind.jobCompleted,
      title: 'Job completed',
      body: 'Furniture Assembly marked as done',
      timeLabel: '3 hours ago',
      unread: false,
    ),
    _Notification(
      kind: _Kind.reminder,
      title: 'Reminder',
      body: 'You have a job starting in 1 hour',
      timeLabel: '4 hours ago',
      unread: false,
    ),
  ];

  void _markRead(_Notification n) {
    if (!n.unread) return;
    setState(() {
      _items = _items
          .map((x) => identical(x, n) ? x.asRead() : x)
          .toList(growable: false);
    });
  }

  void _clearAll() {
    if (_items.isEmpty) return;
    setState(() => _items = const []);
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
      body: Column(
        children: [
          _Header(
            onBack: () => Navigator.maybePop(context),
            onClearAll: _items.isEmpty ? null : _clearAll,
          ),
          Expanded(
            child: _items.isEmpty
                ? const _EmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const Divider(
                      height: 1,
                      thickness: 0.6,
                      color: Color(0xFFF1F5F9),
                    ),
                    itemBuilder: (_, i) {
                      final n = _items[i];
                      return _NotificationRow(
                        notification: n,
                        onTap: () => _markRead(n),
                      );
                    },
                  ),
          ),
        ],
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
        4, MediaQuery.of(context).padding.top + 6, 12, 12,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back,
                color: Color(0xFF101828), size: 22),
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
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
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
    final style = _styleFor(notification.kind);
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
                    Text(
                      notification.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF101828),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      notification.body,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF4A5565),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.timeLabel,
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

({IconData icon, Color iconBg, Color iconFg}) _styleFor(_Kind kind) {
  switch (kind) {
    case _Kind.jobAlert:
      return (
        icon: Icons.work_outline,
        iconBg: const Color(0xFFDBEAFE),
        iconFg: const Color(0xFF408EE0),
      );
    case _Kind.message:
      return (
        icon: Icons.chat_bubble_outline,
        iconBg: const Color(0xFFDCFCE7),
        iconFg: const Color(0xFF16A34A),
      );
    case _Kind.payment:
      return (
        icon: Icons.currency_rupee,
        iconBg: const Color(0xFFFFEDD4),
        iconFg: const Color(0xFFFF6900),
      );
    case _Kind.rating:
      return (
        icon: Icons.star_outline,
        iconBg: const Color(0xFFFEF3C7),
        iconFg: const Color(0xFFD97706),
      );
    case _Kind.jobCompleted:
      return (
        icon: Icons.work_outline,
        iconBg: const Color(0xFFDBEAFE),
        iconFg: const Color(0xFF408EE0),
      );
    case _Kind.reminder:
      return (
        icon: Icons.access_time,
        iconBg: const Color(0xFFF3F4F6),
        iconFg: const Color(0xFF6B7280),
      );
  }
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
            Icon(Icons.notifications_none,
                size: 44, color: Color(0xFF9CA3AF)),
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

enum _Kind { jobAlert, message, payment, rating, jobCompleted, reminder }

class _Notification {
  final _Kind kind;
  final String title;
  final String body;
  final String timeLabel;
  final bool unread;

  const _Notification({
    required this.kind,
    required this.title,
    required this.body,
    required this.timeLabel,
    required this.unread,
  });

  _Notification asRead() => _Notification(
        kind: kind,
        title: title,
        body: body,
        timeLabel: timeLabel,
        unread: false,
      );
}
