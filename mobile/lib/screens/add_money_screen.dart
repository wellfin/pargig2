import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'select_payment_method_screen.dart';

/// Figma "Add Money" — full-screen replacement for the previous
/// bottom-sheet flow. Reached from the Wallet tab's "+ Add Money"
/// button. Pops with `true` once the topup succeeds so the caller
/// can refresh.
///
/// Backend: still POSTs /payments/wallet/topup (mock-credit until a
/// real gateway is wired). On success the new balance is persisted
/// on the user doc and the auth state is refreshed before pop so
/// the wallet card / home Earnings widget update.
class AddMoneyScreen extends StatefulWidget {
  const AddMoneyScreen({super.key});

  @override
  State<AddMoneyScreen> createState() => _AddMoneyScreenState();
}

class _AddMoneyScreenState extends State<AddMoneyScreen> {
  static const _quickAmounts = [500, 1000, 2000, 5000];

  final TextEditingController _ctrl = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      // Force rebuild so the bottom button enable state tracks the
      // input value.
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  num get _amount {
    final v = double.tryParse(_ctrl.text.trim()) ?? 0;
    return v;
  }

  void _setQuick(int amt) {
    _ctrl.text = amt.toString();
    _ctrl.selection = TextSelection.fromPosition(
      TextPosition(offset: _ctrl.text.length),
    );
    setState(() => _error = null);
  }

  Future<void> _submit() async {
    final amt = _amount;
    if (amt <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }
    // Step 2 of the top-up flow: pick a payment method. The actual
    // /payments/wallet/topup call happens there. We just bubble the
    // result back to Wallet so it can refresh.
    final added = await Navigator.pushNamed(
      context,
      '/select-payment-method',
      arguments: SelectPaymentMethodArgs(amount: amt),
    );
    if (!mounted) return;
    if (added == true) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _amount > 0;
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Column(
        children: [
          _Header(onBack: () => Navigator.maybePop(context)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
              children: [
                const Text(
                  'Enter Amount',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF101828),
                  ),
                ),
                const SizedBox(height: 8),
                _AmountField(controller: _ctrl),
                const SizedBox(height: 24),
                const Text(
                  'Quick Add',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF101828),
                  ),
                ),
                const SizedBox(height: 10),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 2.6,
                  children: _quickAmounts
                      .map((a) => _QuickChip(
                            amount: a,
                            selected: _amount.toInt() == a,
                            onTap: () => _setQuick(a),
                          ))
                      .toList(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                ],
              ],
            ),
          ),
          _Footer(
            enabled: canSubmit,
            onTap: _submit,
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
                  'Add Money',
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

class _AmountField extends StatelessWidget {
  final TextEditingController controller;
  const _AmountField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          const Text(
            '₹',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: false),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                LengthLimitingTextInputFormatter(7),
              ],
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF101828),
              ),
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 4),
                hintText: '0',
                hintStyle: TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final int amount;
  final bool selected;
  final VoidCallback? onTap;
  const _QuickChip({
    required this.amount,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? const Color(0xFFFFEDD4) : const Color(0xFFF3F4F6);
    final border =
        selected ? const Color(0xFFFF6900) : const Color(0xFFE5E7EB);
    final fg = selected ? const Color(0xFFFF6900) : const Color(0xFF101828);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: border,
              width: selected ? 1.2 : 0.8,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            '₹$amount',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _Footer({
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = enabled ? const Color(0xFFFF6900) : const Color(0xFFE5E7EB);
    final fg = enabled ? Colors.white : const Color(0xFF9CA3AF);
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Color(0xFFE5E7EB), width: 0.6),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: SizedBox(
          height: 52,
          width: double.infinity,
          child: ElevatedButton(
            onPressed: enabled ? onTap : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: bg,
              disabledBackgroundColor: bg,
              foregroundColor: fg,
              disabledForegroundColor: fg,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              'Add Money',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
