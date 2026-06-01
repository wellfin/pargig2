import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../state/auth_state.dart';

/// Modal shown before submitting a job application when the user's
/// wallet balance is below the required deposit. Lets the user top
/// up inline (no detour to the Wallet screen) and continue.
///
/// Returns `true` from `show()` if the top-up succeeded and the
/// caller can proceed with the apply / request POST. `false`/`null`
/// if the user cancelled.
class WalletDepositRequiredDialog extends StatefulWidget {
  final num requiredAmount;
  final num currentBalance;

  const WalletDepositRequiredDialog({
    super.key,
    required this.requiredAmount,
    required this.currentBalance,
  });

  static Future<bool> show(
    BuildContext context, {
    required num requiredAmount,
    required num currentBalance,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WalletDepositRequiredDialog(
        requiredAmount: requiredAmount,
        currentBalance: currentBalance,
      ),
    );
    return ok == true;
  }

  @override
  State<WalletDepositRequiredDialog> createState() =>
      _WalletDepositRequiredDialogState();
}

class _WalletDepositRequiredDialogState
    extends State<WalletDepositRequiredDialog> {
  bool _busy = false;
  String? _error;

  num get _topupAmount => widget.requiredAmount - widget.currentBalance;

  Future<void> _topUp() async {
    if (_busy) return;
    // Capture the AuthState reference before any awaits so we don't
    // touch BuildContext after the async gap.
    final auth = context.read<AuthState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.post(
        '/payments/wallet/topup',
        {'amount': _topupAmount},
      );
      // Refresh user so the next apply call sees the new balance.
      await auth.refreshMe();
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is ApiException ? e.message : e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF7ED),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 32,
                  color: Color(0xFFFF6900),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Wallet Deposit Required',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF101828),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You need ₹${widget.requiredAmount.toInt()} in your wallet to apply '
                'for jobs (one-time, for your first 3 jobs). Top up now and '
                "we'll send your application right after.",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Current balance',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    Text(
                      '₹${widget.currentBalance.toInt()}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF101828),
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _busy ? null : _topUp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6900),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          'Add ₹${_topupAmount.toInt()} & Continue',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6B7280),
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

/// Helper that wraps a job-apply submit: checks wallet balance + job
/// rules, and if a deposit is required AND wallet is short, shows
/// the dialog. Returns true if the caller is OK to proceed with the
/// POST /jobs/:id/interest call.
Future<bool> ensureWalletReadyForApply(
  BuildContext context, {
  required num proposedPrice,
  num firstJobFreeBelow = 1000,
  num requiredDeposit = 20,
}) async {
  final auth = context.read<AuthState>();
  final user = auth.user ?? const <String, dynamic>{};
  final completed = (user['jobsCompleted'] as num?)?.toInt() ?? 0;
  final balance = (user['walletBalance'] as num?) ?? 0;

  final isFirstFreeJob = completed == 0 && proposedPrice < firstJobFreeBelow;
  if (isFirstFreeJob) return true;
  if (completed >= 3) return true;
  if (balance >= requiredDeposit) return true;

  // Wallet short — show the dialog and let the user top up inline.
  return WalletDepositRequiredDialog.show(
    context,
    requiredAmount: requiredDeposit,
    currentBalance: balance,
  );
}
