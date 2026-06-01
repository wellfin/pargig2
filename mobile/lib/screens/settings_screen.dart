import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Figma "Settings" — reached from the Settings row on Profile.
/// Three tabs: General (filled in), Privacy + Notification (placeholder
/// empty states until those modules ship).
///
/// General tab:
///   - Dark Mode toggle — persisted in SharedPreferences under
///     `settings.darkMode`. Theme switching itself isn't wired into
///     MaterialApp yet, so the toggle persists the preference for
///     when it is. A snackbar surfaces that detail when the user
///     flips it so the behaviour isn't misleading.
///   - Terms & Conditions → pushes the existing /terms screen.
///   - Privacy Policy → snackbar placeholder.
///   - App Version footer (hardcoded to 1.0.0, matching pubspec).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _darkModeKey = 'settings.darkMode';
  static const _visibilityKey = 'settings.profileVisibility';
  static const _showPhoneKey = 'settings.showPhoneNumber';
  static const _showEmailKey = 'settings.showEmail';
  static const _twoFactorKey = 'settings.twoFactorAuth';
  static const _pushNotifKey = 'settings.pushNotifications';
  static const _emailNotifKey = 'settings.emailNotifications';
  static const _smsNotifKey = 'settings.smsNotifications';
  static const _jobAlertsKey = 'settings.alerts.newJob';
  static const _messageAlertsKey = 'settings.alerts.message';
  static const _paymentAlertsKey = 'settings.alerts.payment';
  static const _languageKey = 'settings.language';
  static const _appVersion = '1.0.0';

  // ISO code → display label rendered on the Language tab. Display
  // labels keep the native-script name so the row is unambiguous for
  // users who don't read English. Order matches the Figma list.
  static const List<({String code, String label})> _languages = [
    (code: 'en', label: 'English'),
    (code: 'hi', label: 'हिन्दी (Hindi)'),
    (code: 'te', label: 'తెలుగు (Telugu)'),
    (code: 'ta', label: 'தமிழ் (Tamil)'),
    (code: 'kn', label: 'ಕನ್ನಡ (Kannada)'),
    (code: 'mr', label: 'मराठी (Marathi)'),
  ];

  int _tabIndex = 0;
  bool _darkMode = false;
  String _visibility = 'public';
  bool _showPhone = true;
  bool _showEmail = false;
  bool _twoFactor = false;
  bool _pushNotif = true;
  bool _emailNotif = true;
  bool _smsNotif = false;
  bool _jobAlerts = true;
  bool _messageAlerts = true;
  bool _paymentAlerts = true;
  String _language = 'en';
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _darkMode = prefs.getBool(_darkModeKey) ?? false;
      _visibility = prefs.getString(_visibilityKey) ?? 'public';
      _showPhone = prefs.getBool(_showPhoneKey) ?? true;
      _showEmail = prefs.getBool(_showEmailKey) ?? false;
      _twoFactor = prefs.getBool(_twoFactorKey) ?? false;
      _pushNotif = prefs.getBool(_pushNotifKey) ?? true;
      _emailNotif = prefs.getBool(_emailNotifKey) ?? true;
      _smsNotif = prefs.getBool(_smsNotifKey) ?? false;
      _jobAlerts = prefs.getBool(_jobAlertsKey) ?? true;
      _messageAlerts = prefs.getBool(_messageAlertsKey) ?? true;
      _paymentAlerts = prefs.getBool(_paymentAlertsKey) ?? true;
      _language = prefs.getString(_languageKey) ?? 'en';
      _ready = true;
    });
  }

  Future<void> _setDarkMode(bool v) async {
    setState(() => _darkMode = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkModeKey, v);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          v
              ? 'Dark mode preference saved (theme switch coming soon)'
              : 'Dark mode disabled',
        ),
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  Future<void> _setVisibility(String v) async {
    setState(() => _visibility = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_visibilityKey, v);
  }

  Future<void> _setShowPhone(bool v) async {
    setState(() => _showPhone = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showPhoneKey, v);
  }

  Future<void> _setShowEmail(bool v) async {
    setState(() => _showEmail = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showEmailKey, v);
  }

  Future<void> _setTwoFactor(bool v) async {
    setState(() => _twoFactor = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_twoFactorKey, v);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          v
              ? 'Two-factor auth enabled (verification setup coming soon)'
              : 'Two-factor auth disabled',
        ),
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  Future<void> _setBoolPref(String key, bool v, void Function(bool) apply) async {
    apply(v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, v);
  }

  Future<void> _setLanguage(String code) async {
    setState(() => _language = code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, code);
    if (!mounted) return;
    final label = _languages
        .firstWhere((l) => l.code == code, orElse: () => _languages.first)
        .label;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Language set to $label (full UI translation coming soon)',
        ),
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  void _openTerms() {
    Navigator.pushNamed(context, '/terms');
  }

  void _openPrivacyPolicy() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Privacy Policy — coming soon'),
        duration: Duration(milliseconds: 1000),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Column(
        children: [
          _Header(onBack: () => Navigator.maybePop(context)),
          _Tabs(
            selected: _tabIndex,
            onTap: (i) => setState(() => _tabIndex = i),
          ),
          Expanded(
            child: !_ready
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFFFF6900)),
                    ),
                  )
                : switch (_tabIndex) {
                    0 => _GeneralBody(
                        darkMode: _darkMode,
                        onDarkModeChanged: _setDarkMode,
                        onOpenTerms: _openTerms,
                        onOpenPrivacy: _openPrivacyPolicy,
                        appVersion: _appVersion,
                      ),
                    1 => _PrivacyBody(
                        visibility: _visibility,
                        onVisibility: _setVisibility,
                        showPhone: _showPhone,
                        onShowPhone: _setShowPhone,
                        showEmail: _showEmail,
                        onShowEmail: _setShowEmail,
                        twoFactor: _twoFactor,
                        onTwoFactor: _setTwoFactor,
                      ),
                    2 => _NotificationsBody(
                        pushNotif: _pushNotif,
                        onPushNotif: (v) => _setBoolPref(
                            _pushNotifKey, v, (b) => _pushNotif = b),
                        emailNotif: _emailNotif,
                        onEmailNotif: (v) => _setBoolPref(
                            _emailNotifKey, v, (b) => _emailNotif = b),
                        smsNotif: _smsNotif,
                        onSmsNotif: (v) => _setBoolPref(
                            _smsNotifKey, v, (b) => _smsNotif = b),
                        jobAlerts: _jobAlerts,
                        onJobAlerts: (v) => _setBoolPref(
                            _jobAlertsKey, v, (b) => _jobAlerts = b),
                        messageAlerts: _messageAlerts,
                        onMessageAlerts: (v) => _setBoolPref(
                            _messageAlertsKey, v, (b) => _messageAlerts = b),
                        paymentAlerts: _paymentAlerts,
                        onPaymentAlerts: (v) => _setBoolPref(
                            _paymentAlertsKey, v, (b) => _paymentAlerts = b),
                      ),
                    _ => _LanguageBody(
                        languages: _languages,
                        selected: _language,
                        onSelect: _setLanguage,
                      ),
                  },
          ),
        ],
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
        4, MediaQuery.of(context).padding.top + 6, 16, 12,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
            onPressed: onBack,
          ),
          const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(right: 40),
                child: Text(
                  'Settings',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  static const _tabs = [
    ('General', Icons.tune),
    ('Privacy', Icons.lock_outline),
    ('Notifications', Icons.notifications_none),
    ('Language', Icons.language),
  ];
  final int selected;
  final ValueChanged<int> onTap;

  const _Tabs({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        // Snap-scroll the active pill into view so users can see it
        // when the tab bar overflows the screen width.
        child: Row(
          children: List.generate(_tabs.length, (i) {
            final active = i == selected;
            final label = _tabs[i].$1;
            final icon = _tabs[i].$2;
            return Padding(
              padding:
                  EdgeInsets.only(right: i == _tabs.length - 1 ? 0 : 8),
              child: Material(
                color: active
                    ? const Color(0xFFFF6900)
                    : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => onTap(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: 14,
                          color: active
                              ? Colors.white
                              : const Color(0xFF4A5565),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: active
                                ? Colors.white
                                : const Color(0xFF4A5565),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _GeneralBody extends StatelessWidget {
  final bool darkMode;
  final ValueChanged<bool> onDarkModeChanged;
  final VoidCallback onOpenTerms;
  final VoidCallback onOpenPrivacy;
  final String appVersion;

  const _GeneralBody({
    required this.darkMode,
    required this.onDarkModeChanged,
    required this.onOpenTerms,
    required this.onOpenPrivacy,
    required this.appVersion,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      children: [
        _RowCard(
          children: [
            _Row(
              icon: Icons.dark_mode_outlined,
              label: 'Dark Mode',
              trailing: Switch.adaptive(
                value: darkMode,
                onChanged: onDarkModeChanged,
                activeThumbColor: const Color(0xFFFF6900),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _RowCard(
          children: [
            _Row(
              icon: Icons.description_outlined,
              label: 'Terms & Conditions',
              trailing: const Icon(Icons.chevron_right,
                  size: 20, color: Color(0xFF9CA3AF)),
              onTap: onOpenTerms,
            ),
            const _Divider(),
            _Row(
              icon: Icons.privacy_tip_outlined,
              label: 'Privacy Policy',
              trailing: const Icon(Icons.chevron_right,
                  size: 20, color: Color(0xFF9CA3AF)),
              onTap: onOpenPrivacy,
            ),
            const _Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Text(
                  'App Version $appVersion',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LanguageBody extends StatelessWidget {
  final List<({String code, String label})> languages;
  final String selected;
  final ValueChanged<String> onSelect;

  const _LanguageBody({
    required this.languages,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      children: [
        const _SectionHeader('Select Language'),
        const SizedBox(height: 8),
        _RowCard(
          children: [
            for (int i = 0; i < languages.length; i++) ...[
              _RadioRow(
                label: languages[i].label,
                selected: selected == languages[i].code,
                onTap: () => onSelect(languages[i].code),
              ),
              if (i != languages.length - 1) const _Divider(),
            ],
          ],
        ),
      ],
    );
  }
}

class _NotificationsBody extends StatelessWidget {
  final bool pushNotif;
  final ValueChanged<bool> onPushNotif;
  final bool emailNotif;
  final ValueChanged<bool> onEmailNotif;
  final bool smsNotif;
  final ValueChanged<bool> onSmsNotif;
  final bool jobAlerts;
  final ValueChanged<bool> onJobAlerts;
  final bool messageAlerts;
  final ValueChanged<bool> onMessageAlerts;
  final bool paymentAlerts;
  final ValueChanged<bool> onPaymentAlerts;

  const _NotificationsBody({
    required this.pushNotif,
    required this.onPushNotif,
    required this.emailNotif,
    required this.onEmailNotif,
    required this.smsNotif,
    required this.onSmsNotif,
    required this.jobAlerts,
    required this.onJobAlerts,
    required this.messageAlerts,
    required this.onMessageAlerts,
    required this.paymentAlerts,
    required this.onPaymentAlerts,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      children: [
        const _SectionHeader('Notification Channels'),
        const SizedBox(height: 8),
        _RowCard(
          children: [
            _Row(
              icon: Icons.notifications_active_outlined,
              label: 'Push Notifications',
              trailing: Switch.adaptive(
                value: pushNotif,
                onChanged: onPushNotif,
                activeThumbColor: const Color(0xFFFF6900),
              ),
            ),
            const _Divider(),
            _Row(
              icon: Icons.mail_outline,
              label: 'Email Notifications',
              trailing: Switch.adaptive(
                value: emailNotif,
                onChanged: onEmailNotif,
                activeThumbColor: const Color(0xFFFF6900),
              ),
            ),
            const _Divider(),
            _Row(
              icon: Icons.sms_outlined,
              label: 'SMS Notifications',
              trailing: Switch.adaptive(
                value: smsNotif,
                onChanged: onSmsNotif,
                activeThumbColor: const Color(0xFFFF6900),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const _SectionHeader('Alert Preferences'),
        const SizedBox(height: 8),
        _RowCard(
          children: [
            _TwoLineRow(
              icon: Icons.work_outline,
              title: 'New Job Alerts',
              subtitle: 'Get notified about new jobs',
              trailing: Switch.adaptive(
                value: jobAlerts,
                onChanged: onJobAlerts,
                activeThumbColor: const Color(0xFFFF6900),
              ),
            ),
            const _Divider(),
            _TwoLineRow(
              icon: Icons.chat_bubble_outline,
              title: 'Message Alerts',
              subtitle: 'New messages from clients',
              trailing: Switch.adaptive(
                value: messageAlerts,
                onChanged: onMessageAlerts,
                activeThumbColor: const Color(0xFFFF6900),
              ),
            ),
            const _Divider(),
            _TwoLineRow(
              icon: Icons.payments_outlined,
              title: 'Payment Alerts',
              subtitle: 'Payment confirmations',
              trailing: Switch.adaptive(
                value: paymentAlerts,
                onChanged: onPaymentAlerts,
                activeThumbColor: const Color(0xFFFF6900),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PrivacyBody extends StatelessWidget {
  final String visibility;
  final ValueChanged<String> onVisibility;
  final bool showPhone;
  final ValueChanged<bool> onShowPhone;
  final bool showEmail;
  final ValueChanged<bool> onShowEmail;
  final bool twoFactor;
  final ValueChanged<bool> onTwoFactor;

  const _PrivacyBody({
    required this.visibility,
    required this.onVisibility,
    required this.showPhone,
    required this.onShowPhone,
    required this.showEmail,
    required this.onShowEmail,
    required this.twoFactor,
    required this.onTwoFactor,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      children: [
        const _SectionHeader('Profile Visibility'),
        const SizedBox(height: 8),
        _RowCard(
          children: [
            _RadioRow(
              label: 'Public',
              selected: visibility == 'public',
              onTap: () => onVisibility('public'),
            ),
            const _Divider(),
            _RadioRow(
              label: 'Connections',
              selected: visibility == 'connections',
              onTap: () => onVisibility('connections'),
            ),
            const _Divider(),
            _RadioRow(
              label: 'Private',
              selected: visibility == 'private',
              onTap: () => onVisibility('private'),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const _SectionHeader('Contact Information'),
        const SizedBox(height: 8),
        _RowCard(
          children: [
            _Row(
              icon: Icons.phone_outlined,
              label: 'Show Phone Number',
              trailing: Switch.adaptive(
                value: showPhone,
                onChanged: onShowPhone,
                activeThumbColor: const Color(0xFFFF6900),
              ),
            ),
            const _Divider(),
            _Row(
              icon: Icons.mail_outline,
              label: 'Show Email',
              trailing: Switch.adaptive(
                value: showEmail,
                onChanged: onShowEmail,
                activeThumbColor: const Color(0xFFFF6900),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const _SectionHeader('Security'),
        const SizedBox(height: 8),
        _RowCard(
          children: [
            _TwoLineRow(
              icon: Icons.shield_outlined,
              title: 'Two-Factor Authentication',
              subtitle: 'Add extra security to your account',
              trailing: Switch.adaptive(
                value: twoFactor,
                onChanged: onTwoFactor,
                activeThumbColor: const Color(0xFFFF6900),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Color(0xFF101828),
        ),
      ),
    );
  }
}

class _RadioRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RadioRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? const Color(0xFFFF6900)
                  : Colors.transparent,
              width: selected ? 1.4 : 0,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF101828),
                  ),
                ),
              ),
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? const Color(0xFFFF6900)
                        : const Color(0xFFD1D5DB),
                    width: 1.6,
                  ),
                ),
                alignment: Alignment.center,
                child: selected
                    ? Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF6900),
                          shape: BoxShape.circle,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TwoLineRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  const _TwoLineRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF6B7280)),
          const SizedBox(width: 12),
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
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

class _RowCard extends StatelessWidget {
  final List<Widget> children;
  const _RowCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
      ),
      child: Column(children: children),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget trailing;
  final VoidCallback? onTap;

  const _Row({
    required this.icon,
    required this.label,
    required this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF6B7280)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF101828),
                  ),
                ),
              ),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.6,
      color: const Color(0xFFF1F5F9),
      margin: const EdgeInsets.symmetric(horizontal: 14),
    );
  }
}

