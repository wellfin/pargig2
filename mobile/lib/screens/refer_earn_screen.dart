import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Figma "Refer & Earn" — reached from the Refer & Earn quick-action
/// tile on the Profile screen. Three tabs (Overview / History /
/// Earnings); only the Overview is filled in since there's no
/// referral backend yet — History and Earnings show friendly empty
/// states so the tab bar isn't dead weight.
///
/// The referral code is a fixed placeholder ("WORK2026") and the
/// Total / Completed / Pending counts are mock values matching the
/// Figma. When a referral service exists, those four values become
/// the only data the screen needs to bind.
class ReferEarnScreen extends StatefulWidget {
  const ReferEarnScreen({super.key});

  @override
  State<ReferEarnScreen> createState() => _ReferEarnScreenState();
}

class _ReferEarnScreenState extends State<ReferEarnScreen> {
  static const _referralCode = 'WORK2026';
  static const _bonusPerReferral = 100;

  // Mock referral history — replace with /referrals API when the
  // service exists. Stats below are derived from this list so the
  // Overview totals always stay in sync with what History shows.
  static final List<_Referral> _referrals = [
    _Referral(
      name: 'Amit Kumar',
      joinedAt: DateTime(2026, 4, 15),
      firstJobAt: DateTime(2026, 4, 18),
      completed: true,
    ),
    _Referral(
      name: 'Priya Sharma',
      joinedAt: DateTime(2026, 4, 10),
      firstJobAt: DateTime(2026, 4, 12),
      completed: true,
    ),
    _Referral(
      name: 'Raj Patel',
      joinedAt: DateTime(2026, 4, 20),
      completed: false,
    ),
    _Referral(
      name: 'Sneha Reddy',
      joinedAt: DateTime(2026, 4, 5),
      firstJobAt: DateTime(2026, 4, 8),
      completed: true,
    ),
    _Referral(
      name: 'Karthik Singh',
      joinedAt: DateTime(2026, 3, 28),
      firstJobAt: DateTime(2026, 4, 1),
      completed: true,
    ),
    _Referral(
      name: 'Rohit Verma',
      joinedAt: DateTime(2026, 3, 22),
      firstJobAt: DateTime(2026, 3, 25),
      completed: true,
    ),
    _Referral(
      name: 'Anjali Iyer',
      joinedAt: DateTime(2026, 3, 15),
      firstJobAt: DateTime(2026, 3, 19),
      completed: true,
    ),
    _Referral(
      name: 'Vikram Joshi',
      joinedAt: DateTime(2026, 3, 10),
      completed: false,
    ),
  ];

  int get _total => _referrals.length;
  int get _completed => _referrals.where((r) => r.completed).length;
  int get _pending => _referrals.where((r) => !r.completed).length;

  int _tabIndex = 0;

  Future<void> _copyLink() async {
    await Clipboard.setData(
      const ClipboardData(
        text: 'Join Pargig with my code $_referralCode '
            'and we both earn ₹$_bonusPerReferral!',
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Referral link copied to clipboard'),
        duration: Duration(milliseconds: 1000),
      ),
    );
  }

