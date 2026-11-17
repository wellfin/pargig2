import 'package:flutter/material.dart';

/// One FAQ answer, on its own screen.
///
/// The Help Center used to open answers in place, which is fine for a
/// one-line reply and poor for the ones that run to a paragraph: the
/// list jumps under your thumb as a row grows, and a long answer pushes
/// everything below it off the screen. A full screen gives the answer
/// the whole width, keeps the reader's place, and makes Back mean one
/// obvious thing.
///
/// Content only — no network call. Everything here was passed in by the
/// Help Center, which holds the catalogue, so this screen works with no
/// connection at all. That is deliberate: someone who cannot reach the
/// server is exactly the person who needs the help screen.
class HelpArticleArgs {
  /// The question, shown as the article title.
  final String title;

  /// The full answer.
  final String body;

  /// Which category it came from, shown as a small label above the
  /// title so a reader arriving from a search still knows where they
  /// are. Null when the caller has no category to give.
  final String? category;
  final IconData? categoryIcon;
  final Color? categoryColor;
  final Color? categoryBg;

  const HelpArticleArgs({
    required this.title,
    required this.body,
    this.category,
    this.categoryIcon,
    this.categoryColor,
    this.categoryBg,
  });
}

class HelpArticleScreen extends StatelessWidget {
  const HelpArticleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;

    // Reached without arguments — a deep link, or a hot reload that lost
    // them. Say so plainly rather than rendering an empty page.
    if (args is! HelpArticleArgs) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F6F8),
        appBar: AppBar(
          backgroundColor: const Color(0xFF3B5BA9),
          foregroundColor: Colors.white,
          title: const Text('Help'),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'That article could not be opened. Go back to the Help '
              'Center and pick it from the list.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: Column(
        children: [
          _ArticleHeader(category: args.category),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (args.category != null) ...[
                        _CategoryChip(
                          label: args.category!,
                          icon: args.categoryIcon,
                          color: args.categoryColor,
                          background: args.categoryBg,
                        ),
                        const SizedBox(height: 14),
                      ],
                      Text(
                        args.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF101828),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: Color(0xFFF1F3F5),
                      ),
                      const SizedBox(height: 14),
                      // 1.65 line height and 15px: this is the one screen
                      // in the app meant to be read rather than scanned.
                      Text(
                        args.body,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Color(0xFF374151),
                          height: 1.65,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _DidThisHelp(
                  onContact: () =>
                      Navigator.pushNamed(context, '/my-services'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ArticleHeader extends StatelessWidget {
  final String? category;

  const _ArticleHeader({this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF3B5BA9),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                tooltip: 'Back',
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0x33FFFFFF),
                  minimumSize: const Size(40, 40),
                ),
              ),
              Expanded(
                child: Text(
                  category ?? 'Help Center',
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              // Balances the back button so the title sits centred.
              const SizedBox(width: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? color;
  final Color? background;

  const _CategoryChip({
    required this.label,
    this.icon,
    this.color,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final fg = color ?? const Color(0xFF3B5BA9);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background ?? const Color(0xFFE8EEFC),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// Closes the article with the one thing a reader who is still stuck
/// needs: a way out. Support is raised against a job, so it goes to the
/// same place every other "talk to us" in the app goes.
class _DidThisHelp extends StatelessWidget {
  final VoidCallback onContact;

  const _DidThisHelp({required this.onContact});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4EC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Did this answer your question?',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101828),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'If something is still unclear, raise it against the job and '
            'we will pick it up from there.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF6B5B4D),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onContact,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6900),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Contact Support',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
