import 'package:flutter/material.dart';

/// Job Amount / Tip Amount / Total Amount, itemised.
///
/// One widget shared by Job Details and the completed-job screen, so the
/// same job shows the same three figures wherever it is opened. Two
/// copies would eventually disagree, and money that disagrees with
/// itself across screens is money nobody trusts.
///
/// The tip row is hidden when there is no tip: three lines reading 5000,
/// 0 and 5000 explain nothing, and a zero invites the reader to wonder
/// what they missed.
class AmountBreakup extends StatelessWidget {
  final num jobAmount;
  final num tip;
  final num total;

  /// Shown above the rows. Null hides it, for screens that already have
  /// a heading of their own directly above.
  final String? title;

  const AmountBreakup({
    super.key,
    required this.jobAmount,
    required this.tip,
    required this.total,
    this.title = 'Payment Breakup',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF101828),
              ),
            ),
            const SizedBox(height: 10),
          ],
          _BreakupRow(label: 'Job Amount', value: jobAmount),
          if (tip > 0) ...[
            const SizedBox(height: 6),
            _BreakupRow(
              label: 'Tip Amount',
              value: tip,
              valueColor: const Color(0xFF16A34A),
            ),
          ],
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 10),
          _BreakupRow(label: 'Total Amount', value: total, bold: true),
        ],
      ),
    );
  }
}

class _BreakupRow extends StatelessWidget {
  final String label;
  final num value;
  final bool bold;
  final Color? valueColor;

  const _BreakupRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: bold ? 14.5 : 13.5,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: bold ? const Color(0xFF101828) : const Color(0xFF4A5565),
            ),
          ),
        ),
        Text(
          '₹${value.toInt()}',
          style: TextStyle(
            fontSize: bold ? 16 : 14,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            color:
                valueColor ??
                (bold ? const Color(0xFF101828) : const Color(0xFF364153)),
          ),
        ),
      ],
    );
  }
}