  Future<void> _share() async {
    // share_plus isn't wired into pubspec yet, so this falls back to
    // clipboard with a different snackbar — same UX outcome (the user
    // can paste into their messaging app of choice) without adding a
    // native dependency.
    await Clipboard.setData(
      const ClipboardData(
        text: 'Hey! Join Pargig — the gig-work app — using my code '
            '$_referralCode and we both get ₹$_bonusPerReferral. '
            'Download the app and enter the code at signup.',
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Share text copied — paste it anywhere'),
        duration: Duration(milliseconds: 1000),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Column(
        children: [
          _Header(onBack: () => Navigator.maybePop(context)),
          _Tabs(
            selected: _tabIndex,
            onTap: (i) => setState(() => _tabIndex = i),
          ),
          Expanded(
            child: switch (_tabIndex) {
              0 => _OverviewBody(
                  bonusPerReferral: _bonusPerReferral,
                  code: _referralCode,
                  total: _total,
                  completed: _completed,
                  pending: _pending,
                  onCopyLink: _copyLink,
                  onShare: _share,
                ),
              1 => _HistoryBody(
                  referrals: _referrals,
                  bonusPerReferral: _bonusPerReferral,
                ),
              _ => _EarningsBody(
                  referrals: _referrals,
                  bonusPerReferral: _bonusPerReferral,
                ),
            },
          ),
        ],
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
      decoration: const BoxDecoration(color: Color(0xFF408EE0)),
      padding: EdgeInsets.fromLTRB(
        4, MediaQuery.of(context).padding.top + 6, 16, 12,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
            onPressed: onBack,
          ),
          const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(right: 40),
                child: Text(
                  'Refer & Earn',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  static const _labels = ['Overview', 'History', 'Earnings'];
  final int selected;
  final ValueChanged<int> onTap;

  const _Tabs({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: List.generate(_labels.length, (i) {
          final active = i == selected;
          return Padding(
            padding: EdgeInsets.only(right: i == _labels.length - 1 ? 0 : 8),
            child: Material(
              color: active ? const Color(0xFFFF6900) : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => onTap(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 8),
                  child: Text(
                    _labels[i],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: active ? Colors.white : const Color(0xFF4A5565),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _OverviewBody extends StatelessWidget {
  final int bonusPerReferral;
  final String code;
  final int total;
  final int completed;
  final int pending;
  final Future<void> Function() onCopyLink;
  final Future<void> Function() onShare;

  const _OverviewBody({
    required this.bonusPerReferral,
    required this.code,
    required this.total,
    required this.completed,
    required this.pending,
    required this.onCopyLink,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      children: [
        _HeroCard(bonus: bonusPerReferral),
        const SizedBox(height: 16),
        _CodeCard(code: code, onCopyLink: onCopyLink, onShare: onShare),
        const SizedBox(height: 16),
        _StatsRow(total: total, completed: completed, pending: pending),
        const SizedBox(height: 16),
        const _HowItWorksCard(),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  final int bonus;
  const _HeroCard({required this.bonus});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF8A33), Color(0xFFFF6900)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: Color(0x33FFFFFF),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.card_giftcard,
                size: 28, color: Colors.white),
          ),
          const SizedBox(height: 14),
          Text(
            'Earn ₹$bonus per Referral',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Share your code and earn rewards\nwhen friends join!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Color(0xEEFFFFFF),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  final String code;
  final Future<void> Function() onCopyLink;
  final Future<void> Function() onShare;

  const _CodeCard({
    required this.code,
    required this.onCopyLink,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
      ),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        children: [
          const Text(
            'Your Referral Code',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: const Color(0xFFFFD9B3), width: 1.2),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Center(
              child: Text(
                code,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFFF6900),
                  letterSpacing: 4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: onCopyLink,
                    icon: const Icon(Icons.copy_outlined,
                        size: 16, color: Color(0xFF374151)),
                    label: const Text(
                      'Copy Link',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF374151),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      side: const BorderSide(
                        color: Color(0xFFE5E7EB),
                        width: 1,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: onShare,
                    icon: const Icon(Icons.share_outlined,
                        size: 16, color: Colors.white),
                    label: const Text(
                      'Share',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6900),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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

class _StatsRow extends StatelessWidget {
  final int total;
  final int completed;
  final int pending;

  const _StatsRow({
    required this.total,
    required this.completed,
    required this.pending,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatChip(
            value: total,
            label: 'Total',
            bg: Color(0xFFF3F4F6),
            valueColor: Color(0xFF101828),
            labelColor: Color(0xFF6B7280),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatChip(
            value: completed,
            label: 'Completed',
            bg: Color(0xFFDCFCE7),
            valueColor: Color(0xFF16A34A),
            labelColor: Color(0xFF166534),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatChip(
            value: pending,
            label: 'Pending',
            bg: Color(0xFFFFEDD4),
            valueColor: Color(0xFFFF6900),
            labelColor: Color(0xFF7E2A0C),
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final int value;
  final String label;
  final Color bg;
  final Color valueColor;
  final Color labelColor;

  const _StatChip({
    required this.value,
    required this.label,
    required this.bg,
    required this.valueColor,
    required this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: labelColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _HowItWorksCard extends StatelessWidget {
  const _HowItWorksCard();

  static const _steps = [
    (
      title: 'Share your code',
      body: 'Send your referral code to friends',
    ),
    (
      title: 'They sign up',
      body: 'Friend joins using your code',
    ),
    (
      title: 'Earn rewards',
      body: 'Get ₹100 after their first job',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How it works',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101828),
            ),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < _steps.length; i++) ...[
            _StepRow(
              index: i + 1,
              title: _steps[i].title,
              body: _steps[i].body,
            ),
            if (i != _steps.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final int index;
  final String title;
  final String body;

  const _StepRow({
    required this.index,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: Color(0xFFFFEDD4),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '$index',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFFFF6900),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF101828),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B7280),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HistoryBody extends StatelessWidget {
  final List<_Referral> referrals;
  final int bonusPerReferral;

  const _HistoryBody({
    required this.referrals,
    required this.bonusPerReferral,
  });

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _fmt(DateTime dt) => '${_months[dt.month - 1]} ${dt.day}, ${dt.year}';

  @override
  Widget build(BuildContext context) {
    if (referrals.isEmpty) {
      return const _PlaceholderTab(
        icon: Icons.history_outlined,
        title: 'No referrals yet',
        body: 'Your referral history will appear here once '
            'friends start signing up.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      itemCount: referrals.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final r = referrals[i];
        return _ReferralRow(
          referral: r,
          bonusPerReferral: bonusPerReferral,
          joinedLabel: 'Joined ${_fmt(r.joinedAt)}',
          firstJobLabel: r.firstJobAt == null
              ? null
              : 'First job: ${_fmt(r.firstJobAt!)}',
        );
      },
    );
  }
}

class _ReferralRow extends StatelessWidget {
  final _Referral referral;
  final int bonusPerReferral;
  final String joinedLabel;
  final String? firstJobLabel;

  const _ReferralRow({
    required this.referral,
    required this.bonusPerReferral,
    required this.joinedLabel,
    required this.firstJobLabel,
  });

  @override
  Widget build(BuildContext context) {
    final completed = referral.completed;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: Color(0xFFF3F4F6),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.person_outline,
                    size: 18, color: Color(0xFF6B7280)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      referral.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF101828),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined,
                            size: 12, color: Color(0xFF9CA3AF)),
                        const SizedBox(width: 4),
                        Text(
                          joinedLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(completed: completed),
            ],
          ),
          if (firstJobLabel != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    firstJobLabel!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
                Text(
                  '+₹$bonusPerReferral',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF16A34A),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool completed;
  const _StatusPill({required this.completed});

  @override
  Widget build(BuildContext context) {
    final bg = completed
        ? const Color(0xFFDCFCE7)
        : const Color(0xFFFFEDD4);
    final fg = completed
        ? const Color(0xFF16A34A)
        : const Color(0xFFFF6900);
    final icon = completed ? Icons.check_circle : Icons.access_time;
    final label = completed ? 'Completed' : 'Pending';
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _EarningsBody extends StatelessWidget {
  final List<_Referral> referrals;
  final int bonusPerReferral;

  const _EarningsBody({
    required this.referrals,
    required this.bonusPerReferral,
  });

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _fmt(DateTime dt) => '${_months[dt.month - 1]} ${dt.day}, ${dt.year}';

  @override
  Widget build(BuildContext context) {
    // Only completed referrals produce a bonus payout. Sort
    // most-recent first by firstJobAt (fallback to joinedAt) so the
    // newest credit sits at the top.
    final earned = referrals.where((r) => r.completed).toList()
      ..sort((a, b) {
        final da = a.firstJobAt ?? a.joinedAt;
        final db = b.firstJobAt ?? b.joinedAt;
        return db.compareTo(da);
      });
    final total = earned.length * bonusPerReferral;

    if (earned.isEmpty) {
      return const _PlaceholderTab(
        icon: Icons.payments_outlined,
        title: 'No earnings yet',
        body: 'Bonus payouts from completed referrals will '
            'show up here.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      children: [
        _TotalEarnedCard(total: total, count: earned.length),
        const SizedBox(height: 16),
        const Text(
          'Earnings History',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF101828),
          ),
        ),
        const SizedBox(height: 10),
        ...earned.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _EarningRow(
                amount: bonusPerReferral,
                referral: r,
                dateLabel: _fmt(r.firstJobAt ?? r.joinedAt),
              ),
            )),
      ],
    );
  }
}

class _TotalEarnedCard extends StatelessWidget {
  final int total;
  final int count;
  const _TotalEarnedCard({required this.total, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Expanded(
                child: Text(
                  'Total Earned',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xEEFFFFFF),
                  ),
                ),
              ),
              Icon(Icons.trending_up, size: 18, color: Colors.white),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '₹$total',
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'From $count successful referral${count == 1 ? '' : 's'}',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xCCFFFFFF),
            ),
          ),
        ],
      ),
    );
  }
}

class _EarningRow extends StatelessWidget {
  final int amount;
  final _Referral referral;
  final String dateLabel;
  const _EarningRow({
    required this.amount,
    required this.referral,
    required this.dateLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.currency_rupee,
                    size: 16, color: Color(0xFF6B7280)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '₹$amount',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF101828),
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'First Job Bonus',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  color: Color(0xFFDCFCE7),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.check,
                    size: 14, color: Color(0xFF16A34A)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 0.6,
            color: const Color(0xFFF1F5F9),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  referral.name,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF374151),
                  ),
                ),
              ),
              const Icon(Icons.calendar_today_outlined,
                  size: 12, color: Color(0xFF9CA3AF)),
              const SizedBox(width: 4),
              Text(
                dateLabel,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Referral {
  final String name;
  final DateTime joinedAt;
  final DateTime? firstJobAt;
  final bool completed;

  const _Referral({
    required this.name,
    required this.joinedAt,
    this.firstJobAt,
    required this.completed,
  });
}

class _PlaceholderTab extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _PlaceholderTab({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: const Color(0xFF9CA3AF)),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF101828),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
