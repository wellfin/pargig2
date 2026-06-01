import 'dart:async';

import 'package:flutter/material.dart';

/// Brief success confirmation shown after a job-taker submits their
/// application via /apply-for-job. Auto-dismisses after ~1.8s and pops
/// back to /job-details (with `true` so the details screen refreshes
/// and flips the bottom button to "Already Applied").
class ApplicationSentScreen extends StatefulWidget {
  const ApplicationSentScreen({super.key});

  @override
  State<ApplicationSentScreen> createState() => _ApplicationSentScreenState();
}

class _ApplicationSentScreenState extends State<ApplicationSentScreen> {
  Timer? _autoClose;

  @override
  void initState() {
    super.initState();
    _autoClose = Timer(const Duration(milliseconds: 1800), _goHome);
  }

  void _goHome() {
    if (!mounted) return;
    // Clear the whole nav stack and land on Home. The application is
    // submitted — there's no reason to keep apply / job-details below.
    Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
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
        // Tap anywhere to dismiss early — feels snappier than waiting
        // out the timer when the user has already read the message.
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
                    'Application Sent!',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF101828),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'The job poster will review your application',
                    textAlign: TextAlign.center,
                    style: TextStyle(
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
