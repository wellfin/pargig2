import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_state.dart';

/// "How do you want to start?" — final role confirmation shown right after
/// the profile-setup wizard finishes. The user already picked a role
/// pre-auth from the onboarding screen, but this lets them confirm or
/// flip it before landing on /home.
class RoleChooserScreen extends StatefulWidget {
  const RoleChooserScreen({super.key});

  @override
  State<RoleChooserScreen> createState() => _RoleChooserScreenState();
}

class _RoleChooserScreenState extends State<RoleChooserScreen> {
  String? _busyRole;

  void _goBack() {
    // Normal case: pop one step. Onboarding lands here as the stack root
    // (the wizard was cleared), so fall back to the last profile-setup step
    // the user came from — skills for jobtakers, address for jobgivers.
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
      return;
    }
    final role = context.read<AuthState>().activeRole;
    Navigator.pushReplacementNamed(
      context,
      role == 'jobtaker' ? '/profile-setup/skills' : '/profile-setup/address',
    );
  }

  Future<void> _pick(String role) async {
    if (_busyRole != null) return;
    setState(() => _busyRole = role);
    try {
      // Flip the active role immediately on tap — the user's intent is
      // "I am a jobtaker now (or jobgiver now)", so we don't wait until
      // they hit Apply on the setup screen. mode:'add' keeps the other
      // role on their account so they can switch back later via Profile
      // → Switch Mode without re-onboarding. The Apply tap on the setup
      // screen still calls switchRole('...', mode:'replace') for users
      // who want a single-role account.
      final auth = context.read<AuthState>();
      if (auth.activeRole != role) {
        await auth.switchRole(role, mode: 'add');
      }
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        role == 'jobtaker' ? '/find-work-setup' : '/hire-workers-setup',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not switch role: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyRole = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeRole = context.watch<AuthState>().activeRole;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _goBack,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.arrow_back,
                        size: 24,
                        color: Color(0xFF101828),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'How do you want to start?',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF101828),
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'You can switch roles anytime',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF64748B),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              _RoleCard(
                title: 'Find Work',
                subtitle: 'Browse and apply for jobs in your area',
                icon: Icons.search,
                iconBg: const Color(0xFFFF6900),
                iconFg: Colors.white,
                cardBg: const Color(0xFFFFF7ED),
                borderColor: activeRole == 'jobtaker'
                    ? const Color(0xFFFF6900)
                    : const Color(0xFFFFD9B3),
                busy: _busyRole == 'jobtaker',
                onTap: () => _pick('jobtaker'),
              ),
              const SizedBox(height: 12),
              _RoleCard(
                title: 'Hire Workers',
                subtitle: 'Post jobs and find the right people',
                icon: Icons.business_center_outlined,
                iconBg: const Color(0xFF101828),
                iconFg: Colors.white,
                cardBg: Colors.white,
                borderColor: activeRole == 'jobgiver'
                    ? const Color(0xFF101828)
                    : const Color(0xFFE5E7EB),
                busy: _busyRole == 'jobgiver',
                onTap: () => _pick('jobgiver'),
              ),
              const SizedBox(height: 20),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: const Text(
                    'You can switch roles any time',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF408EE0),
                      decoration: TextDecoration.underline,
                      decorationColor: Color(0xFF408EE0),
                    ),
                  ),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final Color cardBg;
  final Color borderColor;
  final bool busy;
  final VoidCallback onTap;

  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.cardBg,
    required this.borderColor,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.4),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: busy
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation<Color>(iconFg),
                        ),
                      )
                    : Icon(icon, color: iconFg, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF101828),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF4A5565),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
