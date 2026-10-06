import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/home_api.dart';
import '../config.dart';
import '../state/auth_state.dart';
import '../utils/rating.dart';

/// Full-screen results list shown after the user taps Apply Filters on
/// the SearchJobs screen. Renders the Figma "Cleaning — 12 jobs found
/// within 5km" card-list design. Navigated to via
/// `Navigator.pushNamed('/job-list-results', arguments: JobListArgs(...))`.
class JobListArgs {
  final double? lat;
  final double? lng;
  final double radiusKm;
  final String? query;
  final double? minPrice;
  final double? maxPrice;
  final List<String> categories;
  final String sortBy;
  // Optional pre-fetched results — if provided, the screen renders them
  // immediately and refetches on pull-to-refresh.
  final List<Map<String, dynamic>>? initialResults;

  const JobListArgs({
    required this.lat,
    required this.lng,
    required this.radiusKm,
    required this.categories,
    required this.sortBy,
    this.query,
    this.minPrice,
    this.maxPrice,
    this.initialResults,
  });
}

class JobListResultsScreen extends StatefulWidget {
  const JobListResultsScreen({super.key});

  @override
  State<JobListResultsScreen> createState() => _JobListResultsScreenState();
}

class _JobListResultsScreenState extends State<JobListResultsScreen> {
  JobListArgs? _args;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _results = const [];
  final Set<String> _favorites = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_args != null) return;
    final raw = ModalRoute.of(context)?.settings.arguments;
    if (raw is JobListArgs) {
      _args = raw;
      if (raw.initialResults != null) {
        _results = raw.initialResults!;
        _loading = false;
      } else {
        _fetch();
      }
    } else {
      _loading = false;
      _error = 'No filters provided';
    }
  }

  Future<void> _fetch() async {
    final a = _args;
    if (a == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await HomeApi.browse(
        lat: a.lat,
        lng: a.lng,
        radiusKm: a.radiusKm,
        limit: 50,
        q: a.query,
        minPrice: a.minPrice,
        maxPrice: a.maxPrice,
        categories: a.categories.isEmpty ? null : a.categories,
        sortBy: a.sortBy,
      );
      if (!mounted) return;
      setState(() {
        _results = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  String _headerTitle() {
    final cats = _args?.categories ?? const <String>[];
    if (cats.length == 1) return cats.first;
    if (cats.isEmpty) return 'All Jobs';
    return 'Jobs';
  }

  String _countLine() {
    return '${_results.length} jobs found';
  }

  // Back goes one step (to the search screen). Falls back to Home if this
  // somehow opened as the only route, so it's never a dead end.
  void _goBack() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              title: _headerTitle(),
              subtitle: _countLine(),
              onBack: _goBack,
              onSearchTap: _goBack,
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading && _results.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6900)),
        ),
      );
    }
    if (_error != null && _results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 40,
                color: Color(0xFFDC2626),
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _fetch, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'No jobs match your filters yet. Try clearing a category.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: const Color(0xFFFF6900),
      onRefresh: _fetch,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: _results.length,
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (_, i) {
          final job = _results[i];
          final id = (job['_id'] ?? '').toString();
          return _JobCard(
            job: job,
            distanceKm: _distanceKm(job),
            timeAgo: _timeAgo(job['createdAt']),
            isFav: _favorites.contains(id),
            onFavTap: () => setState(() {
              if (_favorites.contains(id)) {
                _favorites.remove(id);
              } else {
                _favorites.add(id);
              }
            }),
            onTap: () =>
                Navigator.pushNamed(context, '/job-details', arguments: id),
          );
        },
      ),
    );
  }

  double _distanceKm(Map<String, dynamic> job) {
    final jobLoc = job['location'];
    final jobCoords = (jobLoc is Map ? jobLoc['coordinates'] : null);
    if (jobCoords is! List ||
        jobCoords.length != 2 ||
        (jobCoords[0] == 0 && jobCoords[1] == 0)) {
      return 0;
    }
    final jLng = (jobCoords[0] as num).toDouble();
    final jLat = (jobCoords[1] as num).toDouble();

    final refLat = _args?.lat;
    final refLng = _args?.lng;
    if (refLat == null || refLng == null) {
      // Fallback to viewer's workArea / home from auth state.
      final user = context.read<AuthState>().user ?? const <String, dynamic>{};
      List? c;
      final wa = user['workArea'];
      if (wa is Map && wa['coordinates'] is List) {
        final t = wa['coordinates'] as List;
        if (t.length == 2 && !(t[0] == 0 && t[1] == 0)) c = t;
      }
      if (c == null) {
        final home = user['location'];
        if (home is Map && home['coordinates'] is List) {
          final t = home['coordinates'] as List;
          if (t.length == 2 && !(t[0] == 0 && t[1] == 0)) c = t;
        }
      }
      if (c == null) return 0;
      return _haversine(
        (c[1] as num).toDouble(),
        (c[0] as num).toDouble(),
        jLat,
        jLng,
      );
    }
    return _haversine(refLat, refLng, jLat, jLng);
  }

  String _timeAgo(dynamic raw) {
    if (raw == null) return '';
    DateTime? dt;
    if (raw is String) dt = DateTime.tryParse(raw)?.toLocal();
    if (raw is DateTime) dt = raw;
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return '$h hour${h == 1 ? '' : 's'} ago';
    }
    if (diff.inDays < 7) {
      final d = diff.inDays;
      return '$d day${d == 1 ? '' : 's'} ago';
    }
    final w = (diff.inDays / 7).floor();
    if (w < 4) return '$w week${w == 1 ? '' : 's'} ago';
    final m = (diff.inDays / 30).floor();
    return '$m month${m == 1 ? '' : 's'} ago';
  }

  static double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final VoidCallback onSearchTap;

  const _Header({
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.onSearchTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF408EE0),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 18),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
            onPressed: onBack,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xCCFFFFFF),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white, size: 22),
            onPressed: onSearchTap,
          ),
        ],
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final double distanceKm;
  final String timeAgo;
  final bool isFav;
  final VoidCallback onFavTap;
  final VoidCallback onTap;

  const _JobCard({
    required this.job,
    required this.distanceKm,
    required this.timeAgo,
    required this.isFav,
    required this.onFavTap,
    required this.onTap,
  });

  String? _photoUrl() {
    final photos = job['photos'];
    if (photos is List && photos.isNotEmpty) {
      final raw = photos.first?.toString() ?? '';
      if (raw.isEmpty) return null;
      return raw.startsWith('http') ? raw : '${AppConfig.apiBase}$raw';
    }
    return null;
  }

  String _posterLine() {
    final poster = job['jobgiver'];
    if (poster is Map) {
      final name = (poster['name'] ?? '').toString().trim();
      final shown = name.isEmpty ? 'Unknown' : _shortName(name);
      // Always show a star. Hiding it for unrated givers meant two
      // adjacent rows disagreed about whether posters have ratings at all.
      return 'Posted by $shown ⭐ ${displayRating(poster['rating'])}';
    }
    return '';
  }

  String _shortName(String full) {
    final parts = full.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first;
    return '${parts.first} ${parts.last[0]}.';
  }

  String _distanceText() {
    if (distanceKm <= 0) return 'Nearby';
    if (distanceKm < 1) return '${(distanceKm * 1000).round()} m away';
    if (distanceKm < 10) return '${distanceKm.toStringAsFixed(1)} km away';
    return '${distanceKm.round()} km away';
  }

  @override
  Widget build(BuildContext context) {
    final title = (job['title'] ?? '').toString();
    final basePrice = (job['finalPrice'] ?? job['proposedBudget'] ?? 0) as num;
    final tip = (job['tip'] ?? 0) as num;
    // Price shown everywhere always includes the tip (and the boost fee,
    // when boosted) as one combined total.
    final price =
        (job['isBoosted'] == true
            ? basePrice + AppConfig.boostFee
            : basePrice) +
        tip;
    final urgent = job['isUrgent'] == true;
    final photo = _photoUrl();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      topRight: Radius.circular(18),
                    ),
                    child: SizedBox(
                      height: 160,
                      width: double.infinity,
                      child: photo != null
                          ? Image.network(
                              photo,
                              fit: BoxFit.cover,
                              loadingBuilder: (ctx, child, prog) {
                                if (prog == null) return child;
                                return _placeholder();
                              },
                              errorBuilder: (_, _, _) => _placeholder(),
                            )
                          : _placeholder(),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Material(
                      color: Colors.white,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onFavTap,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            isFav ? Icons.favorite : Icons.favorite_border,
                            size: 18,
                            color: const Color(0xFFFF6900),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (urgent)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6900),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: const Text(
                          'Urgent',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF101828),
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.person_outline,
                          size: 14,
                          color: Color(0xFF6B7280),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _distanceText(),
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF4A5565),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(
                          Icons.access_time,
                          size: 14,
                          color: Color(0xFF6B7280),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          timeAgo,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF4A5565),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _posterLine(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF4A5565),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '₹ ${price.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF101828),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
    color: const Color(0xFFE5E7EB),
    child: const Center(
      child: Icon(Icons.image_outlined, size: 40, color: Color(0xFF9CA3AF)),
    ),
  );
}
