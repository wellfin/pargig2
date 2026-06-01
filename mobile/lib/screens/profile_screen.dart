import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../state/auth_state.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _switchingRole = false;
  bool _loggingOut = false;

  Future<void> _switchMode() async {
    if (_switchingRole) return;
    final auth = context.read<AuthState>();
    final next = auth.isJobGiver ? 'jobtaker' : 'jobgiver';
    setState(() => _switchingRole = true);
    try {
      // mode:'add' appends the second role on the backend so this user
      // ends up with BOTH 'jobgiver' and 'jobtaker' in their roles
      // array (active flips to the one we just switched to). The admin
      // panel then displays the user as "both".
      await auth.switchRole(next, mode: 'add');
      if (!mounted) return;
      // Land the user straight on /home so they see the Hire-mode
      // (or Find Work-mode) layout immediately — the home screen reads
      // auth.isJobGiver and renders the correct sections (Post a New
      // Job + Active Jobs + Nearby Workers for hire mode, browse /
      // recommended for find-work mode). Setup screens are now reached
      // only from initial onboarding; preferences can be tweaked later
      // via Profile.
      Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not switch: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _switchingRole = false);
    }
  }

  Future<void> _logout() async {
    if (_loggingOut) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You will need to enter your mobile number again to log back in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFE7000B),
            ),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _loggingOut = true);
    try {
      await context.read<AuthState>().logout();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loggingOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Logout failed: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final u = auth.user ?? const <String, dynamic>{};
    final name = (u['name'] ?? '').toString();
    final mobile = (u['mobile'] ?? '').toString();
    final isVerified = u['isVerifiedProfessional'] == true;
    final ratingAvg = u['rating'] is Map
        ? (u['rating']['average'] as num?)?.toDouble() ?? 0.0
        : 0.0;
    final ratingCount = u['rating'] is Map
        ? (u['rating']['count'] as num?)?.toInt() ?? 0
        : 0;
    final jobsCompleted = (u['jobsCompleted'] as num?)?.toInt() ?? 0;
    final jobsCancelled = (u['jobsCancelled'] as num?)?.toInt() ?? 0;
    final totalJobs = jobsCompleted + jobsCancelled;
    final successPct =
        totalJobs == 0 ? '—' : '${((jobsCompleted / totalJobs) * 100).round()}%';
    final skills = u['skills'] is List
        ? (u['skills'] as List).whereType<String>().toList()
        : <String>[];
    final photo = (u['photo'] ?? '').toString();
    final modeLabel = auth.isJobGiver ? 'Hire Worker' : 'Find Work';

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _Header(
            name: name.isEmpty ? mobile : name,
            mobile: mobile,
            photo: photo,
            ratingAvg: ratingAvg,
            ratingCount: ratingCount,
            jobsCompleted: jobsCompleted,
            successPct: successPct,
            isVerified: isVerified,
            onBack: () => Navigator.maybePop(context),
            onEdit: () => Navigator.pushNamed(context, '/edit-profile'),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _CurrentModeCard(
              modeLabel: modeLabel,
              isJobGiver: auth.isJobGiver,
              busy: _switchingRole,
              onSwitch: _switchMode,
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _QuickActionsCard(),
          ),
          if (skills.isNotEmpty) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _SkillsCard(skills: skills),
            ),
          ],
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _AccountSettingsCard(
              isVerified: isVerified,
              onEditProfile: () =>
                  Navigator.pushNamed(context, '/edit-profile'),
              onSettings: () => Navigator.pushNamed(context, '/settings'),
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _HelpSupportCard(),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _LogoutButton(
              busy: _loggingOut,
              onTap: _logout,
            ),
          ),
          const SizedBox(height: 16),
          const _VersionFooter(),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String name;
  final String mobile;
  final String photo;
  final double ratingAvg;
  final int ratingCount;
  final int jobsCompleted;
  final String successPct;
  final bool isVerified;
  final VoidCallback onBack;
  final VoidCallback onEdit;

  const _Header({
    required this.name,
    required this.mobile,
    required this.photo,
    required this.ratingAvg,
    required this.ratingCount,
    required this.jobsCompleted,
    required this.successPct,
    required this.isVerified,
    required this.onBack,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final photoSrc = photo.isEmpty
        ? null
        : photo.startsWith('http')
            ? photo
            : '${AppConfig.apiBase}$photo';
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF408EE0),
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 7.5,
            offset: Offset(0, 10),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 16,
        16,
        20,
      ),
      child: Column(
        children: [
          Row(
            children: [
              _RoundIconButton(icon: Icons.arrow_back, onTap: onBack),
              const Expanded(
                child: Text(
                  'Profile',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              _RoundIconButton(icon: Icons.edit_outlined, onTap: onEdit),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 12.5,
                  offset: Offset(0, 20),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFAFCFF),
                            shape: BoxShape.circle,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: photoSrc != null
                              ? Image.network(
                                  photoSrc,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const Icon(
                                    Icons.person,
                                    size: 40,
                                    color: Color(0xFF408EE0),
                                  ),
                                )
                              : const Icon(
                                  Icons.person,
                                  size: 40,
                                  color: Color(0xFF408EE0),
                                ),
                        ),
                        Positioned(
                          right: -4,
                          bottom: -4,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: const BoxDecoration(
                              color: Color(0xFF408EE0),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0x1A000000),
                                  blurRadius: 7.5,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.photo_camera_outlined,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name.isEmpty ? '—' : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF101828),
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            mobile.isEmpty ? '—' : mobile,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Color(0xFF4A5565),
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _RatingPill(
                                rating: ratingAvg,
                                count: ratingCount,
                              ),
                              if (isVerified) const _VerifiedPill(),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.only(top: 16),
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Color(0xFFF3F4F6), width: 0.8),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _Stat(
                          value: '$jobsCompleted',
                          label: 'Jobs Done',
                        ),
                      ),
                      Expanded(
                        child: _Stat(
                          value: ratingAvg > 0
                              ? ratingAvg.toStringAsFixed(1)
                              : '—',
                          label: 'Rating',
                        ),
                      ),
                      Expanded(
                        child: _Stat(value: successPct, label: 'Success'),
                      ),
                    ],
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

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Material(
        color: const Color(0x33FFFFFF),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Icon(icon, size: 22, color: Colors.white),
        ),
      ),
    );
  }
}

