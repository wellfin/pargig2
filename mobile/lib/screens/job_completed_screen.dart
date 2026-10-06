import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/home_api.dart';
import '../config.dart';
import '../state/auth_state.dart';
import 'chat_screen.dart';
import 'payment_request_screen.dart';
import 'rate_experience_screen.dart';
import '../utils/rating.dart';

/// Args for Navigator.pushNamed('/job-completed', ...).
class JobCompletedArgs {
  final String jobId;
  const JobCompletedArgs({required this.jobId});
}

/// Figma "Job Completed" — landing screen after a worker submits
/// their proof on Complete Job. Renders a celebratory header banner
/// + a focused job summary (title, total, category + completed
/// pills, location/date/time/client mini-grid, description, client
/// details card) and the worker's two follow-ups: Rate & Review
/// and Request to Pay. Distinct from the generic job_details_screen
/// (that one is the long pre-acceptance view).
class JobCompletedScreen extends StatefulWidget {
  const JobCompletedScreen({super.key});

  @override
  State<JobCompletedScreen> createState() => _JobCompletedScreenState();
}

class _JobCompletedScreenState extends State<JobCompletedScreen> {
  String? _jobId;
  Map<String, dynamic>? _job;
  bool _loading = true;
  String? _error;

  /// This job's two ratings from the caller's point of view: what they
  /// left, and what the other side left them. Either can be null.
  Map<String, dynamic>? _myRating;
  Map<String, dynamic>? _theirRating;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_jobId != null) return;
    final raw = ModalRoute.of(context)?.settings.arguments;
    if (raw is JobCompletedArgs) {
      _jobId = raw.jobId;
      _fetch();
    }
  }

  Future<void> _fetch() async {
    final id = _jobId;
    if (id == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final job = await HomeApi.jobById(id);
      if (!mounted) return;
      setState(() {
        _job = job;
        _loading = false;
      });
      _fetchRatings();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  /// Loads what was exchanged on this job, so a finished job can show
  /// the rating itself instead of a button that only earns a 409.
  ///
  /// Deliberately not fatal: a failure here leaves both sides null, the
  /// screen falls back to offering the button, and the rating screen
  /// still reports the duplicate cleanly. Losing this is a worse label,
  /// not a broken screen, so it never touches _error.
  Future<void> _fetchRatings() async {
    final id = _jobId;
    if (id == null) return;
    try {
      final res = await ApiClient.get('/ratings/job/$id');
      if (!mounted || res is! Map) return;
      setState(() {
        _myRating = res['given'] is Map
            ? Map<String, dynamic>.from(res['given'] as Map)
            : null;
        _theirRating = res['received'] is Map
            ? Map<String, dynamic>.from(res['received'] as Map)
            : null;
      });
    } catch (_) {
      // Leave both null; the button path below still works.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _Header(onBack: _onBack),
          Expanded(child: _body()),
          if (_job != null && !_loading) _bottomBar(),
        ],
      ),
    );
  }

  void _onBack() {
    // Skip the intermediate Complete Job + Job Status screens — back
    // from here drops the worker straight on My Jobs so they don't
    // bounce through the now-stale completion flow.
    Navigator.pushNamedAndRemoveUntil(context, '/my-jobs', (_) => false);
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF16A34A)),
        ),
      );
    }
    if (_error != null || _job == null) {
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
                _error ?? 'Job not found',
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
    final job = _job!;
    final title = (job['title'] ?? 'Job').toString();
    final desc = (job['description'] ?? '').toString();
    final category = (job['category'] ?? '').toString();
    final price = _price(job);
    final tip = (job['tip'] ?? 0) as num;
    final loc = job['location'] is Map ? job['location'] as Map : const {};
    final locText = [loc['address'], loc['city']]
        .map((s) => (s ?? '').toString())
        .where((s) => s.trim().isNotEmpty)
        .join(', ');
    // Prefer the scheduled slot; urgent / immediate jobs have no
    // scheduledAt, so fall back to when the job was completed and then
    // when it was posted so Date / Time never render an empty dash.
    final whenRaw =
        job['scheduledAt'] ?? job['completedAt'] ?? job['createdAt'];
    final scheduledDt = whenRaw != null
        ? DateTime.tryParse(whenRaw.toString())?.toLocal()
        : null;
    final giver = job['jobgiver'] is Map ? job['jobgiver'] as Map : const {};
    final clientName = (giver['name'] ?? 'Client').toString();

    return RefreshIndicator(
      color: const Color(0xFF16A34A),
      onRefresh: _fetch,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        children: [
          const _CompletedBanner(),
          const SizedBox(height: 16),
          _titleRow(title, price, tip),
          const SizedBox(height: 10),
          Row(
            children: [
              if (category.trim().isNotEmpty) ...[
                _Pill(
                  text: category,
                  bg: const Color(0xFFFFEDD4),
                  fg: const Color(0xFFFF6900),
                ),
                const SizedBox(width: 8),
              ],
              const _Pill(
                text: 'Completed',
                bg: Color(0xFFDCFCE7),
                fg: Color(0xFF15803D),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _detailGrid(
            locText: locText.isEmpty ? '—' : locText,
            dateText: scheduledDt != null ? _fmtDate(scheduledDt) : '—',
            timeText: scheduledDt != null ? _fmtTime(scheduledDt) : '—',
            clientName: clientName,
          ),
          if (desc.trim().isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text(
              'Description',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF101828),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              desc,
              style: const TextStyle(
                fontSize: 13.5,
                color: Color(0xFF374151),
                height: 1.55,
              ),
            ),
          ],
          const SizedBox(height: 18),
          _ClientDetailsCard(job: job, onChat: _openChat),
        ],
      ),
    );
  }

  Widget _titleRow(String title, String? price, num tip) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101828),
            ),
          ),
        ),
        if (price != null) ...[
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                price,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF101828),
                ),
              ),
              const Text(
                'Total',
                style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
              ),
              // Hint showing how much of the total above is the tip —
              // price already includes it. Shown to both worker and giver.
              if (tip > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '+ ₹${tip.toInt()} tip',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF16A34A),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _detailGrid({
    required String locText,
    required String dateText,
    required String timeText,
    required String clientName,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _DetailTile(
                icon: Icons.location_on_outlined,
                label: 'Location',
                value: locText,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _DetailTile(
                icon: Icons.calendar_today_outlined,
                label: 'Date',
                value: dateText,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _DetailTile(
                icon: Icons.access_time,
                label: 'Time',
                value: timeText,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _DetailTile(
                icon: Icons.person_outline,
                label: 'Client',
                value: clientName,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _paidRow() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFFDCFCE7),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFBBF7D0), width: 1),
          ),
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, size: 18, color: Color(0xFF16A34A)),
              SizedBox(width: 8),
              Text(
                'Payment Received',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF15803D),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: TextButton(
            onPressed: () => Navigator.pushNamedAndRemoveUntil(
              context,
              '/home',
              (_) => false,
            ),
            child: const Text(
              'Back to Home',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// This job's ratings, both directions, shown in place of the button.
  ///
  /// Each line is only drawn when that rating exists, so a one-sided
  /// exchange does not print an empty row the reader takes for a zero.
  /// The "Rate Your Client" button is still offered underneath when only
  /// the other side has rated.
  Widget _ratingSummaryRow() {
    Widget line(String label, int stars) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF364153),
              ),
            ),
          ),
          for (var i = 0; i < 5; i++)
            Icon(
              i < stars ? Icons.star : Icons.star_border,
              size: 16,
              color: i < stars
                  ? const Color(0xFFFFB400)
                  : const Color(0xFFD1D5DB),
            ),
          const SizedBox(width: 6),
          Text(
            '$stars',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101828),
            ),
          ),
        ],
      ),
    );

    final mine = (_myRating?['stars'] as num?)?.toInt();
    final theirs = (_theirRating?['stars'] as num?)?.toInt();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (theirs != null) line('They rated you', theirs),
          if (mine != null)
            line('You rated them', mine)
          else
            SizedBox(
              width: double.infinity,
              height: 36,
              child: TextButton(
                onPressed: _rateClient,
                child: const Text(
                  'Rate Your Client',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFF6900),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Opens the rating screen so the worker can rate the CLIENT.
  ///
  /// `mandatory: false` keeps the Optional link and the back button — the
  /// worker is never blocked by this, unlike the giver's rating of them,
  /// which is required.
  Future<void> _rateClient() async {
    final job = _job;
    final id = _jobId;
    if (job == null || id == null) return;
    final giver = job['jobgiver'] is Map ? job['jobgiver'] as Map : const {};
    await Navigator.pushNamed(
      context,
      '/rate-experience',
      arguments: RateExperienceArgs(
        jobId: id,
        jobTitle: (job['title'] ?? 'Job').toString(),
        clientName: (giver['name'] ?? 'the client').toString(),
        // Land back on My Jobs rather than the worker flow's default
        // Payment Request — by this point payment is either already done
        // or has its own button on this screen.
        nextRoute: '/my-jobs',
      ),
    );
    // A successful rating clears the stack, so arriving back here
    // normally means they skipped. Re-check anyway rather than assume.
    if (mounted) _fetchRatings();
  }

  Widget _bottomBar() {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE5E7EB), width: 0.8)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        // Worker-side landing after Submit Completion. Two follow-ups:
        // get paid, and rate the client. The rating half was missing
        // entirely — nothing in the app pushed /rate-experience for a
        // worker, so only the client could ever rate.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Once the client has settled up there's nothing left to ask
            // for — swap the request button for a plain confirmation and
            // send the worker home instead.
            if (_job?['paymentReleasedAt'] != null)
              _paidRow()
            else
              _orangeOutlineButton(label: 'Request to Pay', onTap: _requestPay),
            // Rating the client is optional for the worker (the reverse
            // direction is required of the giver), so this is a quiet
            // secondary action rather than a blocking step.
            //
            // Once rated, the button is replaced by what was actually
            // exchanged on this job. If the lookup failed, both are null
            // and the button stays — a second tap then gets the
            // backend's 409, which the rating screen shows inline.
            const SizedBox(height: 8),
            if (_myRating != null || _theirRating != null)
              _ratingSummaryRow()
            else
              SizedBox(
                width: double.infinity,
                height: 44,
                child: TextButton.icon(
                  onPressed: _rateClient,
                  icon: const Icon(
                    Icons.star_border,
                    size: 18,
                    color: Color(0xFFFF6900),
                  ),
                  label: const Text(
                    'Rate Your Client',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFF6900),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _orangeOutlineButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFFF6900), width: 1.4),
          foregroundColor: const Color(0xFFFF6900),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  void _requestPay() {
    final id = _jobId;
    if (id == null) return;
    final job = _job ?? const {};
    final giver = job['jobgiver'] is Map ? job['jobgiver'] as Map : const {};
    final priceRaw = job['finalPrice'] ?? job['proposedBudget'];
    // Requested amount includes the tip, matching what the backend now
    // actually pays out on release (platform fee never applies to the
    // tip). Deliberately excludes the boost fee — that's the giver's
    // cost for extra visibility, not money that reaches the worker.
    num? amount = priceRaw is num ? priceRaw : null;
    if (amount != null) {
      amount = amount + ((job['tip'] ?? 0) as num);
    }
    Navigator.pushNamed(
      context,
      '/payment-request',
      arguments: PaymentRequestArgs(
        jobId: id,
        amount: amount,
        jobTitle: (job['title'] ?? '').toString(),
        clientName: (giver['name'] ?? '').toString(),
      ),
    );
  }

  void _openChat() {
    final job = _job ?? const {};
    final giver = job['jobgiver'] is Map ? job['jobgiver'] as Map : const {};
    final giverId = (giver['_id'] ?? '').toString();
    final giverName = (giver['name'] ?? 'Client').toString();
    final giverMobile = (giver['mobile'] ?? '').toString();
    final me = context.read<AuthState>().user?['_id']?.toString();
    // Can't open a room with yourself — surface a hint instead of a
    // broken thread if somehow viewing your own posted job.
    if (giverId.isEmpty || giverId == me) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat not available for this job')),
      );
      return;
    }
    // Real-backend chat: passing userId wires the thread to
    // /chat/direct/with/:userId/open with polling — works whether the
    // client is currently online or offline.
    Navigator.pushNamed(
      context,
      '/chat',
      arguments: ChatArgs(
        name: giverName,
        userId: giverId,
        mobile: giverMobile.isEmpty ? null : giverMobile,
      ),
    );
  }

  String? _price(Map<String, dynamic> job) {
    num? n;
    final f = job['finalPrice'];
    if (f is num) n = f;
    n ??= () {
      final p = job['proposedBudget'];
      return p is num ? p : null;
    }();
    if (n == null) return null;
    // Total shown always includes the tip (and the boost fee, when
    // boosted) — kept separate from the raw amount used for _requestPay.
    if (job['isBoosted'] == true) n = n + AppConfig.boostFee;
    n = n + ((job['tip'] ?? 0) as num);
    return '₹${n.toStringAsFixed(0)}';
  }

  String _fmtDate(DateTime dt) {
    const months = [
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
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _fmtTime(DateTime dt) {
    final h12 = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final mm = dt.minute.toString().padLeft(2, '0');
    final ap = dt.hour < 12 ? 'AM' : 'PM';
    return '$h12:$mm $ap';
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onBack;
  const _Header({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Color(0xFF408EE0)),
      padding: EdgeInsets.fromLTRB(
        8,
        MediaQuery.of(context).padding.top + 8,
        16,
        12,
      ),
      child: Row(
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
                child: const Icon(
                  Icons.arrow_back,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'Job Details',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletedBanner extends StatelessWidget {
  const _CompletedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBBF7D0), width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.check_circle, size: 20, color: Color(0xFF16A34A)),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Job Completed',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF166534),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'This job has been successfully completed',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF166534),
                    height: 1.4,
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

class _Pill extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const _Pill({required this.text, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF6B7280)),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101828),
              height: 1.3,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _ClientDetailsCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final VoidCallback onChat;
  const _ClientDetailsCard({required this.job, required this.onChat});

  double? _rating(Map giver) =>
      ratingAverage(giver['rating']) ?? kUnratedDefault;

  @override
  Widget build(BuildContext context) {
    final giver = job['jobgiver'] is Map ? job['jobgiver'] as Map : const {};
    final name = (giver['name'] ?? 'Client').toString();
    final rating = _rating(giver);
    final photoRaw = (giver['photo'] ?? '').toString();
    final photo = photoRaw.isEmpty
        ? null
        : (photoRaw.startsWith('http')
              ? photoRaw
              : '${AppConfig.apiBase}$photoRaw');

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Client Details',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101828),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFE5E7EB),
                backgroundImage: photo != null ? NetworkImage(photo) : null,
                child: photo == null
                    ? const Icon(
                        Icons.person,
                        color: Color(0xFF9CA3AF),
                        size: 26,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF101828),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    if (rating != null)
                      Row(
                        children: [
                          const Icon(
                            Icons.star,
                            size: 14,
                            color: Color(0xFFFFB400),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${rating.toStringAsFixed(1)} rating',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      )
                    else
                      const Text(
                        'Verified',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: 36,
                height: 36,
                child: Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(
                      color: Color(0xFFE5E7EB),
                      width: 0.8,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: onChat,
                    child: const Icon(
                      Icons.chat_bubble_outline,
                      size: 16,
                      color: Color(0xFF6B7280),
                    ),
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
