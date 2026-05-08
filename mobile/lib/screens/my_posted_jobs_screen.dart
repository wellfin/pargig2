import 'package:flutter/material.dart';

import '../api/home_api.dart';
import '../config.dart';

class MyPostedJobsScreen extends StatefulWidget {
  const MyPostedJobsScreen({super.key});

  @override
  State<MyPostedJobsScreen> createState() => _MyPostedJobsScreenState();
}

class _MyPostedJobsScreenState extends State<MyPostedJobsScreen> {
  static const _tabs = ['Active', 'In Progress', 'Completed', 'Cancelled'];
  static const _activeStatuses = ['open'];
  static const _inProgressStatuses = ['confirmed', 'reached', 'in_progress'];
  static const _completedStatuses = ['completed'];
  static const _cancelledStatuses = ['cancelled', 'disputed'];

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  List<Map<String, dynamic>> _jobs = const [];
  bool _loading = true;
  String? _error;
  int _selected = 0;

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
      final jobs = await HomeApi.myPostedJobs();
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
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

  List<String> _statusesFor(int tab) {
    switch (tab) {
      case 0: return _activeStatuses;
      case 1: return _inProgressStatuses;
      case 2: return _completedStatuses;
      case 3: return _cancelledStatuses;
    }
    return const [];
  }

  int _countFor(int tab) {
    final s = _statusesFor(tab);
    return _jobs.where((j) => s.contains(j['status'])).length;
  }

  String _formatDate(DateTime dt) =>
      '${_months[dt.month - 1]} ${dt.day}, ${dt.year}';

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

  Future<void> _openJob(Map<String, dynamic> job) async {
    final id = (job['_id'] ?? '').toString();
    if (id.isEmpty) return;
    final changed = await Navigator.pushNamed(
      context,
      '/job-details',
      arguments: id,
    );
    if (changed == true && mounted) _load();
  }

  Future<void> _viewInterested(Map<String, dynamic> job) async {
    final id = (job['_id'] ?? '').toString();
    if (id.isEmpty) return;
    final changed = await Navigator.pushNamed(
      context,
      '/applicants',
      arguments: id,
    );
    if (changed == true && mounted) _load();
  }

  void _editJob(Map<String, dynamic> job) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Edit job — coming soon.')),
    );
  }

  Future<void> _deleteJob(Map<String, dynamic> job) async {
    final id = (job['_id'] ?? '').toString();
    if (id.isEmpty) return;
    final cancelled = await Navigator.pushNamed(
      context,
      '/cancel-job',
      arguments: {
        'id': id,
        'title': (job['title'] ?? '').toString(),
      },
    );
    if (cancelled == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _jobs
        .where((j) => _statusesFor(_selected).contains(j['status']))
        .toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Column(
        children: [
          _Header(onBack: () => Navigator.maybePop(context)),
          _TabsBar(
            tabs: List.generate(
              _tabs.length,
              (i) => '${_tabs[i]} (${_countFor(i)})',
            ),
            selected: _selected,
            onTap: (i) => setState(() => _selected = i),
          ),
          Expanded(child: _buildBody(visible)),
        ],
      ),
    );
  }

  Widget _buildBody(List<Map<String, dynamic>> visible) {
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
    if (visible.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inbox_outlined, size: 48, color: Color(0xFF9CA3AF)),
              const SizedBox(height: 12),
              Text(
                'No ${_tabs[_selected].toLowerCase()} jobs',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF101828),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Posted jobs in this state will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Color(0xFF6A7282)),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: const Color(0xFFFF6900),
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        itemCount: visible.length,
        separatorBuilder: (_, _) => const SizedBox(height: 16),
        itemBuilder: (_, i) {
          final j = visible[i];
          final status = (j['status'] ?? '').toString();
          final title = (j['title'] ?? '').toString();
          final desc = (j['description'] ?? '').toString();
          final priceMode = (j['priceMode'] ?? 'open').toString();
          final price = (j['finalPrice'] ?? j['proposedBudget'] ?? 0) as num;
          final scheduled = j['scheduledAt']?.toString();
          final dt = scheduled != null ? DateTime.tryParse(scheduled) : null;
          final loc = j['location'] is Map ? j['location'] as Map : const {};
          final locText = [loc['address'], loc['city']]
              .map((s) => (s ?? '').toString())
              .where((s) => s.trim().isNotEmpty)
              .join(', ');
          final photos = j['photos'] is List
              ? (j['photos'] as List).whereType<String>().toList()
              : <String>[];
          final interestedCount = j['interested'] is List
              ? (j['interested'] as List).length
              : 0;

          return _JobCard(
            photo: photos.isEmpty ? null : photos.first,
            status: status,
            title: title.isEmpty ? '—' : title,
            description: desc,
            dateText: dt != null ? _formatDate(dt) : '—',
            timeText: dt != null ? _formatTime(dt) : '—',
            locationText: locText.isEmpty ? '—' : locText,
            priceText:
                priceMode == 'fixed' && price > 0 ? '₹${price.toInt()}' : 'Open',
            interestedCount: interestedCount,
            onTap: () => _openJob(j),
            onViewInterested: () => _viewInterested(j),
            onEdit: () => _editJob(j),
            onDelete: () => _deleteJob(j),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onBack;
  const _Header({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF3B69B4),
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 7.5,
            offset: Offset(0, 10),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 16,
        16,
        16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: Material(
                  color: const Color(0x33FFFFFF),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onBack,
                    child: const Icon(Icons.arrow_back,
                        size: 24, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 15),
              const Text(
                'My Posted Jobs',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  height: 1.55,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            "Jobs you've posted to hire workers",
            style: TextStyle(
              fontSize: 14,
              color: Color(0xE6FFFFFF),
              height: 1.43,
            ),
          ),
        ],
      ),
    );
  }
}