class _RatingPill extends StatelessWidget {
  final double rating;
  final int count;
  const _RatingPill({required this.rating, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star, size: 14, color: Color(0xFFFFB300)),
          const SizedBox(width: 4),
          Text(
            rating > 0 ? rating.toStringAsFixed(1) : '—',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF408EE0),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            count > 0 ? '($count reviews)' : '(no reviews)',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF4A5565),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerifiedPill extends StatelessWidget {
  const _VerifiedPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(100),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified, size: 14, color: Color(0xFF00A63E)),
          SizedBox(width: 4),
          Text(
            'Verified',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF00A63E),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: Color(0xFF101828),
            height: 1.33,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF4A5565),
          ),
        ),
      ],
    );
  }
}

class _CurrentModeCard extends StatelessWidget {
  final String modeLabel;
  final bool isJobGiver;
  final bool busy;
  final VoidCallback onSwitch;

  const _CurrentModeCard({
    required this.modeLabel,
    required this.isJobGiver,
    required this.busy,
    required this.onSwitch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 1.5,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isJobGiver
                  ? const Color(0xFFFFF7ED)
                  : const Color(0xFFFFEDD4),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              isJobGiver ? Icons.business_center_outlined : Icons.search,
              size: 24,
              color: const Color(0xFFFF6900),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Current Mode',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF4A5565),
                    height: 1.43,
                  ),
                ),
                Text(
                  modeLabel,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF101828),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 40,
            child: ElevatedButton(
              onPressed: busy ? null : onSwitch,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF408EE0),
                disabledBackgroundColor: const Color(0xFF408EE0),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Switch Mode',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 1.5,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF101828),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _QuickActionTile(
                  icon: Icons.favorite_border,
                  iconBg: Color(0xFFEFF6FF),
                  iconColor: Color(0xFF2B7FFF),
                  title: 'Saved Jobs',
                  subtitle: '0 jobs',
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _QuickActionTile(
                  icon: Icons.location_on_outlined,
                  iconBg: Color(0xFFF0FDF4),
                  iconColor: Color(0xFF00A63E),
                  title: 'Addresses',
                  subtitle: '1 saved',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _QuickActionTile(
                  icon: Icons.credit_card_outlined,
                  iconBg: Color(0xFFFAF5FF),
                  iconColor: Color(0xFF9333EA),
                  title: 'Payment',
                  subtitle: 'No cards',
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _QuickActionTile(
                  icon: Icons.star_outline,
                  iconBg: const Color(0xFFFFF7ED),
                  iconColor: const Color(0xFFFF6900),
                  title: 'Refer & Earn',
                  subtitle: '₹0 earned',
                  onTap: () =>
                      Navigator.pushNamed(context, '/refer-earn'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _QuickActionTile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: iconBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 24, color: iconColor),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF101828),
                  height: 1.43,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF4A5565),
                  height: 1.33,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkillsCard extends StatelessWidget {
  final List<String> skills;
  const _SkillsCard({required this.skills});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 1.5,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Skills',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF101828),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: skills
                .map((s) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEDD4),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        s,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFFF54900),
                          height: 1.43,
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _AccountSettingsCard extends StatelessWidget {
  final bool isVerified;
  final VoidCallback onEditProfile;
  final VoidCallback onSettings;

  const _AccountSettingsCard({
    required this.isVerified,
    required this.onEditProfile,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Account Settings',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF101828),
                  height: 1.4,
                ),
              ),
            ),
          ),
          _SettingsRow(
            icon: Icons.person_outline,
            iconBg: const Color(0xFFF3F4F6),
            iconColor: const Color(0xFF364153),
            title: 'Edit Profile',
            subtitle: 'Update your personal information',
            onTap: onEditProfile,
          ),
          _SettingsRow(
            icon: Icons.verified_user_outlined,
            iconBg: const Color(0xFFDCFCE7),
            iconColor: const Color(0xFF00A63E),
            title: 'KYC Verification',
            subtitle: isVerified ? 'Identity verified' : 'Not yet verified',
            trailing: isVerified
                ? const Text(
                    'Verified',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF00A63E),
                    ),
                  )
                : const Icon(Icons.chevron_right,
                    color: Color(0xFF6A7282), size: 20),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('KYC flow coming soon')),
              );
            },
          ),
          _SettingsRow(
            icon: Icons.settings_outlined,
            iconBg: const Color(0xFFDBEAFE),
            iconColor: const Color(0xFF2B7FFF),
            title: 'Settings',
            subtitle: 'Notifications, privacy & more',
            onTap: onSettings,
          ),
        ],
      ),
    );
  }
}

