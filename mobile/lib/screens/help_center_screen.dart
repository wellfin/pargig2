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
      // Written as numbered steps rather than a paragraph: somebody
      // reading this is mid-signup with the app open, following along
      // one line at a time, not reading for comprehension. The list
      // row shows only the question, so a multi-line answer costs
      // nothing on the way in.
      _Faq(
        'How do I create an account?',
        '1. Open the PARGIG application.\n'
            '2. Enter your registered mobile number.\n'
            '3. Verify your mobile number using the OTP received.\n'
            '4. Complete the profile details requested in the '
            'application.\n'
            '5. Submit the details to complete registration.\n'
            '\n'
            'Once registration is successful, you can start using '
            'PARGIG. There is no password to remember, and the same '
            'number works for both working and hiring.\n'
            '\n'
            'If the OTP is not received: check your mobile network, '
            'verify that the mobile number is correct, use Resend OTP, '
            'and contact support if the issue continues.',
      ),
      // Job Giver and Job Taker are kept in brackets rather than
      // dropped: they are the words support and the admin panel use,
      // so somebody who has been told "switch to Job Giver" needs to
      // land on the right button. The button's own word comes first,
      // because that is what they are looking at.
      //
      // The last paragraph is here because it is the question
      // underneath the question — people switching the first time
      // expect to be setting up a second account, and worry about
      // where their money went.
      _Faq(
        'How do I switch between working and hiring?',
        'PARGIG has two modes on one account:\n'
            '\n'
            'Hire (Job Giver) — post a job and hire someone for it.\n'
            'Work (Job Taker) — find jobs near you and earn.\n'
            '\n'
            'To switch, use the Work / Hire pill at the top of the Home '
            'screen, or tap Switch Mode on your Profile. The app shows '
            'the features for that mode straight away: Work lists jobs '
            'you can apply to and your earnings, Hire lists the jobs '
            'you have posted and the workers near you.\n'
            '\n'
            'Switching does not create a second account. Your profile, '
            'your number, your wallet and your ratings are the same on '
            'both sides — only what the Home screen shows you changes.',
      ),
      // Steps, for the same reason as the account answer: this is read
      // with the form open, one line at a time.
      //
      // Each step names the control as the screen labels it. "Choose
      // the worker preference" sends somebody hunting; "Experienced
      // or Anyone" is on the button in front of them. The mode is
      // "Hire" for the same reason — jobgiver is the internal role
      // name and appears nowhere a user can see.
      //
      // No category step: it is inferred from the description in step
      // two rather than picked, which is why the old answer's "pick a
      // category" was already wrong.
      _Faq(
        'How do I post a job?',
        '1. Log in and switch to Hire on the Home screen.\n'
            '2. Tap Post a Job.\n'
            '3. Enter the job title and describe the work — you can '
            'type it or use Voice Input.\n'
            '4. Set the job location.\n'
            '5. Choose who can apply: Experienced for skilled workers '
            'only, or Anyone.\n'
            '6. Set the price — Fixed Price for your own budget, or '
            'Open to Offers to collect quotes.\n'
            '7. Say when you need it: mark it Urgent for the next '
            '10–15 minutes, or pick a date and time.\n'
            '8. Add photos if they help explain the work. This is '
            'optional.\n'
            '9. Review the details on the last screen and submit.\n'
            '\n'
            'Once posted, the job is shown to workers whose location '
            'and preferences match it. Check the description, location, '
            'timing and price before you submit — that is the screen '
            'to catch a mistake on.\n'
            '\n'
            'You can also Boost a post for ₹${AppConfig.boostFee} to '
            'show it to three times as many workers.',
      ),
      // The last two paragraphs are the point of this answer, not an
      // afterthought. Applying is not getting the job, and a worker
      // who believes otherwise turns up to something that was given
      // to somebody else. It is stated twice on purpose: once as the
      // step, once on its own.
      //
      // There is no immediate/scheduled filter to offer — Urgent is a
      // tag on the card, so the honest instruction is to look for it
      // rather than to filter by it.
      _Faq(
        'How do I find work?',
        '1. Log in and switch to Work on the Home screen.\n'
            '2. Set where you want jobs from — type your area, or tap '
            'GPS to fill it in automatically.\n'
            '3. Choose your search radius: 1–5, 5–10, 10–20 or above '
            '20 km.\n'
            '4. Add your skills and years of experience. These decide '
            'what appears under Recommended for You.\n'
            '5. Browse Jobs Near You and Recommended for You. Use '
            'Search to filter by category or distance, or to sort by '
            'Nearest First, Most Recent, Highest Pay or Lowest Pay.\n'
            '6. Check the title, location, timing and the price '
            'offered. Jobs needed right away carry an Urgent tag.\n'
            '7. Open the job to read the full description and what is '
            'required.\n'
            '8. Tap Apply for Job if you are comfortable with the '
            'work, the price and the timing. You can accept the budget '
            'as posted, or send your own price with a short message.\n'
            '\n'
            'Applying is not the same as getting the job. The client '
            'picks from everyone who applied, and you are notified if '
            'they choose you — so keep applying to others in the '
            'meantime.\n'
            '\n'
            'Once you are hired, you can follow the job under My Jobs.',
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
      // First in the section: it is the question asked before any of
      // the others, and the answer decides which of them applies.
      //
      // The list matches what the picker actually draws — UPI apps,
      // cards, Cash on Delivery, Pargig Wallet. Net banking is in the
      // backend's method enum but is never offered, so it is left out
      // rather than promised.
      //
      // "Wallet, if enabled" became "if your balance covers it":
      // there is no enable switch, there is a balance check that
      // refuses when it is short, and that is what somebody will
      // actually run into.
      _Faq(
        'Which payment methods are accepted?',
        'UPI — Paytm, PhonePe, Google Pay, Amazon Pay or '
            'Freecharge.\n'
            'Debit and credit cards.\n'
            'Cash on Delivery — you hand the money over in person.\n'
            'PARGIG Wallet — if your balance covers the amount. If it '
            'does not, the app says how much is short and you can add '
            'money and try again.\n'
            '\n'
            'How it goes:\n'
            '1. Open the payment screen for the job, or Add Money for '
            'a top-up.\n'
            '2. Check the amount and any charges shown.\n'
            '3. Pick a method.\n'
            '4. Complete the payment.\n'
            '5. The status appears in the app — on the job for a job '
            'payment, in your wallet history for a top-up.\n'
            '\n'
            'Cash works differently from the rest: nothing passes '
            'through PARGIG, so there is no held payment and nothing '
            'to release. See “What happens on a cash job?”.',
      ),
      // Two paths, and they differ on the one point people most want
      // answered: who is holding the money right now.
      //
      // Online, PARGIG holds it — paymentController puts it in
      // 'on_hold' with the note "Payment held in escrow" and credits
      // the worker's wallet only when the client releases. Cash never
      // passes through PARGIG at all. Saying "we do not hold your
      // money" would be true of one and false of the other, and the
      // false half is the one somebody would act on.
      //
      // Only the client can release, and nothing releases it
      // automatically, so the dispute route is not a footnote here.
      _Faq(
        'When do I get paid for a job?',
        'It depends on how the client is paying.\n'
            '\n'
            'Paid online (UPI, card, net banking)\n'
            '1. The client pays up front, and PARGIG holds that money '
            'until the work is done.\n'
            '2. You do the job and mark it complete.\n'
            '3. The client confirms and releases the payment, or '
            'reports a problem.\n'
            '4. On release it lands in your in-app wallet and you get '
            'a Payment received notification.\n'
            '\n'
            'Paid in cash\n'
            'The client hands you the money in person, so nothing is '
            'added to your wallet — you already have it. See the next '
            'answer.\n'
            '\n'
            'If the client does not release or pay after you have '
            'completed the job, raise a Payment Not Received dispute '
            'from the job. PARGIG reviews the job record and what both '
            'sides provide, and records the outcome. PARGIG does not '
            'pay the amount out of its own funds.',
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
      // Quick Add really is 500 / 1000 / 2000 / 5000, and picking the
      // method really is its own screen after the amount — both worth
      // naming, because a step that does not match the screen in front
      // of somebody makes them doubt the rest of the article.
      //
      // The last paragraph is the one that matters. There is no
      // withdraw-to-bank anywhere in the app or the backend: money
      // enters by top-up and by job payouts, and leaves only by
      // paying for a job with the wallet. Somebody topping up without
      // knowing that can put money somewhere they cannot get it back
      // from, so it is stated here rather than discovered later.
      _Faq(
        'How do I add money to my wallet?',
        '1. Open the Wallet tab.\n'
            '2. Tap Add Money.\n'
            '3. Enter an amount, or pick one from Quick Add — ₹500, '
            '₹1,000, ₹2,000 or ₹5,000.\n'
            '4. Choose a payment method on the next screen.\n'
            '5. Complete the payment.\n'
            '6. The balance updates as soon as the payment is '
            'confirmed, and the credit appears in your wallet '
            'history.\n'
            '\n'
            'If the payment goes through but the balance has not '
            'moved, pull down to refresh — confirmation can take a '
            'moment. If it still has not, contact support with the '
            'transaction details.\n'
            '\n'
            'What the balance is for: paying for jobs inside PARGIG. '
            'Money comes in from a top-up or from a job you were paid '
            'for. There is no withdraw-to-bank option in the app '
            'today, so only add what you expect to spend here — if you '
            'need a balance moved out, ask support.',
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
