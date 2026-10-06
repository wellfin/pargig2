import 'package:flutter/material.dart';

/// Args for Navigator.pushNamed('/money-added', ...).
class MoneyAddedArgs {
  final double amount;
  final double? newBalance;
  final String? methodLabel;
  final String? transactionId;

  const MoneyAddedArgs({
    required this.amount,
    this.newBalance,
    this.methodLabel,
    this.transactionId,
  });
}

/// Figma "Money Added!" — the end of Add Money -> Select Payment Method.
///
/// Purely a confirmation: the credit already happened server-side when
/// the gateway confirmed, so nothing here can fail or needs retrying.
/// Done clears back to the wallet, which re-reads the balance rather than
/// trusting a number passed through the stack.
class MoneyAddedScreen extends StatefulWidget {
  const MoneyAddedScreen({super.key});

  @override
  State<MoneyAddedScreen> createState() => _MoneyAddedScreenState();
}

class _MoneyAddedScreenState extends State<MoneyAddedScreen> {
  MoneyAddedArgs? _args;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_args != null) return;
    final raw = ModalRoute.of(context)?.settings.arguments;
    if (raw is MoneyAddedArgs) setState(() => _args = raw);
  }

  void _done() {
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/wallet',
      (route) => route.settings.name == '/home',
    );
  }

  @override
  Widget build(BuildContext context) {
    final args = _args;
    final amount = args?.amount ?? 0;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  color: Color(0xFFDCFCE7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_outline,
                  size: 52,
                  color: Color(0xFF16A34A),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Money Added!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF101828),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '₹${amount.toStringAsFixed(0)} added to your wallet',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: Color(0xFF6B7280),
                  height: 1.5,
                ),
              ),
              if (args?.newBalance != null ||
                  (args?.transactionId ?? '').isNotEmpty) ...[
                const SizedBox(height: 22),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFE5E7EB),
                      width: 0.8,
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    children: [
                      _Row(
                        label: 'Amount',
                        value: '₹${amount.toStringAsFixed(0)}',
                        bold: true,
                      ),
                      if ((args?.methodLabel ?? '').isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _Row(label: 'Paid via', value: args!.methodLabel!),
                      ],
                      if (args?.newBalance != null) ...[
                        const SizedBox(height: 10),
                        _Row(
                          label: 'Wallet balance',
                          value: '₹${args!.newBalance!.toStringAsFixed(0)}',
                        ),
                      ],
                      if ((args?.transactionId ?? '').isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _Row(
                          label: 'Transaction ID',
                          value: args!.transactionId!,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: _done,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    side: const BorderSide(
                      color: Color(0xFFFF6900),
                      width: 1.4,
                    ),
                    foregroundColor: const Color(0xFFFF6900),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
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

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _Row({required this.label, required this.value, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: bold ? const Color(0xFF16A34A) : const Color(0xFF101828),
            ),
          ),
        ),
      ],
    );
  }
}
