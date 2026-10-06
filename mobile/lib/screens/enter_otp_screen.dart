import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import 'job_started_screen.dart';

/// Args for Navigator.pushNamed('/enter-otp', ...).
class EnterOtpArgs {
  final String jobId;
  final String? clientName;
  const EnterOtpArgs({required this.jobId, this.clientName});
}

/// Stage 2 of Start Job Verification. The worker has already POSTed
/// /jobs/:id/reach, the backend issued a 6-digit code, pushed it to
/// the jobgiver, and now the worker collects that code from the
/// client and verifies it here.
///
/// Layout matches the "OTP Sent Successfully" Figma:
///   - green success banner (with the client's real name)
///   - 6 segmented digit boxes with auto-advance + backspace-back
///   - 30s resend countdown → tappable Resend OTP at 0
///   - orange Important card
///   - Verify OTP & Start Job button, disabled until 6 digits typed
class EnterOtpScreen extends StatefulWidget {
  const EnterOtpScreen({super.key});

  @override
  State<EnterOtpScreen> createState() => _EnterOtpScreenState();
}

class _EnterOtpScreenState extends State<EnterOtpScreen> {
  static const int _otpLength = 6;
  static const int _resendSeconds = 30;

  EnterOtpArgs? _args;
  late final List<TextEditingController> _ctrls;
  late final List<FocusNode> _focuses;

  Timer? _ticker;
  int _seconds = _resendSeconds;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(_otpLength, (_) => TextEditingController());
    _focuses = List.generate(_otpLength, (_) => FocusNode());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focuses.first.requestFocus();
    });
    _startTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_args != null) return;
    final raw = ModalRoute.of(context)?.settings.arguments;
    if (raw is EnterOtpArgs) {
      setState(() => _args = raw);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    for (final c in _ctrls) {
      c.dispose();
    }
    for (final f in _focuses) {
      f.dispose();
    }
    super.dispose();
  }

  String get _code => _ctrls.map((c) => c.text).join();

  void _startTimer() {
    _ticker?.cancel();
    setState(() => _seconds = _resendSeconds);
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_seconds <= 1) {
        t.cancel();
        setState(() => _seconds = 0);
      } else {
        setState(() => _seconds--);
      }
    });
  }

  void _onDigitChanged(int i, String v) {
    if (_error != null) setState(() => _error = null);
    final digits = v.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 1) {
      // Pasted / autofilled multi-digit value (e.g. the whole 6-digit PIN
      // copied from the client). Spread it across the boxes starting at the
      // one being edited, so pasting the full code into the first box fills
      // all six instead of dropping everything but the first digit.
      for (int j = i; j < _otpLength; j++) {
        final srcIndex = j - i;
        _ctrls[j].text = srcIndex < digits.length ? digits[srcIndex] : '';
      }
      final filledUpTo = (i + digits.length).clamp(0, _otpLength);
      final focusIndex = filledUpTo >= _otpLength ? _otpLength - 1 : filledUpTo;
      _focuses[focusIndex].requestFocus();
      setState(() {});
      return;
    }
    if (v.isNotEmpty && i < _otpLength - 1) {
      _focuses[i + 1].requestFocus();
    }
    setState(() {});
  }

  KeyEventResult _onKeyEvent(int i, FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        _ctrls[i].text.isEmpty &&
        i > 0) {
      _focuses[i - 1].requestFocus();
      _ctrls[i - 1].clear();
      setState(() {});
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _resend() async {
    final id = _args?.jobId;
    if (id == null || _seconds > 0 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.post('/jobs/$id/reach', {});
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('PIN resent to client')));
      _startTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : e.toString();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final id = _args?.jobId;
    if (id == null || _busy) return;
    final code = _code;
    if (code.length != _otpLength) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.post('/jobs/$id/start/verify', {'otp': code});
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/job-started',
        (_) => false,
        arguments: JobStartedArgs(jobId: id),
      );
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
    final client = (_args?.clientName ?? '').trim();
    final clientLabel = client.isEmpty ? 'the client' : client;
    final clientPossessive = client.isEmpty ? "the client's" : "$client's";
    final canVerify = !_busy && _code.length == _otpLength;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _Header(onBack: () => Navigator.maybePop(context)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              children: [
                _OtpSentBanner(clientPossessive: clientPossessive),
                const SizedBox(height: 22),
                const Text(
                  'Enter 6-Digit PIN',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF101828),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Ask $clientLabel to tell you the PIN',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _otpLength,
                    (i) => Padding(
                      padding: EdgeInsets.only(
                        right: i == _otpLength - 1 ? 0 : 8,
                      ),
                      child: _OtpBox(
                        controller: _ctrls[i],
                        focusNode: _focuses[i],
                        isError: _error != null,
                        onChanged: (v) => _onDigitChanged(i, v),
                        onKeyEvent: (n, e) => _onKeyEvent(i, n, e),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: _seconds > 0
                      ? Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(
                                text: 'Resend PIN in ',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                              TextSpan(
                                text: '${_seconds}s',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF408EE0),
                                ),
                              ),
                            ],
                          ),
                        )
                      : TextButton(
                          onPressed: _busy ? null : _resend,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 28),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Resend PIN',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF408EE0),
                            ),
                          ),
                        ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                const _ImportantNoticeCard(),
              ],
            ),
          ),
          _bottomBar(canVerify),
        ],
      ),
    );
  }

  Widget _bottomBar(bool canVerify) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE5E7EB), width: 0.8)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: SizedBox(
          height: 52,
          width: double.infinity,
          child: ElevatedButton(
            onPressed: canVerify ? _verify : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF408EE0),
              disabledBackgroundColor: const Color(0xFFCBD5E1),
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white,
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
                    'Verify PIN & Start Job',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
        8,
        MediaQuery.of(context).padding.top + 8,
        16,
        12,
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
                child: const Icon(
                  Icons.arrow_back,
                  size: 18,
                  color: Colors.white,
                ),
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

class _OtpSentBanner extends StatelessWidget {
  final String clientPossessive;
  const _OtpSentBanner({required this.clientPossessive});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBBF7D0), width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, size: 20, color: Color(0xFF16A34A)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PIN Sent Successfully!',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF166534),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'PIN has been sent to $clientPossessive device',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF166534),
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

class _ImportantNoticeCard extends StatelessWidget {
  const _ImportantNoticeCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD9B3), width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.error_outline, size: 18, color: Color(0xFFFF6900)),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Important',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF7E2A0C),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Make sure the client is present and ready to provide '
                  'the PIN before starting',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF7E2A0C),
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

class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isError;
  final ValueChanged<String> onChanged;
  final FocusOnKeyEventCallback onKeyEvent;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.isError,
    required this.onChanged,
    required this.onKeyEvent,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = controller.text.isNotEmpty;
    final hasFocus = focusNode.hasFocus;
    final Color borderColor = isError
        ? const Color(0xFFDC2626)
        : (hasValue || hasFocus)
        ? const Color(0xFF408EE0)
        : const Color(0xFFD1D5DB);
    return Focus(
      onKeyEvent: onKeyEvent,
      child: SizedBox(
        width: 44,
        height: 50,
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          // No maxLength — it would truncate a pasted multi-digit PIN to a
          // single character before onChanged runs, so the paste-spread in
          // _onDigitChanged never sees the full code. Length is enforced by
          // the auto-advance + spread logic instead.
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF101828),
          ),
          decoration: InputDecoration(
            counterText: '',
            isCollapsed: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: borderColor, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: borderColor, width: 1.4),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: borderColor, width: 1),
            ),
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
