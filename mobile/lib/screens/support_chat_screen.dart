import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../api/home_api.dart';
import '../config.dart';
import '../state/auth_state.dart';

/// The user's thread with the Pargig support desk.
///
/// Separate from ChatScreen rather than a flag on it. The two look
/// alike and are not alike: a direct chat has a partner with a profile,
/// a phone number and a job between them, and every one of those is
/// absent here. Bolting a "but sometimes there is no partner" branch
/// onto ChatScreen would have put that absence into the call button,
/// the header, the report-user sheet and the read receipts all at once.
///
/// What it promises: nothing it cannot keep. There is no agent waiting
/// on the other end — the message lands in a queue in the admin panel
/// and a person opens it. The empty state says so, in those words,
/// rather than "we usually reply in 5 minutes".
class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  static const Duration _pollInterval = Duration(seconds: 5);

  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  final List<_Msg> _messages = [];
  String? _roomId;
  String? _meId;
  Timer? _poll;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _meId = (context.read<AuthState>().user?['_id'] ?? '').toString();
      _open();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final room = await HomeApi.openSupportChat();
      if (!mounted) return;
      _roomId = (room['_id'] ?? '').toString();
      _absorb(room['messages']);
      setState(() => _loading = false);
      WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
      // The desk answers from a browser, so the only way a reply
      // arrives is if we ask for it.
      _poll = Timer.periodic(_pollInterval, (_) => _refresh());
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

  Future<void> _refresh() async {
    final id = _roomId;
    if (id == null || !mounted) return;
    try {
      final room = await HomeApi.fetchChatRoom(id);
      if (!mounted) return;
      _absorb(room['messages']);
      // GET marks the desk's replies read, which is what clears the
      // dot on the bottom-nav Messages icon.
      context.read<AuthState>().refreshUnreadChats();
    } catch (_) {
      // next tick retries
    }
  }

  /// A reply from the desk carries `senderAdmin` and no `sender`, so
  /// "not me" cannot be decided by comparing ids alone — an admin
  /// message would otherwise read as an empty id, which is also what a
  /// malformed row looks like.
  void _absorb(dynamic raw) {
    if (raw is! List) return;
    final mapped = <_Msg>[];
    for (final m in raw) {
      if (m is! Map) continue;
      final body = (m['body'] ?? '').toString();
      if (body.isEmpty) continue;

      final admin = m['senderAdmin'];
      final fromDesk = admin != null;
      final adminName = admin is Map
          ? (admin['name'] ?? '').toString().trim()
          : '';

      final sender = m['sender'];
      final senderId = sender is Map
          ? (sender['_id'] ?? '').toString()
          : (sender ?? '').toString();

      final createdRaw = m['createdAt']?.toString();
      final created = createdRaw == null
          ? null
          : DateTime.tryParse(createdRaw)?.toLocal();

      mapped.add(
        _Msg(
          text: body,
          mine: !fromDesk && senderId.isNotEmpty && senderId == _meId,
          agent: adminName,
          time: created == null ? '' : _clock(created),
          day: created,
          pending: false,
        ),
      );
    }
    if (_same(mapped, _messages)) return;
    final grew = mapped.length > _messages.length;
    setState(() {
      _messages
        ..clear()
        ..addAll(mapped);
    });
    if (grew) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
    }
  }

  bool _same(List<_Msg> a, List<_Msg> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].text != b[i].text ||
          a[i].mine != b[i].mine ||
          a[i].agent != b[i].agent ||
          a[i].pending != b[i].pending) {
        return false;
      }
    }
    return true;
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    final id = _roomId;
    if (text.isEmpty || _sending || id == null) return;

    // Optimistic, so the thread does not sit still for a round trip.
    // Removed again if the POST fails — a message that only ever
    // existed on this screen is worse than no message, because the
    // person stops waiting for an answer that was never asked for.
    final optimistic = _Msg(
      text: text,
      mine: true,
      agent: '',
      time: _clock(DateTime.now()),
      day: DateTime.now(),
      pending: true,
    );
    setState(() {
      _sending = true;
      _messages.add(optimistic);
      _inputCtrl.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());

    try {
      await HomeApi.sendChatMessage(id, text);
      if (!mounted) return;
      setState(() => _sending = false);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _messages.remove(optimistic);
        _inputCtrl.text = text;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException
                ? e.message
                : 'Could not send that. Check your connection.',
          ),
        ),
      );
    }
  }

  Future<void> _call() async {
    final phone = AppConfig.supportPhone.trim();
    if (phone.isEmpty) return;
    final uri = Uri(
      scheme: 'tel',
      path: phone.replaceAll(RegExp(r'[^0-9+]'), ''),
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No dialler available on this phone')),
      );
    }
  }

  void _toBottom() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
  }

  static String _clock(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m ${dt.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final canCall = AppConfig.supportPhone.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Column(
        children: [
          _Header(
            onBack: () => Navigator.maybePop(context),
            onCall: canCall ? _call : null,
          ),
          Expanded(child: _body()),
          _Composer(
            controller: _inputCtrl,
            enabled: _roomId != null && !_sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                size: 38,
                color: AppColors.muted,
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _open, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }

    return ListView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      children: [
        const _Intro(),
        const SizedBox(height: 14),
        for (final m in _messages) _Bubble(msg: m),
      ],
    );
  }
}

// --------------------------------------------------------------- model

class _Msg {
  final String text;
  final bool mine;

  /// Name of the admin who replied. Empty on the user's own messages.
  final String agent;
  final String time;
  final DateTime? day;

  /// Written on this screen but not yet acknowledged by the server.
  final bool pending;

  const _Msg({
    required this.text,
    required this.mine,
    required this.agent,
    required this.time,
    required this.day,
    required this.pending,
  });
}

// --------------------------------------------------------------- pieces

class _Header extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback? onCall;
  const _Header({required this.onBack, this.onCall});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        8,
        MediaQuery.of(context).padding.top + 8,
        8,
        12,
      ),
      decoration: const BoxDecoration(color: Color(0xFF3B5BA9)),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: Colors.white24,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.support_agent_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pargig Support',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2),
                // Not "Online". Nobody is sitting here.
                Text(
                  'We reply as soon as someone is free',
                  style: TextStyle(color: Color(0xFFD6DEF5), fontSize: 11.5),
                ),
              ],
            ),
          ),
          if (onCall != null)
            IconButton(
              onPressed: onCall,
              tooltip: 'Call support',
              icon: const Icon(Icons.call_outlined, color: Colors.white),
            ),
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF3FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD6DEF5)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tell us what you need help with',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F3570),
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Write your question here and our team will answer in this '
            'chat. Replies are not instant — you can close the app and '
            'come back, the conversation stays here.',
            style: TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF3F4E73)),
          ),
          SizedBox(height: 8),
          Text(
            'For a problem with a specific job — payment, quality, '
            'behaviour — raising a ticket from that job gets it to the '
            'right person faster.',
            style: TextStyle(fontSize: 12.5, height: 1.5, color: Color(0xFF68759B)),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final _Msg msg;
  const _Bubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final mine = msg.mine;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.76,
              ),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              decoration: BoxDecoration(
                color: mine ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(mine ? 14 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 14),
                ),
                border: mine
                    ? null
                    : Border.all(color: const Color(0xFFE6E8EE)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Who answered, by name. "Support" alone reads like a
                  // bot; a name is a person who can be held to it.
                  if (!mine && msg.agent.isNotEmpty) ...[
                    Text(
                      msg.agent,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF3B5BA9),
                      ),
                    ),
                    const SizedBox(height: 3),
                  ],
                  Text(
                    msg.text,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.42,
                      color: mine ? Colors.white : AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        msg.time,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: mine ? Colors.white70 : AppColors.muted,
                        ),
                      ),
                      if (mine) ...[
                        const SizedBox(width: 5),
                        Icon(
                          msg.pending
                              ? Icons.schedule
                              : Icons.check_rounded,
                          size: 12,
                          color: Colors.white70,
                        ),
                      ],
                    ],
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

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE6E8EE))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Type your message…',
                  hintStyle: const TextStyle(color: AppColors.muted),
                  filled: true,
                  fillColor: const Color(0xFFF3F4F6),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => enabled ? onSend() : null,
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: enabled ? AppColors.primary : const Color(0xFFE6E8EE),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: enabled ? onSend : null,
                child: const Padding(
                  padding: EdgeInsets.all(11),
                  child: Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
