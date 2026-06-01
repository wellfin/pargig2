import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/home_api.dart';
import '../state/auth_state.dart';

/// Wallet tab — opened from the bottom-nav wallet icon. Mirrors the
/// Figma:
///   * blue header (back arrow + "Wallet")
///   * peach Total Balance card with "+ Add Money" outline button
///   * Earnings Summary — This Month / Last Month side-by-side cards
///     computed from the transactions array returned by
///     /payments/me/earnings (no extra endpoint needed)
///   * Transaction History list with green-down / red-up icons
///   * 5-tab bottom nav with Wallet active
///
/// "Add Money" opens a bottom sheet with quick chips + custom amount
/// that POSTs /payments/wallet/topup — the legacy flow, re-skinned.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  bool _loading = true;
  String? _error;
  List<_Txn> _transactions = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Capture AuthState before any awaits to avoid using BuildContext
    // across async gaps.
    final auth = context.read<AuthState>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await HomeApi.walletSummary();
      // Refresh the auth state so the balance card matches what the
      // backend just returned (the user doc has walletBalance too).
      await auth.refreshMe();
      if (!mounted) return;
      final raw = res['transactions'];
      final txns = raw is List
          ? raw
              .whereType<Map>()
              .map((m) => _Txn.fromJson(Map<String, dynamic>.from(m)))
              .toList()
          : <_Txn>[];
      setState(() {
        _transactions = txns;
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

  ({num thisMonth, num lastMonth}) _earningsSplit() {
    final now = DateTime.now();
    final thisStart = DateTime(now.year, now.month, 1);
    final lastStart = DateTime(now.year, now.month - 1, 1);
    num thisMonth = 0;
    num lastMonth = 0;
    for (final t in _transactions) {
      if (t.amount <= 0) continue;
      // Treat any positive-credit type as earnings for the summary.
      if (t.type != 'payout' && t.type != 'payment' && t.type != 'refund') {
        continue;
      }
      if (t.at == null) continue;
      if (t.at!.isAfter(thisStart) || t.at!.isAtSameMomentAs(thisStart)) {
        thisMonth += t.amount;
      } else if (t.at!.isAfter(lastStart) || t.at!.isAtSameMomentAs(lastStart)) {
        lastMonth += t.amount;
      }
    }
    return (thisMonth: thisMonth, lastMonth: lastMonth);
  }

  String _formatDateTime(DateTime dt) {
    final h12 = dt.hour == 0
        ? 12
        : dt.hour > 12
            ? dt.hour - 12
            : dt.hour;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${_months[dt.month - 1]} ${dt.day}, ${dt.year} • $h12:$mm $ampm';
  }

  Future<void> _openAddMoney() async {
    final added = await Navigator.pushNamed(context, '/add-money');
    if (added == true && mounted) _load();
  }

  void _onNavTap(int i) {
    if (i == 3) return; // already on Wallet
    if (i == 0) {
      Navigator.popUntil(context, ModalRoute.withName('/home'));
      return;
    }
    final auth = context.read<AuthState>();
    if (i == 1) {
      Navigator.pushNamed(
        context,
        auth.isJobGiver ? '/my-posted-jobs' : '/my-jobs',
      );
      return;
    }
    if (i == 2) {
      Navigator.pushNamed(context, '/messages');
      return;
    }
    if (i == 4) {
      Navigator.pushNamed(context, '/profile');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final balance = (auth.user?['walletBalance'] is num)
        ? auth.user!['walletBalance'] as num
        : 0;
    final split = _earningsSplit();

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Column(
        children: [
          _Header(onBack: () => Navigator.maybePop(context)),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFFFF6900)),
                    ),
                  )
                : RefreshIndicator(
                    color: const Color(0xFFFF6900),
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      children: [
                        _BalanceCard(
                          balance: balance,
                          onAdd: _openAddMoney,
                        ),
                        const SizedBox(height: 20),
                        const _SectionTitle('Earnings Summary'),
                        const SizedBox(height: 10),
                        _EarningsRow(
                          thisMonth: split.thisMonth,
                          lastMonth: split.lastMonth,
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const _SectionTitle('Transaction History'),
                            GestureDetector(
                              onTap: () => ScaffoldMessenger.of(context)
                                  .showSnackBar(
                                const SnackBar(
                                  content: Text('Full history coming soon'),
                                  duration: Duration(milliseconds: 900),
                                ),
                              ),
                              child: const Text(
                                'View All',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFFF6900),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (_error != null)
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFFECACA),
                              ),
                            ),
                            padding: const EdgeInsets.all(14),
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFFB91C1C),
                              ),
                            ),
                          )
                        else if (_transactions.isEmpty)
                          _EmptyTxnsCard()
                        else
                          _TxnList(
                            transactions:
                                _transactions.take(5).toList(growable: false),
                            formatDateTime: _formatDateTime,
                          ),
                      ],
                    ),
                  ),
          ),
          _BottomNav(
            currentIndex: 3,
            onTap: _onNavTap,
            isWorkMode: !auth.isJobGiver,
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
                  'Wallet',
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

class _BalanceCard extends StatelessWidget {
  final num balance;
  final VoidCallback onAdd;
  const _BalanceCard({required this.balance, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFEDD4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD9B3), width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Total Balance',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF7E2A0C),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '₹${balance.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Color(0xFF101828),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 40,
            child: OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 16, color: Color(0xFFFF6900)),
              label: const Text(
                'Add Money',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFFF6900),
                ),
              ),
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFFFF6900), width: 1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: Color(0xFF101828),
      ),
    );
  }
}

