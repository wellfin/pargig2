import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/home_api.dart';
import '../state/auth_state.dart';

/// Ratings for every past job, split into what this user RECEIVED and
/// what they GAVE.
///
/// The profile only ever showed one aggregate star average. There was no
/// way for either side to look back at an individual past job and see
/// what was exchanged on it — a worker's number moved with nothing
/// saying who moved it, and neither side could check what they
/// themselves had left. The two directions are separate tabs because
/// they are separate facts: mixing them into one feed makes the reader
/// decode every row to work out which way it points.
///
/// Both roles use this screen unchanged. A job giver's received ratings
/// come from workers and vice versa, but the shape is identical, so
/// nothing here branches on role.
class MyReviewsScreen extends StatefulWidget {
  const MyReviewsScreen({super.key});

  @override
  State<MyReviewsScreen> createState() => _MyReviewsScreenState();
}

class _MyReviewsScreenState extends State<MyReviewsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  List<Map<String, dynamic>> _ratings = const [];
  Map<String, int> _breakdown = const {};
  double _average = 0;
  int _total = 0;
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _given = const [];
  bool _givenLoading = true;
  String? _givenError;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _asList(dynamic res) {
    final raw = res is Map ? res['ratings'] : res;
    return raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : const [];
  }

  /// Ratings this user left on past jobs. Scoped to the caller by the
  /// backend, so it needs no user id.
  Future<void> _loadGiven() async {
    setState(() {
      _givenLoading = true;
      _givenError = null;
    });
    try {
      final res = await ApiClient.get('/ratings/given');
      if (!mounted) return;
      setState(() {
        _given = _asList(res);
        _givenLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _givenLoading = false;
        _givenError = e is ApiException ? e.message : e.toString();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadGiven();
  }

  Future<void> _load() async {
    final me = context.read<AuthState>().user?['_id']?.toString();
    if (me == null || me.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Sign in to see your reviews';
        _givenLoading = false;
        _givenError = 'Sign in to see your reviews';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.get('/ratings/user/$me');
      if (!mounted) return;
      setState(() {
        _ratings = _asList(res);
        if (res is Map) {
          _average = (res['average'] as num?)?.toDouble() ?? 0;
          _total = (res['total'] as num?)?.toInt() ?? _ratings.length;
          final b = res['breakdown'];
          _breakdown = b is Map
              ? b.map(
                  (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
                )
              : const {};
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF408EE0),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Ratings & Reviews',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: const Color(0xCCFFFFFF),
          labelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          tabs: [
            Tab(text: 'Received${_total > 0 ? ' ($_total)' : ''}'),
            Tab(text: 'Given${_given.isNotEmpty ? ' (${_given.length})' : ''}'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_receivedTab(), _givenTab()],
      ),
    );
  }

  /// What other people thought of this user. Keeps the star summary,
  /// because that average is the number the profile shows.
  Widget _receivedTab() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: _error != null
          ? _scrollableMessage(_error!, isError: true)
          : _ratings.isEmpty
          ? _scrollableMessage(
              'No ratings received yet.\nFinish a job and what the '
              'other side gave you shows up here.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
              children: [
                _summary(),
                const SizedBox(height: 14),
                for (final r in _ratings) ...[
                  _ReviewCard(rating: r, received: true),
                  const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }

  /// What this user left on past jobs. No star summary here: an average
  /// of the scores you handed out is not a fact about you.
  Widget _givenTab() {
    if (_givenLoading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _loadGiven,
      child: _givenError != null
          ? _scrollableMessage(_givenError!, isError: true)
          : _given.isEmpty
          ? _scrollableMessage(
              'You have not rated anyone yet.\nRatings you leave after '
              'a job show up here.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
              children: [
                for (final r in _given) ...[
                  _ReviewCard(rating: r, received: false),
                  const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }

  // Scrollable so pull-to-retry still works with nothing in the list.
  Widget _scrollableMessage(String text, {bool isError = false}) => ListView(
    children: [
      const SizedBox(height: 140),
      Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.star_border,
                size: 42,
                color: isError ? const Color(0xFFDC2626) : Colors.grey.shade400,
              ),
              const SizedBox(height: 12),
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: isError
                      ? const Color(0xFFDC2626)
                      : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _summary() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDEFF3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            children: [
              Text(
                _average.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF101828),
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              _Stars(stars: _average.round(), size: 14),
              const SizedBox(height: 4),
              Text(
                '$_total ${_total == 1 ? 'review' : 'reviews'}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
            ],
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              children: [
                // 5 down to 1, the order people expect to read.
                for (var s = 5; s >= 1; s--)
                  _BreakdownRow(
                    stars: s,
                    count: _breakdown['$s'] ?? 0,
                    total: _total,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final int stars;
  final int count;
  final int total;
  const _BreakdownRow({
    required this.stars,
    required this.count,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : count / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            child: Text(
              '$stars',
              style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
            ),
          ),
          const Icon(Icons.star, size: 11, color: Color(0xFFFFB400)),
          const SizedBox(width: 6),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 6,
                backgroundColor: const Color(0xFFF3F4F6),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFFFFB400),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 18,
            child: Text(
              '$count',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> rating;

  /// true = this user was rated; false = this user did the rating.
  /// Decides which side of the pair is the counterparty worth naming --
  /// showing people their own name back says nothing.
  final bool received;

  const _ReviewCard({required this.rating, required this.received});

  @override
  Widget build(BuildContext context) {
    final key = received ? 'rater' : 'ratee';
    final other = rating[key] is Map ? rating[key] as Map : const {};
    final name = (other['name'] ?? 'Someone').toString();
    final photo = (other['photo'] ?? '').toString();
    final job = rating['job'] is Map ? rating['job'] as Map : const {};
    final jobTitle = (job['title'] ?? '').toString();
    final stars = (rating['stars'] as num?)?.toInt() ?? 0;
    final review = (rating['review'] ?? '').toString().trim();
    final tags = rating['tags'] is List
        ? (rating['tags'] as List).whereType<String>().toList()
        : const <String>[];
    final when = DateTime.tryParse(
      (rating['createdAt'] ?? '').toString(),
    )?.toLocal();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDEFF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: photo.trim().isEmpty
                    ? null
                    : NetworkImage(HomeApi.absoluteUrl(photo)),
                child: photo.trim().isEmpty
                    ? Icon(Icons.person, size: 18, color: Colors.grey.shade600)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF101828),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      received ? 'rated you' : 'you rated',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                    if (jobTitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        jobTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _Stars(stars: stars, size: 15),
            ],
          ),
          if (review.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              review,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Color(0xFF364153),
              ),
            ),
          ],
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in tags)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      t,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (when != null) ...[
            const SizedBox(height: 10),
            Text(
              _ago(when),
              style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
            ),
          ],
        ],
      ),
    );
  }

  static String _ago(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) {
      return '${d.inHours} ${d.inHours == 1 ? 'hour' : 'hours'} ago';
    }
    if (d.inDays < 7) {
      return '${d.inDays} ${d.inDays == 1 ? 'day' : 'days'} ago';
    }
    final w = (d.inDays / 7).floor();
    return '$w ${w == 1 ? 'week' : 'weeks'} ago';
  }
}

class _Stars extends StatelessWidget {
  final int stars;
  final double size;
  const _Stars({required this.stars, required this.size});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (i) => Icon(
          i < stars ? Icons.star : Icons.star_border,
          size: size,
          color: i < stars ? const Color(0xFFFFB400) : const Color(0xFFD1D5DB),
        ),
      ),
    );
  }
}
