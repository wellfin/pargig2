import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_state.dart';

class ProfileSetupSkillsScreen extends StatefulWidget {
  const ProfileSetupSkillsScreen({super.key});

  @override
  State<ProfileSetupSkillsScreen> createState() =>
      _ProfileSetupSkillsScreenState();
}

class _ProfileSetupSkillsScreenState extends State<ProfileSetupSkillsScreen> {
  static const List<String> _allSkills = [
    'Cleaning',
    'Plumbing',
    'Electrical',
    'Painting',
    'Carpentry',
    'Gardening',
    'AC Repair',
    'Appliance Repair',
    'Others',
  ];

  static const List<String> _experienceOptions = [
    'Less than 1 year',
    '1-2 years',
    '3-5 years',
    '5-10 years',
    '10+ years',
  ];

  late Set<String> _selectedSkills;
  String? _experience;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthState>().user ?? const {};
    final existingSkills = user['skills'];
    _selectedSkills = existingSkills is List
        ? existingSkills.map((e) => e.toString()).toSet()
        : <String>{};
    final existingExp = (user['yearsOfExperience'] ?? '').toString();
    _experience = _experienceOptions.contains(existingExp) ? existingExp : null;
  }

  void _toggleSkill(String skill) {
    setState(() {
      if (_selectedSkills.contains(skill)) {
        _selectedSkills.remove(skill);
      } else {
        _selectedSkills.add(skill);
      }
      if (_error != null) _error = null;
    });
  }

  Future<void> _pickExperience() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Years of Experience',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF101828),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ..._experienceOptions.map(
                (opt) => ListTile(
                  title: Text(opt),
                  trailing: _experience == opt
                      ? const Icon(Icons.check, color: Color(0xFFFF6900))
                      : null,
                  onTap: () => Navigator.pop(sheetCtx, opt),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) {
      setState(() {
        _experience = picked;
        if (_error != null) _error = null;
      });
    }
  }

  Future<void> _completeSetup() async {
    if (_selectedSkills.isEmpty) {
      setState(() => _error = 'Pick at least one skill to continue');
      return;
    }
    if (_experience == null) {
      setState(() => _error = 'Select your years of experience');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<AuthState>().updateProfile({
        'skills': _selectedSkills.toList(),
        'yearsOfExperience': _experience,
      });
      if (!mounted) return;
      // Wizard done — confirm role on /role-chooser before landing on /home.
      // Clear the wizard stack so back from role-chooser doesn't re-enter it.
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/role-chooser',
        (route) => false,
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const _Header(currentStep: 3, totalSteps: 3),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Label('Select Your Skills'),
                    const SizedBox(height: 12),
                    _SkillsGrid(
                      skills: _allSkills,
                      selected: _selectedSkills,
                      onToggle: _toggleSkill,
                    ),
                    const SizedBox(height: 24),
                    const _Label('Years of Experience'),
                    const SizedBox(height: 8),
                    _ExperienceDropdown(
                      value: _experience,
                      onTap: _pickExperience,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFDC2626),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _CompleteSetupButton(
                loading: _saving,
                onTap: _saving ? null : _completeSetup,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  const _Header({required this.currentStep, required this.totalSteps});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
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
          Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      } else {
                        // Reached here directly (e.g. role-chooser cleared
                        // the wizard stack before landing back on this
                        // step). Step back to step 2 instead of skipping
                        // straight past it to onboarding.
                        Navigator.pushReplacementNamed(
                          context,
                          '/profile-setup/address',
                        );
                      }
                    },
                    child: const Icon(
                      Icons.arrow_back,
                      size: 24,
                      color: Color(0xFF101828),
                    ),
                  ),
                ),
              ),
              const Expanded(
                child: Text(
                  'Setup Profile',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF101828),
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: 40),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: List.generate(totalSteps, (i) {
              final filled = i < currentStep;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i == totalSteps - 1 ? 0 : 8),
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: filled
                          ? const Color(0xFFFF6900)
                          : const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: Color(0xFF364153),
        height: 1.5,
      ),
    );
  }
}

class _SkillsGrid extends StatelessWidget {
  final List<String> skills;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  const _SkillsGrid({
    required this.skills,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: skills.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 50,
      ),
      itemBuilder: (_, i) {
        final skill = skills[i];
        final isSelected = selected.contains(skill);
        return _SkillChip(
          label: skill,
          selected: isSelected,
          onTap: () => onToggle(skill),
        );
      },
    );
  }
}

class _SkillChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SkillChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFFFEDD4) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFFEDD4) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? const Color(0xFFFF6900)
                  : const Color(0xFFE5E7EB),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: selected
                  ? const Color(0xFFFF6900)
                  : const Color(0xFF364153),
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _ExperienceDropdown extends StatelessWidget {
  final String? value;
  final VoidCallback onTap;

  const _ExperienceDropdown({required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.isNotEmpty;
    return Material(
      color: const Color(0xFFF3F4F6),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  hasValue ? value! : 'Select experience',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: hasValue
                        ? const Color(0xFF101828)
                        : const Color(0xFF364153),
                    height: 1.5,
                  ),
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down,
                size: 22,
                color: Color(0xFF364153),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompleteSetupButton extends StatelessWidget {
  final bool loading;
  final VoidCallback? onTap;
  const _CompleteSetupButton({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
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
                  'Complete Setup',
                  style: TextStyle(
                    color: Color(0xFFFF6900),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                  ),
                ),
        ),
      ),
    );
  }
}
