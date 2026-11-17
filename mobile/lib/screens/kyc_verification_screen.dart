import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../state/auth_state.dart';

/// Identity verification.
///
/// What this screen is allowed to claim is bounded by what the backend
/// actually does, which is this and no more: a user sends a document,
/// an admin approves or rejects it in the panel with a remark, and an
/// approval sets isVerifiedProfessional and the "verified" badge.
///
/// So the copy here says verification is OPTIONAL, because nothing in
/// the codebase blocks an unverified user from posting a job, accepting
/// one, or being paid. It does not say Aadhaar is required, because no
/// code requires it — the document type is a free choice among five,
/// and the server stores an unrecognised one as 'other' rather than
/// refusing it. If that ever changes, this screen has to change with it.
///
/// Two steps from the written flow are deliberately not invented here:
/// there is no selfie capture and no separate verification OTP, because
/// neither exists in the backend. The mobile number IS already verified
/// — by the OTP at login — so that step is shown as done, truthfully,
/// rather than asked for again.
class KycVerificationScreen extends StatefulWidget {
  const KycVerificationScreen({super.key});

  @override
  State<KycVerificationScreen> createState() => _KycVerificationScreenState();
}

/// The five values backend/models/userModel.js documentSchema accepts.
/// Kept in this order so the list reads from the most commonly held
/// document downwards.
const _docTypes = <_DocType>[
  _DocType('aadhaar', 'Aadhaar card', Icons.badge_outlined),
  _DocType('pan', 'PAN card', Icons.credit_card_outlined),
  _DocType('license', 'Driving licence', Icons.directions_car_outlined),
  _DocType(
    'certification',
    'Skill certificate',
    Icons.workspace_premium_outlined,
  ),
  _DocType('other', 'Something else', Icons.description_outlined),
];

class _DocType {
  final String value;
  final String label;
  final IconData icon;
  const _DocType(this.value, this.label, this.icon);
}

class _KycVerificationScreenState extends State<KycVerificationScreen> {
  final _picker = ImagePicker();

