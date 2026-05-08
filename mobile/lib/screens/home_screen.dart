import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/home_api.dart';
import '../config.dart';
import '../state/auth_state.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Curated categories with their visual asset; counts come from backend.
  static const _curatedCategories = <_CuratedCategory>[
    _CuratedCategory('Plumbing', 'assets/home/cat_plumbing.png'),
    _CuratedCategory('Carpentry', 'assets/home/cat_carpentry.png'),
    _CuratedCategory('Painting', 'assets/home/cat_painting.png'),
    _CuratedCategory('Cleaning', 'assets/home/cat_cleaning.png'),
    _CuratedCategory('Electrical', 'assets/home/cat_electrical.png'),
    _CuratedCategory('Babysitting', 'assets/home/cat_babysitting.png'),
  ];

  // Fallback image used when a job has no photo, keyed by category.
  static const _categoryFallback = <String, String>{
    'Cleaning': 'assets/home/rec_home_cleaning.png',
    'Plumbing': 'assets/home/rec_plumbing.png',
    'Painting': 'assets/home/rec_painting.png',
    'Carpentry': 'assets/home/rec_furniture.png',
    'Assembly': 'assets/home/rec_furniture.png',
    'Electrical': 'assets/home/rec_plumbing.png',
    'Babysitting': 'assets/home/cat_babysitting.png',
  };
  static const _genericFallback = 'assets/home/job_cleaning_house.png';

  Map<String, int> _categoryCounts = const {};
  List<Map<String, dynamic>> _nearbyJobs = const [];
  List<Map<String, dynamic>> _recommendedJobs = const [];
  Map<String, dynamic> _earnings = const {};

  // Hire-view state.
  List<Map<String, dynamic>> _myPostedJobs = const [];
  List<Map<String, dynamic>> _nearbyWorkers = const [];

  bool _loading = true;
  String? _loadError;
  int _bottomIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });

    final auth = context.read<AuthState>();
    // Pull the latest user record (location, jobsCompleted, rating, etc.) so
    // any backend-side changes — including the seed script — show up without
    // a full app restart. Failure is non-fatal; we fall through to the data
    // fetches below using whatever auth state we already have.
    try {
      await auth.refreshMe();
    } catch (_) {}
    if (!mounted) return;
    final loc = auth.user?['location'] is Map
        ? auth.user!['location'] as Map
        : const {};
    final coords = loc['coordinates'];
    double? lat;
    double? lng;
    if (coords is List && coords.length == 2) {
      lng = (coords[0] as num?)?.toDouble();
      lat = (coords[1] as num?)?.toDouble();
      if (lat == 0 && lng == 0) {
        lat = null;
        lng = null;
      }
    }

    try {
      final isJobGiver = auth.isJobGiver;
      const emptyList = <Map<String, dynamic>>[];
      // Fetch in parallel. Hire view needs posted jobs + nearby workers
      // instead of categories + jobs feed. Each branch returns an explicitly
      // typed empty list so Future.wait can infer a homogeneous type.
      final categoriesF = !isJobGiver
          ? HomeApi.categories()
          : Future<List<Map<String, dynamic>>>.value(emptyList);
      final nearbyF = !isJobGiver
          ? HomeApi.browse(lat: lat, lng: lng, radiusKm: 5, limit: 4)
          : Future<List<Map<String, dynamic>>>.value(emptyList);
      final recommendedF = !isJobGiver
          ? HomeApi.browse(lat: lat, lng: lng, radiusKm: 25, limit: 8)
          : Future<List<Map<String, dynamic>>>.value(emptyList);
      final earningsF = HomeApi.earnings();
      final postedJobsF = isJobGiver
          ? HomeApi.myPostedJobs()
          : Future<List<Map<String, dynamic>>>.value(emptyList);
      final workersF = isJobGiver
          ? HomeApi.nearbyWorkers(lat: lat, lng: lng, radiusKm: 5, limit: 12)
          : Future<List<Map<String, dynamic>>>.value(emptyList);

      final results = await Future.wait<dynamic>([
        categoriesF,
        nearbyF,
        recommendedF,
        earningsF,
        postedJobsF,
        workersF,
      ]);
      if (!mounted) return;
      final categories = results[0] as List<Map<String, dynamic>>;
      final nearby = results[1] as List<Map<String, dynamic>>;
      final recommended = results[2] as List<Map<String, dynamic>>;
      final nearbyIds = nearby.map((j) => j['_id']).toSet();
      setState(() {
        _categoryCounts = {
          for (final c in categories)
            (c['category'] ?? '').toString(): (c['count'] as num?)?.toInt() ?? 0,
        };
        _nearbyJobs = nearby;
        _recommendedJobs = recommended
            .where((j) => !nearbyIds.contains(j['_id']))
            .take(4)
            .toList();
        _earnings = results[3] as Map<String, dynamic>;
        _myPostedJobs = results[4] as List<Map<String, dynamic>>;
        _nearbyWorkers = results[5] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e is ApiException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  bool _useCurrentLocation = false;
  bool _gpsLoading = false;

  Future<void> _toggleRole() async {
    final auth = context.read<AuthState>();
    final newRole = auth.isJobGiver ? 'jobtaker' : 'jobgiver';
    try {
      await auth.switchRole(newRole);
      if (mounted) _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't switch role: $e")),
      );
    }
  }

  Future<void> _toggleCurrentLocation() async {
    if (_gpsLoading) return;
    if (_useCurrentLocation) {
      // Turning off — keep the saved location, just flip the visual.
      setState(() => _useCurrentLocation = false);
      return;
    }
    setState(() {
      _useCurrentLocation = true;
      _gpsLoading = true;
    });
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) throw 'Turn on location services';
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw 'Location permission denied';
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      String? address;
      String? city;
      String? state;
      String? pincode;
      try {
        final placemarks =
            await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          address = [p.street, p.subLocality]
              .whereType<String>()
              .where((s) => s.trim().isNotEmpty)
              .join(', ');
          city = p.locality ?? p.subAdministrativeArea;
          state = p.administrativeArea;
          pincode = p.postalCode;
        }
      } catch (_) {
        // Coordinates captured even if reverse geocoding failed.
      }
      if (!mounted) return;
      await context.read<AuthState>().updateLocation(
            pos.latitude,
            pos.longitude,
            address: address,
            city: city,
            state: state,
            pincode: pincode,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location updated to your current spot'),
          duration: Duration(milliseconds: 1200),
        ),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() => _useCurrentLocation = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  void _onTabTapped(int i) {
    if (i == _bottomIndex) return;
    setState(() => _bottomIndex = i);
    if (i != 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Coming soon'),
          duration: Duration(milliseconds: 800),
        ),
      );
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted) setState(() => _bottomIndex = 0);
      });
    }
  }

  String? _firstPhotoUrl(Map<String, dynamic> job) {
    final photos = job['photos'];
    if (photos is List && photos.isNotEmpty) {
      final raw = photos.first?.toString();
      if (raw != null && raw.isNotEmpty) {
        return raw.startsWith('http') ? raw : '${AppConfig.apiBase}$raw';
      }
    }
    return null;
  }

  String _fallbackForCategory(String? category) {
    return _categoryFallback[category ?? ''] ?? _genericFallback;
  }

  double _distanceKmFrom(Map<String, dynamic> job) {
    final auth = context.read<AuthState>();
    final myLoc = auth.user?['location'] is Map
        ? auth.user!['location'] as Map
        : const {};
    final myCoords = myLoc['coordinates'];
    final jobLoc = job['location'] is Map ? job['location'] as Map : const {};
    final jobCoords = jobLoc['coordinates'];
    if (myCoords is! List ||
        jobCoords is! List ||
        myCoords.length != 2 ||
        jobCoords.length != 2) {
      return 0;
    }
    final myLng = (myCoords[0] as num?)?.toDouble() ?? 0;
    final myLat = (myCoords[1] as num?)?.toDouble() ?? 0;
    final jLng = (jobCoords[0] as num?)?.toDouble() ?? 0;
    final jLat = (jobCoords[1] as num?)?.toDouble() ?? 0;
    if ((myLat == 0 && myLng == 0) || (jLat == 0 && jLng == 0)) return 0;
    return _haversineKm(myLat, myLng, jLat, jLng);
  }

  static double _haversineKm(double aLat, double aLng, double bLat, double bLng) {
    const r = 6371.0;
    double toRad(double v) => v * 3.141592653589793 / 180.0;
    final dLat = toRad(bLat - aLat);
    final dLng = toRad(bLng - aLng);
    final h = (1 - _cos(dLat)) / 2 +
        _cos(toRad(aLat)) * _cos(toRad(bLat)) * (1 - _cos(dLng)) / 2;
    return 2 * r * _asin(_sqrt(h));
  }

  static double _cos(double v) => _trig(v, 0);
  static double _sqrt(double v) => v <= 0 ? 0 : _power(v, 0.5);
  static double _asin(double v) {
    if (v <= -1) return -1.5707963267948966;
    if (v >= 1) return 1.5707963267948966;
    // Taylor approx good enough for small distances on a phone screen
    return v + (v * v * v) / 6.0 + (3 * v * v * v * v * v) / 40.0;
  }

  static double _trig(double v, int kind) {
    // kind=0 cos. Use Taylor series; we don't need high precision for ~km display.
    var x = v;
    while (x > 3.141592653589793) {
      x -= 2 * 3.141592653589793;
    }
    while (x < -3.141592653589793) {
      x += 2 * 3.141592653589793;
    }
    final x2 = x * x;
    return 1 - x2 / 2 + (x2 * x2) / 24 - (x2 * x2 * x2) / 720;
  }

  static double _power(double base, double exp) {
    // Only used with exp=0.5 (sqrt). Newton's method.
    if (exp == 0.5) {
      var s = base;
      for (var i = 0; i < 20; i++) {
        s = (s + base / s) / 2;
      }
      return s;
    }
    return base;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final user = auth.user ?? const {};
    final loc = user['location'] is Map ? user['location'] as Map : const {};
    final city = (loc['city'] ?? '').toString();
    final address = (loc['address'] ?? '').toString();
    final locationLabel = [
      if (address.isNotEmpty) address,
      if (city.isNotEmpty) city,
    ].join(', ');
    final locationDisplay =
        locationLabel.isEmpty ? 'Set your location' : locationLabel;

    final rating = user['rating'] is Map
        ? ((user['rating']['average'] ?? 0) as num).toStringAsFixed(1)
        : '0.0';
    final jobsDone = (user['jobsCompleted'] ?? 0).toString();
    final jobsCancelled = (user['jobsCancelled'] ?? 0) as int;
    final completed = int.tryParse(jobsDone) ?? 0;
    final totalJobs = completed + jobsCancelled;
    final successPct = totalJobs == 0
        ? '—'
        : '${((completed / totalJobs) * 100).round()}%';

    final isWorking = !auth.isJobGiver;
    final today = (_earnings['today'] as num?)?.toInt() ?? 0;
    final thisWeek = (_earnings['thisWeek'] as num?)?.toInt() ?? 0;
    final deltaPct = (_earnings['deltaPct'] as num?)?.toInt();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            RefreshIndicator(
              color: const Color(0xFFFF6900),
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 90),
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                children: [
                  _Header(
                    locationLabel: locationDisplay,
                    isWorking: isWorking,
                    onToggleWorking: _toggleRole,
                    useCurrentLocation: _useCurrentLocation,
                    gpsLoading: _gpsLoading,
                    onToggleCurrentLocation: _toggleCurrentLocation,
                    todayEarnings: today,
                    weekEarnings: thisWeek,
                    deltaPct: deltaPct,
                    onSearchTap: () =>
                        Navigator.pushNamed(context, '/search'),
                    onNotificationsTap: () =>
                        ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Notifications coming soon')),
                    ),
                  ),
                  if (_loadError != null) _ErrorBanner(
                    message: _loadError!,
                    onRetry: _refresh,
                  ),
                  if (auth.isJobGiver) ...[
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _PostNewJobButton(
                        onTap: () async {
                          final posted = await Navigator.pushNamed(
                            context,
                            '/post-job',
                          );
                          if (posted == true && mounted) _refresh();
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    _SectionHeader(
                      title: 'Active Jobs',
                      onViewAll: () async {
                        final changed = await Navigator.pushNamed(
                          context,
                          '/my-posted-jobs',
                        );
                        if (changed == true && mounted) _refresh();
                      },
                      viewAllColor: const Color(0xFFFF6900),
                    ),
                    const SizedBox(height: 12),
                    _ActiveJobsList(
                      jobs: _myPostedJobs
                          .where((j) => const ['open', 'confirmed', 'in_progress']
                              .contains(j['status']))
                          .take(3)
                          .toList(),
                      loading: _loading && _myPostedJobs.isEmpty,
                      onTapJob: (job) async {
                        final id = (job['_id'] ?? '').toString();
                        if (id.isEmpty) return;
                        final changed = await Navigator.pushNamed(
                          context,
                          '/job-details',
                          arguments: id,
                        );
                        if (changed == true && mounted) _refresh();
                      },
                    ),
                    const SizedBox(height: 24),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Recent Activity',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF101828),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _RecentActivityList(jobs: _myPostedJobs),
                    const SizedBox(height: 24),
                    _SectionHeader(
                      title: 'Nearby Workers',
                      icon: Icons.handyman_outlined,
                      onViewAll: () {},
                      viewAllColor: const Color(0xFFFF6900),
                    ),
                    const SizedBox(height: 12),
                    _NearbyWorkersRow(
                      workers: _nearbyWorkers,
                      loading: _loading && _nearbyWorkers.isEmpty,
                    ),
                    const SizedBox(height: 24),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: _VerifiedWorkersCard(),
                    ),
                    const SizedBox(height: 24),
                  ] else ...[
                    const SizedBox(height: 20),
                    _SectionHeader(
                      title: 'Browse all categories',
                      onViewAll: () => Navigator.pushNamed(context, '/search'),
                    ),
                    const SizedBox(height: 16),
                    _CategoriesRow(
                      items: _curatedCategories,
                      counts: _categoryCounts,
                      onTapCategory: (name) => Navigator.pushNamed(
                        context,
                        '/search',
                        arguments: {'category': name},
                      ),
                    ),
                    const SizedBox(height: 28),
                    _SectionHeader(
                      title: 'Jobs Near You',
                      onViewAll: () => Navigator.pushNamed(context, '/search'),
                    ),
                    const SizedBox(height: 16),
                    if (_loading && _nearbyJobs.isEmpty)
                      const _LoadingBlock(height: 410)
                    else if (_nearbyJobs.isEmpty)
                      const _EmptyState(message: 'No jobs near you yet.')
                    else
                      _NearbyGrid(
                        items: _nearbyJobs,
                        photoUrl: _firstPhotoUrl,
                        fallbackForCategory: _fallbackForCategory,
                        distanceKm: _distanceKmFrom,
                      ),
                    const SizedBox(height: 24),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Recommended for You',
                        style: TextStyle(
                          fontSize: 18,
                          color: Color(0xFF1B2431),
                          letterSpacing: -0.54,
                          height: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_loading && _recommendedJobs.isEmpty)
                      const _LoadingBlock(height: 320)
                    else if (_recommendedJobs.isEmpty)
                      const _EmptyState(message: 'No recommendations yet.')
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: _recommendedJobs
                              .map((j) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _RecommendedCard(
                                      job: j,
                                      photoUrl: _firstPhotoUrl(j),
                                      fallback: _fallbackForCategory(
                                        (j['category'] ?? '').toString(),
                                      ),
                                      distanceKm: _distanceKmFrom(j),
                                    ),
                                  ))
                              .toList(),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _PerformanceCard(
                        jobsDone: jobsDone,
                        rating: rating,
                        successPct: successPct,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ],
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: _BottomNav(
                currentIndex: _bottomIndex,
                onTap: _onTabTapped,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CuratedCategory {
  final String name;
  final String image;
  const _CuratedCategory(this.name, this.image);
}

class _LoadingBlock extends StatelessWidget {
  final double height;
  const _LoadingBlock({required this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6900)),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: Center(
        child: Text(
          message,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF6A7282),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF991B1B),
                ),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFDC2626),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Retry', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String locationLabel;
  final bool isWorking;
  final VoidCallback onToggleWorking;
  final bool useCurrentLocation;
  final bool gpsLoading;
  final VoidCallback onToggleCurrentLocation;
  final int todayEarnings;
  final int weekEarnings;
  final int? deltaPct;
  final VoidCallback onSearchTap;
  final VoidCallback onNotificationsTap;

  const _Header({
    required this.locationLabel,
    required this.isWorking,
    required this.onToggleWorking,
    required this.useCurrentLocation,
    required this.gpsLoading,
    required this.onToggleCurrentLocation,
    required this.todayEarnings,
    required this.weekEarnings,
    required this.deltaPct,
    required this.onSearchTap,
    required this.onNotificationsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF3B69B4),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            top: -46,
            left: -46,
            child: Container(
              width: 324,
              height: 100,
              decoration: const BoxDecoration(
                color: Color(0xFF2F62B5),
                borderRadius: BorderRadius.all(Radius.circular(1000)),
              ),
            ),
          ),
          Positioned(
            top: 95,
            right: -46,
            child: Container(
              width: 100,
              height: 100,
              decoration: const BoxDecoration(
                color: Color(0xFF2F62B5),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Current Location',
                            style: TextStyle(
                              fontSize: 10,
                              color: Color(0xA6FFFFFF),
                              height: 1.4,
                            ),
                          ),
                          Text(
                            locationLabel,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                              height: 1.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    _GpsToggle(
                      isOn: useCurrentLocation,
                      loading: gpsLoading,
                      onTap: onToggleCurrentLocation,
                    ),
                    const SizedBox(width: 12),
                    Material(
                      color: const Color(0x0DFFFFFF),
                      shape: const CircleBorder(),
                      child: InkWell(
                        onTap: onNotificationsTap,
                        customBorder: const CircleBorder(),
                        child: const SizedBox(
                          width: 32,
                          height: 32,
                          child: Icon(
                            Icons.notifications_none,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _RoleToggle(
                      isWorking: isWorking,
                      onChanged: onToggleWorking,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: _SearchField(onTap: onSearchTap)),
                  ],
                ),
                const SizedBox(height: 14),
                _EarningsCard(
                  today: todayEarnings,
                  week: weekEarnings,
                  deltaPct: deltaPct,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GpsToggle extends StatelessWidget {
  final bool isOn;
  final bool loading;
  final VoidCallback onTap;
  const _GpsToggle({
    required this.isOn,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 56,
        height: 32,
        decoration: BoxDecoration(
          color: isOn ? const Color(0xFF00C950) : const Color(0x4DFFFFFF),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 180),
              left: isOn ? 28 : 4,
              top: 4,
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x1A000000),
                      blurRadius: 6,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: loading
                    ? const Padding(
                        padding: EdgeInsets.all(5),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Color(0xFF00C950)),
                        ),
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleToggle extends StatelessWidget {
  final bool isWorking;
  final VoidCallback onChanged;
  const _RoleToggle({required this.isWorking, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget pill(String label, bool active) {
      return GestureDetector(
        onTap: () {
          if ((label == 'Work' && !isWorking) ||
              (label == 'Hire' && isWorking)) {
            onChanged();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFFF6900) : Colors.transparent,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: active ? Colors.white : const Color(0xFF4A5565),
              height: 1.7,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          pill('Work', isWorking),
          pill('Hire', !isWorking),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final VoidCallback onTap;
  const _SearchField({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(50),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(50),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: const [
              Icon(Icons.search, color: Color(0xFF777777), size: 18),
              SizedBox(width: 12),
              Text(
                'Search for Job',
                style: TextStyle(
                  color: Color(0xFF777777),
                  fontSize: 12,
                  letterSpacing: -0.36,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EarningsCard extends StatelessWidget {
  final int today;
  final int week;
  final int? deltaPct;
  const _EarningsCard({
    required this.today,
    required this.week,
    required this.deltaPct,
  });

  @override
  Widget build(BuildContext context) {
    final delta = deltaPct;
    final deltaText = delta == null
        ? null
        : delta >= 0
            ? '$delta% higher than last week'
            : '${delta.abs()}% lower than last week';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Today's Earnings",
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFFFEDD4),
                      height: 1.33,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹$today',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      height: 1.33,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'This Week',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFFFEDD4),
                      height: 1.33,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹$week',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (deltaText != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  delta != null && delta < 0
                      ? Icons.trending_down
                      : Icons.trending_up,
                  size: 16,
                  color: const Color(0xFFE5FFE5),
                ),
                const SizedBox(width: 8),
                Text(
                  deltaText,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xE6FFFFFF),
                    height: 1.33,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback onViewAll;
  final IconData? icon;
  final Color viewAllColor;
  const _SectionHeader({
    required this.title,
    required this.onViewAll,
    this.icon,
    this.viewAllColor = const Color(0xFF1B2431),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: const Color(0xFFFF6900)),
                const SizedBox(width: 8),
              ],
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF101828),
                  letterSpacing: -0.36,
                ),
              ),
            ],
          ),
          GestureDetector(
            onTap: onViewAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Text(
                    'View all',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: viewAllColor,
                      letterSpacing: -0.36,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 14,
                    color: viewAllColor,
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

class _CategoriesRow extends StatelessWidget {
  final List<_CuratedCategory> items;
  final Map<String, int> counts;
  final ValueChanged<String> onTapCategory;
  const _CategoriesRow({
    required this.items,
    required this.counts,
    required this.onTapCategory,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _CategoryItem(
          category: items[i],
          count: counts[items[i].name],
          onTap: () => onTapCategory(items[i].name),
        ),
      ),
    );
  }
}

class _CategoryItem extends StatelessWidget {
  final _CuratedCategory category;
  final int? count;
  final VoidCallback onTap;
  const _CategoryItem({
    required this.category,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = count ?? 0;
    final label = c > 0 ? '$c ${c == 1 ? 'job' : 'jobs'}' : null;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            ClipOval(
              child: Image.asset(
                category.image,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              category.name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF1B2431),
                letterSpacing: -0.36,
                height: 1.3,
              ),
            ),
            if (label != null)
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFFF6900),
                  letterSpacing: -0.36,
                  height: 1.3,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NearbyGrid extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final String? Function(Map<String, dynamic>) photoUrl;
  final String Function(String?) fallbackForCategory;
  final double Function(Map<String, dynamic>) distanceKm;

  const _NearbyGrid({
    required this.items,
    required this.photoUrl,
    required this.fallbackForCategory,
    required this.distanceKm,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 12,
          mainAxisExtent: 196,
        ),
        itemBuilder: (_, i) {
          final job = items[i];
          return _NearbyCard(
            title: (job['title'] ?? '').toString(),
            priceInr: (job['finalPrice'] ?? job['proposedBudget'] ?? 0) as num,
            distanceKm: distanceKm(job),
            photoUrl: photoUrl(job),
            fallback: fallbackForCategory((job['category'] ?? '').toString()),
          );
        },
      ),
    );
  }
}

class _NearbyCard extends StatelessWidget {
  final String title;
  final num priceInr;
  final double distanceKm;
  final String? photoUrl;
  final String fallback;

  const _NearbyCard({
    required this.title,
    required this.priceInr,
    required this.distanceKm,
    required this.photoUrl,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: _JobImage(
            url: photoUrl,
            fallback: fallback,
            width: double.infinity,
            height: 131,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF1B2431),
            letterSpacing: -0.39,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 13,
                  color: Color(0xFF6A7282),
                ),
                const SizedBox(width: 4),
                Text(
                  distanceKm > 0 ? '${distanceKm.toStringAsFixed(1)} km' : '—',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6A7282),
                  ),
                ),
              ],
            ),
            Text(
              '₹${priceInr.toInt()}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF101828),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RecommendedCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final String? photoUrl;
  final String fallback;
  final double distanceKm;

  const _RecommendedCard({
    required this.job,
    required this.photoUrl,
    required this.fallback,
    required this.distanceKm,
  });

  @override
  Widget build(BuildContext context) {
    final title = (job['title'] ?? '').toString();
    final category = (job['category'] ?? 'Other').toString();
    final price = (job['finalPrice'] ?? job['proposedBudget'] ?? 0) as num;
    final urgent = (job['preference'] ?? '') == 'experienced' ||
        (job['priceMode'] == 'fixed');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Row(
          children: [
            _JobImage(
              url: photoUrl,
              fallback: fallback,
              width: 96,
              height: 104,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF101828),
                              height: 1.4,
                            ),
                          ),
                        ),
                        if (urgent)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFEDD4),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: const Text(
                              'Urgent',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFFF54900),
                                height: 1.33,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      category,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF4A5565),
                        height: 1.42,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              size: 16,
                              color: Color(0xFF6A7282),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              distanceKm > 0
                                  ? '${distanceKm.toStringAsFixed(1)} km'
                                  : '—',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF6A7282),
                                height: 1.42,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '₹${price.toInt()}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF101828),
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JobImage extends StatelessWidget {
  final String? url;
  final String fallback;
  final double width;
  final double height;

  const _JobImage({
    required this.url,
    required this.fallback,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final asset = Image.asset(
      fallback,
      width: width,
      height: height,
      fit: BoxFit.cover,
    );
    if (url == null) return asset;
    return Image.network(
      url!,
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => asset,
      loadingBuilder: (ctx, child, progress) {
        if (progress == null) return child;
        return SizedBox(
          width: width,
          height: height,
          child: Container(
            color: const Color(0xFFF3F4F6),
          ),
        );
      },
    );
  }
}

class _PerformanceCard extends StatelessWidget {
  final String jobsDone;
  final String rating;
  final String successPct;

  const _PerformanceCard({
    required this.jobsDone,
    required this.rating,
    required this.successPct,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEFF6FF), Color(0xFFECFEFF)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDBEAFE), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your Performance',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF101828),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _Stat(value: jobsDone, label: 'Jobs Done', color: Color(0xFF155DFC)),
              _Stat(value: rating, label: 'Rating', color: Color(0xFF00A63E)),
              _Stat(value: successPct, label: 'Success', color: Color(0xFFF54900)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _Stat({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: color,
            height: 1.33,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF4A5565),
            height: 1.33,
          ),
        ),
      ],
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _BottomNav({required this.currentIndex, required this.onTap});

  static const _items = <_NavItem>[
    _NavItem('Home', Icons.home_outlined, Icons.home),
    _NavItem('Jobs', Icons.work_outline, Icons.work),
    _NavItem('Messages', Icons.chat_bubble_outline, Icons.chat_bubble),
    _NavItem('Wallet', Icons.account_balance_wallet_outlined,
        Icons.account_balance_wallet),
    _NavItem('Profile', Icons.person_outline, Icons.person),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        9,
        16,
        MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFE5E7EB), width: 0.8),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(_items.length, (i) {
          final item = _items[i];
          final active = i == currentIndex;
          return GestureDetector(
            onTap: () => onTap(i),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    active ? item.activeIcon : item.icon,
                    size: 24,
                    color: active
                        ? const Color(0xFFFF6900)
                        : const Color(0xFF4A5565),
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

class _PostNewJobButton extends StatelessWidget {
  final VoidCallback onTap;
  const _PostNewJobButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.add, color: Color(0xFFFF6900)),
        label: const Text(
          'Post a New Job',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Color(0xFFFF6900),
          ),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFFF6900), width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class _ActiveJobsList extends StatelessWidget {
  final List<Map<String, dynamic>> jobs;
  final bool loading;
  final ValueChanged<Map<String, dynamic>>? onTapJob;
  const _ActiveJobsList({
    required this.jobs,
    required this.loading,
    this.onTapJob,
  });

  static const _statusStyles = <String, _StatusStyle>{
    'open': _StatusStyle(
      label: 'Finding Workers',
      icon: Icons.access_time,
      bg: Color(0xFFFFF7ED),
      border: Color(0xFFFFD6A8),
      fg: Color(0xFFF54900),
    ),
    'confirmed': _StatusStyle(
      label: 'Confirmed',
      icon: Icons.check_circle,
      bg: Color(0xFFEFF6FF),
      border: Color(0xFFBEDBFF),
      fg: Color(0xFF155DFC),
    ),
    'in_progress': _StatusStyle(
      label: 'In Progress',
      icon: Icons.flash_on,
      bg: Color(0xFFEFF6FF),
      border: Color(0xFFBEDBFF),
      fg: Color(0xFF155DFC),
    ),
  };

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const _LoadingBlock(height: 120);
    }
    if (jobs.isEmpty) {
      return const _EmptyState(
        message: 'No active jobs yet. Tap "Post a New Job" to start.',
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: jobs
            .map(
              (j) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ActiveJobCard(
                  job: j,
                  style: _statusStyles[(j['status'] ?? '').toString()] ??
                      _statusStyles['open']!,
                  onTap: onTapJob == null ? null : () => onTapJob!(j),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _StatusStyle {
  final String label;
  final IconData icon;
  final Color bg;
  final Color border;
  final Color fg;
  const _StatusStyle({
    required this.label,
    required this.icon,
    required this.bg,
    required this.border,
    required this.fg,
  });
}

class _ActiveJobCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final _StatusStyle style;
  final VoidCallback? onTap;
  const _ActiveJobCard({
    required this.job,
    required this.style,
    this.onTap,
  });

  String _agoFromCreatedAt(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) {
      return '${diff.inHours} ${diff.inHours == 1 ? 'hour' : 'hours'} ago';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays} ${diff.inDays == 1 ? 'day' : 'days'} ago';
    }
    return '${(diff.inDays / 7).floor()} weeks ago';
  }

  @override
  Widget build(BuildContext context) {
    final title = (job['title'] ?? '').toString();
    final category = (job['category'] ?? 'Other').toString();
    final price = (job['finalPrice'] ?? job['proposedBudget'] ?? 0) as num;
    final ago = _agoFromCreatedAt(job['createdAt']?.toString());
    final interested = job['interested'] is List
        ? (job['interested'] as List).length
        : 0;
    final status = (job['status'] ?? '').toString();
    final isInProgress = status == 'in_progress' || status == 'confirmed';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF3F4F6), width: 0.8),
          ),
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF101828),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ago.isEmpty ? category : '$category • $ago',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF6A7282),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '₹${price.toInt()}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF101828),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: style.bg,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: style.border, width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(style.icon, size: 12, color: style.fg),
                    const SizedBox(width: 6),
                    Text(
                      style.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: style.fg,
                      ),
                    ),
                  ],
                ),
              ),
              if (isInProgress)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.star, size: 16, color: Color(0xFFFFB300)),
                    SizedBox(width: 4),
                    Text(
                      '4.8',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF4A5565),
                      ),
                    ),
                  ],
                )
              else
                Text(
                  '$interested interested',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF101828),
                  ),
                ),
            ],
          ),
        ],
      ),
        ),
      ),
    );
  }
}

