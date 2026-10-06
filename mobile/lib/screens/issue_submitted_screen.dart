import 'package:flutter/material.dart';

/// What was just filed.
class IssueSubmittedArgs {
  final String jobTitle;
  final String code;
  const IssueSubmittedArgs({required this.jobTitle, this.code = ''});
}

/// Need Help, final step — confirmation.
///
/// The only way out is Back to Job History, and it clears the Need Help
/// screens from the stack. Swiping back into a form that has already been
/// submitted would invite a second identical report.
class IssueSubmittedScreen extends StatelessWidget {
  const IssueSubmittedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final raw = ModalRoute.of(context)?.settings.arguments;
    final args = raw is IssueSubmittedArgs
        ? raw
        : const IssueSubmittedArgs(jobTitle: '');

    void backToHistory() => Navigator.pushNamedAndRemoveUntil(
      context,
      '/my-services',
      (route) => route.settings.name == '/home' || route.isFirst,
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) backToHistory();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6F8),
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          foregroundColor: const Color(0xFF101828),
          elevation: 0,
          scrolledUnderElevation: 0.5,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: backToHistory,
          ),
          title: const Text(
            'Issue Submitted',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101828),
            ),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              Container(
                width: 82,
                height: 82,
                decoration: const BoxDecoration(
                  color: Color(0xFFDCFCE7),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.check_circle_outline,
                  size: 46,
                  color: Color(0xFF16A34A),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Issue Submitted',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF101828),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Your service issue has been submitted successfully.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Our team will review it and get back to you.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 26),
              if (args.jobTitle.trim().isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'SERVICE',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: Color(0xFF60A5FA),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        args.jobTitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                      // The reference is what support asks for on the
                      // phone, so it belongs on the one screen the user
                      // is looking at when they think to write it down.
                      if (args.code.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Reference ${args.code}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF60A5FA),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: backToHistory,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF364153),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Back to Job History',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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
