import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/home_api.dart';
import '../state/auth_state.dart';
import 'chat_screen.dart';
import '../widgets/nav_unread_badge.dart';

/// Figma "Messages" screen — opened from the bottom-nav chat icon.
/// Header + search field + conversation list backed by the
/// /chat/rooms feed (was a fixed mock list before). Each row binds
/// to a real ChatRoom — tapping it opens /chat in real-backend mode
/// with the partner's userId so the worker / client conversation
/// continues server-side.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  List<_Conversation> _conversations = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await HomeApi.chatRooms();
      if (!mounted) return;
      final convs = rows
          .map(_toConversation)
          .whereType<_Conversation>()
          .toList();
      setState(() {
        _conversations = convs;
        _loading = false;
      });
      // Re-pull unread badge state — opening/closing rooms or new
      // messages while we were away will have shifted it.
      if (mounted) context.read<AuthState>().refreshUnreadChats();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException
            ? e.message
            : e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  _Conversation? _toConversation(Map<String, dynamic> r) {
    final partner = r['partner'];
    if (partner is! Map) return null;
    final id = (partner['_id'] ?? '').toString();
    final name = (partner['name'] ?? 'User').toString().trim();
    final body = (r['lastMessage'] ?? '').toString();
    final atRaw = r['lastMessageAt']?.toString();
    // Convert UTC to local so the "Yesterday" / "Apr 12" date labels
    // match the user's wall clock — otherwise a midnight-IST message
    // would show as the previous day in UTC.
    final at = atRaw == null ? null : DateTime.tryParse(atRaw)?.toLocal();
    final unread = r['unread'] is num ? (r['unread'] as num).toInt() : 0;
    return _Conversation(
      userId: id,
      name: name.isEmpty ? 'User' : name,
      lastMessage: body.isEmpty ? 'Start the conversation' : body,
      timeLabel: at == null ? '' : _relativeTime(at),
      online: false, // backend doesn't ship presence yet
      unread: unread,
    );
  }

  String _relativeTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} mins ago';
    if (diff.inHours < 24) {
      return '${diff.inHours} ${diff.inHours == 1 ? "hour" : "hours"} ago';
    }
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${_months[dt.month - 1]} ${dt.day}';
  }

  List<_Conversation> get _visible {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _conversations;
    return _conversations.where((c) {
      return c.name.toLowerCase().contains(q) ||
          c.lastMessage.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openConversation(_Conversation c) async {
    await Navigator.pushNamed(
      context,
      '/chat',
      arguments: ChatArgs(
        name: c.name,
        userId: c.userId.isEmpty ? null : c.userId,
        online: c.online,
      ),
    );
    if (mounted) _load();
  }

  void _onNavTap(int i) {
    // Messages tab — no-op (already here).
    if (i == 2) return;
    // Home → drop back through the stack to /home so we don't pile
    // multiple Home routes on top of each other.
    if (i == 0) {
      Navigator.popUntil(context, ModalRoute.withName('/home'));
      return;
    }
    final auth = context.read<AuthState>();
    if (i == 1) {
      Navigator.pushNamed(
        context,
        auth.isJobGiver ? '/my-posted-jobs' : '/my-jobs',
      );
      return;
    }
    if (i == 3) {
      Navigator.pushNamed(context, '/wallet');
      return;
    }
    if (i == 4) {
      Navigator.pushNamed(context, '/profile');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final visible = _visible;
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Column(
        children: [
          _Header(onBack: () => Navigator.maybePop(context)),
          _SearchBar(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
          ),
          Expanded(
            child: _loading && _conversations.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFFFF6900),
                      ),
                    ),
                  )
                : _error != null && _conversations.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 36,
                            color: Color(0xFFDC2626),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFFDC2626)),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _load,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : visible.isEmpty
                ? const _EmptyState()
                : RefreshIndicator(
                    color: const Color(0xFFFF6900),
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const Divider(
                        height: 1,
                        thickness: 0.6,
                        color: Color(0xFFF1F5F9),
                        indent: 76,
                      ),
                      itemBuilder: (_, i) => _ConversationTile(
                        conversation: visible[i],
                        onTap: () => _openConversation(visible[i]),
                      ),
                    ),
                  ),
          ),
          _BottomNav(
            currentIndex: 2,
            onTap: _onNavTap,
            isWorkMode: !auth.isJobGiver,
          ),
        ],
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
        14,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
            onPressed: onBack,
          ),
          const Expanded(
            child: Center(
              child: Padding(
                // Offsets the back arrow on the left so the title
                // sits truly centred in the header.
                padding: EdgeInsets.only(right: 40),
                child: Text(
                  'Messages',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _SearchBar({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF408EE0),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE5E7EB), width: 0.6),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            const Icon(Icons.search, size: 18, color: Color(0xFF6B7280)),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                style: const TextStyle(fontSize: 14, color: Color(0xFF101828)),
                decoration: const InputDecoration(
                  hintText: 'Search messages...',
                  hintStyle: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
                  isCollapsed: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                  border: InputBorder.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final _Conversation conversation;
  final VoidCallback onTap;

  const _ConversationTile({required this.conversation, required this.onTap});

  String _initials() {
    final parts = conversation.name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE5E7EB),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _initials(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ),
                    if (conversation.online)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conversation.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF101828),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      conversation.lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    conversation.timeLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (conversation.unread > 0)
                    Container(
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF6900),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${conversation.unread}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 18),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.chat_bubble_outline, size: 40, color: Color(0xFF9CA3AF)),
            SizedBox(height: 12),
            Text(
              'No conversations',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF101828),
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Messages with workers and clients will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool isWorkMode;

  const _BottomNav({
    required this.currentIndex,
    required this.onTap,
    required this.isWorkMode,
  });

  List<_NavItem> get _items => [
    const _NavItem('Home', Icons.home_outlined, Icons.home),
    _NavItem(isWorkMode ? 'My Jobs' : 'Jobs', Icons.work_outline, Icons.work),
    const _NavItem('Messages', Icons.chat_bubble_outline, Icons.chat_bubble),
    const _NavItem(
      'Wallet',
      Icons.account_balance_wallet_outlined,
      Icons.account_balance_wallet,
    ),
    const _NavItem('Profile', Icons.person_outline, Icons.person),
  ];

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<AuthState>().unreadChats;
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        9,
        16,
        MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB), width: 0.8)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(_items.length, (i) {
          final item = _items[i];
          final active = i == currentIndex;
          // Messages tab sits at index 2 — red dot only when unread > 0.
          // Count of unread messages, not a bare dot.
          final badgeCount = i == 2 ? unread : 0;
          return GestureDetector(
            onTap: () => onTap(i),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  NavUnreadBadge(
                    icon: active ? item.activeIcon : item.icon,
                    color: active
                        ? const Color(0xFFFF6900)
                        : const Color(0xFF4A5565),
                    count: badgeCount,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: active
                          ? const Color(0xFFFF6900)
                          : const Color(0xFF4A5565),
                      height: 1.33,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  const _NavItem(this.label, this.icon, this.activeIcon);
}

class _Conversation {
  // Empty string when this conversation isn't backed by a real
  // ChatRoom (legacy callers). Real conversations from /chat/rooms
  // always have one.
  final String userId;
  final String name;
  final String lastMessage;
  final String timeLabel;
  final bool online;
  final int unread;

  const _Conversation({
    this.userId = '',
    required this.name,
    required this.lastMessage,
    required this.timeLabel,
    required this.online,
    required this.unread,
  });
}
