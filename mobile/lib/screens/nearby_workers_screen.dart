import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/home_api.dart';
import '../config.dart';
import '../state/auth_state.dart';
import 'chat_screen.dart';

/// Figma "Nearby Workers" — reached from the View All link on the
/// Hire-mode home screen's Nearby Workers section. Pulls the same
/// /users/nearby-workers feed the home preview uses, then lets the
/// jobgiver filter by skill chip + free-text search.
///
/// Each card binds to the User shape: name, photo, rating.average,
/// rating.count, skills, isAvailable, lastLocationAt, jobsCompleted,
/// currentLocation.coordinates. Hourly rate isn't on the user model
/// yet — when present (forward-compat after EditProfile lands it
/// on the backend) it renders as ₹X/hr, otherwise the row shows
/// "Rate not set".
class NearbyWorkersScreen extends StatefulWidget {
  const NearbyWorkersScreen({super.key});

  @override
  State<NearbyWorkersScreen> createState() => _NearbyWorkersScreenState();
}

class _NearbyWorkersScreenState extends State<NearbyWorkersScreen> {
  static const _filters = ['All', 'Cleaning', 'Plumbing', 'Electrical'];

  final TextEditingController _searchCtrl = TextEditingController();
  String _filter = 'All';
  String _query = '';
  List<Map<String, dynamic>> _workers = const [];
  final Set<String> _favorites = <String>{};
  bool _loading = true;
  String? _error;
  ({double lat, double lng})? _origin;

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
    final auth = context.read<AuthState>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _origin = _originFromUser(auth.user);
      final list = await HomeApi.nearbyWorkers(
        lat: _origin?.lat,
        lng: _origin?.lng,
        radiusKm: ((auth.user?['searchRadiusKm'] as num?)?.toDouble()) ?? 10,
        limit: 50,
      );
      if (!mounted) return;
      setState(() {
        _workers = list;
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

  ({double lat, double lng})? _originFromUser(Map<String, dynamic>? user) {
    if (user == null) return null;
    for (final key in const ['workArea', 'location', 'currentLocation']) {
      final raw = user[key];
      if (raw is! Map) continue;
      final coords = raw['coordinates'];
      if (coords is! List || coords.length < 2) continue;
      final lng = (coords[0] as num?)?.toDouble();
      final lat = (coords[1] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      if (lat == 0 && lng == 0) continue;
      return (lat: lat, lng: lng);
    }
    return null;
  }

  List<Map<String, dynamic>> get _visible {
    final q = _query.trim().toLowerCase();
    return _workers.where((w) {
      // Free-text search: match against name or any skill.
      if (q.isNotEmpty) {
        final name = (w['name'] ?? '').toString().toLowerCase();
        final skills = w['skills'] is List
            ? (w['skills'] as List).whereType<String>().toList()
            : <String>[];
        final inName = name.contains(q);
        final inSkill = skills.any((s) => s.toLowerCase().contains(q));
        if (!inName && !inSkill) return false;
      }
      // Filter pill: require skills to contain the picked label.
      if (_filter != 'All') {
        final skills = w['skills'] is List
            ? (w['skills'] as List).whereType<String>().toList()
            : <String>[];
        final lower = _filter.toLowerCase();
        if (!skills.any((s) => s.toLowerCase().contains(lower))) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  double? _distanceTo(Map<String, dynamic> worker) {
    final origin = _origin;
    if (origin == null) return null;
    final raw = worker['currentLocation'] is Map
        ? worker['currentLocation']
        : (worker['location'] is Map ? worker['location'] : null);
    if (raw is! Map) return null;
    final coords = raw['coordinates'];
    if (coords is! List || coords.length < 2) return null;
    final lng = (coords[0] as num?)?.toDouble();
    final lat = (coords[1] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    if (lat == 0 && lng == 0) return null;
    return _haversineKm(origin.lat, origin.lng, lat, lng);
  }

  static double _haversineKm(double aLat, double aLng, double bLat, double bLng) {
    const r = 6371.0;
    final dLat = _deg2rad(bLat - aLat);
    final dLng = _deg2rad(bLng - aLng);
    final s = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(aLat)) *
            math.cos(_deg2rad(bLat)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.atan2(math.sqrt(s), math.sqrt(1 - s));
  }

  static double _deg2rad(double d) => d * math.pi / 180.0;

  String _availabilityLabel(Map<String, dynamic> w) {
    final isOnline = w['isAvailable'] == true;
    final last = w['lastLocationAt']?.toString();
    if (isOnline) return 'Available Now';
    if (last != null) {
      final dt = DateTime.tryParse(last);
      if (dt != null) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final dtDay = DateTime(dt.year, dt.month, dt.day);
        if (dtDay == today) return 'Available Today';
      }
    }
    return 'Offline';
  }

  void _toggleFavorite(String id) {
    setState(() {
      if (_favorites.contains(id)) {
        _favorites.remove(id);
      } else {
        _favorites.add(id);
      }
    });
  }

  void _openChat(Map<String, dynamic> w) {
    final name = (w['name'] ?? 'Worker').toString();
    final id = (w['_id'] ?? '').toString();
    Navigator.pushNamed(
      context,
      '/chat',
      arguments: ChatArgs(
        name: name,
        userId: id.isEmpty ? null : id,
        online: w['isAvailable'] == true,
      ),
    );
  }

  void _call(Map<String, dynamic> w) {
    final name = (w['name'] ?? 'Worker').toString();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Calling $name…'),
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          const SizedBox(height: 4),
          _FilterPills(
            filters: _filters,
            selected: _filter,
            onTap: (v) => setState(() => _filter = v),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFFFF6900)),
                    ),
                  )
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline,
                                  size: 40, color: Color(0xFFDC2626)),
                              const SizedBox(height: 10),
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Color(0xFFDC2626)),
                              ),
                              const SizedBox(height: 14),
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
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 16, 20),
                              itemCount: visible.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (_, i) {
                                final w = visible[i];
                                final id = (w['_id'] ?? '').toString();
                                return _WorkerCard(
                                  worker: w,
                                  distanceKm: _distanceTo(w),
                                  availability: _availabilityLabel(w),
                                  favorite: _favorites.contains(id),
                                  onFavorite: () => _toggleFavorite(id),
                                  onChat: () => _openChat(w),
                                  onCall: () => _call(w),
                                );
                              },
                            ),
                          ),
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
        4, MediaQuery.of(context).padding.top + 6, 16, 12,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
            onPressed: onBack,
          ),
          const SizedBox(width: 4),
          const Text(
            'Nearby Workers',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.white,
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
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF101828),
                ),
                decoration: const InputDecoration(
                  hintText: 'Search by name or skill...',
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
          ],
        ),
      ),
    );
  }
}

