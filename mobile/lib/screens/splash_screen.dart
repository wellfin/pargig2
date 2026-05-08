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
    final ok = await ServerDiscovery.discover();
    if (!mounted) return;
    setState(() {
      _discovering = false;
      _serverFound = ok;
      _statusMessage = ok ? null : "Can't reach Pargig server";
    });
    if (ok) {
      // Restore the saved session, if any, so returning users skip the
      // login flow and land back where they left off (PhonePe-style:
      // re-auth is only needed after explicit logout or uninstall).
      try {
        await context.read<AuthState>().tryRestore();
      } catch (_) {}
      if (!mounted) return;
      _maybeNavigate();
    }
  }

  Future<void> _retryDiscovery() async {
    setState(() {
      _discovering = true;
      _serverFound = false;
      _statusMessage = 'Connecting to server…';
    });
    await _bootstrap();
  }

  Future<void> _maybeNavigate() async {
    if (_navigated || !_minElapsed || !_serverFound) return;
    final auth = context.read<AuthState>();
    if (auth.restoring) return;
    _navigated = true;
    if (!mounted) return;
    final next = auth.isAuthed ? auth.resumeRoute() : '/login';
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
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF94A3B8),
              ),
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
