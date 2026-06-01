import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_state.dart';

/// Pre-auth marketing / role-picker screen, rebuilt from scratch
/// against the 2026-05-27 Figma. Old raster-overlay implementation is
/// gone — everything except the hero illustration is now native Flutter
/// (Material icons in coloured chips). The hero still uses the top
/// ~20% crop of popular_tasks.png since the worker pose matches the
/// new comp.
///
/// Flow: pick role (Post Job / Find Job) → "Get Started" stashes the
/// role on AuthState.pendingRole and pushes /login (mobile entry →
/// /otp). Tapping a tile in the grid is decorative for now.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  // Post Job is the visual default in the Figma (orange-bordered card).
  String _role = 'jobgiver';

  Future<void> _start() async {
    final auth = context.read<AuthState>();
    auth.pendingRole = _role;
    if (auth.isAuthed) {
      try {
        await auth.switchRole(_role);
      } catch (_) {}
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        '/profile-setup',
        arguments: {'role': _role},
      );
      return;
    }
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  void _showLearnMore() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
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
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _HeroCrop(),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _RoleCards(
                  selected: _role,
                  onSelect: (r) => setState(() => _role = r),
                ),
              ),
              const SizedBox(height: 22),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: _SectionHeader(
                  title: 'Popular services',
                  trailing: 'View all',
                ),
              ),
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: _ServicesGrid(),
              ),
              const SizedBox(height: 18),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: _InfoBanner(
                  icon: Icons.access_time,
                  bold: 'Hire help for any small task — ',
                  rest: 'from 1 hour to 1 day or more',
                  highlightRest: true,
                ),
              ),
              const SizedBox(height: 10),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: _InfoBanner(
                  icon: Icons.verified_user_outlined,
                  bold:
                      'Pargig connects users with helpers for everyday tasks.\n',
                  rest: 'High-risk or sensitive jobs are not allowed.',
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  height: 58,
                  child: ElevatedButton(
                    onPressed: _start,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF408EE0),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                      shadowColor: Colors.transparent,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Get Started',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(Icons.chevron_right, size: 24),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: TextButton(
                  onPressed: _showLearnMore,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF408EE0),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Learn More',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.chevron_right, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── hero crop ────────────────────────────────────────────────────────
// popular_tasks.png is 941×1672 and bundles the original Figma comp.
// We only need the worker character at the top (0–20%), so we crop the
// raster with an OverflowBox + ClipRect. The "Skip" pill in the
// top-right corner of the export is masked with a small white block.
const double _kPopularTasksAspect = 1672 / 941;
const double _kHeroEndRatio = 0.205;

class _HeroCrop extends StatelessWidget {
  const _HeroCrop();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    // Once hero.png is dropped at assets/onboarding/hero.png we render it
    // full-width at its natural aspect. Until then we fall back to a
    // 20.5% top crop of popular_tasks.png (worker character only).
    return Image.asset(
      'assets/onboarding/hero.png',
      width: w,
      fit: BoxFit.fitWidth,
      errorBuilder: (_, _, _) => _LegacyHeroCrop(width: w),
    );
  }
}

class _LegacyHeroCrop extends StatelessWidget {
  final double width;
  const _LegacyHeroCrop({required this.width});