class _EarningsRow extends StatelessWidget {
  final num thisMonth;
  final num lastMonth;
  const _EarningsRow({required this.thisMonth, required this.lastMonth});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _EarningsCard(
            label: 'This Month',
            amount: thisMonth,
            bg: const Color(0xFFFFEDD4),
            border: const Color(0xFFFFD9B3),
            labelColor: const Color(0xFF7E2A0C),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _EarningsCard(
            label: 'Last Month',
            amount: lastMonth,
            bg: const Color(0xFFEFF6FF),
            border: const Color(0xFFBFDBFE),
            labelColor: const Color(0xFF408EE0),
          ),
        ),
      ],
    );
  }
}

class _EarningsCard extends StatelessWidget {
  final String label;
  final num amount;
  final Color bg;
  final Color border;
  final Color labelColor;
  const _EarningsCard({
    required this.label,
    required this.amount,
    required this.bg,
    required this.border,
    required this.labelColor,
  });

  String _formatAmount(num v) {
    final i = v.toInt();
    final str = i.toString();
    // Indian number grouping: 1,23,456 — not 123,456. Quick path: only
    // groups beyond the last three digits use 2-digit clusters.
    if (str.length <= 3) return '₹$str';
    final last3 = str.substring(str.length - 3);
    final rest = str.substring(0, str.length - 3);
    final grouped = rest.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{2})+$)'),
      (m) => '${m[1]},',
    );
    return '₹$grouped,$last3';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: labelColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _formatAmount(amount),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF101828),
            ),
          ),
        ],
      ),
    );
  }
}

class _TxnList extends StatelessWidget {
  final List<_Txn> transactions;
  final String Function(DateTime) formatDateTime;

  const _TxnList({required this.transactions, required this.formatDateTime});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
      ),
      child: Column(
        children: List.generate(transactions.length, (i) {
          final t = transactions[i];
          final isLast = i == transactions.length - 1;
          return Column(
            children: [
              _TxnRow(txn: t, formatDateTime: formatDateTime),
              if (!isLast)
                const Divider(
                  height: 1,
                  thickness: 0.6,
                  color: Color(0xFFF1F5F9),
                  indent: 60,
                ),
            ],
          );
        }),
      ),
    );
  }
}

class _TxnRow extends StatelessWidget {
  final _Txn txn;
  final String Function(DateTime) formatDateTime;
  const _TxnRow({required this.txn, required this.formatDateTime});

  ({String label, bool credit}) _meta() {
    switch (txn.type) {
      case 'wallet_topup':
        return (label: 'Added to Wallet', credit: true);
      case 'payout':
      case 'payment':
        return (label: 'Job Payment Received', credit: true);
      case 'refund':
        return (label: 'Refund Received', credit: true);
      case 'wallet_deduct':
      case 'fee':
        return (label: 'Payment to Worker', credit: false);
      default:
        return (label: txn.note ?? 'Transaction', credit: txn.amount >= 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = _meta();
    final credit = meta.credit;
    final iconBg = credit ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2);
    final iconFg = credit ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    final amountFg = credit ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    final amountPrefix = credit ? '+' : '-';
    final at = txn.at;
    final dateLabel = at == null ? '' : formatDateTime(at);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(
              credit ? Icons.south_west : Icons.north_east,
              size: 16,
              color: iconFg,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meta.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF101828),
                  ),
                ),
                if (dateLabel.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    dateLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$amountPrefix₹${txn.amount.abs().toInt()}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: amountFg,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyTxnsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
      ),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        children: const [
          Icon(Icons.receipt_long_outlined,
              size: 32, color: Color(0xFF9CA3AF)),
          SizedBox(height: 10),
          Text(
            'No transactions yet',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF101828),
            ),
          ),
          SizedBox(height: 2),
          Text(
            'Top-ups and job earnings will show up here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool isWorkMode;

  const _BottomNav({
    required this.currentIndex,
    required this.onTap,
    required this.isWorkMode,
  });

  List<_NavItem> get _items => [
        const _NavItem('Home', Icons.home_outlined, Icons.home),
        _NavItem(
          isWorkMode ? 'My Jobs' : 'Jobs',
          Icons.work_outline,
          Icons.work,
        ),
        const _NavItem(
            'Messages', Icons.chat_bubble_outline, Icons.chat_bubble),
        const _NavItem(
          'Wallet',
          Icons.account_balance_wallet_outlined,
          Icons.account_balance_wallet,
        ),
        const _NavItem('Profile', Icons.person_outline, Icons.person),
      ];

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<AuthState>().unreadChats;
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        9,
        16,
        MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFE5E7EB), width: 0.8),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(_items.length, (i) {
          final item = _items[i];
          final active = i == currentIndex;
          final showDot = i == 2 && unread > 0;
          return GestureDetector(
            onTap: () => onTap(i),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 30,
                    height: 26,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          active ? item.activeIcon : item.icon,
                          size: 24,
                          color: active
                              ? const Color(0xFFFF6900)
                              : const Color(0xFF4A5565),
                        ),
                        if (showDot)
                          Positioned(
                            right: 2,
                            top: 0,
                            child: Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE7000B),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white, width: 1.4),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: active
                          ? const Color(0xFFFF6900)
                          : const Color(0xFF4A5565),
                      height: 1.33,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  const _NavItem(this.label, this.icon, this.activeIcon);
}

class _Txn {
  final String type;
  final num amount;
  final DateTime? at;
  final String? note;

  const _Txn({
    required this.type,
    required this.amount,
    required this.at,
    required this.note,
  });

  factory _Txn.fromJson(Map<String, dynamic> j) {
    final amount = j['amount'];
    final created = j['createdAt']?.toString();
    return _Txn(
      type: (j['type'] ?? '').toString(),
      amount: amount is num ? amount : 0,
      at: created == null ? null : DateTime.tryParse(created),
      note: j['note']?.toString(),
    );
  }
}
