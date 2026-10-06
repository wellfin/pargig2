import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_state.dart';

/// Pre-auth landing screen — the second screen after splash.
///
/// Rebuilt against the 2026-08 Figma: wordmark, value proposition, the
/// Post Job / Find Job role picker, GET STARTED, and the twelve popular
/// task categories.
///
/// The routing behaviour is unchanged and deliberately so: picking a role
/// stashes it on [AuthState.pendingRole] and pushes /login (mobile entry →
/// /otp → /terms → /profile-setup → wizard → /role-chooser → /home). An
/// already-authenticated user switches role and goes straight to profile
/// setup. Breaking that chain here would strand people mid-signup.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  // Post Job is the default in the design — it renders as the
  // orange-bordered card.
  String _role = 'jobgiver';

  Future<void> _start() async {
    final auth = context.read<AuthState>();
    auth.pendingRole = _role;
    if (auth.isAuthed) {
      try {
        await auth.switchRole(_role);
      } catch (_) {
        // A failed switch must not block signup; the role chooser later
        // in the flow can still correct it.
      }
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

  // Tapping a category is a shortcut into the same signup flow rather
  // than a dead decoration: someone who taps "Need a Plumber" wants to
  // hire, so it preselects Post Job and starts.
  void _tapCategory() {
    setState(() => _role = 'jobgiver');
    _start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // The blue band runs to the very top of the screen, so the status
      // bar sits on it — hence SafeArea only below, with the band adding
      // the inset itself.
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _HeaderBand(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // IntrinsicHeight, not a bare stretch: the two subtitles wrap
                  // to different line counts, and the cards must still match
                  // height. A plain CrossAxisAlignment.stretch here asks for an
                  // infinite height inside the scroll view and throws.
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _RoleCard(
                            icon: Icons.work_outline,
                            title: 'Post Job',
                            subtitle: 'Hire workers for daily tasks',
                            accent: const Color(0xFFFF6900),
                            tint: const Color(0xFFFFEDD4),
                            selected: _role == 'jobgiver',
                            onTap: () => setState(() => _role = 'jobgiver'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _RoleCard(
                            icon: Icons.search,
                            title: 'Find Job',
                            subtitle: 'Discover small jobs anywhere',
                            accent: const Color(0xFF2B7FFF),
                            tint: const Color(0xFFDBEAFE),
                            selected: _role == 'jobtaker',
                            onTap: () => setState(() => _role = 'jobtaker'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: _start,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        side: const BorderSide(
                          color: Color(0xFFFF6900),
                          width: 1.4,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'GET STARTED',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: Color(0xFFFF6900),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _SectionDivider(label: 'Popular Task Categories'),
                  const SizedBox(height: 14),
                  _CategoryGrid(onTap: _tapCategory),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Blue banner: wordmark, tagline and the value proposition.
///
/// Full-bleed to the top edge with rounded bottom corners, so it reads as
/// one block rather than a card floating on white.
class _HeaderBand extends StatelessWidget {
  const _HeaderBand();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4C93EA), Color(0xFF2F7BE0)],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(26),
          bottomRight: Radius.circular(26),
        ),
      ),
      // Top padding carries the status-bar inset so the gradient reaches
      // the top of the display instead of starting under a white strip.
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 16,
        20,
        26,
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: _Wordmark()),
          SizedBox(height: 8),
          Center(
            child: Text(
              'Post Any Need. Take Any Job',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
          SizedBox(height: 26),
          Text(
            'Need Help With Anything?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'From 1 hour to 1 day or more. You decide the price.',
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              // Softer than the heading so the two are distinguishable
              // against the same blue.
              color: Color(0xCCFFFFFF),
            ),
          ),
        ],
      ),
    );
  }
}

/// "P PARGIG" in white, sitting directly on the blue band.
///
/// The earlier black pill is gone with the white header — on blue it read
/// as a sticker rather than a logo.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'P',
          style: TextStyle(
            fontSize: 27,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            height: 1,
          ),
        ),
        SizedBox(width: 7),
        Text(
          'PARGIG',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            color: Colors.white,
            height: 1,
          ),
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final Color tint;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.tint,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              // The unselected card keeps a faint border rather than none,
              // so the two sit as a pair instead of one looking disabled.
              color: selected ? accent : const Color(0xFFE5E7EB),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
                child: Icon(icon, size: 21, color: accent),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF101828),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "— Popular Task Categories —" with a rule either side.