class _RecentActivityList extends StatelessWidget {
  final List<Map<String, dynamic>> jobs;
  const _RecentActivityList({required this.jobs});

  @override
  Widget build(BuildContext context) {
    // Derive simple activity from posted jobs: most-recent interest applied,
    // and most-recent completed job.
    final activities = <_ActivityItem>[];
    for (final j in jobs) {
      final interested = j['interested'];
      if (interested is List && interested.isNotEmpty) {
        final last = interested.last;
        if (last is Map) {
          final taker = last['jobtaker'];
          final name = taker is Map
              ? (taker['name'] ?? 'Someone').toString()
              : 'Someone';
          activities.add(_ActivityItem(
            message: '$name applied for ${j['title'] ?? 'your job'}',
            createdAt: last['createdAt']?.toString(),
          ));
        }
      }
      if (j['status'] == 'completed' && j['completedAt'] != null) {
        activities.add(_ActivityItem(
          message: '${j['title'] ?? 'Job'} completed',
          createdAt: j['completedAt']?.toString(),
        ));
      }
    }
    activities.sort((a, b) {
      final at = DateTime.tryParse(a.createdAt ?? '') ?? DateTime(0);
      final bt = DateTime.tryParse(b.createdAt ?? '') ?? DateTime(0);
      return bt.compareTo(at);
    });

    if (activities.isEmpty) {
      return const _EmptyState(message: 'No recent activity yet.');
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: activities.take(3).map((a) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.message,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF101828),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _ago(a.createdAt),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF6A7282),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  static String _ago(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} mins ago';
    if (diff.inHours < 24) {
      return '${diff.inHours} ${diff.inHours == 1 ? 'hour' : 'hours'} ago';
    }
    return '${diff.inDays} ${diff.inDays == 1 ? 'day' : 'days'} ago';
  }
}