class _TabsBar extends StatelessWidget {
  final List<String> tabs;
  final int selected;
  final ValueChanged<int> onTap;

  const _TabsBar({
    required this.tabs,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB), width: 0.8),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(tabs.length, (i) {
            final isSel = i == selected;
            return Padding(
              padding: EdgeInsets.only(right: i == tabs.length - 1 ? 0 : 8),
              child: Material(
                color: isSel ? Colors.white : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => onTap(i),
                  child: Ink(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: isSel ? Colors.white : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(16),
                      border: isSel
                          ? Border.all(
                              color: const Color(0xFFFF6900),
                              width: 1,
                            )
                          : null,
                      boxShadow: isSel
                          ? const [
                              BoxShadow(
                                color: Color(0x1A000000),
                                blurRadius: 3,
                                offset: Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        tabs[i],
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: isSel
                              ? const Color(0xFFFF6900)
                              : const Color(0xFF4A5565),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _StatusPillStyle {
  final String label;
  final IconData icon;
  final Color bg;
  final Color fg;
  const _StatusPillStyle({
    required this.label,
    required this.icon,
    required this.bg,
    required this.fg,
  });
}

const _pillByStatus = <String, _StatusPillStyle>{
  'open': _StatusPillStyle(
    label: 'Finding Workers',
    icon: Icons.access_time,
    bg: Color(0xFFFFEDD4),
    fg: Color(0xFFF54900),
  ),
  'confirmed': _StatusPillStyle(
    label: 'Confirmed',
    icon: Icons.check_circle,
    bg: Color(0xFFEFF6FF),
    fg: Color(0xFF155DFC),
  ),
  'reached': _StatusPillStyle(
    label: 'Worker Reached',
    icon: Icons.location_on,
    bg: Color(0xFFEFF6FF),
    fg: Color(0xFF155DFC),
  ),
  'in_progress': _StatusPillStyle(
    label: 'In Progress',
    icon: Icons.flash_on,
    bg: Color(0xFFEFF6FF),
    fg: Color(0xFF155DFC),
  ),
  'completed': _StatusPillStyle(
    label: 'Completed',
    icon: Icons.check_circle,
    bg: Color(0xFFDCFCE7),
    fg: Color(0xFF00A63E),
  ),
  'cancelled': _StatusPillStyle(
    label: 'Cancelled',
    icon: Icons.cancel_outlined,
    bg: Color(0xFFFEE2E2),
    fg: Color(0xFFE7000B),
  ),
  'disputed': _StatusPillStyle(
    label: 'Disputed',
    icon: Icons.error_outline,
    bg: Color(0xFFFEE2E2),
    fg: Color(0xFFE7000B),
  ),
};

class _JobCard extends StatelessWidget {
  final String? photo;
  final String status;
  final String title;
  final String description;
  final String dateText;
  final String timeText;
  final String locationText;
  final String priceText;
  final int interestedCount;
  final VoidCallback onTap;
  final VoidCallback onViewInterested;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _JobCard({
    required this.photo,
    required this.status,
    required this.title,
    required this.description,
    required this.dateText,
    required this.timeText,
    required this.locationText,
    required this.priceText,
    required this.interestedCount,
    required this.onTap,
    required this.onViewInterested,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final pill = _pillByStatus[status] ?? _pillByStatus['open']!;
    final isCancelledOrCompleted =
        status == 'cancelled' || status == 'disputed' || status == 'completed';
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 1,
      shadowColor: const Color(0x14000000),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF3F4F6), width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PhotoBanner(photo: photo, pill: pill),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF101828),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF4A5565),
                        height: 1.43,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _IconLine(
                            icon: Icons.calendar_today_outlined,
                            text: dateText,
                          ),
                        ),
                        Expanded(
                          child: _IconLine(
                            icon: Icons.access_time,
                            text: timeText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _IconLine(
                            icon: Icons.location_on_outlined,
                            text: locationText,
                          ),
                        ),
                        Text(
                          priceText,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF101828),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (status == 'open')
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 44,
                              child: OutlinedButton.icon(
                                onPressed: onViewInterested,
                                icon: const Icon(
                                  Icons.visibility_outlined,
                                  size: 16,
                                  color: Color(0xFFFF6900),
                                ),
                                label: Text(
                                  'View Interested ($interestedCount)',
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
                            icon: Icons.edit_outlined,
                            bg: const Color(0xFFF3F4F6),
                            fg: const Color(0xFF364153),
                            onTap: onEdit,
                          ),
                          const SizedBox(width: 8),
                          _SquareIconButton(
                            icon: Icons.delete_outline,
                            bg: const Color(0xFFFEF2F2),
                            fg: const Color(0xFFE7000B),
                            onTap: onDelete,
                          ),
                        ],
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton(
                          onPressed: onTap,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            side: BorderSide(
                              color: isCancelledOrCompleted
                                  ? const Color(0xFFE5E7EB)
                                  : const Color(0xFFFF6900),
                              width: 1,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            'View Details',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: isCancelledOrCompleted
                                  ? const Color(0xFF4A5565)
                                  : const Color(0xFFFF6900),
                            ),
                          ),
                        ),
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
}

class _PhotoBanner extends StatelessWidget {
  final String? photo;
  final _StatusPillStyle pill;
  const _PhotoBanner({required this.photo, required this.pill});

  @override
  Widget build(BuildContext context) {
    final src = (photo == null || photo!.isEmpty)
        ? null
        : photo!.startsWith('http')
            ? photo!
            : '${AppConfig.apiBase}$photo';
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Stack(
        children: [
          SizedBox(
            height: 128,
            width: double.infinity,
            child: src == null
                ? Container(
                    color: const Color(0xFFE5E7EB),
                    child: const Icon(
                      Icons.image_outlined,
                      size: 40,
                      color: Color(0xFF9CA3AF),
                    ),
                  )
                : Image.network(
                    src,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: const Color(0xFFE5E7EB),
                      child: const Icon(
                        Icons.broken_image,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: pill.bg,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(pill.icon, size: 16, color: pill.fg),
                  const SizedBox(width: 6),
                  Text(
                    pill.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: pill.fg,
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

class _IconLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _IconLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF6A7282)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF4A5565),
              height: 1.43,
            ),
          ),
        ),
      ],
    );
  }
}

class _SquareIconButton extends StatelessWidget {
  final IconData icon;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;

  const _SquareIconButton({
    required this.icon,
    required this.bg,
    required this.fg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Center(child: Icon(icon, size: 18, color: fg)),
        ),
      ),
    );
  }
}