class _SectionDivider extends StatelessWidget {
  final String label;
  const _SectionDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    const line = Expanded(
      child: Divider(thickness: 0.8, color: Color(0xFFBEDBFF)),
    );
    return Row(
      children: [
        line,
        // Arrows point inward at the label, per the design.
        const Icon(Icons.arrow_right_alt, size: 15, color: Color(0xFFBEDBFF)),
        // Flexible, not a bare Padding: the label claims its natural width
        // before the Expanded rules get any, so on a narrow screen the
        // rules collapse to zero and the text overflows the row instead.
        Flexible(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF408EE0),
              ),
            ),
          ),
        ),
        Transform.flip(
          flipX: true,
          child: const Icon(
            Icons.arrow_right_alt,
            size: 15,
            color: Color(0xFFBEDBFF),
          ),
        ),
        line,
      ],
    );
  }
}

/// One category tile: caption, illustration, and an icon fallback.
class _Category {
  final String title;
  final IconData icon;
  final String asset;
  final Color tint;
  final Color accent;
  const _Category(this.title, this.icon, this.asset, this.tint, this.accent);
}

const _blueTint = Color(0xFFDBEAFE);
const _blue = Color(0xFF2B7FFF);
const _sandTint = Color(0xFFF5EBDC);
const _sand = Color(0xFF9A6B3F);
const _redTint = Color(0xFFFEE2E2);
const _red = Color(0xFFDC2626);
const _slateTint = Color(0xFFE5E7EB);
const _slate = Color(0xFF374151);

/// The twelve categories, in Figma order.
///
/// `asset` is the illustration in assets/onboarding/tiles/, exported from
/// the Figma and named by position — 1.png is the first tile, 12.png the
/// last. The numbering in the captions and the filenames are the same
/// sequence, so the list order below IS the mapping: reordering this list
/// without renaming the files would silently mislabel every tile.
///
/// `icon`/`tint` are a fallback for a missing or corrupt file, colour-
/// matched to the artwork each stands in for.
const _categories = <_Category>[
  _Category(
    'Need Someone to Help With Any Task',
    Icons.person_outline,
    '1',
    _blueTint,
    _blue,
  ),
  _Category(
    'Need a Plumber or Electrician',
    Icons.build_outlined,
    '2',
    _blueTint,
    _blue,
  ),
  _Category(
    'Quick Home / Vehicle Cleaning',
    Icons.cleaning_services_outlined,
    '3',
    _sandTint,
    _sand,
  ),
  _Category(
    'Need a Shop Helper',
    Icons.storefront_outlined,
    '4',
    _blueTint,
    _blue,
  ),
  _Category(
    'Parent Care or Pet Care Assistance',
    Icons.people_outline,
    '5',
    _blueTint,
    _blue,
  ),
  _Category(
    'Event Setup or Home Shifting Help',
    Icons.event_outlined,
    '6',
    _blueTint,
    _blue,
  ),
  _Category(
    'Need a Vehicle for a Trip',
    Icons.directions_car_outlined,
    '7',
    _redTint,
    _red,
  ),
  _Category(
    'Need a Driver for a Day',
    Icons.airline_seat_recline_normal,
    '8',
    _slateTint,
    _slate,
  ),
  _Category(
    'Collect or Submit Documents',
    Icons.description_outlined,
    '9',
    _blueTint,
    _blue,
  ),
  _Category(
    'Buy & Deliver Anything',
    Icons.shopping_cart_outlined,
    '10',
    _blueTint,
    _blue,
  ),
  _Category(
    'Need a Caretaker / Watchman',
    Icons.home_outlined,
    '11',
    _sandTint,
    _sand,
  ),
  _Category(
    'One-Time Tutor / Learning Assistance',
    Icons.school_outlined,
    '12',
    _blueTint,
    _blue,
  ),
];

class _CategoryGrid extends StatelessWidget {
  final VoidCallback onTap;
  const _CategoryGrid({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      // Inside a SingleChildScrollView, so the grid must size itself and
      // not scroll independently.
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _categories.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        // Tall enough for a three-line caption at the longest title, so
        // no tile clips its own text.
        childAspectRatio: 0.78,
      ),
      itemBuilder: (_, i) =>
          _CategoryTile(index: i + 1, category: _categories[i], onTap: onTap),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final int index;
  final _Category category;
  final VoidCallback onTap;
  const _CategoryTile({
    required this.index,
    required this.category,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x14000000)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: 46, height: 46, child: _artwork()),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  '$index. ${category.title}',
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9.5,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF364153),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _artwork() => Image.asset(
    'assets/onboarding/tiles/${category.asset}.png',
    fit: BoxFit.contain,
    // The export is missing until the Figma assets are added, and a
    // missing file must never blank the tile.
    errorBuilder: (_, _, _) => _iconChip(),
  );

  Widget _iconChip() => Container(
    margin: const EdgeInsets.all(3),
    decoration: BoxDecoration(color: category.tint, shape: BoxShape.circle),
    child: Icon(category.icon, size: 21, color: category.accent),
  );
}
