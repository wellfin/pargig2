import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/home_api.dart';
import 'enter_otp_screen.dart';

/// Args passed via Navigator.pushNamed('/start-job-verification', ...)
class StartJobVerificationArgs {
  final String jobId;
  const StartJobVerificationArgs({required this.jobId});
}

/// Figma "Start Job Verification" — two stages:
///   1. Show job details + "How it works" + a Send OTP to Client
///      button. Tapping it POSTs /jobs/:id/reach, which makes the
///      backend issue a 6-digit OTP and push it to the jobgiver.
///   2. Once sent, the screen flips to an OTP-entry layout. The
///      worker asks the client for the code and enters it.
///      Verify & Start Job POSTs /jobs/:id/start/verify with the
///      code, which flips the job to in_progress.
class StartJobVerificationScreen extends StatefulWidget {
  const StartJobVerificationScreen({super.key});

  @override
  State<StartJobVerificationScreen> createState() =>
      _StartJobVerificationScreenState();
}

class _StartJobVerificationScreenState
    extends State<StartJobVerificationScreen> {
  String? _jobId;
  Map<String, dynamic>? _job;
  bool _loading = true;
  String? _error;

  bool _busy = false;
  String? _otpError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_jobId != null) return;
    final raw = ModalRoute.of(context)?.settings.arguments;
    if (raw is StartJobVerificationArgs) {
      _jobId = raw.jobId;
      _fetch();
    }
  }

  String? _clientName() {
    final giver = _job?['jobgiver'];
    if (giver is Map) {
      final n = (giver['name'] ?? '').toString().trim();
      if (n.isNotEmpty) return n;
    }
    return null;
  }

  Future<void> _fetch() async {
    final id = _jobId;
    if (id == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final job = await HomeApi.jobById(id);
      if (!mounted) return;
      setState(() {
        _job = job;
        _loading = false;
      });
      // If the backend already issued the OTP (status=reached), skip
      // Stage 1 entirely and jump straight to the OTP entry module so
      // the worker doesn't re-issue a fresh code on refresh / resume.
      final status = (job['status'] ?? '').toString();
      if (status == 'reached') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.pushReplacementNamed(
            context,
            '/enter-otp',
            arguments: EnterOtpArgs(jobId: id, clientName: _clientName()),
          );
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _sendOtp() async {
    final id = _jobId;
    if (id == null || _busy) return;
    setState(() {
      _busy = true;
      _otpError = null;
    });
    try {
      await ApiClient.post('/jobs/$id/reach', {});
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        '/enter-otp',
        arguments: EnterOtpArgs(jobId: id, clientName: _clientName()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _otpError = e is ApiException ? e.message : e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _Header(onBack: () => Navigator.maybePop(context)),
          Expanded(child: _body()),
          if (_job != null && !_loading) _bottomBar(),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF408EE0)),
        ),
      );
    }
    if (_error != null || _job == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 40, color: Color(0xFFDC2626)),
              const SizedBox(height: 10),
              Text(
                _error ?? 'Job not found',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton(onPressed: _fetch, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        const _VerificationInfoCard(),
        const SizedBox(height: 14),
        _JobDetailsCard(job: _job!),
        const SizedBox(height: 14),
        const _HowItWorksCard(),
        if (_otpError != null) ...[
          const SizedBox(height: 12),
          Text(
            _otpError!,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFFDC2626),
            ),
          ),
        ],
      ],
    );
  }

  Widget _bottomBar() {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Color(0xFFE5E7EB), width: 0.8),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: SizedBox(
          height: 52,
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _busy ? null : _sendOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF408EE0),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'Send OTP to Client',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
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
        8, MediaQuery.of(context).padding.top + 8, 16, 12,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: Material(
              color: const Color(0x33FFFFFF),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onBack,
                child: const Icon(Icons.arrow_back,
                    size: 18, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'Start Job Verification',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _VerificationInfoCard extends StatelessWidget {
  const _VerificationInfoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDBEAFE), width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.shield_outlined,
              size: 20, color: Color(0xFF408EE0)),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Client Verification Required',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF408EE0),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'An OTP will be sent to the client to verify that you '
                  'have arrived at the location',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF1E3A8A),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JobDetailsCard extends StatelessWidget {
  final Map<String, dynamic> job;
  const _JobDetailsCard({required this.job});

  String _now() {
    final dt = DateTime.now();
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final title = (job['title'] ?? 'Job').toString();
    final giver = job['jobgiver'] is Map ? job['jobgiver'] as Map : const {};
    final clientName = (giver['name'] ?? 'Client').toString();
    final loc = job['location'] is Map ? job['location'] as Map : const {};
    final locText = [loc['address'], loc['city']]
        .map((s) => (s ?? '').toString())
        .where((s) => s.trim().isNotEmpty)
        .join(', ');

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
          const Text(
            'Job Details',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101828),
            ),
          ),
          const SizedBox(height: 12),
          _row(
            iconBg: const Color(0xFFDBEAFE),
            iconColor: const Color(0xFF408EE0),
            icon: Icons.location_on_outlined,
            label: 'Job',
            value: title,
          ),
          const SizedBox(height: 10),
          _row(
            iconBg: const Color(0xFFF3E8FF),
            iconColor: const Color(0xFF7C3AED),
            icon: Icons.person_outline,
            label: 'Client',
            value: clientName,
          ),
          const SizedBox(height: 10),
          _row(
            iconBg: const Color(0xFFDCFCE7),
            iconColor: const Color(0xFF16A34A),
            icon: Icons.place_outlined,
            label: 'Location',
            value: locText.isEmpty ? '—' : locText,
          ),
          const SizedBox(height: 10),
          _row(
            iconBg: const Color(0xFFFFEDD4),
            iconColor: const Color(0xFFFF6900),
            icon: Icons.access_time,
            label: 'Time',
            value: _now(),
          ),
        ],
      ),
    );
  }

  Widget _row({
    required Color iconBg,
    required Color iconColor,
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 16, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF6B7280),
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF101828),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HowItWorksCard extends StatelessWidget {
  const _HowItWorksCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD9B3), width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Row(
            children: [
              Icon(Icons.description_outlined,
                  size: 16, color: Color(0xFF7E2A0C)),
              SizedBox(width: 6),
              Text(
                'How it works',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF7E2A0C),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          _Step(n: 1, text: 'Click "Send OTP to Client" below'),
          _Step(n: 2, text: 'Client will receive a 6-digit OTP on their device'),
          _Step(n: 3, text: 'Ask the client to tell you the OTP'),
          _Step(n: 4, text: 'Enter the OTP and start working'),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String text;
  const _Step({required this.n, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            child: Text(
              '$n.',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFFFF6900),
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF7E2A0C),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

