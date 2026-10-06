import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/home_api.dart';
import '../state/auth_state.dart';
import '../utils/invoice_pdf.dart';
import 'job_completed_screen.dart';
import 'rate_experience_screen.dart';

/// Which side of the payment is looking at this screen.
///
/// The giver's visit *performs* the release; the worker's only displays
/// the receipt for a payment that already happened. Same layout, opposite
/// direction of money — hence "paid to" versus "received from".
enum PaymentStatusRole { payer, payee }

/// Args for Navigator.pushNamed('/payment-status', ...).
class PaymentStatusArgs {
  final String jobId;
  final String jobTitle;
  final String workerName;
  final double amount;
  // Human label of whatever the giver picked on Select Payment Method.
  final String methodLabel;
  final bool isCod;
  final PaymentStatusRole role;
  // Set when the payment already completed (worker receipt, or a
  // gateway-confirmed payment): the screen then shows this reference
  // instead of releasing again.
  final String? transactionId;
  // Who the money came from, shown on the worker's receipt.
  final String? clientName;

  const PaymentStatusArgs({
    required this.jobId,
    required this.jobTitle,
    required this.workerName,
    required this.amount,
    required this.methodLabel,
    required this.isCod,
    this.role = PaymentStatusRole.payer,
    this.transactionId,
    this.clientName,
  });
}

/// Figma "Processing Payment" → "Payment Successful". Owns the actual
/// POST /payments/jobs/:id/release: it opens on the spinner, fires the
/// release, then swaps to the receipt in place — so the giver never sees
/// a dead screen while money moves.
///
/// The receipt line differs by method: a cash settlement has no reference
/// to quote so it shows "Cash on Delivery", while an online one shows the
/// transaction id the backend minted.
///
/// Done hands off to Rate Experience (which the giver can skip — rating
/// is never required) and from there back to My Posted Jobs.
class PaymentStatusScreen extends StatefulWidget {
  const PaymentStatusScreen({super.key});

  @override
  State<PaymentStatusScreen> createState() => _PaymentStatusScreenState();
}

