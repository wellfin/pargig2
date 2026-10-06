import 'package:flutter/material.dart';

import 'select_release_payment_method_screen.dart';

/// Args passed via Navigator.pushNamed('/release-payment', ...).
class ReleasePaymentArgs {
  final String jobId;
  final String jobTitle;
  final String workerName;
  final double amount;

  const ReleasePaymentArgs({
    required this.jobId,
    required this.jobTitle,
    required this.workerName,
    required this.amount,
  });
}

/// Figma "Payment" — confirmation step for releasing a completed
/// job's payment to the worker. Pushed from the Hire-mode My Posted
/// Jobs "Release Payment" button. Pops with `true` once the release
/// succeeds so the caller can reload and flip the source button to
/// "Payment Released".
class ReleasePaymentScreen extends StatefulWidget {
  const ReleasePaymentScreen({super.key});

  @override
  State<ReleasePaymentScreen> createState() => _ReleasePaymentScreenState();
}

class _ReleasePaymentScreenState extends State<ReleasePaymentScreen> {
  ReleasePaymentArgs? _args;
  // Kept so the busy spinner can briefly show while navigation
  // animates and the user can't double-tap Confirm & Pay.
  bool _submitting = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_args != null) return;
    final raw = ModalRoute.of(context)?.settings.arguments;
    if (raw is ReleasePaymentArgs) {
      setState(() => _args = raw);
    }
  }

  Future<void> _confirm() async {
    final args = _args;
    if (args == null || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    // Step 2: pick a payment method, which hands off to /payment-status
    // for the actual release + receipt. That screen clears the stack on
    // Done, so control only returns here if the user backed out — reset
    // the busy flag and let them try again.
    await Navigator.pushNamed(
      context,
      '/select-release-payment-method',
      arguments: SelectReleasePaymentMethodArgs(
        jobId: args.jobId,
        jobTitle: args.jobTitle,
        workerName: args.workerName,
        amount: args.amount,
      ),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final args = _args;
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Column(
        children: [
          _Header(onBack: () => Navigator.maybePop(context)),
          Expanded(
            child: args == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                    children: [
                      _AmountCard(amount: args.amount),
                      const SizedBox(height: 16),
                      _DetailsCard(
                        jobTitle: args.jobTitle,
                        workerName: args.workerName,
                        amount: args.amount,
                      ),
                      const SizedBox(height: 16),
                      const _InfoBanner(
                        text:
                            'Payment will be released to the worker after '
                            'you confirm job completion.',
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFECACA)),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFFB91C1C),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          if (args != null) _Footer(busy: _submitting, onTap: _confirm),
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
              child: Padding(
                padding: EdgeInsets.only(right: 40),
                child: Text(
                  'Payment',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF101828),
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

class _AmountCard extends StatelessWidget {
  final double amount;
  const _AmountCard({required this.amount});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF8A33), Color(0xFFFF6900)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payment Amount',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xEEFFFFFF),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '₹${amount.toInt()}',
            style: const TextStyle(
              fontSize: 32,
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

class _DetailsCard extends StatelessWidget {
  final String jobTitle;
  final String workerName;
  final double amount;

  const _DetailsCard({
    required this.jobTitle,
    required this.workerName,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
          _DetailRow(label: 'Job Title', value: jobTitle),
          const SizedBox(height: 8),
          _DetailRow(label: 'Worker', value: workerName),
          const SizedBox(height: 10),
          Container(height: 0.6, color: const Color(0xFFF1F5F9)),
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Total',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF101828),
                  ),
                ),
              ),
              Text(
                '₹${amount.toInt()}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF101828),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
          ),
        ),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF101828),
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final String text;
  const _InfoBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD9B3), width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 16, color: Color(0xFFFF6900)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF7E2A0C),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;

  const _Footer({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE5E7EB), width: 0.6)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: SizedBox(
          height: 50,
          width: double.infinity,
          child: OutlinedButton(
            onPressed: busy ? null : onTap,
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFFFF6900), width: 1.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFFFF6900),
                      ),
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '₹',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFFF6900),
                        ),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Confirm & Pay',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFFF6900),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
