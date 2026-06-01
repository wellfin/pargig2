import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../api/home_api.dart';
import '../config.dart';
import 'job_completed_screen.dart';

/// Args for Navigator.pushNamed('/complete-job', ...).
class CompleteJobArgs {
  final String jobId;
  final String? jobTitle;
  const CompleteJobArgs({required this.jobId, this.jobTitle});
}

/// Figma "Complete Job" — the worker uploads up to 4 proof-of-
/// completion photos and an optional note, then submits. Submit
/// POSTs /jobs/:id/complete with { photos: [...], note: '...' };
/// the backend stores the proof on the job and issues a 6-digit
/// completion OTP to the jobgiver.
class CompleteJobScreen extends StatefulWidget {
  const CompleteJobScreen({super.key});

  @override
  State<CompleteJobScreen> createState() => _CompleteJobScreenState();
}

class _CompleteJobScreenState extends State<CompleteJobScreen> {
  static const int _maxPhotos = 4;

  CompleteJobArgs? _args;
  final _picker = ImagePicker();
  final _noteCtrl = TextEditingController();

  // Tracks each tile's upload URL (null = empty slot).
  final List<String?> _photos = List.filled(_maxPhotos, null);
  final List<bool> _uploading = List.filled(_maxPhotos, false);

  bool _submitting = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_args != null) return;
    final raw = ModalRoute.of(context)?.settings.arguments;
    if (raw is CompleteJobArgs) {
      setState(() => _args = raw);
    }
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _addPhoto(int slot) async {
    if (_uploading[slot] || _submitting) return;
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (picked == null) return;
    setState(() {
      _uploading[slot] = true;
      _error = null;
    });
    try {
      final url = await HomeApi.uploadJobPhoto(picked.path);
      if (!mounted) return;
      setState(() {
        if (url != null) _photos[slot] = url;
        _uploading[slot] = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading[slot] = false;
        _error = 'Photo upload failed: $e';
      });
    }
  }

  void _removePhoto(int slot) {
    if (_submitting) return;
    setState(() => _photos[slot] = null);
  }

  Future<void> _submit() async {
    final id = _args?.jobId;
    if (id == null || _submitting) return;
    final urls = _photos.whereType<String>().toList();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ApiClient.post('/jobs/$id/complete', {
        'photos': urls,
        'note': _noteCtrl.text.trim(),
      });
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/job-completed',
        (_) => false,
        arguments: JobCompletedArgs(jobId: id),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e is ApiException ? e.message : e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = (_args?.jobTitle ?? '').trim();
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _Header(onBack: () => Navigator.maybePop(context)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              children: [
                Text(
                  title.isEmpty ? 'Complete Job' : title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF101828),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Upload proof of completion',
                  style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Upload Photos',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF101828),
                  ),
                ),
                const SizedBox(height: 10),
                _photoGrid(),
                const SizedBox(height: 22),
                const Text(
                  'Additional Notes (Optional)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF101828),
                  ),
                ),
                const SizedBox(height: 10),
                _noteField(),
                const SizedBox(height: 16),
                const _ProofTipCard(),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                ],
              ],
            ),
          ),
          _bottomBar(),
        ],
      ),
    );
  }

  Widget _photoGrid() {
    return LayoutBuilder(
      builder: (context, c) {
        const cols = 3;
        const gap = 10.0;
        final tile = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: List.generate(_maxPhotos, (i) {
            return SizedBox(
              width: tile,
              height: tile,
              child: _PhotoTile(
                url: _photos[i],
                uploading: _uploading[i],
                onAdd: () => _addPhoto(i),
                onRemove: () => _removePhoto(i),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _noteField() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: TextField(
        controller: _noteCtrl,
        minLines: 3,
        maxLines: 5,
        maxLength: 2000,
        style: const TextStyle(fontSize: 13.5, color: Color(0xFF101828)),
        decoration: const InputDecoration(
          isCollapsed: true,
          counterText: '',
          border: InputBorder.none,
          hintText: 'Any additional details about the completed work...',
          hintStyle: TextStyle(fontSize: 13.5, color: Color(0xFF9CA3AF)),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final hasPhoto = _photos.any((p) => p != null);
    final canSubmit = !_submitting && hasPhoto;
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Color(0xFFE5E7EB), width: 0.8),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: SizedBox(
          height: 52,
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: canSubmit ? _submit : null,
            icon: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFFFF6900),
                      ),
                    ),
                  )
                : const Icon(Icons.upload_outlined,
                    size: 18, color: Color(0xFFFF6900)),
            label: const Text(
              'Submit Completion',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              side: BorderSide(
                color: canSubmit
                    ? const Color(0xFFFF6900)
                    : const Color(0xFFFFC79A),
                width: 1.4,
              ),
              foregroundColor: const Color(0xFFFF6900),
              disabledForegroundColor: const Color(0xFFFFC79A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
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
        8,
        MediaQuery.of(context).padding.top + 8,
        16,
        12,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: Material(
              color: const Color(0x33FFFFFF),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onBack,
                child: const Icon(Icons.arrow_back,
                    size: 18, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'Complete Job',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final String? url;
  final bool uploading;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  const _PhotoTile({
    required this.url,
    required this.uploading,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (uploading) {
      return _frame(
        const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
        ),
      );
    }
    if (url != null) {
      final full = url!.startsWith('http')
          ? url!
          : '${AppConfig.apiBase}$url';
      return _frame(
        Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                full,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Center(
                  child: Icon(Icons.broken_image_outlined,
                      color: Color(0xFF9CA3AF), size: 22),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: Material(
                color: const Color(0xCC000000),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onRemove,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close,
                        size: 14, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
        showBorder: false,
      );
    }
    return InkWell(
      onTap: onAdd,
      borderRadius: BorderRadius.circular(12),
      child: _frame(
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.photo_camera_outlined,
                size: 22, color: Color(0xFF9CA3AF)),
            SizedBox(height: 4),
            Text(
              'Add Photo',
              style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _frame(Widget child, {bool showBorder = true}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: showBorder
            ? Border.all(color: const Color(0xFFE5E7EB), width: 0.8)
            : null,
      ),
      child: child,
    );
  }
}

class _ProofTipCard extends StatelessWidget {
  const _ProofTipCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD9B3), width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: const Text(
        "Photos help build trust and can be used as evidence if there's "
        'any dispute.',
        style: TextStyle(
          fontSize: 12.5,
          color: Color(0xFF7E2A0C),
          height: 1.5,
        ),
      ),
    );
  }
}
