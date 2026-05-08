import 'package:flutter/material.dart';

import '../api/home_api.dart';
import '../config.dart';

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
          _Header(onBack: () => Navigator.maybePop(context)),
          Expanded(child: _buildBody()),
          if (_job != null && !_loading)
            _BottomActions(
              applicants: (_job!['interested'] is List)
                  ? (_job!['interested'] as List).length
                  : 0,
              cancelDisabled: ['completed', 'cancelled']
                  .contains((_job!['status'] ?? '').toString()),
              onCancel: _confirmCancel,
              onViewApplicants: _viewApplicants,
            ),
        ],
      ),
    );
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

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (photos.isNotEmpty) _PhotoStrip(photos: photos),
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
              lines: [
                'Distance: ${_distanceText(job)}',
                'Duration: ${_durationText(job)}',
                'Payment: Cash or Online',
              ],
            ),
          ),
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
            child: _PostedByCard(
              name: giverName,
              rating: giverRating,
              memberSince: giverSince,
              jobsPosted: giver['jobsPosted'] is num
                  ? (giver['jobsPosted'] as num).toInt()
                  : 1,
            ),
          ),
        ],
      ),
    );
  }

  String _distanceText(Map<String, dynamic> job) {
    final loc = job['location'];
    if (loc is Map && loc['coordinates'] is List) {
      // Distance to the viewer is not pre-computed; show address-based hint.
      return 'Nearby';
    }
    return '—';
  }

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
  const _Header({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF3B69B4),
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
          const Text(
            'Job Details',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoStrip extends StatelessWidget {
  final List<String> photos;
  const _PhotoStrip({required this.photos});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 128,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final url = photos[i];
          final src = url.startsWith('http') ? url : '${AppConfig.apiBase}$url';
          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 192,
              height: 128,
              child: Image.network(
                src,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: const Color(0xFFF3F4F6),
                  child: const Icon(Icons.broken_image,
                      color: Color(0xFF94A3B8)),
                ),
              ),
            ),
          );
        },
      ),
    );
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

class _OrangeInfoCard extends StatelessWidget {
  final List<String> lines;
  const _OrangeInfoCard({required this.lines});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD6A8), width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 20, color: Color(0xFFFF6900)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Job Details',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF7E2A0C),
                  ),
                ),
                const SizedBox(height: 4),
                ...lines.map(
                  (l) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      l,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF9F2D00),
                        height: 1.43,
                      ),
                    ),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: const Color(0xFF6A7282)),
              const Spacer(),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF4A5565),
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

class _PostedByCard extends StatelessWidget {
  final String name;
  final String rating;
  final String memberSince;
  final int jobsPosted;

  const _PostedByCard({
    required this.name,
    required this.rating,
    required this.memberSince,
    required this.jobsPosted,
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