class _ActivityItem {
  final String message;
  final String? createdAt;
  _ActivityItem({required this.message, required this.createdAt});
}

class _NearbyWorkersRow extends StatelessWidget {
  final List<Map<String, dynamic>> workers;
  final bool loading;
  const _NearbyWorkersRow({required this.workers, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const _LoadingBlock(height: 260);
    }
    if (workers.isEmpty) {
      return const _EmptyState(message: 'No verified workers near you yet.');
    }
    return SizedBox(
      height: 260,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: workers.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _WorkerCard(worker: workers[i]),
      ),
    );
  }
}

class _WorkerCard extends StatelessWidget {
  final Map<String, dynamic> worker;
  const _WorkerCard({required this.worker});

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
        ? (worker['skills'] as List).cast<String>()
        : <String>[];
    final isVerified = worker['isVerifiedProfessional'] == true;
    final photo = worker['photo']?.toString();
    final photoUrl = (photo != null && photo.isNotEmpty)
        ? (photo.startsWith('http') ? photo : '${AppConfig.apiBase}$photo')
        : null;

    return Container(
      width: 160,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF3F4F6), width: 0.8),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 134,
                  height: 134,
                  color: const Color(0xFFE5E7EB),
                  child: photoUrl != null
                      ? Image.network(
                          photoUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.person,
                            size: 60,
                            color: Color(0xFF94A3B8),
                          ),
                        )
                      : const Icon(
                          Icons.person,
                          size: 60,
                          color: Color(0xFF94A3B8),
                        ),
                ),
              ),
              Positioned(
                top: -3,
                right: -3,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: isVerified
                        ? const Color(0xFF00C950)
                        : const Color(0xFF94A3B8),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.6),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF101828),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.star, size: 12, color: Color(0xFFFFB300)),
              const SizedBox(width: 4),
              Text(
                rating,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF101828),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '($ratingCount)',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6A7282),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            skills.isEmpty ? '' : skills.take(2).join(' '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF4A5565),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _VerifiedWorkersCard extends StatelessWidget {
  const _VerifiedWorkersCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEFF6FF), Color(0xFFECFEFF)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDBEAFE), width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF2B7FFF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.verified_user,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Verified Workers',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF101828),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'All workers are background verified with ratings from real customers',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF4A5565),
                    height: 1.43,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: const [
                    Icon(Icons.check_circle, size: 16, color: Color(0xFF00C950)),
                    SizedBox(width: 4),
                    Text(
                      'ID Verified',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF364153),
                      ),
                    ),
                    SizedBox(width: 16),
                    Icon(Icons.check_circle, size: 16, color: Color(0xFF00C950)),
                    SizedBox(width: 4),
                    Text(
                      'Insured',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF364153),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
