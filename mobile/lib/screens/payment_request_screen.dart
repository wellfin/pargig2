import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/home_api.dart';
import 'payment_qr_screen.dart';

/// Args for Navigator.pushNamed('/payment-request', ...). Optional
/// fields are pre-fetched hints from upstream screens so we can
/// render the amount card without a network round-trip; the screen
/// still re-fetches the job to guarantee fresh data.
class PaymentRequestArgs {
  final String jobId;
  final num? amount;
  final String? jobTitle;
  final String? clientName;
  const PaymentRequestArgs({
    required this.jobId,
    this.amount,
    this.jobTitle,
    this.clientName,
  });
}

/// Figma "Payment" — worker-side payout-request screen reached
/// after Rating Thanks (auto) or via Request to Pay on Job
/// Completed. Shows the amount, job details summary, payout method
/// chooser (Cash / UPI / Card), and a Request to Pay button that
/// POSTs /payments/request — pinging the client to release payment
/// via the chosen method.
class PaymentRequestScreen extends StatefulWidget {
  const PaymentRequestScreen({super.key});

  @override
  State<PaymentRequestScreen> createState() => _PaymentRequestScreenState();
}

class _PaymentRequestScreenState extends State<PaymentRequestScreen> {
  PaymentRequestArgs? _args;
  Map<String, dynamic>? _job;
  bool _loading = true;
  String? _error;

  String _method = 'upi';
  bool _submitting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_args != null) return;
    final raw = ModalRoute.of(context)?.settings.arguments;
    if (raw is PaymentRequestArgs) {
      _args = raw;
      _fetch();
    }
  }

  Future<void> _fetch() async {
    final id = _args?.jobId;
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
        // Pre-fill the chooser with whatever the worker previously
        // picked (if any) so a re-open of this screen is sticky.
        final prev = (job['payoutMethod'] ?? '').toString();
        if (['cash', 'upi', 'card'].contains(prev)) _method = prev;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  num? _amount() {
    if (_args?.amount != null) return _args!.amount;
    final job = _job;
    if (job == null) return null;
    final f = job['finalPrice'];
    if (f is num) return f;
    final p = job['proposedBudget'];
    return p is num ? p : null;
  }

  String _amountText() {
    final n = _amount();
    return n == null ? '—' : '₹${n.toStringAsFixed(0)}';
  }

  String _jobTitle() {
    final fromArgs = (_args?.jobTitle ?? '').trim();
    if (fromArgs.isNotEmpty) return fromArgs;
    return (_job?['title'] ?? 'Home Cleaning').toString();
  }

  String _clientName() {
    final fromArgs = (_args?.clientName ?? '').trim();
    if (fromArgs.isNotEmpty) return fromArgs;
    final giver = _job?['jobgiver'];
    if (giver is Map) return (giver['name'] ?? 'Client').toString();
    return 'Client';
  }

  Future<void> _request() async {
    final id = _args?.jobId;
    if (id == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      await ApiClient.post('/payments/request', {
        'jobId': id,
        'method': _method,
      });
      if (!mounted) return;
      if (_method == 'upi') {
        // Worker chose UPI → push the scannable BHIM UPI QR screen
        // so the client can pay on-the-spot. Cash / Card just notify
        // and exit (no on-device flow needed today).
        Navigator.pushNamed(
          context,
          '/payment-qr',
          arguments: PaymentQrArgs(
            jobId: id,
            amount: _amount(),
            jobTitle: _jobTitle(),
            clientName: _clientName(),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Payment request sent — client will pay via '
            '${_label(_method)}',
          ),
        ),
      );
      Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : e.toString())),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _label(String m) {
    switch (m) {
      case 'upi':
        return 'UPI';
      case 'card':
        return 'Card';
      default:
        return 'Cash';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _Header(onBack: () => Navigator.maybePop(context)),
          Expanded(child: _body()),
          _bottomBar(),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading && _job == null) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6900)),
        ),
      );
    }
    if (_error != null && _job == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 40, color: Color(0xFFDC2626)),
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton(onPressed: _fetch, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final amount = _amountText();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        _AmountCard(amount: amount),
        const SizedBox(height: 16),
        _JobDetailsCard(
          title: _jobTitle(),
          clientName: _clientName(),
          totalText: amount,
        ),
        const SizedBox(height: 14),
        const _HoldNoticeCard(),
        const SizedBox(height: 18),
        const _MethodLabel(),
        const SizedBox(height: 10),
        _methodRow(),
      ],
    );
  }

  Widget _methodRow() {
    return Row(
      children: [
        Expanded(
          child: _MethodTile(
            icon: Icons.currency_rupee,
            label: 'Cash',
            selected: _method == 'cash',
            onTap: () => setState(() => _method = 'cash'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MethodTile(
            icon: Icons.smartphone,
            label: 'UPI',
            selected: _method == 'upi',
            onTap: () => setState(() => _method = 'upi'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MethodTile(
            icon: Icons.credit_card,
            label: 'Card',
            selected: _method == 'card',
            onTap: () => setState(() => _method = 'card'),
          ),
        ),
      ],
    );
  }

  Widget _bottomBar() {
    final canSubmit = !_submitting && _job != null;
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Color(0xFFE5E7EB), width: 0.8),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: SizedBox(
          height: 50,
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: canSubmit ? _request : null,
            icon: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFFFF6900)),
                    ),
                  )
                : const Icon(Icons.currency_rupee,
                    size: 18, color: Color(0xFFFF6900)),
            label: const Text(
              'Request to Pay',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              side: BorderSide(
                color: canSubmit
                    ? const Color(0xFFFF6900)
                    : const Color(0xFFFFC79A),
                width: 1.4,
              ),
              foregroundColor: const Color(0xFFFF6900),
              disabledForegroundColor: const Color(0xFFFFC79A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
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
                child: const Icon(Icons.arrow_back,
                    size: 18, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'Payment',
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

class _AmountCard extends StatelessWidget {
  final String amount;
  const _AmountCard({required this.amount});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFF6900),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payment Amount',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            amount,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _JobDetailsCard extends StatelessWidget {
  final String title;
  final String clientName;
  final String totalText;
  const _JobDetailsCard({
    required this.title,
    required this.clientName,
    required this.totalText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Job Details',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101828),
            ),
          ),
          const SizedBox(height: 12),
          _row('Job Title', title),
          const SizedBox(height: 8),
          _row('Client', clientName),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF101828),
                ),
              ),
              Text(
                totalText,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFFF6900),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101828),
            ),
          ),
        ),
      ],
    );
  }
}

class _HoldNoticeCard extends StatelessWidget {
  const _HoldNoticeCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD9B3), width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: const Text(
        'Payment will be released to the worker after you confirm job '
        'completion.',
        style: TextStyle(
          fontSize: 12.5,
          color: Color(0xFF7E2A0C),
          height: 1.5,
        ),
      ),
    );
  }
}

class _MethodLabel extends StatelessWidget {
  const _MethodLabel();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Text(
          'Payment Method ',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF101828),
          ),
        ),
        Text(
          '* ',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFFFF6900),
          ),
        ),
        Text(
          '(Required)',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFFFF6900),
          ),
        ),
      ],
    );
  }
}

class _MethodTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _MethodTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? const Color(0xFF408EE0)
                : const Color(0xFFE5E7EB),
            width: selected ? 1.6 : 0.8,
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: selected
                  ? const Color(0xFF408EE0)
                  : const Color(0xFF6B7280),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected
                    ? const Color(0xFF408EE0)
                    : const Color(0xFF374151),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