class _HelpSupportCard extends StatelessWidget {
  const _HelpSupportCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Help & Support',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF101828),
                  height: 1.4,
                ),
              ),
            ),
          ),
          _SettingsRow(
            icon: Icons.help_outline,
            iconBg: const Color(0xFFFFEDD4),
            iconColor: const Color(0xFFFF6900),
            title: 'Help Center',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Help center coming soon')),
              );
            },
          ),
          _SettingsRow(
            icon: Icons.description_outlined,
            iconBg: const Color(0xFFF3F4F6),
            iconColor: const Color(0xFF364153),
            title: 'Terms & Conditions',
            onTap: () => Navigator.pushNamed(context, '/terms'),
          ),
          _SettingsRow(
            icon: Icons.shield_outlined,
            iconBg: const Color(0xFFF3F4F6),
            iconColor: const Color(0xFF364153),
            title: 'Privacy Policy',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Privacy policy coming soon')),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  const _SettingsRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: Color(0xFFF3F4F6), width: 0.8),
          ),
        ),
        child: Row(
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
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF101828),
                      height: 1.5,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF4A5565),
                        height: 1.43,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            trailing ??
                const Icon(Icons.chevron_right,
                    color: Color(0xFF6A7282), size: 20),
          ],
        ),
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;
  const _LogoutButton({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: busy ? null : onTap,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFFE7000B),
                    ),
                  ),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout, size: 20, color: Color(0xFFE7000B)),
                    SizedBox(width: 12),
                    Text(
                      'Logout',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFE7000B),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _VersionFooter extends StatelessWidget {
  const _VersionFooter();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Text(
            'Version 1.0.0',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Color(0xFF6A7282)),
          ),
          SizedBox(height: 4),
          Text(
            'Pargig',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF99A1AF)),
          ),
        ],
      ),
    );
  }
}
