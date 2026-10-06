import 'dart:async';

import 'package:flutter/material.dart';

import 'payment_request_screen.dart';

/// Args for Navigator.pushNamed('/rating-thanks', ...). Optional —
/// the screen still works without them (falls back to /home).
class RatingThanksArgs {
  final String jobId;
  final num? amount;
  final String? jobTitle;
  final String? clientName;
  // Explicit destination for flows that don't end in Payment Request
  // (the giver rates after paying, so theirs ends on My Posted Jobs).
  final String? nextRoute;
  const RatingThanksArgs({
    required this.jobId,
    this.amount,
    this.jobTitle,
    this.clientName,
    this.nextRoute,
  });
}

/// Brief success confirmation shown after a worker submits their
/// /ratings POST on the Rate Experience screen. Auto-clears the
/// stack to /payment-request (when args carry a jobId) so the
/// worker can request payout right away; falls back to /home when
/// no jobId is supplied. Tap anywhere to skip the wait. Mirrors
/// the application_sent / job_started pattern.
class RatingThanksScreen extends StatefulWidget {
  const RatingThanksScreen({super.key});

  @override
  State<RatingThanksScreen> createState() => _RatingThanksScreenState();
}

class _RatingThanksScreenState extends State<RatingThanksScreen> {
  Timer? _autoClose;
  RatingThanksArgs? _args;

  @override
  void initState() {
    super.initState();
    _autoClose = Timer(const Duration(milliseconds: 2200), _advance);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_args != null) return;
    final raw = ModalRoute.of(context)?.settings.arguments;
    if (raw is RatingThanksArgs) _args = raw;
  }

  void _advance() {
    if (!mounted) return;
    final args = _args;
    if (args == null || args.jobId.isEmpty) {
      Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
      return;
    }
    final next = args.nextRoute;
    if (next != null && next.isNotEmpty) {
      Navigator.pushNamedAndRemoveUntil(context, next, (_) => false);
      return;
    }
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/payment-request',
      (_) => false,
      arguments: PaymentRequestArgs(
        jobId: args.jobId,
        amount: args.amount,
        jobTitle: args.jobTitle,
        clientName: args.clientName,
      ),
    );
  }

  @override
  void dispose() {
    _autoClose?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _autoClose?.cancel();
            _advance();
          },
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 112,
                    height: 112,
                    decoration: const BoxDecoration(
                      color: Color(0xFFDCFCE7),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle_outline,
                      size: 60,
                      color: Color(0xFF16A34A),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Thanks for Rating!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF101828),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Your feedback helps improve our community',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6B7280),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
