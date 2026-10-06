import 'package:flutter/material.dart';

import '../api/home_api.dart';

class CancelJobScreen extends StatefulWidget {
  const CancelJobScreen({super.key});

  @override
  State<CancelJobScreen> createState() => _CancelJobScreenState();
}

class _CancelJobScreenState extends State<CancelJobScreen> {
  static const _reasons = [
    'Found another worker',
    'Job no longer needed',
    'Price too high',
    'Worker not responding',
    'Change in schedule',
    'Other reason',
  ];

  String? _jobId;
  String _jobTitle = '';
  String? _selected;
  bool _submitting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_jobId == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map) {
        _jobId = args['id']?.toString();
        _jobTitle = (args['title'] ?? '').toString();
      } else if (args is String) {
        _jobId = args;
      }
    }
  }

  Future<void> _confirm() async {
    if (_selected == null || _submitting || _jobId == null) return;
    setState(() => _submitting = true);
    try {
      await HomeApi.cancelJob(_jobId!, reason: _selected);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Job cancelled')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not cancel: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm = _selected != null && !_submitting;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _Header(
            onBack: _submitting ? null : () => Navigator.maybePop(context),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFE2E2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.cancel_outlined,
                        size: 32,
                        color: Color(0xFFE7000B),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Cancel Job?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF101828),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _jobTitle.isEmpty ? 'This job' : _jobTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF4A5565),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Why are you cancelling?',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF364153),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._reasons.map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ReasonOption(
                        label: r,
                        selected: _selected == r,
                        onTap: _submitting
                            ? null
                            : () => setState(() => _selected = r),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cancellation Policy',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF408EE0),
                            height: 1.4,
                          ),
                        ),
                        SizedBox(height: 8),
                        _PolicyLine('Free cancellation before worker accepts'),
                        SizedBox(height: 4),
                        _PolicyLine('50% refund if cancelled 24hrs before job'),
                        SizedBox(height: 4),
                        _PolicyLine('No refund if cancelled within 24hrs'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: Opacity(
                      opacity: canConfirm ? 1 : 0.5,
                      child: ElevatedButton(
                        onPressed: canConfirm ? _confirm : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFB2C36),
                          disabledBackgroundColor: const Color(0xFFFB2C36),
                          foregroundColor: Colors.white,
                          disabledForegroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Text(
                                'Confirm Cancellation',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.maybePop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF3F4F6),
                        foregroundColor: const Color(0xFF364153),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Keep Job',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
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

class _Header extends StatelessWidget {
  final VoidCallback? onBack;
  const _Header({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF408EE0),
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 1.5,
            offset: Offset(0, 1),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 16,
        16,
        16,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: onBack,
                child: const Icon(
                  Icons.arrow_back,
                  size: 24,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const Expanded(
            child: Text(
              'Cancel Job',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _ReasonOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _ReasonOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFFFF1F2) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFFF1F2) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? const Color(0xFFFB2C36)
                  : const Color(0xFFE5E7EB),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: selected
                        ? const Color(0xFFE7000B)
                        : const Color(0xFF364153),
                    height: 1.5,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle,
                  size: 20,
                  color: Color(0xFFFB2C36),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PolicyLine extends StatelessWidget {
  final String text;
  const _PolicyLine(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      '• $text',
      style: const TextStyle(
        fontSize: 14,
        color: Color(0xFF408EE0),
        height: 1.43,
      ),
    );
  }
}