class _FilterPills extends StatelessWidget {
  final List<String> filters;
  final String selected;
  final ValueChanged<String> onTap;

  const _FilterPills({
    required this.filters,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final f = filters[i];
          final active = f == selected;
          return Material(
            color: active ? Colors.white : Colors.white,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => onTap(f),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: active
                        ? const Color(0xFFFF6900)
                        : const Color(0xFFE5E7EB),
                    width: active ? 1.4 : 1,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                child: Text(
                  f,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: active
                        ? const Color(0xFFFF6900)
                        : const Color(0xFF4A5565),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WorkerCard extends StatelessWidget {
  final Map<String, dynamic> worker;
  final double? distanceKm;
  final String availability;
  final bool favorite;
  final VoidCallback onFavorite;
  final VoidCallback onChat;
  final VoidCallback onCall;

  const _WorkerCard({
    required this.worker,
    required this.distanceKm,
    required this.availability,
    required this.favorite,
    required this.onFavorite,
    required this.onChat,
    required this.onCall,
  });

  String? _photoUrl() {
    final p = worker['photo']?.toString();
    if (p == null || p.isEmpty) return null;
    return p.startsWith('http') ? p : '${AppConfig.apiBase}$p';
  }

  @override
  Widget build(BuildContext context) {
    final name = (worker['name'] ?? 'Worker').toString();
    final rating = worker['rating'] is Map
        ? ((worker['rating']['average'] ?? 0) as num).toStringAsFixed(1)
        : '0.0';
    final ratingCount = worker['rating'] is Map
        ? (worker['rating']['count'] ?? 0).toString()
        : '0';
    final skills = worker['skills'] is List
        ? (worker['skills'] as List).whereType<String>().toList()
        : <String>[];
    final jobsCompleted = (worker['jobsCompleted'] as num?)?.toInt() ?? 0;
    final headline = skills.isNotEmpty ? skills.first : 'Worker';
    final rateRaw = worker['hourlyRate'];
    final rateText = rateRaw is num ? '₹${rateRaw.toInt()}/hr' : null;
    final isAvailableNow = availability == 'Available Now';
    final photoUrl = _photoUrl();
    final distance = distanceKm == null
        ? null
        : '${distanceKm!.toStringAsFixed(distanceKm! < 10 ? 1 : 0)} km';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: Color(0xFFE5E7EB),
                  shape: BoxShape.circle,
                ),
                clipBehavior: Clip.antiAlias,
                child: photoUrl == null
                    ? const Icon(Icons.person,
                        color: Color(0xFF94A3B8), size: 28)
                    : Image.network(
                        photoUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.person,
                          color: Color(0xFF94A3B8),
                          size: 28,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF101828),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      headline,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.star,
                            size: 13, color: Color(0xFFFFB300)),
                        const SizedBox(width: 4),
                        Text(
                          rating,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF101828),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '($ratingCount)',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                        if (distance != null) ...[
                          const SizedBox(width: 10),
                          const Icon(Icons.location_on_outlined,
                              size: 13, color: Color(0xFF6B7280)),
                          const SizedBox(width: 2),
                          Text(
                            distance,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onFavorite,
                icon: Icon(
                  favorite ? Icons.favorite : Icons.favorite_outline,
                  size: 22,
                  color: favorite
                      ? const Color(0xFFE7000B)
                      : const Color(0xFF9CA3AF),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _AvailabilityPill(
                label: availability,
                online: isAvailableNow,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$jobsCompleted jobs',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
            ],
          ),
          if (skills.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: skills
                  .take(4)
                  .map((s) => Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Text(
                          s,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF4A5565),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: OutlinedButton.icon(
                    onPressed: onChat,
                    icon: const Icon(Icons.chat_bubble_outline,
                        size: 16, color: Color(0xFFFF6900)),
                    label: const Text(
                      'Chat',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFFF6900),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      side: const BorderSide(
                          color: Color(0xFFFF6900), width: 1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 42,
                height: 42,
                child: Material(
                  color: const Color(0xFF16A34A),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onCall,
                    child: const Center(
                      child: Icon(Icons.call,
                          size: 18, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 0.6,
            color: const Color(0xFFF1F5F9),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text(
                'Hourly Rate',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B7280),
                ),
              ),
              const Spacer(),
              Text(
                rateText ?? 'Not set',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: rateText == null
                      ? const Color(0xFF9CA3AF)
                      : const Color(0xFFFF6900),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AvailabilityPill extends StatelessWidget {
  final String label;
  final bool online;

  const _AvailabilityPill({required this.label, required this.online});

  @override
  Widget build(BuildContext context) {
    final bg = online ? const Color(0xFFDCFCE7) : const Color(0xFFF3F4F6);
    final fg = online ? const Color(0xFF16A34A) : const Color(0xFF6B7280);
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
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
            Icon(Icons.handyman_outlined,
                size: 40, color: Color(0xFF9CA3AF)),
            SizedBox(height: 12),
            Text(
              'No workers match',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF101828),
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Try a different skill filter or clear the search.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