  String _type = 'aadhaar';
  File? _picked;
  bool _uploading = false;
  bool _refreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // A decision made in the panel never reaches the handset on its own,
    // so the status is re-read every time this screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh(quiet: true));
  }

  Future<void> _refresh({bool quiet = false}) async {
    if (!quiet) setState(() => _refreshing = true);
    try {
      await context.read<AuthState>().refreshUser();
    } catch (_) {
      // A failed refresh leaves the last known status on screen, which
      // is better than an error where a status used to be.
    } finally {
      if (mounted && !quiet) setState(() => _refreshing = false);
    }
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final x = await _picker.pickImage(
        source: source,
        // The server caps uploads at 10 MB. A modern phone camera can
        // clear that on one shot, so it is shrunk before it is sent
        // rather than being refused after the upload has run.
        maxWidth: 1800,
        imageQuality: 85,
      );
      if (x == null) return;
      setState(() {
        _picked = File(x.path);
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Could not open that: $e');
    }
  }

  Future<void> _submit() async {
    final file = _picked;
    if (file == null) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      await context.read<AuthState>().uploadDocument(
        type: _type,
        filePath: file.path,
      );
      if (!mounted) return;
      setState(() {
        _picked = null;
        _uploading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sent for review')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = 'Could not send it: $e';
      });
    }
  }

  void _sheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pick(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pick(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final user = auth.user ?? const {};
    final verified = user['isVerifiedProfessional'] == true;

    final docs = (user['documents'] is List)
        ? List<Map<String, dynamic>>.from(
            (user['documents'] as List)
                .whereType<Map>()
                .map((d) => Map<String, dynamic>.from(d)),
          )
        : <Map<String, dynamic>>[];
    // Newest first: the one that decides the current state is the one
    // sent last, and it should not be at the bottom of a long list.
    docs.sort(
      (a, b) => (b['uploadedAt'] ?? '').toString().compareTo(
        (a['uploadedAt'] ?? '').toString(),
      ),
    );

    final hasPending = docs.any((d) => d['status'] == 'pending');
    final latestRejected = docs.isNotEmpty && docs.first['status'] == 'rejected'
        ? docs.first
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF3B5BA9),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'KYC Verification',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            onPressed: _refreshing ? null : () => _refresh(),
            tooltip: 'Check status',
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(quiet: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _StatusBanner(
              verified: verified,
              pending: hasPending,
              rejected: latestRejected,
            ),
            const SizedBox(height: 16),

            if (!verified) ...[
              const _WhyPanel(),
              const SizedBox(height: 16),
            ],

            // Nothing more to ask for once a document is approved or is
            // sitting with a reviewer. Showing the form anyway would
            // invite a second upload that changes nothing.
            if (!verified && !hasPending) ...[
              _SubmitPanel(
                types: _docTypes,
                selected: _type,
                onType: (v) => setState(() => _type = v),
                picked: _picked,
                onPick: _sheet,
                onClear: () => setState(() => _picked = null),
                onSubmit: _picked == null || _uploading ? null : _submit,
                uploading: _uploading,
                error: _error,
              ),
              const SizedBox(height: 16),
            ],

            if (docs.isNotEmpty) _HistoryPanel(docs: docs),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ status

class _StatusBanner extends StatelessWidget {
  final bool verified;
  final bool pending;
  final Map<String, dynamic>? rejected;

  const _StatusBanner({
    required this.verified,
    required this.pending,
    required this.rejected,
  });

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color fg;
    late final IconData icon;
    late final String title;
    late final String body;

    if (verified) {
      bg = const Color(0xFFDCFCE7);
      fg = const Color(0xFF087443);
      icon = Icons.verified_rounded;
      title = 'Identity verified';
      body =
          'A Verified badge now shows on your profile, so people can see '
          'your identity was checked.';
    } else if (pending) {
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFF92610A);
      icon = Icons.hourglass_top_rounded;
      title = 'Under review';
      body =
          'Your document has reached our team. Reviews are done by a '
          'person, so this usually takes a day or two. Pull down to check '
          'for an update — we cannot notify you yet.';
    } else if (rejected != null) {
      bg = const Color(0xFFFEE2E2);
      fg = const Color(0xFF9F1239);
      icon = Icons.error_outline_rounded;
      title = 'Not accepted';
      final remark = (rejected!['remark'] ?? '').toString().trim();
      body = remark.isEmpty
          ? 'That document could not be accepted. You can send another one '
                'below.'
          : 'Reason given: $remark\n\nYou can send another one below.';
    } else {
      bg = const Color(0xFFE8EEFC);
      fg = const Color(0xFF2B4B91);
      icon = Icons.shield_outlined;
      title = 'Not verified yet';
      body =
          'Verification is optional. You can post jobs, accept work and be '
          'paid without it — it adds a Verified badge that tells the other '
          'side your identity was checked.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 13,
                    color: fg.withValues(alpha: 0.92),
                    height: 1.5,
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

// ------------------------------------------------------------ why/how

class _WhyPanel extends StatelessWidget {
  const _WhyPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How it works',
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101828),
            ),
          ),
          SizedBox(height: 14),
          _Step(
            n: '1',
            text: 'Your mobile number is already verified — that was the '
                'OTP you entered when you signed in.',
            done: true,
          ),
          _Step(
            n: '2',
            text: 'Pick one document that shows your name, and photograph '
                'it or choose a photo you already have.',
          ),
          _Step(
            n: '3',
            text: 'Send it. Our team checks it by hand.',
          ),
          _Step(
            n: '4',
            text: 'Come back here for the result. If it is not accepted '
                'you will see the reason and can send another.',
            last: true,
          ),
          SizedBox(height: 14),
          Text(
            'Make sure the whole document is in frame and the text is '
            'readable — a blurred or cropped photo is the usual reason '
            'one is sent back.',
            style: TextStyle(
              fontSize: 12.5,
              color: Color(0xFF6B7280),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String n;
  final String text;
  final bool done;
  final bool last;

  const _Step({
    required this.n,
    required this.text,
    this.done = false,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: done ? const Color(0xFFDCFCE7) : const Color(0xFFE8EEFC),
              shape: BoxShape.circle,
            ),
            child: done
                ? const Icon(Icons.check, size: 13, color: Color(0xFF087443))
                : Text(
                    n,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2B4B91),
                    ),
                  ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13.5,
                color: Color(0xFF374151),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ submit

class _SubmitPanel extends StatelessWidget {
  final List<_DocType> types;
  final String selected;
  final ValueChanged<String> onType;
  final File? picked;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final VoidCallback? onSubmit;
  final bool uploading;
  final String? error;

  const _SubmitPanel({
    required this.types,
    required this.selected,
    required this.onType,
    required this.picked,
    required this.onPick,
    required this.onClear,
    required this.onSubmit,
    required this.uploading,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Which document are you sending?',
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101828),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Any one of these is fine — pick whichever you have to hand.',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 14),
          ...types.map(
            (t) => _TypeRow(
              type: t,
              selected: t.value == selected,
              onTap: () => onType(t.value),
            ),
          ),
          const SizedBox(height: 16),
          if (picked == null)
            _PickButton(onTap: onPick)
          else
            _Preview(file: picked!, onReplace: onPick, onClear: onClear),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(
              error!,
              style: const TextStyle(fontSize: 13, color: Color(0xFFB91C1C)),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B5BA9),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFD1D5DB),
                disabledForegroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: uploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Submit for verification',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Your document is visible only to the Pargig team reviewing '
            'it. It is never shown to job givers or workers.',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7280),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeRow extends StatelessWidget {
  final _DocType type;
  final bool selected;
  final VoidCallback onTap;

  const _TypeRow({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFF2F6FF) : Colors.white,
            border: Border.all(
              color: selected
                  ? const Color(0xFF3B5BA9)
                  : const Color(0xFFE5E7EB),
              width: selected ? 1.6 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                type.icon,
                size: 20,
                color: selected
                    ? const Color(0xFF3B5BA9)
                    : const Color(0xFF6B7280),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  type.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: const Color(0xFF1B2431),
                  ),
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected
                    ? const Color(0xFF3B5BA9)
                    : const Color(0xFFD1D5DB),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickButton extends StatelessWidget {
  final VoidCallback onTap;

  const _PickButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 26),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          border: Border.all(color: const Color(0xFFD1D5DB)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          children: [
            Icon(
              Icons.add_a_photo_outlined,
              size: 26,
              color: Color(0xFF6B7280),
            ),
            SizedBox(height: 8),
            Text(
              'Add a photo of the document',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  final File file;
  final VoidCallback onReplace;
  final VoidCallback onClear;

  const _Preview({
    required this.file,
    required this.onReplace,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            file,
            width: double.infinity,
            height: 190,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onReplace,
                child: const Text('Replace'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: onClear,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB91C1C),
                ),
                child: const Text('Remove'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ----------------------------------------------------------- history

class _HistoryPanel extends StatelessWidget {
  final List<Map<String, dynamic>> docs;

  const _HistoryPanel({required this.docs});

  static const _labels = {
    'aadhaar': 'Aadhaar card',
    'pan': 'PAN card',
    'license': 'Driving licence',
    'certification': 'Skill certificate',
    'other': 'Document',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What you have sent',
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101828),
            ),
          ),
          const SizedBox(height: 12),
          ...docs.map((d) {
            final status = (d['status'] ?? 'pending').toString();
            final remark = (d['remark'] ?? '').toString().trim();
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _labels[d['type']] ?? 'Document',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1B2431),
                          ),
                        ),
                      ),
                      _StatusChip(status: status),
                    ],
                  ),
                  Text(
                    _when(d['uploadedAt']),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                  if (remark.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      remark,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF6B7280),
                        height: 1.45,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  static String _when(dynamic raw) {
    final d = DateTime.tryParse((raw ?? '').toString())?.toLocal();
    if (d == null) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return 'Sent ${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color fg;
    late final String label;
    switch (status) {
      case 'approved':
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF087443);
        label = 'Approved';
        break;
      case 'rejected':
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFF9F1239);
        label = 'Not accepted';
        break;
      default:
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFF92610A);
        label = 'Under review';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}