  @override
  Widget build(BuildContext context) {
    final w = width;
    final naturalH = w * _kPopularTasksAspect;
    return SizedBox(
      width: w,
      height: naturalH * _kHeroEndRatio,
      child: ClipRect(
        child: Stack(
          children: [
            OverflowBox(
              maxWidth: w,
              maxHeight: naturalH,
              alignment: Alignment.topCenter,
              child: Image.asset(
                'assets/onboarding/popular_tasks.png',
                width: w,
                fit: BoxFit.fitWidth,
                alignment: Alignment.topCenter,
                errorBuilder: (_, _, _) => Container(
                  width: w,
                  height: naturalH * _kHeroEndRatio,
                  color: const Color(0xFFEFF6FF),
                ),
              ),
            ),
            // Mask the baked-in "Skip" label top-right.
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                width: w * 0.18,
                height: w * 0.07,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── role cards ───────────────────────────────────────────────────────
class _RoleCards extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;

  const _RoleCards({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _RoleCard(
            title: 'Post Job',
            subtitle: 'Hire workers for daily tasks',
            icon: Icons.work_outline,
            accent: const Color(0xFFFF6900),
            iconBg: const Color(0xFFFFEDD4),
            iconColor: const Color(0xFFFF6900),
            selected: selected == 'jobgiver',
            onTap: () => onSelect('jobgiver'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _RoleCard(
            title: 'Find Job',
            subtitle: 'Discover small jobs any where',
            icon: Icons.search,
            accent: const Color(0xFF408EE0),
            iconBg: const Color(0xFFDBEAFE),
            iconColor: const Color(0xFF408EE0),
            selected: selected == 'jobtaker',
            onTap: () => onSelect('jobtaker'),
          ),
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final Color iconBg;
  final Color iconColor;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.iconBg,
    required this.iconColor,
    required this.selected,
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
          height: 150,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? accent : const Color(0x1F000000),
              width: selected ? 1.5 : 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 4,
                offset: Offset(0, 2),
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                  const SizedBox(width: 6),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── section header ───────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final String trailing;
  const _SectionHeader({required this.title, required this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF101828),
          ),
        ),
        Row(
          children: [
            Text(
              trailing,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF408EE0),
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 16,
              color: Color(0xFF408EE0),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── services grid ────────────────────────────────────────────────────
class _ServiceTile {
  final String title;
  final String subtitle;
  final IconData icon;
  // Filename inside assets/onboarding/tiles/ (without extension). When
  // the PNG exists we render Image.asset; if it's missing the Material
  // icon `icon` is used instead so the screen keeps working before the
  // exports land.
  final String asset;
  final bool highlighted;
  const _ServiceTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.asset,
    this.highlighted = false,
  });
}

class _ServicesGrid extends StatelessWidget {
  const _ServicesGrid();

  static const _tiles = <_ServiceTile>[
    _ServiceTile(
      title: 'Home cleaning',
      subtitle: 'Book trusted cleaners for your home',
      icon: Icons.cleaning_services,
      asset: 'home_cleaning',
    ),
    _ServiceTile(
      title: 'Quick car wash',
      subtitle: 'Get your car cleaned at your doorstep',
      icon: Icons.local_car_wash,
      asset: 'car_wash',
    ),
    _ServiceTile(
      title: 'Elder support',
      subtitle: 'Trained helpers for elderly care',
      icon: Icons.elderly,
      asset: 'elder_support',
    ),
    _ServiceTile(
      title: 'Pet care',
      subtitle: 'Loving pet care for your pet',
      icon: Icons.pets,
      asset: 'pet_care',
    ),
    _ServiceTile(
      title: 'Shop assistance',
      subtitle: 'Get help for shopping & more',
      icon: Icons.storefront,
      asset: 'shop_assistance',
    ),
    _ServiceTile(
      title: 'Event help',
      subtitle: 'Helpers for events and functions',
      icon: Icons.celebration,
      asset: 'event_help',
    ),
    _ServiceTile(
      title: 'Tech support',
      subtitle: 'Get expert tech support',
      icon: Icons.headset_mic,
      asset: 'tech_support',
    ),
    _ServiceTile(
      title: 'Pick up & deliver',
      subtitle: 'Food, buy something locally and deliver or anything',
      icon: Icons.delivery_dining,
      asset: 'pickup_deliver',
    ),
    _ServiceTile(
      title: 'Collect parcel',
      subtitle: 'Collect parcels from office or home',
      icon: Icons.inventory_2_outlined,
      asset: 'collect_parcel',
    ),
    _ServiceTile(
      title: 'Buy & deliver',
      subtitle: 'Buy anything & deliver to you',
      icon: Icons.shopping_bag_outlined,
      asset: 'buy_deliver',
    ),
    _ServiceTile(
      title: 'Stand in queue',
      subtitle: 'Stand in queue for any service',
      icon: Icons.groups,
      asset: 'stand_in_queue',
    ),
    _ServiceTile(
      title: 'Home repairs',
      subtitle: 'Minor repair & maintenance work',
      icon: Icons.home_repair_service,
      asset: 'home_repairs',
    ),
    _ServiceTile(
      title: 'Plumbing',
      subtitle: 'Professional plumbing services',
      icon: Icons.plumbing,
      asset: 'plumbing',
    ),
    _ServiceTile(
      title: 'Painting',
      subtitle: 'Home & office painting services',
      icon: Icons.format_paint,
      asset: 'painting',
    ),
    _ServiceTile(
      title: 'AC repair',
      subtitle: 'AC installation & repair services',
      icon: Icons.ac_unit,
      asset: 'ac_repair',
    ),
    _ServiceTile(
      title: 'More tasks',
      subtitle: 'Explore more services',
      icon: Icons.apps,
      asset: 'more_tasks',
      highlighted: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 8,
        childAspectRatio: 0.58,
      ),
      itemCount: _tiles.length,
      itemBuilder: (_, i) => _ServiceTileCard(tile: _tiles[i]),
    );
  }
}

class _ServiceTileCard extends StatelessWidget {
  final _ServiceTile tile;
  const _ServiceTileCard({required this.tile});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: tile.highlighted
              ? const Color(0xFF408EE0)
              : const Color(0x14000000),
          width: tile.highlighted ? 1.4 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          // Prefer the per-tile illustration (assets/onboarding/tiles/
          // <name>.png). If it's missing, fall back to a Material icon
          // inside a light-blue circle so the screen still renders.
          SizedBox(
            width: 56,
            height: 56,
            child: Image.asset(
              'assets/onboarding/tiles/${tile.asset}.png',
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Container(
                width: 44,
                height: 44,
                margin: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Color(0xFFDBEAFE),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  tile.icon,
                  size: 22,
                  color: const Color(0xFF408EE0),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            tile.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101828),
              height: 1.15,
            ),
          ),
          const SizedBox(height: 3),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                tile.subtitle,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
                style: const TextStyle(
                  fontSize: 7.8,
                  color: Color(0xFF6B7280),
                  height: 1.25,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── info banners ─────────────────────────────────────────────────────
class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String bold;
  final String rest;
  final bool highlightRest;
  const _InfoBanner({
    required this.icon,
    required this.bold,
    required this.rest,
    this.highlightRest = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: Color(0xFF408EE0),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF101828),
                  height: 1.35,
                ),
                children: [
                  TextSpan(
                    text: bold,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: rest,
                    style: TextStyle(
                      fontWeight:
                          highlightRest ? FontWeight.w700 : FontWeight.w400,
                      color: highlightRest
                          ? const Color(0xFF408EE0)
                          : const Color(0xFF4A5565),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── learn more sheet ─────────────────────────────────────────────────
class _LearnMoreSheet extends StatelessWidget {
  const _LearnMoreSheet();

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'How Pargig works',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF101828),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Pargig is a marketplace for everyday small tasks. Post a '
              'job in minutes, get matched with verified helpers near you, '
              'and pay only when the work is done.',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF4A5565),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            const _LearnPoint(
              icon: Icons.work_outline,
              title: 'Post Job',
              body:
                  'Describe what you need, set a budget, and confirm. '
                  'Workers nearby get notified.',
            ),
            const SizedBox(height: 12),
            const _LearnPoint(
              icon: Icons.search,
              title: 'Find Job',
              body:
                  'Browse open jobs around you, apply with your offer, '
                  'and start earning.',
            ),
            const SizedBox(height: 12),
            const _LearnPoint(
              icon: Icons.verified_user_outlined,
              title: 'Safe & Trusted',
              body:
                  'Every helper is verified. OTP-based job start and '
                  'completion keeps payments protected.',
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF408EE0),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Got it',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LearnPoint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _LearnPoint({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: Color(0xFFDBEAFE),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: const Color(0xFF408EE0)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF101828),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF6B7280),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
