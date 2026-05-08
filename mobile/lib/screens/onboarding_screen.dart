import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_state.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  Future<void> _continue(
    BuildContext context, {
    String? roleHint,
  }) async {
    final role = (roleHint == 'jobtaker') ? 'jobtaker' : 'jobgiver';
    try {
      await context.read<AuthState>().switchRole(role);
    } catch (_) {
      // Non-fatal; the wizard still threads the choice via route args below.
    }
    if (!context.mounted) return;
    Navigator.pushReplacementNamed(
      context,
      '/profile-setup',
      arguments: {'role': role},
    );
  }

  void _showLearnMore(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _LearnMoreSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _HeroIllustration(),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Expanded(
                      child: _PrimaryRoleCard(
                        title: 'Post Job',
                        subtitle: 'Hire workers for daily tasks',
                        icon: Icons.work_outline,
                        accent: const Color(0xFFFF6900),
                        iconBg: const Color(0xFFFFEDD4),
                        iconColor: const Color(0xFFFF6900),
                        bordered: true,
                        onTap: () =>
                            _continue(context, roleHint: 'jobgiver'),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: _PrimaryRoleCard(
                        title: 'Find Job',
                        subtitle: 'Discover small jobs any where',
                        icon: Icons.search,
                        accent: const Color(0xFF2563EB),
                        iconBg: const Color(0xFFDBEAFE),
                        iconColor: const Color(0xFF2563EB),
                        bordered: false,
                        onTap: () =>
                            _continue(context, roleHint: 'jobtaker'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const _ServiceGrid(),
              const SizedBox(height: 18),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: _InfoBanner(
                  icon: Icons.access_time_filled,
                  iconColor: Color(0xFF2563EB),
                  bg: Color(0xFFEFF6FF),
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF101828),
                        height: 1.35,
                      ),
                      children: [
                        TextSpan(text: 'Hire help for any small task —\n'),
                        TextSpan(
                          text: 'from 1 hour to 1 day or more',
                          style: TextStyle(
                            color: Color(0xFF2563EB),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: _InfoBanner(
                  icon: Icons.verified_user,
                  iconColor: Color(0xFF2563EB),
                  bg: Color(0xFFEFF6FF),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pargig connects users with helpers for everyday tasks.',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF101828),
                          height: 1.35,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'High-risk or sensitive jobs are not allowed.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF4A5565),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => _continue(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Get Started',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 6),
                        Icon(Icons.chevron_right, size: 22),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () => _showLearnMore(context),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF2563EB),
                  ),
                  child: const Text(
                    'Learn More',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroIllustration extends StatelessWidget {
  const _HeroIllustration();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return SizedBox(
      width: w,
      height: w * 0.78,
      child: ClipRect(
        child: OverflowBox(
          maxWidth: w,
          maxHeight: w * 1.4,
          alignment: Alignment.topCenter,
          child: Image.asset(
            'assets/onboarding/hero_full.png',
            width: w,
            fit: BoxFit.fitWidth,
            alignment: Alignment.topCenter,
          ),
        ),
      ),
    );
  }
}

class _PrimaryRoleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final Color iconBg;
  final Color iconColor;
  final bool bordered;
  final VoidCallback onTap;

  const _PrimaryRoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.iconBg,
    required this.iconColor,
    required this.bordered,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 136,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: bordered ? accent : const Color(0x1F000000),
              width: bordered ? 1.5 : 1,
            ),
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
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF101828),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF4A5565),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceGrid extends StatelessWidget {
  const _ServiceGrid();

  static const _items = <_Service>[
    _Service('Home cleaning', Icons.cleaning_services_outlined),
    _Service('Arranging\nfurniture', Icons.weekend_outlined),
    _Service('Quick car\nwash', Icons.local_car_wash_outlined),
    _Service('Elder\nsupport', Icons.elderly),
    _Service('Pet care', Icons.pets_outlined),
    _Service('Shop\nassistance', Icons.storefront_outlined),
    _Service('Event help', Icons.celebration_outlined),
    _Service('Tech\nsupport', Icons.computer_outlined),
    _Service('Pick up &\ndeliver', Icons.delivery_dining_outlined),
    _Service('Collect\nparcel', Icons.inventory_2_outlined),
    _Service('Buy &\ndeliver', Icons.shopping_bag_outlined),
    _Service('Stand in\nqueue', Icons.groups_outlined),
  ];

  static const _subtitles = <String>[
    '',
    '',
    '',
    'Hospital visit,\nwalking, shopping etc.',
    'Walking or caring\nyour pet',
    '',
    'Set up, catering\nor any function support',
    '',
    'Food, buy something\nlocally & deliver\nor anything',
    'From office or\nhome and give',
    'Buy something\nlocally & deliver\nor anything',
    'Stand in queue\nfor any service\nor places',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _items.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.78,
        ),
        itemBuilder: (_, i) => _ServiceTile(
          label: _items[i].label,
          icon: _items[i].icon,
          subtitle: _subtitles[i],
        ),
      ),
    );
  }
}

class _Service {
  final String label;
  final IconData icon;
  const _Service(this.label, this.icon);
}

class _ServiceTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final String subtitle;

  const _ServiceTile({
    required this.label,
    required this.icon,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x14000000)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: Color(0xFFDBEAFE),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: const Color(0xFF2563EB)),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF101828),
              height: 1.15,
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Expanded(
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 8,
                  color: Color(0xFF6B7280),
                  height: 1.2,
                ),
                overflow: TextOverflow.fade,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color bg;
  final Widget child;

  const _InfoBanner({
    required this.icon,
    required this.iconColor,
    required this.bg,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x14000000)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: iconColor),
          const SizedBox(width: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _LearnMoreSheet extends StatelessWidget {
  const _LearnMoreSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'About Pargig',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF101828),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Pargig is a hyper-local marketplace for short, everyday tasks. '
              'Post a job in seconds or browse open requests near you and earn '
              'on your own schedule. We focus on small, low-risk gigs — from '
              'an hour of cleaning to a day of help — and keep payments and '
              'chat in one place.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF4A5565),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
