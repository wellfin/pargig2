import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import 'help_article_screen.dart';

/// Help Center — reached from Profile › Help & Support › Help Center.
///
/// Everything on this screen is answered offline. Someone who cannot
/// reach the server, or whose login is the thing that is broken, is
/// exactly the person who needs help, so the answers ship with the app
/// rather than coming from an endpoint.
///
/// The questions are real and the answers describe what this app
/// actually does. Where the Figma showed a view count under each
/// question ("1234 views") there is none here: the app does not count
/// them, and a made-up number tells the reader something untrue about
/// which answers other people found useful.
class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_Section> get _results {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _catalogue;
    final out = <_Section>[];
    for (final section in _catalogue) {
      final hits = section.items
          .where(
            (i) =>
                i.question.toLowerCase().contains(q) ||
                i.answer.toLowerCase().contains(q),
          )
          .toList();
      if (hits.isNotEmpty) {
        out.add(
          _Section(
            title: section.title,
            icon: section.icon,
            iconBg: section.iconBg,
            iconColor: section.iconColor,
            items: hits,
          ),
        );
      }
    }
    return out;
  }

  /// The Chat tile. Opens the user's one thread with the support
  /// desk — a real conversation that persists, not a form.
  ///
  /// This used to land on /my-services, on the reasoning that support
  /// is always about a job. It is not: "how do I change my number" has
  /// no job to file it under, and sending that person to a list of
  /// their jobs asked them to pick one at random before they could
  /// speak to anybody.
  void _openChat() => Navigator.pushNamed(context, '/support-chat');

  /// The orange Contact Support button, and the Call tile. Both open
  /// the phone's dialler on AppConfig.supportPhone.
  ///
  /// That number is a placeholder today — see the warning on the
  /// constant. Until it is replaced, this button opens a dialler onto
  /// a line that does not answer, which is why the card beside it also
  /// offers the chat.
  Future<void> _callSupport() async {
    final phone = AppConfig.supportPhone.trim();
    if (phone.isEmpty) {
      // No desk to ring. Say so rather than opening an empty dialler.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No support number is set up yet. Use Chat instead.'),
        ),
      );
      return;
    }
    await _launch(
      // Strip spaces, hyphens and brackets — the dialler takes digits
      // and a leading +, and chokes on the rest.
      Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+]'), '')),
      'No dialler available on this phone',
    );
  }

  /// Every route into an answer ends here — tapping a row under a
  /// category and tapping a search result both open the same screen,
  /// so there is one article view to get right rather than two.
  void _openArticle(_Section section, _Faq item) {
    Navigator.pushNamed(
      context,
      '/help-article',
      arguments: HelpArticleArgs(
        title: item.question,
        body: item.answer,
        category: section.title,
        categoryIcon: section.icon,
        categoryColor: section.iconColor,
        categoryBg: section.iconBg,
      ),
    );
  }

  Future<void> _launch(Uri uri, String failureMessage) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sections = _results;
    final phone = AppConfig.supportPhone.trim();
    final email = AppConfig.supportEmail.trim();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: Column(
        children: [
          _Header(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                _QuickActions(
                  onChat: _openChat,
                  onCall: phone.isEmpty ? null : _callSupport,
                  onEmail: email.isEmpty
                      ? null
                      : () => _launch(
                          Uri(scheme: 'mailto', path: email),
                          'No email app set up on this phone',
                        ),
                ),
                const SizedBox(height: 18),
                if (sections.isEmpty)
                  const _NoResults()
                else
                  ...sections.map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _SectionCard(
                        section: s,
                        onOpen: (item) => _openArticle(s, item),
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                _StillNeedHelp(onCall: _callSupport, onChat: _openChat),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- header

class _Header extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _Header({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF3B5BA9),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
          child: Column(
            children: [
              Row(
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
                  const Expanded(
                    child: Text(
                      'Help Center',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  // Balances the back button so the title sits centred.
                  const SizedBox(width: 40),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'How can we help you today?',
                style: TextStyle(fontSize: 13.5, color: Color(0xFFD6E0F5)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search for help…',
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 20,
                    color: Color(0xFF6B7280),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide.none,
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

// -------------------------------------------------------- quick actions

class _QuickActions extends StatelessWidget {
  final VoidCallback onChat;
  // Null hides the tile — see AppConfig.supportPhone / supportEmail.
  final VoidCallback? onCall;
  final VoidCallback? onEmail;

  const _QuickActions({
    required this.onChat,
    required this.onCall,
    required this.onEmail,
  });

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      _ActionTile(
        icon: Icons.chat_bubble_outline,
        bg: const Color(0xFFE8EEFC),
        fg: const Color(0xFF3B5BA9),
        label: 'Chat',
        onTap: onChat,
      ),
      if (onCall != null)
        _ActionTile(
          icon: Icons.call_outlined,
          bg: const Color(0xFFE3F5E8),
          fg: const Color(0xFF16A34A),
          label: 'Call',
          onTap: onCall!,
        ),
      if (onEmail != null)
        _ActionTile(
          icon: Icons.mail_outline,
          bg: const Color(0xFFF1E9FB),
          fg: const Color(0xFF8B5CF6),
          label: 'Email',
          onTap: onEmail!,
        ),
    ];

    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: tiles[i]),
        ],
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color bg;
  final Color fg;
  final String label;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.bg,
    required this.fg,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                child: Icon(icon, size: 21, color: fg),
              ),
              const SizedBox(height: 9),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF364153),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- sections

class _SectionCard extends StatelessWidget {
  final _Section section;
  final ValueChanged<_Faq> onOpen;

  const _SectionCard({required this.section, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: section.iconBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(section.icon, size: 18, color: section.iconColor),
                ),
                const SizedBox(width: 11),
                Text(
                  section.title,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF101828),
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < section.items.length; i++)
            _FaqRow(
              item: section.items[i],
              onTap: () => onOpen(section.items[i]),
              showDivider: i > 0,
            ),
        ],
      ),
    );
  }
}

class _FaqRow extends StatelessWidget {
  final _Faq item;
  final VoidCallback onTap;
  final bool showDivider;

  const _FaqRow({
    required this.item,
    required this.onTap,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDivider)
          const Divider(height: 1, thickness: 1, color: Color(0xFFF1F3F5)),
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    item.question,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1B2431),
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Points right, and stays pointing right: this row goes
                // somewhere now rather than unfolding in place.
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: Color(0xFF9CA3AF),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 38, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        children: [
          Icon(Icons.search_off, size: 34, color: Color(0xFF9CA3AF)),
          SizedBox(height: 12),
          Text(
            'No results found. Please try another keyword or '
            'contact support.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF101828),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _StillNeedHelp extends StatelessWidget {
  final VoidCallback onCall;
  final VoidCallback onChat;
  const _StillNeedHelp({required this.onCall, required this.onChat});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6900),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Text(
            'Still need help?',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Call our support team and we will help you out.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFFFFE6D5),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 46,
            child: ElevatedButton.icon(
              onPressed: onCall,
              icon: const Icon(Icons.call_rounded, size: 18),
              label: const Text(
                'Contact Support',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFFFF6900),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 26),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // A phone call is no use to someone who cannot take one —
          // no credit, a noisy site, or a question that needs a link
          // in the reply. The written route stays one tap away.
          TextButton(
            onPressed: onChat,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text(
              'Or write to us instead',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
                decorationColor: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ catalogue

class _Faq {
  final String question;
  final String answer;
  const _Faq(this.question, this.answer);
}

class _Section {
  final String title;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final List<_Faq> items;

  const _Section({
    required this.title,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.items,
  });
}

const _catalogue = <_Section>[
  _Section(
    title: 'Getting Started',
    icon: Icons.menu_book_outlined,
    iconBg: Color(0xFFE8EEFC),
    iconColor: Color(0xFF3B5BA9),
    items: [
      _Faq(
        'How do I create an account?',
        'Enter your mobile number on the sign-in screen. We send a '
            'six-digit code to that number — type it in and your account '
            'is ready. There is no password to remember, and the same '
            'number works for both working and hiring.',
      ),
      _Faq(
        'How do I switch between working and hiring?',
        'Use the Work / Hire switch at the top of the Home screen. Work '
            'shows jobs you can apply to and your earnings; Hire shows the '
            'jobs you have posted and the workers near you. Your account '
            'and wallet stay the same on both sides.',
      ),
      _Faq(
        'How do I post a job?',
        'Switch to Hire, tap Post a Job, then pick a category, describe '
            'the work, set the location and your budget. Mark it Urgent if '
            'you need someone within the next 10–15 minutes. You can also '
            'Boost a post for ₹${AppConfig.boostFee} to show it to three '
            'times as many workers.',
      ),
      _Faq(
        'How do I find work?',
        'In Work mode, Jobs Near You and Recommended for You list jobs '
            'inside your search radius. Open one and apply — you can accept '
            'the budget as posted or send your own price with a short '
            'message. The client then picks from everyone who applied.',
      ),
      _Faq(
        'Why am I not seeing any jobs nearby?',
        'Three things decide what you see: location permission, the '
            'Current Location switch on Home, and your search radius in '
            'Settings. If location is off we cannot measure distance, so '
            'the nearby lists stay empty.',
      ),
    ],
  ),
  _Section(
    title: 'Payments & Wallet',
    icon: Icons.credit_card_outlined,
    iconBg: Color(0xFFE3F5E8),
    iconColor: Color(0xFF16A34A),
    items: [
      _Faq(
        'When do I get paid for a job?',
        'After the job is marked complete and the client confirms it. '
            'The amount is credited to your in-app wallet straight away, '
            'and you will see a Payment received notification. Cash jobs '
            'work differently — see the next answer.',
      ),
      _Faq(
        'What happens on a cash job?',
        'The client hands you the money in person, so nothing is added '
            'to your wallet — you already have it. The job still appears '
            'in your earnings history, marked as cash, so your records '
            'stay complete.',
      ),
      _Faq(
        'Does Pargig take a commission?',
        'Your first three jobs are free of any platform fee. After that '
            'a small fee is deducted from the job amount before it reaches '
            'your wallet. Tips are never charged — whatever a client tips '
            'you, you keep in full.',
      ),
      _Faq(
        'How do I add money to my wallet?',
        'Open the Wallet tab and tap Add Money. Choose an amount and pay '
            'through the payment screen. The balance updates as soon as the '
            'payment is confirmed, and every credit and debit is listed in '
            'the wallet history.',
      ),
      _Faq(
        'I paid but the job still shows unpaid',
        'Give it a moment and pull down to refresh — confirmation from '
            'the payment provider can take a few seconds. If it still has '
            'not moved, raise a ticket on that job from My Services and '
            'include the transaction ID from your bank or UPI app.',
      ),
      _Faq(
        'How do refunds work?',
        'Report the problem on the job itself, from My Services › the '
            'job › report an issue. Our team reviews what happened and, '
            'where a refund is due, returns it to the wallet or the '
            'original payment method.',
      ),
    ],
  ),
  _Section(
    title: 'Jobs & Hiring',
    icon: Icons.work_outline,
    iconBg: Color(0xFFFFEDD4),
    iconColor: Color(0xFFFF6900),
    items: [
      _Faq(
        'How do I track a job in progress?',
        'Open My Jobs and tap the job. The status screen shows the live '
            'timeline — accepted, on the way, started, completed — along '
            'with the other person\'s contact card and the buttons for '
            'whatever the next step is.',
      ),
      _Faq(
        'What is the six-digit PIN for?',
        'It proves the worker actually arrived. When they set off, the '
            'client receives a PIN. The worker asks for it on arrival and '
            'enters it in the app, and only then does the job start. Never '
            'share that PIN before the worker is in front of you.',
      ),
      _Faq(
        'How do I complete a job?',
        'Tap Mark as Completed on the job status screen and add a photo '
            'and a short note as proof of the work. The client confirms it '
            'from their side, and the payment is released once they do.',
      ),
      _Faq(
        'Can I cancel a job?',
        'Yes. Open the job and use Cancel. Cancelling before anyone has '
            'been hired costs nothing. Once a worker is on the way, '
            'cancelling affects both sides, so do it only when you have '
            'to — repeated cancellations lower your rating.',
      ),
      _Faq(
        'What if the worker does not arrive in time?',
        'An urgent job carries a 15-minute arrival timer. If it runs out '
            'without the worker arriving, the job is cancelled '
            'automatically and reopened for other workers.',
      ),
      _Faq(
        'How do ratings work?',
        'After a job is paid, both sides rate each other out of five. '
            'The score people see is the average of every rating you have '
            'received, so a single bad job does not define it. You can see '
            'both the ratings you received and the ones you gave from your '
            'Profile.',
      ),
    ],
  ),
  _Section(
    title: 'Safety & Security',
    icon: Icons.shield_outlined,
    iconBg: Color(0xFFF1E9FB),
    iconColor: Color(0xFF8B5CF6),
    items: [
      _Faq(
        'Never share your login code or job PIN',
        'Pargig will never ask you for your six-digit login code, and no '
            'member of our team will ever ask for a job PIN over a call or '
            'a message. Anyone who does is trying to take over your '
            'account or start a job you have not agreed to.',
      ),
      _Faq(
        'How do I report a problem with a job?',
        'Open My Services (or Job History if you work), pick the job and '
            'choose report an issue. Select what went wrong and describe '
            'it. The ticket carries the job, the other person and the '
            'payment with it, so our team can act without asking you to '
            'repeat everything.',
      ),
      _Faq(
        'Staying safe when you meet someone',
        'Keep the conversation and the payment inside the app — a '
            'request to move to another app or to pay outside Pargig means '
            'we cannot help if it goes wrong. Check the rating and the '
            'name before you start, and tell someone where you are going '
            'for a job at an unfamiliar address.',
      ),
      // Written against what the code does and nothing more. Nothing in
      // Pargig blocks an unverified user from posting, working or being
      // paid, and no document type is required — so this does not say
      // otherwise. If verification is ever made compulsory, or a
      // particular document is, this answer has to be rewritten first.
      _Faq(
        'What is KYC verification, and do I have to do it?',
        'It is optional. You can post jobs, accept work and be paid '
            'without it. What it adds is a Verified badge on your '
            'profile, which tells the other side that we have checked '
            'your identity — useful when someone is deciding whether to '
            'let you into their home, or whether to trust you with their '
            'money.\n\n'
            'Your mobile number is already verified: that was the code '
            'you entered when you signed in. KYC is the step beyond that.',
      ),
      _Faq(
        'How do I get verified?',
        'Open Profile and tap KYC Verification.\n\n'
            '1. Choose one document that shows your name — an Aadhaar '
            'card, PAN card, driving licence or a skill certificate. Any '
            'one of them is fine; none is compulsory.\n'
            '2. Photograph it, or pick a photo you already have.\n'
            '3. Tap Submit for verification.\n'
            '4. Come back to the same screen for the result.\n\n'
            'A person on our team looks at every document by hand, so '
            'this usually takes a day or two. We cannot notify you when '
            'it is decided yet, so pull down on that screen to refresh '
            'it.\n\n'
            'Make sure the whole document is in frame and the text is '
            'readable. A blurred or cropped photo is the usual reason one '
            'comes back.',
      ),
      _Faq(
        'My document was not accepted. What now?',
        'The KYC Verification screen shows the reason our reviewer gave. '
            'Read it, fix what it points at, and send the document again '
            'from the same screen — there is no limit on how many times '
            'you may try.\n\n'
            'If the reason does not make sense to you, raise a ticket and '
            'we will look at it again.',
      ),
      _Faq(
        'Who can see my document?',
        'Only the Pargig team member reviewing it. It is never shown to '
            'job givers, to workers, or on your profile. What other '
            'people see is the Verified badge — never the document '
            'behind it.',
      ),
      _Faq(
        'Keeping your account secure',
        'Your account is tied to your mobile number, so keep that number '
            'active and your SIM safe. If you lose the number or suspect '
            'someone else has used your account, raise a ticket '
            'immediately so we can lock it.',
      ),
    ],
  ),
];
