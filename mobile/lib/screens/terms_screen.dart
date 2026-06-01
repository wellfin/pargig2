import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_state.dart';

class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  bool _accepting = false;
  String? _error;

  static const _terms = <_Term>[
    _Term(
      '1. Acceptance of Terms',
      'By accessing and using Pargig, you accept and agree to be bound by the '
          'terms and provision of this agreement. If you do not agree to these '
          'terms, please do not use our services.',
    ),
    _Term(
      '2. User Responsibilities',
      'Users are responsible for maintaining the confidentiality of their '
          'account information and for all activities that occur under their '
          'account. You agree to provide accurate and complete information when '
          'creating an account.',
    ),
    _Term(
      '3. Service Providers',
      'Pargig acts as a platform connecting users with service providers. We '
          'are not responsible for the quality, safety, or legality of the '
          'services provided. All transactions are between users and service '
          'providers.',
    ),
    _Term(
      '4. Payment Terms',
      "Payment for services must be made through the platform's approved "
          'payment methods. Service fees, cancellation charges, and refund '
          'policies will be clearly communicated before confirming any booking.',
    ),
    _Term(
      '5. Cancellation Policy',
      'Cancellations must be made within the specified timeframe. Cancellation '
          'charges may apply based on the timing of cancellation. Full refunds '
          'are available for cancellations made 24 hours before the scheduled '
          'service.',
    ),
    _Term(
      '6. Privacy & Data Protection',
      'We are committed to protecting your privacy. Your personal information '
          'will be collected, stored, and used in accordance with our Privacy '
          'Policy and applicable data protection laws.',
    ),
    _Term(
      '7. Liability Limitations',
      'Pargig shall not be liable for any indirect, incidental, special, or '
          'consequential damages arising from the use of our services. Our '
          'liability is limited to the amount paid for the specific service.',
    ),
    _Term(
      '8. Dispute Resolution',
      'Any disputes arising from the use of our services will be resolved '
          'through arbitration in accordance with the laws of India. Both '
          'parties agree to attempt mediation before pursuing legal action.',
    ),
  ];

  Future<void> _accept() async {
    if (_accepting) return;
    setState(() {
      _accepting = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthState>();
      await auth.acceptTerms();
      if (!mounted) return;
      // After accepting terms, defer to resumeRoute so the user lands on
      // the next missing step (typically /profile-setup for brand-new
      // accounts, or /home for users who somehow re-accepted terms with
      // a fully populated profile).
      Navigator.pushReplacementNamed(context, auth.resumeRoute());
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: SafeArea(
        child: Column(
          children: [
            const _TopBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _HeroCard(),
                    const SizedBox(height: 24),
                    const _FeatureBadges(),
                    const SizedBox(height: 24),
                    ..._terms.map(
                      (t) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _TermCard(title: t.title, body: t.body),
                      ),
                    ),
                    const _ImportantNoticeCard(),
                    const SizedBox(height: 16),
                    if (_error != null) ...[
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFDC2626),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    const Center(
                      child: Text(
                        '© 2026 Pargig. All rights reserved.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _AcceptBar(loading: _accepting, onTap: _accept),
          ],
        ),
      ),
    );
  }
}

class _Term {
  final String title;
  final String body;
  const _Term(this.title, this.body);
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xF2FFFFFF),
        border: Border(
          bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            // Only show a back arrow when there's actually something
            // below /terms on the nav stack. Fresh-registration flow
            // wipes login/OTP from the stack, so the arrow would
            // otherwise be a dead button.
            child: Navigator.canPop(context)
                ? Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.maybePop(context),
                      child: const Icon(
                        Icons.arrow_back,
                        size: 20,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 12),
          const Text(
            'Terms & Conditions',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
              letterSpacing: -0.34,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x0D0284C7), Color(0xFFFFFFFF)],
        ),
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0x1A0284C7),
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 6,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.description_outlined,
              size: 40,
              color: Color(0xFF0284C7),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Terms & Conditions',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
              letterSpacing: -0.2,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Last updated: January 2026',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF64748B),
              height: 1.43,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureBadges extends StatelessWidget {
  const _FeatureBadges();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(
          child: _FeatureBadge(
            label: 'Secure',
            icon: Icons.shield_outlined,
            iconColor: Color(0xFF408EE0),
            iconBg: Color(0xFFDBEAFE),
            cardTint: Color(0xFFEFF6FF),
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: _FeatureBadge(
            label: 'Fair',
            icon: Icons.balance,
            iconColor: Color(0xFF16A34A),
            iconBg: Color(0xFFDCFCE7),
            cardTint: Color(0xFFF0FDF4),
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: _FeatureBadge(
            label: 'Transparent',
            icon: Icons.visibility_outlined,
            iconColor: Color(0xFF9333EA),
            iconBg: Color(0xFFF3E8FF),
            cardTint: Color(0xFFFAF5FF),
          ),
        ),
      ],
    );
  }
}

class _FeatureBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final Color cardTint;

  const _FeatureBadge({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.cardTint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cardTint, Colors.white],
        ),
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
              height: 1.33,
            ),
          ),
        ],
      ),
    );
  }
}

class _TermCard extends StatelessWidget {
  final String title;
  final String body;

  const _TermCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(21, 21, 21, 21),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF64748B),
              height: 1.625,
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
      padding: const EdgeInsets.fromLTRB(21, 21, 21, 21),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFEFCE8), Color(0xFFFFFFFF)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFF085), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 24,
            color: Color(0xFFCA8A04),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Important Notice',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'These terms may be updated from time to time. Continued use '
                  'of the service after changes constitutes acceptance of the '
                  'new terms. We will notify you of any significant changes.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                    height: 1.625,
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

class _AcceptBar extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;
  const _AcceptBar({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SizedBox(
        height: 56,
        child: ElevatedButton(
          onPressed: loading ? null : onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF6900),
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFFFF6900).withAlpha(140),
            disabledForegroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
          ),
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text(
                  'I Accept & Continue',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }
}
