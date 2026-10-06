import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/home_api.dart';
import '../config.dart';
import '../state/auth_state.dart';
import 'chat_screen.dart';
import 'job_status_screen.dart';
import 'release_payment_screen.dart';
import '../utils/invoice_pdf.dart';
import '../utils/job_invoice.dart';
import '../utils/payment_mode.dart';
import '../utils/rating.dart';

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
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
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
      case 0:
        return _activeStatuses;
      case 1:
        return _inProgressStatuses;
      case 2:
        return _completedStatuses;
      case 3:
        return _cancelledStatuses;
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

  void _trackJob(Map<String, dynamic> job) {
    final id = (job['_id'] ?? '').toString();
    if (id.isEmpty) return;
    // Open the Job Status module. Because the signed-in user is the job
    // giver, that screen shows the worker's details + the 6-digit start
    // PIN to read out (no Arrived button — that's the worker's action).
    Navigator.pushNamed(
      context,
      '/job-status',
      arguments: JobStatusArgs(jobId: id),
    );
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

  Future<void> _editJob(Map<String, dynamic> job) async {
    // Reuse the Post Job wizard in edit mode — passing the job document as
    // the route argument pre-fills every field and switches step 2 from
    // "create" to "update" (PUT /jobs/:id). Reload on return so the edited
    // card reflects the new title / price / schedule.
    final updated = await Navigator.pushNamed(
      context,
      '/post-job',
      arguments: job,
    );
    if (updated == true && mounted) _load();
  }

  Future<void> _releasePayment(Map<String, dynamic> job) async {
    final jobId = (job['_id'] ?? '').toString();
    if (jobId.isEmpty) return;
    final taker = job['selectedJobtaker'] is Map
        ? job['selectedJobtaker'] as Map
        : const {};
    final workerName = (taker['name'] ?? 'Worker').toString();
    final amountRaw = job['finalPrice'];
    final baseAmount = amountRaw is num
        ? amountRaw.toDouble()
        : ((job['proposedBudget'] as num?)?.toDouble() ?? 0);
    // Confirmation screen shows the full amount actually released —
    // the backend now folds the tip into the payout too.
    final amount = baseAmount + ((job['tip'] as num?)?.toDouble() ?? 0);
    final title = (job['title'] ?? 'Job').toString();
    // Push the Figma "Payment" confirmation screen — it owns the
    // actual /payments/jobs/:id/release call and pops with `true`
    // once the release succeeds. We reload so the source card flips
    // to "Payment Released".
    final released = await Navigator.pushNamed(
      context,
      '/release-payment',
      arguments: ReleasePaymentArgs(
        jobId: jobId,
        jobTitle: title,
        workerName: workerName,
        amount: amount,
      ),
    );
    if (released == true && mounted) _load();
  }

  void _rehire(Map<String, dynamic> job) {
    // Re-posting a completed job currently routes to the Post Job
    // entry point. The post-job screen doesn't accept prefill args
    // yet — when it does, plumb the job's title / description /
    // category / location / budget through here.
    Navigator.pushNamed(context, '/post-job');
  }

  Future<void> _deleteJob(Map<String, dynamic> job) async {
    final id = (job['_id'] ?? '').toString();
    if (id.isEmpty) return;
    final cancelled = await Navigator.pushNamed(
      context,
      '/cancel-job',
      arguments: {'id': id, 'title': (job['title'] ?? '').toString()},
    );
    if (cancelled == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _jobs
        .where((j) => _statusesFor(_selected).contains(j['status']))
        .toList();
    // In Progress tab: show the most recently accepted / active job first.
    // The job has no dedicated acceptedAt, but updatedAt is bumped when the
    // giver confirms an applicant (and on each later status change), so it's
    // the best "latest accepted on top" proxy. Backend returns everything
    // -createdAt; we re-sort only this tab so the others keep post-date order.
    if (_selected == 1) {
      visible.sort((a, b) {
        final ta = DateTime.tryParse((a['updatedAt'] ?? '').toString());
        final tb = DateTime.tryParse((b['updatedAt'] ?? '').toString());
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta); // newest first
      });
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Column(
        children: [
          _Header(
            // maybePop alone is a dead button here. The release-payment →
            // rate-worker flow ends with pushNamedAndRemoveUntil(..., (_)
            // => false), which clears the whole stack, so this screen is
            // the only route left and there is nothing to pop. Fall back
            // to home, matching what My Jobs and Payment Request already
            // do for the same reason.
            onBack: () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              } else {
                Navigator.pushReplacementNamed(context, '/home');
              }
            },
          ),
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
              const Icon(
                Icons.inbox_outlined,
                size: 48,
                color: Color(0xFF9CA3AF),
              ),
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
          final tip = (j['tip'] ?? 0) as num;
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

          // Worker row data — only meaningful once a worker is assigned
          // (status moves to confirmed / reached / in_progress).
          final taker = j['selectedJobtaker'] is Map
              ? j['selectedJobtaker'] as Map
              : null;
          final takerName = (taker?['name'] ?? '').toString().trim().isEmpty
              ? null
              : taker!['name'].toString();
          final takerId = (taker?['_id'] ?? '').toString();
          // null only when no worker is assigned yet — an assigned but
          // unrated worker shows the 5.0 default like everywhere else.
          final takerRating = taker == null
              ? null
              : ratingAverage(taker['rating']) ?? kUnratedDefault;
          final takerPhoto = taker?['photo']?.toString();
          final jobId = (j['_id'] ?? '').toString();
          // Actual settlement amount for the payment-release action —
          // deliberately NOT the tip-inclusive amount shown on the card,
          // since the tip isn't part of what release payment transfers.
          final finalPriceRaw = j['finalPrice'] ?? j['proposedBudget'] ?? 0;
          final finalPrice = finalPriceRaw is num
              ? finalPriceRaw.toDouble()
              : 0.0;
          final paymentReleased =
              (j['paymentReleasedAt']?.toString().isNotEmpty ?? false);
          // Displayed amount includes the tip (and the boost fee, when
          // boosted) as one combined total. Kept separate from
          // `finalPrice` below, which stays the raw settlement amount
          // used for the actual payment-release action.
          final amount = jobAmount(
            j,
            extra: (j['isBoosted'] == true ? AppConfig.boostFee : 0) + tip,
          );
          final invoice = invoiceFromJob(
            j,
            asWorker: false,
            myName: (context.read<AuthState>().user?['name'] ?? '').toString(),
          );

          return _JobCard(
            photo: photos.isEmpty ? null : photos.first,
            status: status,
            title: title.isEmpty ? '—' : title,
            description: desc,
            dateText: dt != null ? _formatDate(dt) : '—',
            timeText: dt != null ? _formatTime(dt) : '—',
            locationText: locText.isEmpty ? '—' : locText,
            // The amount, whatever the price mode. An open-price job
            // that settled at Rs 850 reads 850 — "Open" there was the
            // question, not the answer, and the card is showing a job
            // that is already done. Whether it was open or fixed moves
            // to the line below, alongside how it was paid.
            priceText: amount == null ? 'Open' : '₹${amount.toInt()}',
            priceSubtitle: priceSubtitle(j),
            interestedCount: interestedCount,
            workerName: takerName,
            workerId: takerId.isEmpty ? null : takerId,
            workerPhoto: takerPhoto,
            workerRating: takerRating,
            finalPrice: finalPrice,
            paymentReleased: paymentReleased,
            invoice: invoice,
            isBoosted: j['isBoosted'] == true,
            onTap: () => _openJob(j),
            onTrack: () => _trackJob(j),
            onViewInterested: () => _viewInterested(j),
            onEdit: () => _editJob(j),
            onDelete: () => _deleteJob(j),
            onRelease: jobId.isEmpty ? null : () => _releasePayment(j),
            onRehire: () => _rehire(j),
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
        color: Color(0xFF408EE0),
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
                    child: const Icon(
                      Icons.arrow_back,
                      size: 24,
                      color: Colors.white,
                    ),
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
                          ? Border.all(color: const Color(0xFFFF6900), width: 1)
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

  /// "Fixed", or "Fixed · COD" once the job has been paid.
  final String priceSubtitle;
  final int interestedCount;
  final String? workerName;
  final String? workerId;
  final String? workerPhoto;
  final double? workerRating;
  final double finalPrice;
  final bool paymentReleased;

  /// Present once the job is paid; drives the Download Invoice button.
  final InvoiceData? invoice;
  final bool isBoosted;
  final VoidCallback onTap;
  final VoidCallback onTrack;
  final VoidCallback onViewInterested;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onRelease;
  final VoidCallback onRehire;

  const _JobCard({
    required this.photo,
    required this.status,
    required this.title,
    required this.description,
    required this.dateText,
    required this.timeText,
    required this.locationText,
    required this.priceText,
    this.priceSubtitle = '',
    required this.interestedCount,
    this.workerName,
    this.workerId,
    this.workerPhoto,
    this.workerRating,
    this.finalPrice = 0,
    this.paymentReleased = false,
    this.invoice,
    this.isBoosted = false,
    required this.onTap,
    required this.onTrack,
    required this.onViewInterested,
    required this.onEdit,
    required this.onDelete,
    this.onRelease,
    required this.onRehire,
  });

  bool get _isInProgressBucket =>
      status == 'confirmed' || status == 'reached' || status == 'in_progress';

  bool get _isCompleted => status == 'completed';

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
                    if (isBoosted) ...[
                      const SizedBox(height: 6),
                      const _BoostedBadge(),
                    ],
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
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              priceText,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF101828),
                              ),
                            ),
                            if (priceSubtitle.isNotEmpty)
                              Text(
                                priceSubtitle,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF6A7282),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    if ((_isInProgressBucket || _isCompleted) &&
                        workerName != null) ...[
                      const SizedBox(height: 14),
                      _WorkerAssignedCard(
                        name: workerName!,
                        photo: workerPhoto,
                        rating: workerRating,
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (_isInProgressBucket)
                      _InProgressActionRow(
                        onTrack: onTrack,
                        onChat: workerName == null
                            ? null
                            : () => Navigator.pushNamed(
                                context,
                                '/chat',
                                arguments: ChatArgs(
                                  name: workerName!,
                                  userId: workerId,
                                ),
                              ),
                        onCall: workerName == null
                            ? null
                            : () => ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Calling $workerName…'),
                                  duration: const Duration(milliseconds: 900),
                                ),
                              ),
                        // Light up the chat icon's red dot when the
                        // assigned worker has an unread message to us.
                        chatBadge:
                            workerId != null &&
                            context
                                .watch<AuthState>()
                                .unreadPartnerIds
                                .contains(workerId),
                      )
                    else if (_isCompleted)
                      Column(
                        children: [
                          _CompletedActionRow(
                            amount: finalPrice,
                            paymentReleased: paymentReleased,
                            onRelease: onRelease,
                            onRehire: onRehire,
                          ),
                          // The payment screen's invoice button is gone
                          // once that screen closes; this is the way back
                          // to it for any paid job, however long ago.
                          if (invoice != null) ...[
                            const SizedBox(height: 8),
                            DownloadInvoiceButton(invoice: invoice!),
                          ],
                        ],
                      )
                    else if (status == 'open')
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

/// Small orange "Boosted" chip shown on a job the giver paid to boost.
class _BoostedBadge extends StatelessWidget {
  const _BoostedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEDD4),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.bolt, size: 13, color: Color(0xFFF54900)),
          SizedBox(width: 3),
          Text(
            'Boosted',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFFF54900),
            ),
          ),
        ],
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

