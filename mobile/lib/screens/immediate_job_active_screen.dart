import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import 'job_status_screen.dart';

/// Args for Navigator.pushNamed('/immediate-job-active', arguments:)
class ImmediateJobArgs {
  final String jobId;
  final String jobTitle;
  final String? locationText;
  final DateTime? scheduledAt;
  final bool isUrgent;
  // How long (in seconds) the worker has to arrive. Default 15 min.
  final int reachWithinSeconds;

  const ImmediateJobArgs({
    required this.jobId,
    required this.jobTitle,
    this.locationText,
    this.scheduledAt,
    this.isUrgent = false,
    this.reachWithinSeconds = 15 * 60,
  });
}

/// "Reach within MM:SS" countdown screen shown right after the user
/// taps "I Understand" on the Important Notice modal. Runs a live
/// 15-minute timer, offers Start Navigation + Continue to My Jobs,
/// and shows the auto-cancel warning at the bottom.
class ImmediateJobActiveScreen extends StatefulWidget {
  const ImmediateJobActiveScreen({super.key});

  @override
  State<ImmediateJobActiveScreen> createState() =>
      _ImmediateJobActiveScreenState();
}

class _ImmediateJobActiveScreenState extends State<ImmediateJobActiveScreen> {
  ImmediateJobArgs? _args;
  Timer? _ticker;
  int _remaining = 0;
  bool _navBusy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_args != null) return;
    final raw = ModalRoute.of(context)?.settings.arguments;
    if (raw is ImmediateJobArgs) {
      _args = raw;
      _remaining = raw.reachWithinSeconds;
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          if (_remaining > 0) _remaining--;
        });
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _formatRemaining() {
    final h = _remaining ~/ 3600;
    final m = (_remaining % 3600) ~/ 60;
    final s = _remaining % 60;
    if (h > 0) {
      // Scheduled jobs that are hours away: HH:MM:SS
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    // Immediate-style display: MM:SS
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _remainingUnitLabel() {
    if (_remaining <= 0) return 'arrival window closed';
    if (_remaining >= 3600) return 'hr remaining';
    return 'min remaining';
  }

  String _formatTime(DateTime dt) {
    final h12 = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final mm = dt.minute.toString().padLeft(2, '0');
    final ap = dt.hour < 12 ? 'AM' : 'PM';
    return '$h12:$mm $ap';
  }

  Future<void> _startNavigation() async {
    final id = _args?.jobId;
    if (id == null || id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't open navigation — no job id")),
      );
      return;
    }
    if (_navBusy) return;
    setState(() => _navBusy = true);
    // Generate the 6-digit start-verification PIN and push it to the job
    // giver the moment the worker heads to the location. POST /reach makes
    // the backend issue the code, store it on the job (job.startOtp), and
    // notify the jobgiver. The worker later asks the client for the code
    // and enters it on the Start Job Verification screen to begin the job.
    try {
      await ApiClient.post('/jobs/$id/reach', {});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verification PIN sent to the job giver'),
          duration: Duration(milliseconds: 1200),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      // Don't block navigation — the worker can re-send the PIN from the
      // Start Job Verification screen if this failed.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException
                ? e.message
                : "Couldn't send the verification PIN. Try again.",
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _navBusy = false);
    }
    if (!mounted) return;
    // Push the Job Status tracking screen — same module reached by the My
    // Jobs → Start Job tap. Shows the live timeline, client contact card,
    // map placeholder, and the Arrived button.
    Navigator.pushNamed(
      context,
      '/job-status',
      arguments: JobStatusArgs(jobId: id),
    );
  }

  void _continueToMyJobs() {
    // Drop the worker on the Job Status module for this job — the screen
    // with the live timeline and the Arrived button (which issues the PIN
    // and opens OTP entry). If no jobId is available we fall back to
    // clearing the stack to /home.
    final id = _args?.jobId;
    if (id == null || id.isEmpty) {
      Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
      return;
    }
    Navigator.pushNamed(
      context,
      '/job-status',
      arguments: JobStatusArgs(jobId: id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final args = _args;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: args == null
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    "Couldn't load the job — go back and try again.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: () => Navigator.maybePop(context),
                      icon: const Icon(
                        Icons.arrow_back,
                        size: 22,
                        color: Color(0xFF101828),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      width: 88,
                      height: 88,
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
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Job Accepted!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF101828),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "You've successfully accepted this job",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(height: 18),
                  _jobSummary(args),
                  const SizedBox(height: 14),
                  _countdownCard(),
                  const SizedBox(height: 18),
                  _navButton(),
                  const SizedBox(height: 10),
                  _myJobsButton(),
                  const SizedBox(height: 16),
                  _warningCard(),
                ],
              ),
      ),
    );
  }

  Widget _jobSummary(ImmediateJobArgs args) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            args.isUrgent ? 'Urgent: ${args.jobTitle}' : args.jobTitle,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101828),
              height: 1.3,
            ),
          ),
          if (args.locationText != null && args.locationText!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('📍 ', style: TextStyle(fontSize: 14)),
                Expanded(
                  child: Text(
                    args.locationText!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF4A5565),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (args.scheduledAt != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.access_time,
                  size: 14,
                  color: Color(0xFF6B7280),
                ),
                const SizedBox(width: 6),
                Text(
                  _formatTime(args.scheduledAt!),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF4A5565),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _countdownCard() {
    final expired = _remaining <= 0;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: expired ? const Color(0xFFE7000B) : const Color(0xFFFFB070),
          width: 1.4,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        children: [
          Text(
            expired ? 'Time Up' : 'Reach within',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: expired
                  ? const Color(0xFFE7000B)
                  : const Color(0xFFFF6900),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.access_time,
                size: 28,
                color: expired
                    ? const Color(0xFFE7000B)
                    : const Color(0xFFFF6900),
              ),
              const SizedBox(width: 8),
              Text(
                _formatRemaining(),
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: expired
                      ? const Color(0xFFE7000B)
                      : const Color(0xFFFF6900),
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _remainingUnitLabel(),
            style: TextStyle(
              fontSize: 12,
              color: expired
                  ? const Color(0xFFE7000B)
                  : const Color(0xFFCA3500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navButton() {
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        onPressed: _navBusy ? null : _startNavigation,
        icon: _navBusy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6900)),
                ),
              )
            : const Icon(
                Icons.navigation_outlined,
                size: 18,
                color: Color(0xFFFF6900),
              ),
        label: const Text(
          'Start Navigation',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFFFF6900),
          ),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFFF6900), width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _myJobsButton() {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: _continueToMyJobs,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFFF6900), width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Text(
          'Continue to My Jobs',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFFFF6900),
          ),
        ),
      ),
    );
  }

  Widget _warningCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFEF9C2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFCE38A), width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: Color(0xFFCA8A04)),
          const SizedBox(width: 10),
          Expanded(
            child: const Text(
              'If you fail to arrive on time, the job will be automatically '
              'cancelled and reassigned.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF713F12),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
