import 'dart:async';

import 'package:flutter/material.dart';

/// Args for `Navigator.pushNamed('/request-sent', arguments: ...)`.
class RequestSentArgs {
  final num customAmount;
  const RequestSentArgs({required this.customAmount});
}

/// Confirmation shown after the job-taker submits a custom-amount
/// request via /request-custom-amount. Auto-dismisses after ~1.8s
/// (or instant on tap) and clears the nav stack back to /home.
class RequestSentScreen extends StatefulWidget {
  const RequestSentScreen({super.key});

  @override
  State<RequestSentScreen> createState() => _RequestSentScreenState();
}

class _RequestSentScreenState extends State<RequestSentScreen> {
  Timer? _autoClose;
  RequestSentArgs? _args;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_args != null) return;
    final raw = ModalRoute.of(context)?.settings.arguments;
    if (raw is RequestSentArgs) _args = raw;
    _autoClose ??= Timer(const Duration(milliseconds: 1800), _goHome);
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
  }

  @override
  void dispose() {
    _autoClose?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amount = _args?.customAmount;
    final amountText = amount != null ? '₹${amount.toInt()}' : 'amount';
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _autoClose?.cancel();
            _goHome();
          },
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: const BoxDecoration(
                      color: Color(0xFFDCFCE7),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle_outline,
                      size: 56,
                      color: Color(0xFF16A34A),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Request Sent!',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF101828),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your custom amount of $amountText has been sent to the '
                    'client for review.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
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