class _PaymentStatusScreenState extends State<PaymentStatusScreen> {
  PaymentStatusArgs? _args;
  bool _working = true;
  // Generating + sharing the PDF is async; block re-taps so the
  // share sheet cannot be opened twice.
  bool _invoiceBusy = false;
  String? _error;
  String? _transactionId;
  double? _paidAmount;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_args != null) return;
    final raw = ModalRoute.of(context)?.settings.arguments;
    if (raw is PaymentStatusArgs) {
      _args = raw;
      // The worker arrives after the money has already moved — showing a
      // receipt, not making a payment. Releasing again from here would be
      // both wrong and impossible (only the giver may release).
      if (raw.role == PaymentStatusRole.payee) {
        _transactionId = raw.transactionId;
        _paidAmount = raw.amount;
        _working = false;
      } else {
        _release();
      }
    }
  }

  Future<void> _release() async {
    final args = _args;
    if (args == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final res = await HomeApi.releaseJobPayment(
        args.jobId,
        methodLabel: args.methodLabel,
        isCod: args.isCod,
      );
      if (!mounted) return;
      final txn = (res['transactionId'] ?? '').toString();
      final payout = res['payoutAmount'];
      setState(() {
        _transactionId = txn.isEmpty ? null : txn;
        _paidAmount = payout is num ? payout.toDouble() : null;
        _working = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = e is ApiException
            ? e.message
            : e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _done() {
    final args = _args;
    if (args == null) return;
    // The worker's job is finished and paid — hand them the completed-job
    // summary. They don't rate from here.
    if (args.role == PaymentStatusRole.payee) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/job-completed',
        (_) => false,
        arguments: JobCompletedArgs(jobId: args.jobId),
      );
      return;
    }
    // Rating the worker is REQUIRED of the giver — mandatory:true removes
    // the skip link and the back route, so the only way out of the rating
    // screen is to give one. They land on My Posted Jobs afterwards.
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/rate-experience',
      (route) => route.settings.name == '/home',
      arguments: RateExperienceArgs(
        jobId: args.jobId,
        jobTitle: args.jobTitle,
        clientName: args.workerName,
        nextRoute: '/my-posted-jobs',
        mandatory: true,
      ),
    );
  }

  /// Builds a real PDF invoice and saves it to the device.
  ///
  /// Straight to Downloads rather than through the share sheet: the
  /// button says Download. On Android 10+ this goes through MediaStore,
  /// so it needs no storage permission; on iOS it lands in the app's
  /// folder in Files. If the OS refuses the write, the share sheet is
  /// offered as a fallback.
  Future<void> _downloadInvoice() async {
    final args = _args;
    if (args == null || _invoiceBusy) return;
    setState(() => _invoiceBusy = true);
    try {
      final auth = context.read<AuthState>();
      final me = (auth.user?['name'] ?? '').toString();
      // On the worker's receipt the payer is the client; on the giver's
      // own screen the payer is them.
      final payer = args.role == PaymentStatusRole.payee
          ? (args.clientName ?? 'Client')
          : (me.trim().isEmpty ? 'Job giver' : me);
      final invoice = InvoiceData(
        jobTitle: args.jobTitle,
        workerName: args.workerName,
        payerName: payer,
        amount: args.amount,
        methodLabel: args.methodLabel,
        transactionId: _transactionId ?? args.transactionId,
        jobId: args.jobId,
        paidAt: DateTime.now(),
        isCod: args.isCod,
      );
      final saved = await InvoicePdf.download(invoice);
      if (!mounted) return;
      if (saved != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Invoice saved to $saved')));
      } else {
        await InvoicePdf.share(invoice);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create the invoice: $e')),
      );
    } finally {
      if (mounted) setState(() => _invoiceBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // No back-out mid-release: the payment is either still moving or
    // already done, and neither state is safe to abandon halfway.
    return PopScope(
      canPop: !_working,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: _working
                ? const _Processing()
                : (_error != null ? _errorView() : _successView()),
          ),
        ),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 52, color: Color(0xFFDC2626)),
          const SizedBox(height: 14),
          const Text(
            'Payment failed',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101828),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              color: Color(0xFF6B7280),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: _release,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFFF6900), width: 1.4),
                foregroundColor: const Color(0xFFFF6900),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Try Again',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.maybePop(context),
            child: const Text(
              'Go back',
              style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _successView() {
    final args = _args!;
    final amount = _paidAmount ?? args.amount;
    return Column(
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
          'Payment Successful!',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF101828),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          // Same event, told from each side: the giver paid it out, the
          // worker received it.
          args.role == PaymentStatusRole.payee
              ? '₹${amount.toStringAsFixed(0)} has been received'
                    '${(args.clientName ?? '').isEmpty ? '' : ' from ${args.clientName}'}'
              : '₹${amount.toStringAsFixed(0)} has been paid to ${args.workerName}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13.5,
            color: Color(0xFF6B7280),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 22),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            children: [
              _ReceiptRow(label: 'Job', value: args.jobTitle),
              const SizedBox(height: 10),
              _ReceiptRow(label: 'Worker', value: args.workerName),
              const SizedBox(height: 10),
              _ReceiptRow(
                label: 'Amount',
                value: '₹${amount.toStringAsFixed(0)}',
                bold: true,
              ),
              const SizedBox(height: 10),
              // Cash has no reference to quote — say so plainly instead of
              // printing an empty "Transaction ID" row.
              if (args.isCod || _transactionId == null)
                _ReceiptRow(
                  label: 'Paid via',
                  value: args.isCod
                      ? 'Cash on Delivery (COD)'
                      : args.methodLabel,
                )
              else ...[
                _ReceiptRow(label: 'Paid via', value: args.methodLabel),
                const SizedBox(height: 10),
                _ReceiptRow(label: 'Transaction ID', value: _transactionId!),
              ],
            ],
          ),
        ),
        const Spacer(),
        // Cash changes hands in person — there's no processed payment to
        // invoice against, so the button only shows for online methods.
        if (!args.isCod) ...[
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _invoiceBusy ? null : _downloadInvoice,
              icon: _invoiceBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.download_outlined,
                      size: 18,
                      color: Color(0xFF374151),
                    ),
              label: const Text(
                'Download Invoice',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151),
                ),
              ),
              style: OutlinedButton.styleFrom(
                backgroundColor: const Color(0xFFF3F4F6),
                side: const BorderSide(color: Color(0xFFE5E7EB), width: 0.8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton(
            onPressed: _done,
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFFFF6900), width: 1.4),
              foregroundColor: const Color(0xFFFF6900),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Done',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

class _Processing extends StatelessWidget {
  const _Processing();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              strokeWidth: 3.4,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6900)),
            ),
          ),
          SizedBox(height: 22),
          Text(
            'Processing Payment...',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101828),
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Please wait',
            style: TextStyle(fontSize: 13.5, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _ReceiptRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

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
              color: bold ? const Color(0xFFFF6900) : const Color(0xFF101828),
            ),
          ),
        ),
      ],
    );
  }
}
