import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../api/home_api.dart';
import '../state/auth_state.dart';

/// Args for Navigator.pushNamed('/chat', ...).
///
/// When `userId` is provided the screen wires up to the real backend
/// chat ( POST /chat/direct/with/:userId/open + polling ). Without
/// `userId` it falls back to the local mock seed used by the Figma
/// Messages tab demo (Raj Kumar transcript).
class ChatArgs {
  final String name;
  final String? userId;
  final bool online;
  // Optional pre-fetched mobile number for the chat partner. When set,
  // the call button can launch the dialer immediately without an extra
  // /users/:id round-trip. Callers (Messages list, Applicants card,
  // Nearby Workers card, etc.) should pass it if they already have it.
  final String? mobile;
  const ChatArgs({
    required this.name,
    this.userId,
    this.online = false,
    this.mobile,
  });
}

/// Figma chat thread — opened by tapping a row on /messages, the
/// Chat button on a worker / client card, or the chat icon on
/// Applicants.
///
/// Persistence: when ChatArgs.userId is set, messages are loaded /
/// posted through the /chat/direct/* + /chat/rooms/:id/messages
/// endpoints, and the screen polls every 4 seconds for the other
/// side's replies. Without a userId, the screen renders a mock
/// transcript and sends are local-only (legacy demo path).
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const Duration _pollInterval = Duration(seconds: 4);

  ChatArgs? _args;
  final List<_Message> _messages = [];
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _seeded = false;

  // Real-backend state. _roomId stays null in mock mode.
  String? _roomId;
  String? _meId;
  Timer? _pollTimer;
  bool _sending = false;
  bool _loadingRoom = false;
  String? _loadError;

  // Canned reply pinned just above the input. Matches the Figma chip.
  static const List<String> _quickReplies = [
    'Yes, sounds good',
    '👍',
    '🙏',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    final raw = ModalRoute.of(context)?.settings.arguments;
    if (raw is ChatArgs) {
      _args = raw;
      _seeded = true;
      _meId = (context.read<AuthState>().user?['_id'] ?? '').toString();
      if (raw.userId != null && raw.userId!.isNotEmpty) {
        // Real-backend mode — open the direct room and start polling.
        _openRealRoom(raw.userId!);
      } else {
        // Mock-only legacy demo path (Raj Kumar transcript etc.).
        _messages.addAll(_seedFor(raw.name));
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollToBottom(),
        );
      }
    }
  }

  Future<void> _openRealRoom(String otherUserId) async {
    setState(() {
      _loadingRoom = true;
      _loadError = null;
    });
    try {
      final room = await HomeApi.openDirectChat(otherUserId);
      if (!mounted) return;
      _roomId = (room['_id'] ?? '').toString();
      _absorbMessages(room['messages']);
      setState(() => _loadingRoom = false);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToBottom(),
      );
      _pollTimer = Timer.periodic(_pollInterval, (_) => _refreshRoom());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingRoom = false;
        _loadError = e is ApiException
            ? e.message
            : e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _refreshRoom() async {
    final id = _roomId;
    if (id == null || !mounted) return;
    try {
      final room = await HomeApi.fetchChatRoom(id);
      if (!mounted) return;
      _absorbMessages(room['messages']);
      // GET /chat/rooms/:id marks the caller's unread messages as
      // read on the backend. Re-pull the total so the bottom-nav
      // Messages dot clears in seconds, not after the home screen's
      // next 20s poll tick.
      context.read<AuthState>().refreshUnreadChats();
    } catch (_) {
      // swallow — next tick retries
    }
  }

  /// Replace the local _messages list with the backend's view, keeping
  /// the scroll position pinned to the bottom only when new rows
  /// actually arrived. Sender == _meId → me bubble; else → them bubble.
  void _absorbMessages(dynamic raw) {
    if (raw is! List) return;
    final mapped = <_Message>[];
    for (final m in raw) {
      if (m is! Map) continue;
      final sender = (m['sender'] ?? '').toString();
      final body = (m['body'] ?? '').toString();
      if (body.isEmpty) continue;
      final created = m['createdAt']?.toString();
      // Mongo returns ISO UTC strings; convert to the device's local
      // tz so the bubble timestamp matches the user's wall clock.
      // Without .toLocal() a 10:30 PM IST message rendered as 5:00 PM.
      final dt =
          created == null ? null : DateTime.tryParse(created)?.toLocal();
      mapped.add(_Message(
        text: body,
        time: dt == null ? '' : _formatTime(dt),
        kind: sender == _meId ? _Kind.me : _Kind.them,
        // Treat any message that has readBy beyond just the sender as
        // seen. Mobile doesn't post read-receipts yet, so for our own
        // bubbles we leave seen=false and the single tick renders.
        seen: false,
      ));
    }
    final grew = mapped.length > _messages.length;
    if (!_listsEqual(mapped, _messages)) {
      setState(() {
        _messages
          ..clear()
          ..addAll(mapped);
      });
      if (grew) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollToBottom(),
        );
      }
    }
  }

  bool _listsEqual(List<_Message> a, List<_Message> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].text != b[i].text || a[i].kind != b[i].kind) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  List<_Message> _seedFor(String name) {
    // Raj Kumar transcript matches the Figma exactly. Other contacts
    // get a sensible opener so the screen never looks empty.
    if (name == 'Raj Kumar') {
      return const [
        _Message(
          text: 'Hi! I saw your job posting for home cleaning.',
          time: '10:30 AM',
          kind: _Kind.them,
        ),
        _Message(
          text: 'Hello! Yes, are you available tomorrow?',
          time: '10:32 AM',
          kind: _Kind.me,
          seen: true,
        ),
        _Message(
          text: 'Yes, I can come at 10 AM. Is that okay?',
          time: '10:33 AM',
          kind: _Kind.them,
        ),
        _Message(
          text: 'Job confirmed for tomorrow at 10 AM',
          time: '',
          kind: _Kind.system,
        ),
        _Message(
          text: 'Perfect! Can you do it for ₹450?',
          time: '10:35 AM',
          kind: _Kind.me,
          seen: true,
        ),
        _Message(
          text: 'I can do ₹480. Deal?',
          time: '10:36 AM',
          kind: _Kind.them,
        ),
        _Message(
          text: 'Sounds good! See you tomorrow.',
          time: '10:37 AM',
          kind: _Kind.me,
          seen: false,
        ),
      ];
    }
    return [
      _Message(
        text: 'Hi, $name here. Let me know if you have any questions.',
        time: 'Just now',
        kind: _Kind.them,
      ),
    ];
  }

  Future<void> _send([String? override]) async {
    final text = (override ?? _inputCtrl.text).trim();
    if (text.isEmpty || _sending) return;
    final roomId = _roomId;
    if (roomId == null) {
      // Mock mode — local-only append.
      setState(() {
        _messages.add(_Message(
          text: text,
          time: _nowLabel(),
          kind: _Kind.me,
          seen: false,
        ));
        _inputCtrl.clear();
      });
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollToBottom());
      return;
    }
    // Real-backend mode — optimistic append, then POST. On failure
    // remove the optimistic bubble and surface a snackbar so the
    // user knows it didn't go through.
    final optimistic = _Message(
      text: text,
      time: _nowLabel(),
      kind: _Kind.me,
      seen: false,
    );
    setState(() {
      _sending = true;
      _messages.add(optimistic);
      _inputCtrl.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    try {
      await HomeApi.sendChatMessage(roomId, text);
      if (!mounted) return;
      // Reconcile with the server's view so the timestamp / order
      // exactly matches the next poll.
      await _refreshRoom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.remove(optimistic));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Message failed: '
            '${e is ApiException ? e.message : e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      _scrollCtrl.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  String _formatTime(DateTime dt) {
    final h12 = dt.hour == 0
        ? 12
        : dt.hour > 12
            ? dt.hour - 12
            : dt.hour;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$h12:$mm $ampm';
  }

  String _nowLabel() {
    final dt = DateTime.now();
    final h12 = dt.hour == 0
        ? 12
        : dt.hour > 12
            ? dt.hour - 12
            : dt.hour;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$h12:$mm $ampm';
  }

  Future<void> _onCall() async {
    // Resolve the partner's phone number, then hand off to the system
    // dialer via tel: URI. Priority:
    //   1. ChatArgs.mobile (when the caller already had it)
    //   2. /users/:userId (fetched on demand)
    //   3. Show a non-blocking snackbar if neither is available.
    String? mobile = _args?.mobile;
    if ((mobile == null || mobile.isEmpty) && (_args?.userId?.isNotEmpty ?? false)) {
      try {
        final res = await ApiClient.get('/users/${_args!.userId}');
        if (res is Map) {
          final m = res['mobile'];
          if (m is String && m.isNotEmpty) mobile = m;
        }
      } catch (_) {
        // Falls through to the no-number snackbar below.
      }
    }
    if (!mounted) return;
    if (mobile == null || mobile.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Phone number not available for ${_args?.name ?? "this user"}"),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    // Strip everything except digits + leading + so the dialer doesn't
    // choke on stray characters (spaces, hyphens, parens). url_launcher's
    // tel: scheme accepts an E.164-ish string.
    final cleaned = mobile.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: cleaned);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No dialer app found on this device'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _onMore() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.notifications_off_outlined),
              title: const Text('Mute notifications'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined,
                  color: Color(0xFFDC2626)),
              title: const Text('Report user',
                  style: TextStyle(color: Color(0xFFDC2626))),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = _args?.name ?? 'Chat';
    final online = _args?.online ?? false;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Column(
        children: [
          _Header(
            name: name,
            online: online,
            onBack: () => Navigator.maybePop(context),
            onCall: _onCall,
            onMore: _onMore,
          ),
          Expanded(
            child: _loadingRoom && _messages.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFFFF6900)),
                    ),
                  )
                : _loadError != null && _messages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline,
                                  size: 36, color: Color(0xFFDC2626)),
                              const SizedBox(height: 10),
                              Text(
                                _loadError!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Color(0xFFDC2626)),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton(
                                onPressed: () {
                                  final id = _args?.userId;
                                  if (id != null) _openRealRoom(id);
                                },
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding:
                            const EdgeInsets.fromLTRB(12, 16, 12, 12),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) =>
                            _Bubble(message: _messages[i]),
                      ),
          ),
          _QuickReplies(
            replies: _quickReplies,
            onTap: (s) => _send(s),
          ),
          _Composer(
            controller: _inputCtrl,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String name;
  final bool online;
  final VoidCallback onBack;
  final VoidCallback onCall;
  final VoidCallback onMore;

  const _Header({
    required this.name,
    required this.online,
    required this.onBack,
    required this.onCall,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Color(0xFF408EE0)),
      padding: EdgeInsets.fromLTRB(
        4, MediaQuery.of(context).padding.top + 6, 8, 10,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
            onPressed: onBack,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                if (online)
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Text(
                      'Online',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xCCFFFFFF),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.call_outlined,
                color: Colors.white, size: 20),
            onPressed: onCall,
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white, size: 20),
            onPressed: onMore,
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final _Message message;
  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    if (message.kind == _Kind.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFDBEAFE),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFBFDBFE), width: 0.8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle,
                    size: 14, color: Color(0xFF408EE0)),
                const SizedBox(width: 6),
                Text(
                  message.text,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF408EE0),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final isMe = message.kind == _Kind.me;
    final bg = isMe ? const Color(0xFFFFEDD4) : Colors.white;
    final fg = const Color(0xFF101828);
    final align = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final radius = isMe
        ? const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: align,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: bg,
                borderRadius: radius,
                border: isMe
                    ? null
                    : Border.all(color: const Color(0xFFE5E7EB), width: 0.6),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0D000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Text(
                message.text,
                style: TextStyle(
                  fontSize: 14,
                  color: fg,
                  height: 1.35,
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(isMe ? 0 : 6, 4, isMe ? 6 : 0, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message.time,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.seen ? Icons.done_all : Icons.done,
                    size: 12,
                    color: message.seen
                        ? const Color(0xFF408EE0)
                        : const Color(0xFF9CA3AF),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickReplies extends StatelessWidget {
  final List<String> replies;
  final ValueChanged<String> onTap;
  const _QuickReplies({required this.replies, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF3F4F6),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: replies.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final r = replies[i];
            return Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => onTap(r),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFFE5E7EB),
                      width: 0.8,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  child: Text(
                    r,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF374151),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  const _Composer({required this.controller, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Color(0xFFE5E7EB), width: 0.6),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF101828),
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Type a message...',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF9CA3AF),
                    ),
                    isCollapsed: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              height: 44,
              child: Material(
                color: const Color(0xFFFF6900),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onSend,
                  child: const Center(
                    child: Icon(Icons.send,
                        size: 18, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Kind { me, them, system }

class _Message {
  final String text;
  final String time;
  final _Kind kind;
  final bool seen;

  const _Message({
    required this.text,
    required this.time,
    required this.kind,
    this.seen = false,
  });
}
