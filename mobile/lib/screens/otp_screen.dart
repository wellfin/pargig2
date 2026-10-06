import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/auth_state.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  static const int _otpLength = 4;
  // Long enough that an SMS has a chance to arrive before someone asks
  // for another, and it doubles as the only throttle on the endpoint —
  // /auth/otp/request has no server-side rate limit.
  static const int _resendSeconds = 30;

  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  bool _loading = false;
  bool _resending = false;
  String? _error;

  Timer? _timer;
  int _seconds = _resendSeconds;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(_otpLength, (_) => TextEditingController());
    _focusNodes = List.generate(_otpLength, (_) => FocusNode());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNodes.first.requestFocus();
    });
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _seconds = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _seconds--);
      if (_seconds <= 0) t.cancel();
    });
  }

  /// Asks the backend for a fresh code. The previous one stops working —
  /// requestOtp overwrites user.otp server-side — so the countdown
  /// restarting is also a hint that any earlier SMS is now stale.
  Future<void> _resend() async {
    if (_seconds > 0 || _resending || _loading) return;
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthState>();
      final mobile = auth.pendingMobile;
      if (mobile == null || mobile.isEmpty) {
        throw 'Go back and enter your mobile number again';
      }
      final dev = await auth.requestOtp(mobile);
      if (!mounted) return;
      // Clear the boxes: the code they may have half-typed is dead now.
      for (final c in _controllers) {
        c.clear();
      }
      _focusNodes.first.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(dev == null ? 'Code sent again' : 'Dev OTP: $dev'),
          backgroundColor: Colors.black87,
        ),
      );
      _startTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _code => _controllers.map((c) => c.text).join();

  void _onDigitChanged(int index, String value) {
    if (_error != null) setState(() => _error = null);
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 1) {
      // Pasted / auto-filled multi-char value (e.g. the whole OTP): spread
      // it across the boxes starting at the one being edited, so pasting
      // the full code into the first box fills all of them.
      for (int i = index; i < _otpLength; i++) {
        final srcIndex = i - index;
        _controllers[i].text = srcIndex < digits.length ? digits[srcIndex] : '';
      }
      final filledUpTo = (index + digits.length).clamp(0, _otpLength);
      final focusIndex = filledUpTo >= _otpLength ? _otpLength - 1 : filledUpTo;
      _focusNodes[focusIndex].requestFocus();
      setState(() {});
      if (_code.length == _otpLength) _submit();
      return;
    }
    if (value.isNotEmpty && index < _otpLength - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    setState(() {});
    if (_code.length == _otpLength) _submit();
  }

  KeyEventResult _onKeyEvent(int index, FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].clear();
      setState(() {});
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _submit() async {
    if (_loading) return;
    final code = _code;
    if (code.length != _otpLength) {
      setState(() => _error = 'Enter the $_otpLength-digit code');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthState>();
      await auth.verifyOtp(code);
      if (!mounted) return;
      // Resume at the first incomplete setup step. Returning users with
      // a fully populated profile go straight to /home.
      //
      // IMPORTANT: pushNamedAndRemoveUntil (not pushReplacementNamed) —
      // it wipes the login / OTP screens from the nav stack so a new
      // user pressing back during the wizard can NOT land back on the
      // OTP number-entry view. Only an explicit logout from Profile
      // takes a user back to /login.
      Navigator.pushNamedAndRemoveUntil(
        context,
        auth.resumeRoute(),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      _focusNodes.last.requestFocus();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mobile = context.watch<AuthState>().pendingMobile ?? '';
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Center(
                child: SizedBox(
                  width: 89,
                  height: 94,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(21),
                    child: Image.asset(
                      'assets/splash/logo.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'POST A JOB/FIND A JOB - YOU DECIDE THE PRICE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF101828),
                  height: 1.86,
                ),
              ),
              const SizedBox(height: 28),
              const Center(
                child: Text(
                  'Enter verification code',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF161616),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  'We have sent you a 4 digit verification code on',
                  style: TextStyle(fontSize: 12, color: Color(0xFF757575)),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  '+91 ${mobile.isEmpty ? '' : mobile}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF505050),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _otpLength,
                  (i) => Padding(
                    padding: EdgeInsets.only(
                      right: i == _otpLength - 1 ? 0 : 16,
                    ),
                    child: _OtpBox(
                      controller: _controllers[i],
                      focusNode: _focusNodes[i],
                      isError: _error != null,
                      onChanged: (v) => _onDigitChanged(i, v),
                      onKeyEvent: (n, e) => _onKeyEvent(i, n, e),
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFFDC2626),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Center(
                child: _resending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : _seconds > 0
                    // Counting down: plain text, not a disabled button.
                    // A greyed button invites tapping and does nothing.
                    ? Text(
                        'Resend code in ${_seconds}s',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF757575),
                        ),
                      )
                    : GestureDetector(
                        onTap: _resend,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Text(
                            'Resend OTP',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFFF6900),
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 24),
              _LoginSignUpButton(
                loading: _loading,
                onTap: _loading ? null : _submit,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
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
        ? const Color(0xFF0F172A)
        : const Color(0xFF79747E);
    return Focus(
      onKeyEvent: onKeyEvent,
      child: SizedBox(
        width: 50,
        height: 50,
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          // No maxLength — it would truncate a pasted OTP to one digit
          // before onChanged runs, defeating the paste-spread below.
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF161616),
          ),
          decoration: InputDecoration(
            counterText: '',
            isCollapsed: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: borderColor, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: borderColor, width: 1.4),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: borderColor, width: 1),
            ),
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _LoginSignUpButton extends StatelessWidget {
  final bool loading;
  final VoidCallback? onTap;
  const _LoginSignUpButton({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 55,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFF6900), width: 1),
          ),
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFFFF6900),
                    ),
                  ),
                )
              : const Text(
                  'Login/Sign up',
                  style: TextStyle(
                    color: Color(0xFFFF6900),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.32,
                  ),
                ),
        ),
      ),
    );
  }
}
