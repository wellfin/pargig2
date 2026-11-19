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
        'Work down this list — it is in the order things usually go '
            'wrong.\n'
            '\n'
            '1. Are you in Work mode? The Work / Hire pill is at the top '
            'of the Home screen. In Hire mode you see the jobs you '
            'posted, not jobs to apply for.\n'
            '2. Is location permission on? Without it the app cannot '
            'measure distance from anything, so every nearby list comes '
            'back empty rather than wrong.\n'
            '3. Is the Current Location switch on Home turned on?\n'
            '4. How wide is your search radius? 1–5 km is narrow in '
            'most places. Widen it and look again.\n'
            '5. Are your skills set? Recommended for You is matched '
            'against them, so an empty skills list leaves that section '
            'thin even when Jobs Near You has plenty.\n'
            '\n'
            'A job you cancelled after being hired for it will not come '
            'back to you — it is offered to other workers instead. And '
            'a job already given to somebody else stops appearing for '
            'everyone.\n'
            '\n'
            'If all of that checks out and the list is still empty, that '
            'is probably the honest answer: nobody has posted near you '
            'yet. Widen the radius and look again through the day.',
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
            'to your wallet — you already have it.\n'
            '\n'
            'The money never passes through PARGIG on a cash job, and '
            'that one fact explains everything else about them:\n'
            '\n'
            'Nothing is held, so there is nothing to release. The job is '
            'still settled in the app, so it lands in your earnings '
            'history as Cash Received and the ratings step follows '
            'normally.\n'
            '\n'
            'There is nothing to reverse either, so a refund cannot be '
            'processed the usual way. The two of you settle it between '
            'you, and a dispute record is an account of what happened '
            'rather than a payment instruction.\n'
            '\n'
            'Your wallet balance does not move. The job appears in your '
            'history; the amount does not appear in your balance.\n'
            '\n'
            'So count the money before you mark the job done. Once you '
            'have left, there is no held payment standing behind you.',
      ),
      _Faq(
        'Does Pargig take a commission?',
        'Your first three jobs carry no platform fee at all.\n'
            '\n'
            'After that the fee is ₹10 or 5% of the job amount, '
            'whichever is larger. A ₹200 job is charged ₹10, because '
            'the flat minimum beats 5%. A ₹2,000 job is charged ₹100, '
            'because 5% beats the minimum.\n'
            '\n'
            'It comes out of the job amount before the payout reaches '
            'your wallet, so it is never a separate charge, and the '
            'amount you will actually receive is shown on the payment '
            'before it is released.\n'
            '\n'
            'Tips are never charged. Whatever a client tips you, you '
            'keep in full — the fee is worked out on the job price '
            'alone.\n'
            '\n'
            'Boosting a post is separate and optional: '
            '₹${AppConfig.boostFee} shows a job to about three times '
            'as many workers. That is a choice a client makes, not a '
            'deduction from anybody.',
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
        'Give it a moment and pull down to refresh. Confirmation comes '
            'back from the payment provider rather than from the app '
            'itself, so there is a gap of a few seconds between your '
            'bank saying yes and the job knowing about it.\n'
            '\n'
            'Do not pay again. A second payment is a second real '
            'transaction, and getting it back is a refund request rather '
            'than an undo.\n'
            '\n'
            'If it still has not moved after a minute or two:\n'
            '1. Check your bank or UPI app and note the transaction ID.\n'
            '2. Open the job and tap Need Help.\n'
            '3. Include that transaction ID, the amount and the time.\n'
            '\n'
            'That ID is what lets the team match your payment to the job '
            'with the provider. Without it the search is much slower, '
            'which is why it is worth copying before you close your '
            'banking app.',
      ),
      // Three things here came out of reading the refund controller
      // rather than from the brief, and all three change what somebody
      // should do:
      //
      //   refundPayment accepts only 'on_hold' or 'paid'. Once the
      //   giver releases, the money is in the worker's wallet and
      //   there is no path back — so "ask before releasing" is the
      //   most useful sentence on the page.
      //
      //   It refunds payment.amount, whole. Nothing anywhere sets
      //   partially_refunded, so promising a partial refund would be
      //   promising a button that does not exist.
      //
      //   Cash and wallet never reached the provider, so there is
      //   nothing to reverse and a human moves the money.
      //
      // The button is Need Help, not Report an Issue.
      _Faq(
        'How do refunds work?',
        'A refund is decided case by case, and only money that '
            'actually reached PARGIG can be returned.\n'
            '\n'
            'How to ask:\n'
            '1. Open the job — Profile, My Services, then the job.\n'
            '2. Tap Need Help and pick what went wrong.\n'
            '3. Give the reason, and attach photos or anything else '
            'that shows it.\n'
            '4. The PARGIG team reviews the job, the payment status '
            'and what both sides sent.\n'
            '5. The outcome is recorded on that job.\n'
            '\n'
            'If it is approved, the money goes back the way it came, '
            'through the payment provider — so how long it takes is '
            'up to that provider and your bank. A payment made in cash '
            'never passed through PARGIG, so there is nothing to '
            'reverse; the dispute record stands as the account of what '
            'happened.\n'
            '\n'
            'Ask before the payment is released. Once the client '
            'releases it, the amount is in the worker’s wallet and the '
            'app cannot pull it back. If something is wrong, open Need '
            'Help first.\n'
            '\n'
            'What PARGIG does not do: guarantee a refund — raising a '
            'dispute is a request, not an outcome; pay one out of its '
            'own funds; or split one — a refund is approved in full or '
            'not at all.\n'
            '\n'
            'If the client simply has not paid after the work was '
            'done, that is not a refund. Raise Payment Not Received '
            'instead. They still owe the agreed amount, and PARGIG '
            'reviews the dispute and records the outcome without '
            'paying the amount itself.',
      ),
    ],
  ),
  _Section(
    title: 'Jobs & Hiring',
    icon: Icons.work_outline,
    iconBg: Color(0xFFFFEDD4),
    iconColor: Color(0xFFFF6900),
    items: [
      // The two sides have different screens with different names, so
      // one instruction cannot serve both: a worker sent to "My
      // Posted Jobs" finds nothing, and a client sent to "My Work"
      // finds the jobs they are doing, not the ones they posted.
      //
      // The status list is the pill map in my_posted_jobs_screen, word
      // for word. The brief guessed at "Posted / Available" and
      // "Accepted"; the app says Finding Workers and Confirmed, and it
      // has a Worker Reached step the brief did not know about — which
      // is the one that matters, because it is the PIN moment.
      _Faq(
        'How do I track a job in progress?',
        'Where to look depends on which side you are on.\n'
            '\n'
            'Hiring: Home, then View All beside Active Jobs — or '
            'Profile, My Posted Jobs. Tabs for Active, In Progress, '
            'Completed and Cancelled.\n'
            '\n'
            'Working: My Work, with tabs for Applied, Accepted, '
            'Ongoing and Completed.\n'
            '\n'
            'Tap any job to see its live status, the other person’s '
            'contact card, and the button for whatever the next step '
            'is.\n'
            '\n'
            'What the statuses mean:\n'
            'Finding Workers — posted, nobody hired yet.\n'
            'Confirmed — a worker has been chosen.\n'
            'Worker Reached — they are at the location. This is when '
            'the six-digit PIN is used.\n'
            'In Progress — work has started.\n'
            'Completed — the work is done. Payment is released from '
            'here.\n'
            'Cancelled — called off before it was done.\n'
            'Disputed — somebody has raised an issue on it, and the '
            'PARGIG team is looking at it.',
      ),
      _Faq(
        'What is the six-digit PIN for?',
        'It proves the worker actually arrived, and it is the only '
            'thing that starts a job.\n'
            '\n'
            'How it works:\n'
            '1. The worker sets off and marks that they are on the way.\n'
            '2. The client gets a six-digit PIN in the app.\n'
            '3. The worker reaches the address and asks for it.\n'
            '4. The client reads it out, the worker types it in, and the '
            'job moves to In Progress.\n'
            '\n'
            'There is one PIN, and it is for starting. Finishing works '
            'differently: the worker submits their completion proof and '
            'the job is done — no second PIN is needed from anybody.\n'
            '\n'
            'Never give the PIN out before the worker is standing in '
            'front of you. Not over a call, not in a message, not '
            '“just to save time”. Reading it out early starts a job '
            'nobody has arrived for, and the clock and the record both '
            'say the work began.\n'
            '\n'
            'Nobody from PARGIG will ever ask you for it.',
      ),
      _Faq(
        'How do I complete a job?',
        'Open the job and tap Mark as Completed. Add a photo of the '
            'finished work and a short note saying what you did — up to '
            'eight photos if the job needs them.\n'
            '\n'
            'Submitting that proof IS the completion. The job reads '
            'Completed on both sides straight away; there is no second '
            'PIN and nothing for the client to approve before it counts '
            'as done. The client is notified at that moment.\n'
            '\n'
            'Releasing the payment is a separate step, and it is theirs '
            'to take. The job is finished either way, but the money '
            'moves when they release it — so the proof is worth doing '
            'properly. It is what you have if they query the work '
            'later.\n'
            '\n'
            'One thing worth knowing: once you have marked a job '
            'complete, the client can no longer cancel it. They have to '
            'release the payment or raise an issue. That guard exists so '
            'nobody can cancel their way out of paying for work that is '
            'already done.',
      ),
      // cancelJob does three things the old answer did not mention, and
      // each one changes what somebody expects to happen:
      //
      //   A worker cancelling does NOT cancel the job. It goes back to
      //   'open' for someone else and that worker is added to
      //   blockedJobtakers, so it never appears for them again. They
      //   think they have ended it; the client sees it relisted.
      //
      //   A giver cannot cancel once the worker has marked complete.
      //   The server says so in those words — it exists to stop
      //   cancelling out of paying for finished work.
      //
      //   Nothing in cancelJob touches the payment. A held amount
      //   stays held until somebody asks.
      //
      // And the old claim that cancellations lower your rating is not
      // true: jobsCancelled feeds the completed/total figure on the
      // profile, while rating comes from Rating documents after a job.
      _Faq(
        'Can I cancel a job?',
        'Yes, from either side — open the job and tap Cancel Job. Give '
            'a reason when it asks; it is recorded on the job.\n'
            '\n'
            'What happens depends on who cancels.\n'
            '\n'
            'If the client cancels, the job is cancelled for good.\n'
            '\n'
            'If the worker cancels, the job is not cancelled — it goes '
            'back to Finding Workers so somebody else can take it, and '
            'it stops appearing for the worker who dropped it. The '
            'client is told their job is live again.\n'
            '\n'
            'Two things you cannot do: cancel a job that is already '
            'completed or cancelled, and — as the client — cancel '
            'after the worker has marked the job complete. At that '
            'point the work is done, so verify the PIN or release the '
            'payment instead.\n'
            '\n'
            'Cancelling does not move money on its own. If a payment '
            'is already held for the job, open Need Help on it and ask '
            '— see “How do refunds work?”.\n'
            '\n'
            'Cancelling does not change your rating, which comes from '
            'what people rate you after a job. It does count towards '
            'the completed-versus-total figure on your profile, so do '
            'it when you have to rather than as a habit.',
      ),
      _Faq(
        'What if the worker does not arrive in time?',
        'When a worker takes a job they say when they expect to be '
            'there, and that time shows on the job. Nothing happens '
            'automatically when it passes — there is no timer that '
            'cancels for you, so the next move is yours.\n'
            '\n'
            'Message them first. Traffic and an overrunning previous job '
            'are the usual reasons, and a worker who answers with a new '
            'time is generally worth waiting for.\n'
            '\n'
            'If they do not answer, or you no longer want to wait, open '
            'the job and tap Cancel Job. Give the reason — it is kept on '
            'the job, which matters if it is ever looked at. You can '
            'then post again.\n'
            '\n'
            'Do not read out the PIN to get things moving. It is what '
            'proves somebody actually turned up, and once it is used the '
            'job counts as started.\n'
            '\n'
            'If a worker repeatedly accepts and does not arrive, report '
            'it through Need Help on the job rather than only '
            'cancelling. A cancellation on its own does not tell anybody '
            'what happened.',
      ),
      // The asymmetry is the answer, and the old version said "both
      // sides rate each other" as though it were symmetric.
      //
      // RateExperienceArgs.mandatory is real: for the client there is
      // no skip link, and PendingRating re-reads "paid and not yet
      // rated" from the server on every launch, so closing the app
      // postpones it rather than escaping it. The worker gets an
      // Optional link.
      //
      // It is owed once the payment is RELEASED, not merely once the
      // job is complete — pendingRating filters on paymentReleasedAt.
      // Somebody waiting to be asked after a cash job would otherwise
      // wonder why nothing happened.
      _Faq(
        'How do ratings work?',
        'Ratings are how trust is built here, so one side of them is '
            'required.\n'
            '\n'
            'Once a job is completed and the payment has been '
            'released:\n'
            '\n'
            'The client must rate the worker. That screen has no skip, '
            'and closing the app does not clear it — it opens again '
            'next time you come back, because it is worked out from '
            'the job rather than remembered on the phone.\n'
            '\n'
            'The worker can rate the client, and there is an Optional '
            'link for anyone who would rather not.\n'
            '\n'
            'To rate: open the completed job, choose your stars out of '
            'five, add a line if you want to, and submit.\n'
            '\n'
            'The score people see is the average of every rating you '
            'have received, so one bad job does not define it. Both '
            'the ratings you received and the ones you gave are on '
            'your Profile.\n'
            '\n'
            'Rate honestly, and on the job that actually happened. If '
            'the rating screen does not appear or will not submit, '
            'contact support.',
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
        'There are two six-digit numbers in PARGIG, and neither should '
            'ever be read out to anyone who asks for it.\n'
            '\n'
            'Your login code is what signs you in. There is no password '
            'on this account — that code IS the account. Anyone holding '
            'it can sign in as you, take your wallet balance into a job '
            'payment, and talk to people as you.\n'
            '\n'
            'The job PIN starts a job. Given out early, it marks a '
            'worker as arrived when they have not, and the record then '
            'says the work began.\n'
            '\n'
            'PARGIG will never ask you for either one. Not support, not '
            'in a call, not in a chat, not to “verify” anything and not '
            'to “speed up” a payment. Anybody who does is not from '
            'PARGIG, however much they know about your job.\n'
            '\n'
            'That last part is worth sitting with: somebody can know '
            'your name, the job title and the amount and still be a '
            'stranger. Knowing the details is not proof of anything.\n'
            '\n'
            'If you have already given a code out, open Help and '
            'contact support straight away.',
      ),
      _Faq(
        'How do I report a problem with a job?',
        'Open the job from Profile, My Services, and tap Need Help.\n'
            '\n'
            '1. Pick the type of problem. The list you see depends on '
            'which side you were on: a client is offered things like '
            'service quality, payment and worker behaviour, a worker '
            'things like payment not received, the requirement '
            'changing, or being unable to get access.\n'
            '2. Tick what specifically happened. The ticks are there so '
            'you do not have to find the words for the common cases.\n'
            '3. Describe it in your own words, and attach photos if you '
            'have them. Photos are what settle most disagreements about '
            'work that was or was not done.\n'
            '4. Submit it.\n'
            '\n'
            'The report carries the job, the other person and the '
            'payment with it, so nobody has to ask you to repeat any of '
            'that. You can follow it on the same job, and the decision '
            'and the reason are recorded there when it is made.\n'
            '\n'
            'Report before the payment is released if money is part of '
            'the problem. Once it is released there is no way to pull it '
            'back through the app.\n'
            '\n'
            'Both sides can report the same job, and both reports are '
            'kept. Yours is not cancelled out by theirs.',
      ),
      _Faq(
        'Staying safe when you meet someone',
        'Before you go:\n'
            'Read the other person’s rating and how many jobs they have '
            'finished. A Verified badge means a PARGIG reviewer has '
            'checked an identity document against their name.\n'
            'Tell somebody where you are going and when you expect to be '
            'back, for any address you do not know.\n'
            'Read the job description properly. A job that turns out to '
            'be different from the description is worth questioning '
            'before you start, not after.\n'
            '\n'
            'While you are there:\n'
            'Keep the conversation in the app. It is the record you have '
            'if anything is disputed later.\n'
            'Keep the payment in the app too. Somebody asking to pay '
            'outside PARGIG, or to move to another app first, is asking '
            'you to give up the only protection either of you has — '
            'there is nothing for us to look at and nothing to hold.\n'
            'Use the PIN properly. It is the thing that proves who was '
            'where, and when.\n'
            '\n'
            'If something feels wrong, leave. No job is worth it, and '
            'cancelling costs you far less than the alternative. Report '
            'it from the job afterwards so there is a record — a '
            'cancellation on its own tells nobody what happened.\n'
            '\n'
            'In an emergency, call the local emergency number first. '
            'PARGIG is not an emergency service and cannot reach you '
            'quickly.',
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
            'It has to be your own document, and the name on it should '
            'match the name on your profile — a reviewer comparing the '
            'two is the whole of what this check is.\n\n'
            'Make sure the whole document is in frame and the text is '
            'readable. A blurred or cropped photo is the usual reason one '
            'comes back.',
      ),
      _Faq(
        'My document was not accepted. What now?',
        'The KYC Verification screen shows the reason the reviewer '
            'gave. Read it, fix what it points at, and send the document '
            'again from the same screen. There is no limit on how many '
            'times you may try, and a rejection does not count against '
            'you anywhere.\n'
            '\n'
            'The usual reasons, in roughly the order they come up:\n'
            'Part of the document is out of frame. All four corners have '
            'to be in the photo.\n'
            'The text is not readable — blurred, too small, or lost in '
            'glare from a flash or a window.\n'
            'The name does not match your profile. If your profile name '
            'is short or spelled differently, fix the profile and try '
            'again.\n'
            'It is a photo of a screen rather than of the document. '
            'Photograph the document itself, flat, in daylight if you '
            'can.\n'
            '\n'
            'You can also send a different document. Any one of Aadhaar, '
            'PAN, a driving licence or a skill certificate is accepted '
            '— none of them is required, so if one is giving you '
            'trouble, use another.\n'
            '\n'
            'If the reason does not make sense to you, raise it through '
            'Help and somebody will look again.',
      ),
      _Faq(
        'Who can see my document?',
        'Only the PARGIG team member reviewing it.\n'
            '\n'
            'It is never shown to clients, never shown to workers, and '
            'never appears on your profile. What other people see is the '
            'Verified badge and nothing else — the badge says a '
            'reviewer checked a document, not which document or what was '
            'on it.\n'
            '\n'
            'It is not shown in chat, not attached to a job, and not '
            'included in anything a dispute shows the other side.\n'
            '\n'
            'The file is stored on PARGIG’s own storage, reachable from '
            'the review queue in the admin panel rather than from '
            'anywhere in the app.\n'
            '\n'
            'Because of all that, nobody will ever need to ask you for '
            'your document through the app. Somebody in a chat asking '
            'you to send an Aadhaar or PAN photo is not PARGIG, whatever '
            'they say — report it from the job and do not send it.',
      ),
      _Faq(
        'Keeping your account secure',
        'Your account is your mobile number. There is no password: '
            'signing in means receiving a code on that number and typing '
            'it in. That is simpler than a password, and it moves the '
            'thing you have to protect — whoever can receive your SMS '
            'can sign in as you.\n'
            '\n'
            'So:\n'
            'Keep the number active. A number you let lapse can be '
            'reissued to somebody else by the operator, and your account '
            'goes with it.\n'
            'Keep the SIM safe, and lock your phone. A code arriving on '
            'a lock screen anybody can read is a code anybody can use.\n'
            'Never read a login code out to anyone, for any reason. '
            'PARGIG will not ask.\n'
            '\n'
            'If you change your number, change it in the app while you '
            'still have the old one. Afterwards is much harder, because '
            'the way back in is a code sent to a number you no longer '
            'have.\n'
            '\n'
            'If you lose the number, or think somebody else has been in '
            'your account, contact support immediately so it can be '
            'locked. Say what you noticed and when — a job you did not '
            'post, a message you did not send, a balance that moved.',
      ),
    ],
  ),
];