/// Worker card shown on confirmed / reached / in_progress posted jobs.
/// Pulls name + photo + ★ rating off the populated selectedJobtaker.
class _WorkerAssignedCard extends StatelessWidget {
  final String name;
  final String? photo;
  final double? rating;

  const _WorkerAssignedCard({
    required this.name,
    required this.photo,
    required this.rating,
  });

  String? _avatarUrl() {
    final p = photo;
    if (p == null || p.isEmpty) return null;
    return p.startsWith('http') ? p : '${AppConfig.apiBase}$p';
  }

  String _initial() {
    final t = name.trim();
    if (t.isEmpty) return '?';
    return t.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final url = _avatarUrl();
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Worker Assigned',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF6900),
                  shape: BoxShape.circle,
                ),
                clipBehavior: Clip.antiAlias,
                child: url == null
                    ? Center(
                        child: Text(
                          _initial(),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Center(
                          child: Text(
                            _initial(),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF101828),
                  ),
                ),
              ),
              if (rating != null) ...[
                const Icon(Icons.star, size: 14, color: Color(0xFFFFB300)),
                const SizedBox(width: 4),
                Text(
                  rating!.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF101828),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Bottom button row for in-progress posted jobs: blue Track Job pill
/// (fills the row, plays icon), plus small chat + green call icon
/// buttons on the right. Chat / Call go null when no worker is
/// populated yet so the icons grey out instead of crashing.
class _InProgressActionRow extends StatelessWidget {
  final VoidCallback onTrack;
  final VoidCallback? onChat;
  final VoidCallback? onCall;
  // Red dot overlay on the chat icon when the assigned worker has
  // sent an unread message to the jobgiver.
  final bool chatBadge;

  const _InProgressActionRow({
    required this.onTrack,
    required this.onChat,
    required this.onCall,
    this.chatBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 44,
            child: ElevatedButton.icon(
              onPressed: onTrack,
              icon: const Icon(
                Icons.play_circle_outline,
                size: 18,
                color: Colors.white,
              ),
              label: const Text(
                'Track Job',
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
        _IconBubble(
          icon: Icons.chat_bubble_outline,
          bg: const Color(0xFFF3F4F6),
          fg: const Color(0xFF6B7280),
          onTap: onChat,
          badge: chatBadge,
        ),
        const SizedBox(width: 8),
        _IconBubble(
          icon: Icons.call,
          bg: const Color(0xFFDCFCE7),
          fg: const Color(0xFF16A34A),
          onTap: onCall,
        ),
      ],
    );
  }
}

/// Bottom action row for Completed posted jobs: orange-outlined
/// "Release Payment (₹X)" on the left (greys out + reads "Payment
/// Released" once paymentReleased is true), blue filled "Rehire"
/// pill on the right. Rehire jumps the user to /post-job.
class _CompletedActionRow extends StatelessWidget {
  final double amount;
  final bool paymentReleased;
  final VoidCallback? onRelease;
  final VoidCallback onRehire;

  const _CompletedActionRow({
    required this.amount,
    required this.paymentReleased,
    required this.onRelease,
    required this.onRehire,
  });

  @override
  Widget build(BuildContext context) {
    final amountInt = amount.toInt();
    final releaseLabel = paymentReleased
        ? 'Payment Released'
        : (amountInt > 0 ? 'Release Payment (₹$amountInt)' : 'Release Payment');
    final disabled = paymentReleased || onRelease == null;
    final releaseFg = paymentReleased
        ? const Color(0xFF6B7280)
        : const Color(0xFFFF6900);
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              onPressed: disabled ? null : onRelease,
              icon: Icon(
                paymentReleased ? Icons.check_circle : Icons.payments_outlined,
                size: 16,
                color: releaseFg,
              ),
              label: Text(
                releaseLabel,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: releaseFg,
                ),
              ),
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                disabledBackgroundColor: Colors.white,
                side: BorderSide(
                  color: paymentReleased
                      ? const Color(0xFFE5E7EB)
                      : const Color(0xFFFF6900),
                  width: 1,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 44,
          child: ElevatedButton(
            onPressed: onRehire,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF408EE0),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Rehire',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

class _IconBubble extends StatelessWidget {
  final IconData icon;
  final Color bg;
  final Color fg;
  final VoidCallback? onTap;
  // Show a red unread dot top-right (used by the chat icon when the
  // assigned worker has sent the jobgiver an unread message).
  final bool badge;

  const _IconBubble({
    required this.icon,
    required this.bg,
    required this.fg,
    required this.onTap,
    this.badge = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: disabled ? const Color(0xFFF3F4F6) : bg,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Center(
                child: Icon(
                  icon,
                  size: 18,
                  color: disabled ? const Color(0xFFD1D5DB) : fg,
                ),
              ),
            ),
          ),
          if (badge)
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
