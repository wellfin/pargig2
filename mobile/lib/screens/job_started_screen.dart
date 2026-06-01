import 'dart:async';

import 'package:flutter/material.dart';

import 'job_status_screen.dart';

/// Args for Navigator.pushNamed('/job-started', ...).
class JobStartedArgs {
  final String jobId;
  const JobStartedArgs({required this.jobId});
}

/// Brief success confirmation shown after the worker successfully
/// POSTs /jobs/:id/start/verify on the Enter OTP screen. Mirrors the
/// /application-sent pattern: auto-dismisses after ~2.2s and clears
/// the nav stack to /job-status so the worker lands on the live
/// tracking screen (now showing Mark as Completed since the job
/// just flipped to in_progress).
class JobStartedScreen extends StatefulWidget {
  const JobStartedScreen({super.key});

  @override
  State<JobStartedScreen> createState() => _JobStartedScreenState();
}

class _JobStartedScreenState extends State<JobStartedScreen> {
  Timer? _autoClose;
  JobStartedArgs? _args;

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
    if (raw is JobStartedArgs) _args = raw;
  }

  void _advance() {
    if (!mounted) return;
    final id = _args?.jobId;
    if (id == null || id.isEmpty) {
      Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
      return;
    }
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/job-status',
      (_) => false,
      arguments: JobStatusArgs(jobId: id),
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
                    'Job Started Successfully!',
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
                    'You can now begin working. Client has verified your '
                    'arrival.',
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
