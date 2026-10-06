import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../api/issues_api.dart';
import 'issue_submitted_screen.dart' show IssueSubmittedArgs;

/// What the describe step is being filled in for.
class DescribeIssueArgs {
  final String jobId;
  final String jobTitle;
  final IssueType issueType;
  const DescribeIssueArgs({
    required this.jobId,
    required this.jobTitle,
    required this.issueType,
  });
}

const _kMinChars = 10;
const _kMaxChars = 500;
const _kMaxPhotos = 5;

/// Need Help, step 2 — what specifically happened, in their words.
///
/// Submit stays disabled until the description clears the minimum, so
/// the rule is visible before the tap rather than as a rejection after
/// it. The same floor is enforced on the server.
class NeedHelpDescribeScreen extends StatefulWidget {
  const NeedHelpDescribeScreen({super.key});

  @override
  State<NeedHelpDescribeScreen> createState() => _NeedHelpDescribeScreenState();
}

class _NeedHelpDescribeScreenState extends State<NeedHelpDescribeScreen> {
  final _picker = ImagePicker();
  final _controller = TextEditingController();

  DescribeIssueArgs? _args;
  final Set<String> _picked = {};

  /// Local file paths of photos chosen but not yet uploaded. Uploading
  /// only on submit means a user who backs out costs nothing.
  final List<String> _photos = [];

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_args != null) return;
    final raw = ModalRoute.of(context)?.settings.arguments;
    if (raw is DescribeIssueArgs) _args = raw;
  }

  int get _len => _controller.text.trim().length;
  bool get _longEnough => _len >= _kMinChars;

  Future<void> _addPhoto() async {
    if (_photos.length >= _kMaxPhotos) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a Photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final file = await _picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1600,
      );
      if (file == null || !mounted) return;
      setState(() => _photos.add(file.path));
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.code == 'camera_access_denied'
            ? 'Camera permission is off. Turn it on for Pargig in your '
                  'phone settings.'
            : 'Could not open the camera on this device.';
      });
    }
  }

  Future<void> _submit() async {
    final args = _args;
    if (args == null || _busy || !_longEnough) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Photos upload first: an issue recorded without the evidence it
      // claims is worse than one that failed outright.
      final urls = <String>[];
      for (final path in _photos) {
        final url = await IssuesApi.uploadPhoto(path);
        if (url != null && url.isNotEmpty) urls.add(url);
      }

      final issue = await IssuesApi.submit(
        jobId: args.jobId,
        issueType: args.issueType.value,
        description: _controller.text.trim(),
        subIssues: _picked.toList(),
        photos: urls,
      );
      if (!mounted) return;
      await Navigator.pushReplacementNamed(
        context,
        '/issue-submitted',
        arguments: IssueSubmittedArgs(
          jobTitle: args.jobTitle,
          code: (issue['code'] ?? '').toString(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is ApiException ? e.message : e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = _args;
    if (args == null) {
      return const Scaffold(body: Center(child: Text('Nothing to report')));
    }
    final subIssues = kSubIssues[args.issueType.value] ?? const <String>[];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: const Color(0xFF101828),
        elevation: 0,
        scrolledUnderElevation: 0.5,
        titleSpacing: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Need Help',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF101828),
              ),
            ),
            Text(
              'Describe the Issue',
              style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          _SelectedIssueCard(type: args.issueType),
          if (subIssues.isNotEmpty) ...[
            const SizedBox(height: 16),
            const _Label('WHAT SPECIFICALLY HAPPENED?'),
            const SizedBox(height: 8),
            for (final s in subIssues)
              _CheckRow(
                label: s,
                checked: _picked.contains(s),
                onTap: () => setState(() {
                  if (!_picked.remove(s)) _picked.add(s);
                }),
              ),
          ],
          const SizedBox(height: 18),
          const Text(
            'Tell us what happened',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101828),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: TextField(
              controller: _controller,
              maxLines: 6,
              maxLength: _kMaxChars,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Please describe the issue in detail...',
                hintStyle: TextStyle(fontSize: 13.5, color: Color(0xFFB0B7C3)),
                border: InputBorder.none,
                counterText: '',
              ),
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: Color(0xFF101828),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _longEnough
                    ? const Row(
                        children: [
                          Icon(Icons.check, size: 13, color: Color(0xFF16A34A)),
                          SizedBox(width: 4),
                          Text(
                            'Good detail',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF16A34A),
                            ),
                          ),
                        ],
                      )
                    : Text(
                        'Minimum $_kMinChars characters',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
              ),
              Text(
                '$_len/$_kMaxChars',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF9CA3AF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Add Photos',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF101828),
                  ),
                ),
              ),
              const Text(
                'Optional',
                style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Add photos as evidence to help us understand the issue better.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: Color(0xFF9CA3AF),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < _photos.length; i++)
                _PhotoThumb(
                  path: _photos[i],
                  onRemove: () => setState(() => _photos.removeAt(i)),
                ),
              if (_photos.length < _kMaxPhotos) _AddPhotoTile(onTap: _addPhoto),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Text(
                _error!,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: Color(0xFFDC2626),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: _longEnough && !_busy ? _submit : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                disabledBackgroundColor: const Color(0xFFCBD5E1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Submit Issue',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- pieces

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 2),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        color: Color(0xFF9CA3AF),
      ),
    ),
  );
}

class _SelectedIssueCard extends StatelessWidget {
  final IssueType type;
  const _SelectedIssueCard({required this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEDEFF3)),
      ),
      child: Row(
        children: [
          Icon(type.icon, size: 19, color: type.iconColor),
          const SizedBox(width: 11),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Selected Issue',
                style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
              ),
              const SizedBox(height: 2),
              Text(
                type.title,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF101828),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final String label;
  final bool checked;
  final VoidCallback onTap;
  const _CheckRow({
    required this.label,
    required this.checked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
          child: Row(
            children: [
              Container(
                width: 19,
                height: 19,
                decoration: BoxDecoration(
                  color: checked ? const Color(0xFF2563EB) : Colors.white,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: checked
                        ? const Color(0xFF2563EB)
                        : const Color(0xFFCBD5E1),
                    width: 1.4,
                  ),
                ),
                child: checked
                    ? const Icon(Icons.check, size: 13, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 11),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  final VoidCallback onTap;
  const _AddPhotoTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 74,
        height: 74,
        decoration: BoxDecoration(
          color: const Color(0xFFF0F6FF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFF93B4F5),
            style: BorderStyle.solid,
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 19, color: Color(0xFF2563EB)),
            SizedBox(height: 2),
            Text(
              'Add Photo',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2563EB),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  final String path;
  final VoidCallback onRemove;
  const _PhotoThumb({required this.path, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 74,
      height: 74,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              File(path),
              width: 74,
              height: 74,
              fit: BoxFit.cover,
              // The file is on this device and was just picked, so a
              // failure here means it was moved or deleted underneath us.
              errorBuilder: (_, _, _) => Container(
                width: 74,
                height: 74,
                color: const Color(0xFFF3F4F6),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.broken_image_outlined,
                  size: 18,
                  color: Color(0xFF9CA3AF),
                ),
              ),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: InkWell(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Color(0xCC101828),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 12, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
