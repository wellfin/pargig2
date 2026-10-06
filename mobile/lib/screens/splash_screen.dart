import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../services/server_discovery.dart';
import '../state/auth_state.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const double _designW = 375;
  static const double _designH = 812;
  static const Duration _minDisplay = Duration(seconds: 2);

  bool _minElapsed = false;
  bool _navigated = false;
  bool _discovering = true;
  bool _serverFound = false;
  String? _statusMessage = 'Connecting to server…';

  @override
  void initState() {
    super.initState();
    Future.delayed(_minDisplay, () {
      if (!mounted) return;
      setState(() => _minElapsed = true);
      _maybeNavigate();
    });
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // Kick off server discovery in the background but DON'T block navigation
    // on it. The app should always reach the UI after the splash, whether
    // the server is reachable or not — connectivity errors are surfaced at
    // action time (login, post job, etc.), not as a hard wall on launch.
    ServerDiscovery.discover()
        .then((ok) {
          if (!mounted) return;
          setState(() {
            _discovering = false;
            _serverFound = ok;
            _statusMessage = null;
          });
        })
        .catchError((_) {
          if (!mounted) return;
          setState(() {
            _discovering = false;
            _statusMessage = null;
          });
        });

    // Always try to restore the saved session — works offline if the token
    // is still cached locally. If the network call fails, AuthState.user
    // just stays null and the user lands on /login.
    try {
      await context.read<AuthState>().tryRestore();
    } catch (_) {}
    if (!mounted) return;
    _maybeNavigate();
  }

  Future<void> _retryDiscovery() async {
    setState(() {
      _discovering = true;
      _statusMessage = null;
    });
    await _bootstrap();
  }

  Future<void> _maybeNavigate() async {
    // Navigation no longer waits on the server probe. As soon as the
    // minimum splash time has elapsed, jump to /login (or wherever
    // resumeRoute() points if the saved session is valid).
    if (_navigated || !_minElapsed) return;
    final auth = context.read<AuthState>();
    if (auth.restoring) return;
    _navigated = true;
    if (!mounted) return;
    // Registered (OTP-verified, token cached) → resume where they left
    // off. resumeRoute() walks the setup checklist (terms → name+photo →
    // address → skills for takers) and returns the first unfinished step,
    // or /home once everything required is done. So a user who closed the
    // app mid-profile-setup reopens straight back on that step instead of
    // slipping into /home with a half-filled profile.
    // Not registered (no token) → /onboarding. The user picks Post Job
    // or Find Job there; tapping Get Started stashes the choice on
    // AuthState.pendingRole and pushes /login → /otp → /terms →
    // /profile-setup → wizard → /role-chooser → /home.
    final next = auth.isAuthed ? auth.resumeRoute() : '/onboarding';
    Navigator.pushReplacementNamed(context, next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final sx = constraints.maxWidth / _designW;
              final sy = constraints.maxHeight / _designH;
              return Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned(
                    left: 266 * sx,
                    top: -4 * sy,
                    width: 160 * sx,
                    height: 264.166 * sy,
                    child: Opacity(
                      opacity: 0.10,
                      child: Image.asset(
                        'assets/splash/tool_top_right.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  Positioned(
                    left: -56 * sx,
                    top: -1 * sy,
                    width: 160 * sx,
                    height: 165.818 * sy,
                    child: Transform.rotate(
                      angle: 3.14159265,
                      child: Opacity(
                        opacity: 0.10,
                        child: Image.asset(
                          'assets/splash/tool_top_left.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: -96 * sx,
                    top: 605 * sy,
                    width: 246.999 * sx,
                    height: 229.798 * sy,
                    child: Transform.rotate(
                      angle: 159.59 * 3.14159265 / 180,
                      child: Opacity(
                        opacity: 0.10,
                        child: Image.asset(
                          'assets/splash/tool_bottom_left.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 247 * sx,
                    top: 658 * sy,
                    width: 200 * sx,
                    height: 154.348 * sy,
                    child: Opacity(
                      opacity: 0.10,
                      child: Image.asset(
                        'assets/splash/tool_bottom_right.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  Center(
                    child: SizedBox(
                      width: 155 * sx,
                      height: 163 * sy,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(31 * sx),
                        child: Image.asset(
                          'assets/splash/logo.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: SafeArea(
              top: false,
              child: _BottomStatus(
                discovering: _discovering,
                serverFound: _serverFound,
                message: _statusMessage,
                onRetry: _retryDiscovery,
                onConfigure: _discovering
                    ? null
                    : () => Navigator.pushNamed(context, '/server'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomStatus extends StatelessWidget {
  final bool discovering;
  final bool serverFound;
  final String? message;
  final VoidCallback onRetry;
  final VoidCallback? onConfigure;

  const _BottomStatus({
    required this.discovering,
    required this.serverFound,
    required this.message,
    required this.onRetry,
    required this.onConfigure,
  });

  @override
  Widget build(BuildContext context) {
    if (serverFound && !discovering) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (discovering) ...[
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6900)),
              ),
            ),
            const SizedBox(height: 10),
          ] else
            const Icon(Icons.cloud_off, color: Color(0xFF7E2A0C), size: 24),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: discovering
                    ? const Color(0xFF64748B)
                    : const Color(0xFF7E2A0C),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (!discovering) ...[
            const SizedBox(height: 4),
            Text(
              'Server: ${AppConfig.apiBase}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                  onPressed: onRetry,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF6900),
                    side: const BorderSide(color: Color(0xFFFF6900)),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  label: const Text('Configure'),
                  onPressed: onConfigure,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
