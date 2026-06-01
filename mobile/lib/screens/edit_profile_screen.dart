import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../config.dart';
import '../state/auth_state.dart';

/// Figma "Edit Profile" — reached from the pencil icon on the Profile
/// header AND the "Edit Profile" row under Account Settings. Distinct
/// from /profile-setup (the multi-step onboarding wizard) — this is a
/// single scrollable form that edits everything at once and PUTs to
/// /users/me on Save.
///
/// Backend fields we persist via /users/me: name, email, bio, skills,
/// yearsOfExperience. The form also surfaces Hourly Rate, Languages,
/// Resume and Certificates because the Figma includes them, but those
/// fields aren't in the User model — they're sent in the patch and
/// the backend silently ignores anything not on its whitelist (so
/// re-enabling them is purely a backend change). Resume + Certificate
/// upload buttons surface a "coming soon" snackbar since file_picker
/// isn't in pubspec yet.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _experienceCtrl = TextEditingController();
  final _hourlyRateCtrl = TextEditingController();
  final _addSkillCtrl = TextEditingController();
  final _addLanguageCtrl = TextEditingController();
  final _picker = ImagePicker();

  List<String> _skills = [];
  List<String> _languages = [];
  File? _pickedPhoto;
  bool _saving = false;
  bool _uploadingPhoto = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    // First frame: populate from the cached user record so the form
    // shows immediately. didChangeDependencies refines it if AuthState
    // updates while this screen is open.
    WidgetsBinding.instance.addPostFrameCallback((_) => _seedFromUser());
  }

  void _seedFromUser() {
    if (_loaded) return;
    final u = context.read<AuthState>().user ?? const <String, dynamic>{};
    _nameCtrl.text = (u['name'] ?? '').toString();
    _emailCtrl.text = (u['email'] ?? '').toString();
    _bioCtrl.text = (u['bio'] ?? '').toString();
    _experienceCtrl.text = (u['yearsOfExperience'] ?? '').toString();
    final rate = u['hourlyRate'];
    _hourlyRateCtrl.text = rate == null ? '' : rate.toString();
    final s = u['skills'];
    _skills = s is List ? s.whereType<String>().toList() : <String>[];
    final l = u['languages'];
    _languages = l is List ? l.whereType<String>().toList() : <String>[];
    setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _bioCtrl.dispose();
    _experienceCtrl.dispose();
    _hourlyRateCtrl.dispose();
    _addSkillCtrl.dispose();
    _addLanguageCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    if (_uploadingPhoto) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (picked == null) return;
    if (!mounted) return;
    // Capture AuthState before the upload await so we don't use
    // BuildContext across the gap.
    final auth = context.read<AuthState>();
    setState(() {
      _pickedPhoto = File(picked.path);
      _uploadingPhoto = true;
    });
    try {
      await auth.uploadPhoto(picked.path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile photo updated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is ApiException
              ? 'Upload failed: ${e.message}'
              : 'Upload failed: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  void _addSkill() {
    final v = _addSkillCtrl.text.trim();
    if (v.isEmpty) return;
    if (_skills.any((s) => s.toLowerCase() == v.toLowerCase())) {
      _addSkillCtrl.clear();
      return;
    }
    setState(() {
      _skills.add(v);
      _addSkillCtrl.clear();
    });
  }

  void _removeSkill(String s) {
    setState(() => _skills.remove(s));
  }

  void _addLanguage() {
    final v = _addLanguageCtrl.text.trim();
    if (v.isEmpty) return;
    if (_languages.any((l) => l.toLowerCase() == v.toLowerCase())) {
      _addLanguageCtrl.clear();
      return;
    }
    setState(() {
      _languages.add(v);
      _addLanguageCtrl.clear();
    });
  }

  void _removeLanguage(String l) {
    setState(() => _languages.remove(l));
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name is required')),
      );
      return;
    }
    final auth = context.read<AuthState>();
    setState(() => _saving = true);
    try {
      final patch = <String, dynamic>{
        'name': name,
        'email': _emailCtrl.text.trim(),
        'bio': _bioCtrl.text.trim(),
        'skills': _skills,
        'yearsOfExperience': _experienceCtrl.text.trim(),
        // Fields below aren't on the backend whitelist yet; sent for
        // forward-compat — backend silently drops them today.
        'languages': _languages,
      };
      final rate = double.tryParse(_hourlyRateCtrl.text.trim());
      if (rate != null) patch['hourlyRate'] = rate;
      await auth.updateProfile(patch);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is ApiException
              ? 'Save failed: ${e.message}'
              : 'Save failed: $e'),
        ),
      );
      setState(() => _saving = false);
    }
  }

  void _comingSoon(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label upload — coming soon'),
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final remotePhoto = context.watch<AuthState>().user?['photo'] as String?;
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Column(
        children: [
          _Header(
            onBack: () => Navigator.maybePop(context),
            onSave: _save,
            saving: _saving,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              children: [
                _PhotoPicker(
                  pickedFile: _pickedPhoto,
                  remoteUrl: remotePhoto,
                  uploading: _uploadingPhoto,
                  onTap: _pickPhoto,
                ),
                const SizedBox(height: 20),
                _LabelledField(
                  label: 'Name',
                  child: _TextInput(
                    controller: _nameCtrl,
                    hint: 'Full name',
                  ),
                ),
                const SizedBox(height: 16),
                _LabelledField(
                  label: 'Email',
                  child: _TextInput(
                    controller: _emailCtrl,
                    hint: 'name@example.com',
                    keyboardType: TextInputType.emailAddress,
                  ),
                ),
                const SizedBox(height: 16),
                _LabelledField(
                  label: 'Bio',
                  child: _TextInput(
                    controller: _bioCtrl,
                    hint: 'Tell clients about yourself',
                    minLines: 3,
                    maxLines: 5,
                  ),
                ),
                const SizedBox(height: 16),
                _LabelledField(
                  label: 'Experience',
                  child: _TextInput(
                    controller: _experienceCtrl,
                    hint: '5+ years',
                  ),
                ),
                const SizedBox(height: 16),
                _LabelledField(
                  label: 'Hourly Rate (₹)',
                  child: _TextInput(
                    controller: _hourlyRateCtrl,
                    hint: '500',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _ChipsCard(
                  title: 'Skills',
                  items: _skills,
                  chipBg: const Color(0xFFFFEDD4),
                  chipFg: const Color(0xFFFF6900),
                  addButtonColor: const Color(0xFFFF6900),
                  addHint: 'Add a skill',
                  controller: _addSkillCtrl,
                  onAdd: _addSkill,
                  onRemove: _removeSkill,
                ),
                const SizedBox(height: 16),
                _ChipsCard(
                  title: 'Languages',
                  items: _languages,
                  chipBg: const Color(0xFFDBEAFE),
                  chipFg: const Color(0xFF408EE0),
                  addButtonColor: const Color(0xFF408EE0),
                  addHint: 'Add a language',
                  controller: _addLanguageCtrl,
                  onAdd: _addLanguage,
                  onRemove: _removeLanguage,
                ),
                const SizedBox(height: 16),
                _UploadCard(
                  title: 'Resume',
                  buttonLabel: 'Upload Resume (PDF, DOC)',
                  onTap: () => _comingSoon('Resume'),
                ),
                const SizedBox(height: 16),
                _UploadCard(
                  title: 'Certificates',
                  buttonLabel: 'Upload Certificates',
                  onTap: () => _comingSoon('Certificates'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onSave;
  final bool saving;
  const _Header({
    required this.onBack,
    required this.onSave,
    required this.saving,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Color(0xFF408EE0)),
      padding: EdgeInsets.fromLTRB(
        4, MediaQuery.of(context).padding.top + 6, 4, 12,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
            onPressed: onBack,
          ),
          const Expanded(
            child: Center(
              child: Text(
                'Edit Profile',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: saving ? null : onSave,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              disabledForegroundColor: const Color(0x80FFFFFF),
            ),
            child: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _PhotoPicker extends StatelessWidget {
  final File? pickedFile;
  final String? remoteUrl;
  final bool uploading;
  final VoidCallback onTap;

  const _PhotoPicker({
    required this.pickedFile,
    required this.remoteUrl,
    required this.uploading,
    required this.onTap,
  });

  ImageProvider? _provider() {
    if (pickedFile != null) return FileImage(pickedFile!);
    final r = remoteUrl;
    if (r == null || r.isEmpty) return null;
    final url = r.startsWith('http') ? r : '${AppConfig.apiBase}$r';
    return NetworkImage(url);
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider();
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: 92,
            height: 92,
            child: Stack(
              children: [
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    shape: BoxShape.circle,
                    image: provider == null
                        ? null
                        : DecorationImage(
                            image: provider, fit: BoxFit.cover),
                  ),
                  alignment: Alignment.center,
                  child: provider == null
                      ? const Icon(Icons.person,
                          size: 42, color: Color(0xFF9CA3AF))
                      : null,
                ),
                if (uploading)
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Color(0x66000000),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6900),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.photo_camera,
                        size: 14, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onTap,
          child: const Text(
            'Upload Profile Photo',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF6B7280),
            ),
          ),
        ),
      ],
    );
  }
}

class _LabelledField extends StatelessWidget {
  final String label;
  final Widget child;
  const _LabelledField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF101828),
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _TextInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int minLines;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const _TextInput({
    required this.controller,
    required this.hint,
    this.minLines = 1,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: TextField(
        controller: controller,
        minLines: minLines,
        maxLines: maxLines,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        style: const TextStyle(
          fontSize: 14,
          color: Color(0xFF101828),
        ),
        decoration: InputDecoration(
          isCollapsed: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: InputBorder.none,
          hintText: hint,
          hintStyle: const TextStyle(
            fontSize: 14,
            color: Color(0xFF9CA3AF),
          ),
        ),
      ),
    );
  }
}

class _ChipsCard extends StatelessWidget {
  final String title;
  final List<String> items;
  final Color chipBg;
  final Color chipFg;
  final Color addButtonColor;
  final String addHint;
  final TextEditingController controller;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  const _ChipsCard({
    required this.title,
    required this.items,
    required this.chipBg,
    required this.chipFg,
    required this.addButtonColor,
    required this.addHint,
    required this.controller,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
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
          const SizedBox(height: 10),
          if (items.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: items
                  .map((s) => _RemovableChip(
                        label: s,
                        bg: chipBg,
                        fg: chipFg,
                        onRemove: () => onRemove(s),
                      ))
                  .toList(),
            ),
          if (items.isNotEmpty) const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: controller,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => onAdd(),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF101828),
                    ),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: InputBorder.none,
                      hintText: addHint,
                      hintStyle: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 44,
                height: 44,
                child: Material(
                  color: addButtonColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: onAdd,
                    child: const Center(
                      child: Icon(Icons.add,
                          size: 22, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RemovableChip extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final VoidCallback onRemove;

  const _RemovableChip({
    required this.label,
    required this.bg,
    required this.fg,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            behavior: HitTestBehavior.opaque,
            child: Icon(Icons.close, size: 14, color: fg),
          ),
        ],
      ),
    );
  }
}

class _UploadCard extends StatelessWidget {
  final String title;
  final String buttonLabel;
  final VoidCallback onTap;

  const _UploadCard({
    required this.title,
    required this.buttonLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
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
          const SizedBox(height: 10),
          DottedBorder(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    const Icon(Icons.upload_outlined,
                        size: 22, color: Color(0xFF6B7280)),
                    const SizedBox(height: 6),
                    Text(
                      buttonLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lightweight dashed-border box. Pure CustomPaint — keeps us from
/// adding the dotted_border package for one widget.
class DottedBorder extends StatelessWidget {
  final Widget child;
  const DottedBorder({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: child,
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  static const _radius = 10.0;
  static const _dash = 5.0;
  static const _gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD1D5DB)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.6, 0.6, size.width - 1.2, size.height - 1.2),
      const Radius.circular(_radius),
    );
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + _dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
