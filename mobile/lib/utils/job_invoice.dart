import 'package:flutter/material.dart';

import 'invoice_pdf.dart';
import 'job_status.dart';

/// Builds the invoice for a job from a My Jobs / My Posted Jobs list
/// entry, so the PDF can be downloaded any time after payment — not only
/// on the one-off payment screen, which is gone for good once closed.
///
/// Returns null until the job is paid, and when the payment summary the
/// backend attaches (`job.payment`) is missing: an invoice with no amount
/// or method on it is worse than no invoice.
///
/// [asWorker] flips who the counterparty is: the worker's list populates
/// `jobgiver`, the giver's populates `selectedJobtaker`, and the signed-in
/// user fills the other side from [myName].
InvoiceData? invoiceFromJob(
  Map<String, dynamic> job, {
  required bool asWorker,
  required String myName,
}) {
  if (!isPaymentSettled(job)) return null;
  final payment = job['payment'];
  if (payment is! Map) return null;

  final amount = (payment['amount'] as num?)?.toDouble() ?? 0;
  if (amount <= 0) return null;

  String nameOf(dynamic user, String fallback) {
    final n = user is Map ? (user['name'] ?? '').toString().trim() : '';
    return n.isEmpty ? fallback : n;
  }

  final me = myName.trim();
  final isCod = payment['isCod'] == true;

  // Invoice date is when the money moved. Falls back through the payment
  // record's own timestamps, then the job's settle stamp.
  final when =
      DateTime.tryParse(
        (payment['releasedAt'] ??
                job['paymentReleasedAt'] ??
                payment['paidAt'] ??
                '')
            .toString(),
      )?.toLocal() ??
      DateTime.now();

  return InvoiceData(
    jobTitle: (job['title'] ?? '').toString(),
    workerName: asWorker
        ? (me.isEmpty ? 'Worker' : me)
        : nameOf(job['selectedJobtaker'], 'Worker'),
    payerName: asWorker
        ? nameOf(job['jobgiver'], 'Client')
        : (me.isEmpty ? 'Job giver' : me),
    amount: amount,
    methodLabel: (payment['method'] ?? '').toString().trim().isNotEmpty
        ? payment['method'].toString()
        : (isCod ? 'Cash on Delivery' : 'Online'),
    transactionId: payment['transactionId']?.toString(),
    jobId: (job['_id'] ?? '').toString(),
    paidAt: when,
    isCod: isCod,
  );
}

/// "Download Invoice" button for a paid job's card.
///
/// Owns its own busy state so the spinner stays on the card that was
/// tapped, and a failure surfaces as a snackbar instead of an uncaught
/// error.
class DownloadInvoiceButton extends StatefulWidget {
  final InvoiceData invoice;
  const DownloadInvoiceButton({super.key, required this.invoice});

  @override
  State<DownloadInvoiceButton> createState() => _DownloadInvoiceButtonState();
}

class _DownloadInvoiceButtonState extends State<DownloadInvoiceButton> {
  bool _busy = false;

  Future<void> _download() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final saved = await InvoicePdf.download(widget.invoice);
      if (!mounted) return;
      if (saved != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Invoice saved to $saved')));
      } else {
        // The OS refused the write — out of space, or storage locked
        // down. Falling back to the share sheet is better than telling
        // the user their invoice is unavailable.
        await InvoicePdf.share(widget.invoice);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create the invoice: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 40,
      child: TextButton.icon(
        onPressed: _busy ? null : _download,
        icon: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF2563EB),
                ),
              )
            : const Icon(
                Icons.download_rounded,
                size: 18,
                color: Color(0xFF2563EB),
              ),
        label: Text(
          _busy ? 'Downloading...' : 'Download Invoice',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF2563EB),
          ),
        ),
        style: TextButton.styleFrom(
          backgroundColor: const Color(0xFFEFF6FF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
