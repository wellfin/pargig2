import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../state/auth_state.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _bio = TextEditingController();
  final _picker = ImagePicker();

  File? _localPhoto;
  bool _uploadingPhoto = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final u = context.read<AuthState>().user ?? {};
    _name.text = (u['name'] ?? '').toString();
    _email.text = (u['email'] ?? '').toString();
    _bio.text = (u['bio'] ?? '').toString();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    Navigator.pop(context);
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked == null) return;
      setState(() {
        _localPhoto = File(picked.path);
        _uploadingPhoto = true;
        _error = null;
      });
      if (!mounted) return;
      await context.read<AuthState>().uploadPhoto(picked.path);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Photo upload failed: $e');
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  void _showPhotoSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take photo'),
                onTap: () => _pickPhoto(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () => _pickPhoto(ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _next() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Full name is required');
      return;
    }
    // Second-line defence on top of the keystroke filter: reject any
    // residual digit (paste-from-clipboard bypasses the formatter on
    // some keyboards) and require at least two consecutive letters
    // so single chars / pure punctuation ("..") can't slip through.
    if (RegExp(r'\d').hasMatch(name)) {
      setState(() => _error = 'Name cannot contain numbers');
      return;
    }
    if (!RegExp(r'[A-Za-zÀ-ɏ]{2,}').hasMatch(name)) {
      setState(() => _error = 'Enter a valid full name');
      return;
    }
    // Profile picture is mandatory. Block until the photo has actually been
    // uploaded to the server — AuthState.uploadPhoto sets user['photo'] on
    // success, so a failed/half-finished upload won't pass.
    if (_uploadingPhoto) {
      setState(() => _error = 'Please wait for your photo to finish uploading');
      return;
    }
    final hasPhoto = (context.read<AuthState>().user?['photo'] ?? '')
        .toString()
        .isNotEmpty;
    if (!hasPhoto) {
      setState(() => _error = 'Profile picture is required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<AuthState>().updateProfile({
        'name': name,
        'email': _email.text.trim(),
        'bio': _bio.text.trim(),
      });
      if (!mounted) return;
      final args = ModalRoute.of(context)?.settings.arguments;
      // pushNamed (not pushReplacement) so the back button on the address
      // step returns here instead of exiting the app.
      Navigator.pushNamed(context, '/profile-setup/address', arguments: args);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final remotePhoto = context.watch<AuthState>().user?['photo'] as String?;
    final remotePhotoUrl = (remotePhoto != null && remotePhoto.isNotEmpty)
        ? (remotePhoto.startsWith('http')
              ? remotePhoto
              : '${AppConfig.apiBase}$remotePhoto')
        : null;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _Header(currentStep: 1, totalSteps: 3),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: _AvatarPicker(
                        localPhoto: _localPhoto,
                        remotePhotoUrl: remotePhotoUrl,
                        uploading: _uploadingPhoto,
                        onTap: _showPhotoSheet,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text(
                        'Profile Photo *',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF101828),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _FieldLabel('Full Name *'),
                    const SizedBox(height: 8),
                    _FilledInput(
                      controller: _name,
                      hint: 'Enter your full name',
                      keyboardType: TextInputType.name,
                      // Reject digits / symbols at the keystroke
                      // level so a user can't type a phone number
                      // into the Name field. Allows letters (incl.
                      // accented), spaces, dots, apostrophes and
                      // hyphens — enough for "Mary-Jane" or
                      // "D'Souza", but not for "9876543210".
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r"[A-Za-zÀ-ɏ .'\-]"),
                        ),
                        LengthLimitingTextInputFormatter(60),
                      ],
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
                    ),
                    const SizedBox(height: 24),
                    _FieldLabel('Email(Optional)'),
                    const SizedBox(height: 8),
                    _FilledInput(
                      controller: _email,
                      hint: 'your.email@example.com',
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 24),
                    _FieldLabel('Bio'),
                    const SizedBox(height: 8),
                    _FilledInput(
                      controller: _bio,
                      hint: 'Tell us about yourself...',
                      maxLines: 4,
                      minHeight: 104,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFDC2626),
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: _NextButton(
                loading: _saving,
                onTap: _saving ? null : _next,
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
                        // Reached here directly (e.g. the app resumed onto
                        // this step for a half-finished signup, so there's
                        // nothing to pop). Back steps to the mobile / OTP
                        // screen so the user can re-do that step.
                        Navigator.pushReplacementNamed(context, '/login');
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

class _AvatarPicker extends StatelessWidget {
  final File? localPhoto;
  final String? remotePhotoUrl;
  final bool uploading;
  final VoidCallback onTap;

  const _AvatarPicker({
    required this.localPhoto,
    required this.remotePhotoUrl,
    required this.uploading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 112,
      height: 112,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 112,
            height: 112,
            decoration: const BoxDecoration(
              color: Color(0xFFF3F4F6),
              shape: BoxShape.circle,
            ),
            clipBehavior: Clip.antiAlias,
            child: _photoOrPlaceholder(),
          ),
          if (uploading)
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0x55000000),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            right: -4,
            bottom: -4,
            child: Material(
              color: const Color(0xFFFF6900),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: const SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(
                    Icons.photo_camera,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoOrPlaceholder() {
    if (localPhoto != null) {
      return Image.file(localPhoto!, fit: BoxFit.cover);
    }
    if (remotePhotoUrl != null) {
      return Image.network(
        remotePhotoUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => const Center(
    child: Icon(
      Icons.photo_camera_outlined,
      size: 40,
      color: Color(0xFF9CA3AF),
    ),
  );
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

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

class _FilledInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final int maxLines;
  final double? minHeight;
  final ValueChanged<String>? onChanged;
  final List<TextInputFormatter>? inputFormatters;

  const _FilledInput({
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.maxLines = 1,
    this.minHeight,
    this.onChanged,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(16),
      ),
      constraints: BoxConstraints(minHeight: minHeight ?? 56),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        onChanged: onChanged,
        inputFormatters: inputFormatters,
        style: const TextStyle(
          fontSize: 16,
          color: Color(0xFF1A1A1A),
          height: 1.5,
        ),
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0x801A1A1A), fontSize: 16),
        ),
      ),
    );
  }
}

class _NextButton extends StatelessWidget {
  final bool loading;
  final VoidCallback? onTap;
  const _NextButton({required this.loading, required this.onTap});

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
                  'Next',
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
