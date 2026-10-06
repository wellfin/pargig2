import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/home_api.dart';
import '../config.dart';
import '../services/routing.dart';
import 'job_status_screen.dart';
import 'request_sent_screen.dart';
import '../utils/job_status.dart';
import '../utils/rating.dart';
import '../state/auth_state.dart';
import 'job_list_results_screen.dart';
import 'request_custom_amount_screen.dart';
import 'urgent_job_popup.dart';
import '../widgets/nav_unread_badge.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Curated categories with their visual asset; counts come from backend.
  static const _curatedCategories = <_CuratedCategory>[
    _CuratedCategory('Plumbing', image: 'assets/home/cat_plumbing.png'),
    _CuratedCategory('Carpentry', image: 'assets/home/cat_carpentry.png'),
    _CuratedCategory('Painting', image: 'assets/home/cat_painting.png'),
    _CuratedCategory('Cleaning', image: 'assets/home/cat_cleaning.png'),
    _CuratedCategory('Electrical', image: 'assets/home/cat_electrical.png'),
    _CuratedCategory('Babysitting', image: 'assets/home/cat_babysitting.png'),
    // Categories without dedicated illustrations — rendered with a Material
    // icon on a coloured circle so they still feel native.
    _CuratedCategory(
      'Repair',
      icon: Icons.build_outlined,
      accent: Color(0xFFFFEDD4),
    ),
    _CuratedCategory(
      'Cooking',
      icon: Icons.restaurant_outlined,
      accent: Color(0xFFFFE2E2),
    ),
    _CuratedCategory(
      'Delivery',
      icon: Icons.local_shipping_outlined,
      accent: Color(0xFFDBEAFE),
    ),
    _CuratedCategory(
      'Helper',
      icon: Icons.handshake_outlined,
      accent: Color(0xFFFEF3C7),
    ),
    _CuratedCategory(
      'Gardening',
      icon: Icons.local_florist_outlined,
      accent: Color(0xFFDCFCE7),
    ),
    _CuratedCategory(
      'Driving',
      icon: Icons.directions_car_outlined,
      accent: Color(0xFFE0E7FF),
    ),
  ];

  // Fallback image used when a job has no photo, keyed by category.
  // Categories without dedicated artwork reuse the closest existing asset
  // until proper illustrations are added.
  static const _categoryFallback = <String, String>{
    'Cleaning': 'assets/home/rec_home_cleaning.png',
    'Plumbing': 'assets/home/rec_plumbing.png',
    'Painting': 'assets/home/rec_painting.png',
    'Carpentry': 'assets/home/rec_furniture.png',
    'Assembly': 'assets/home/rec_furniture.png',
    'Electrical': 'assets/home/cat_electrical.png',
    'Babysitting': 'assets/home/cat_babysitting.png',
    'Repair': 'assets/home/rec_plumbing.png',
    'Cooking': 'assets/home/rec_home_cleaning.png',
    'Delivery': 'assets/home/job_cleaning_house.png',
    'Helper': 'assets/home/rec_home_cleaning.png',
    'Gardening': 'assets/home/rec_furniture.png',
    'Driving': 'assets/home/job_cleaning_house.png',
  };
  static const _genericFallback = 'assets/home/job_cleaning_house.png';

  Map<String, int> _categoryCounts = const {};
  List<Map<String, dynamic>> _nearbyJobs = const [];
  List<Map<String, dynamic>> _recommendedJobs = const [];
  Map<String, dynamic> _earnings = const {};

  // Hire-view state.
  List<Map<String, dynamic>> _myPostedJobs = const [];
  // Worker mode: the jobs this user was actually selected for and has not
  // finished being paid for. Drives the "Your Current Job" card, which is
  // the worker's mirror of the giver's Active Jobs.
  List<Map<String, dynamic>> _myWorkJobs = const [];
  List<Map<String, dynamic>> _nearbyWorkers = const [];

  bool _loading = true;
  String? _loadError;
  int _bottomIndex = 0;
  Timer? _unreadPollTimer;
  Timer? _urgentPollTimer;
  bool _urgentPopupShowing = false;

  // ---- Current-location toggle in the home header ------------------------
  //
  // Default OFF. When the user flips it ON we grab GPS once, reverse-
  // geocode a label for the header, and PUT it to the backend as
  // user.currentLocation. When OFF the header shows the typed profile
  // address from the wizard. One-shot capture per toggle — no background
  // timer/heartbeat. Off-by-default keeps us from prompting for location
  // permission on first home open before the user has expressed intent.
  //
  // The on/off value itself lives on AuthState.isOnline (not a local field)
  // so it survives the many flows that rebuild Home from scratch via
  // pushNamedAndRemoveUntil — otherwise the toggle silently flipped back to
  // off any time the user returned to Home through one of those flows.
  bool get _useCurrentLocation => context.read<AuthState>().isOnline;
  bool _gpsLoading = false;
  String? _liveLocationLabel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _refresh();
      if (mounted && _useCurrentLocation) {
        await _captureCurrentLocation();
      }
      if (!mounted) return;
      // Kick off unread-chat polling so the bottom-nav Messages
      // icon shows the red dot when new messages land. AuthState
      // owns the int + notifyListeners so all BottomNav widgets
      // (home / messages / wallet) refresh together.
      final auth = context.read<AuthState>();
      // Ensure the realtime socket is up (e.g. after a cold start) so the
      // bell count + chat dot update the instant something lands.
      auth.connectRealtime();
      auth.refreshUnreadChats();
      auth.refreshUnreadNotifications();
      // Polling is the fallback when the socket can't connect.
      _unreadPollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        if (mounted) {
          auth.refreshUnreadChats();
          auth.refreshUnreadNotifications();
        }
      });
    });
  }

  @override
  void dispose() {
    _unreadPollTimer?.cancel();
    _urgentPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _captureCurrentLocation() async {
    if (_gpsLoading) return;
    setState(() => _gpsLoading = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      String? label;
      try {
        final placemarks = await placemarkFromCoordinates(
          pos.latitude,
          pos.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          label = [p.subLocality, p.locality, p.administrativeArea]
              .whereType<String>()
              .where((s) => s.trim().isNotEmpty)
              .toSet()
              .join(', ');
          if (label.isEmpty) label = null;
        }
      } catch (_) {
        // Reverse-geocode best-effort; coords still saved.
      }
      if (!mounted) return;
      setState(() => _liveLocationLabel = label);
      // Push to backend so the admin "Current Location" row stays fresh.
      // Failure is non-fatal — the local label still renders in the header.
      try {
        final payload = <String, dynamic>{
          'currentLocation': {
            'type': 'Point',
            'coordinates': [pos.longitude, pos.latitude],
          },
        };
        if (label != null) {
          payload['currentLocationLabel'] = label;
        }
        await context.read<AuthState>().updateProfile(payload);
      } catch (_) {}
    } catch (_) {
      // Silent — keep the toggle visually on; user can flip it to retry.
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  Future<void> _toggleCurrentLocation(bool value) async {
    context.read<AuthState>().setOnline(value);
    setState(() {
      if (!value) _liveLocationLabel = null;
    });
    if (!value) {
      _stopUrgentPollTimer();
      return;
    }

    await _captureCurrentLocation();
    if (!mounted) return;

    final auth = context.read<AuthState>();
    if (!auth.isJobGiver) {
      await _maybeShowUrgentJobPopup();
      _startUrgentPollTimer();
    }
  }

  void _startUrgentPollTimer() {
    _urgentPollTimer?.cancel();
    _urgentPollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted || !_useCurrentLocation) return;
      final auth = context.read<AuthState>();
      if (auth.isJobGiver) return;
      await _refillUrgentQueue();
      await _maybeShowUrgentJobPopup();
    });
  }

  void _stopUrgentPollTimer() {
    _urgentPollTimer?.cancel();
    _urgentPollTimer = null;
    _urgentQueue.clear();
    _urgentCurrentId = null;
    _urgentCooldown = false;
  }

  // Local queue of urgent jobs waiting to be shown, newest-posted first.
  // Refilled every poll tick and drained one popup at a time so closing
  // (or resolving) one immediately reveals the next instead of waiting
  // up to 5s for the next poll.
  final List<Map<String, dynamic>> _urgentQueue = [];
  // job id -> the `updatedAt` we last showed/dismissed it for. A job that
  // gets claimed then re-opened (worker cancelled) gets a new updatedAt,
  // so it reappears in the queue for everyone instead of being
  // suppressed forever.
  final Map<String, String> _urgentDismissedVersion = {};
  String? _urgentCurrentId;
  // True for 5s after a popup closes (accept, custom, or dismiss) so the
  // taker gets a breather instead of the next urgent job stacking instantly.
  bool _urgentCooldown = false;

  Future<void> _refillUrgentQueue() async {
    final auth = context.read<AuthState>();
    if (auth.isJobGiver) return;
    final ref = _viewerLatLng();
    if (ref.lat == null || ref.lng == null) return;
    try {
      final radiusKm =
          ((auth.user?['searchRadiusKm'] as num?)?.toDouble() ?? 10.0).clamp(
            1.0,
            100.0,
          );
      // sortBy: 'recent' (-createdAt) so the newest-posted urgent job
      // bubbles to the front — the job giver's latest post should be
      // shown to online takers before older ones still in the queue.
      final results = await HomeApi.browse(
        lat: ref.lat,
        lng: ref.lng,
        radiusKm: radiusKm,
        limit: 20,
        sortBy: 'recent',
      );
      if (!mounted) return;
      final queuedIds = _urgentQueue
          .map((j) => (j['_id'] ?? '').toString())
          .toSet();
      for (final j in results) {
        if (j['isUrgent'] != true) continue;
        final id = (j['_id'] ?? '').toString();
        if (id.isEmpty || id == _urgentCurrentId || queuedIds.contains(id)) {
          continue;
        }
        final version = (j['updatedAt'] ?? '').toString();
        if (_urgentDismissedVersion[id] == version) continue;
        _urgentQueue.add(j);
      }
      _urgentQueue.sort((a, b) {
        final ca = DateTime.tryParse((a['createdAt'] ?? '').toString());
        final cb = DateTime.tryParse((b['createdAt'] ?? '').toString());
        if (ca == null || cb == null) return 0;
        return cb.compareTo(ca); // newest first
      });
    } catch (_) {
      // Network blip — queue just doesn't grow this tick.
    }
  }

  Future<void> _maybeShowUrgentJobPopup() async {
    if (_urgentPopupShowing || _urgentCooldown) return;
    final auth = context.read<AuthState>();
    if (auth.isJobGiver) return;
    if (_urgentQueue.isEmpty) {
      await _refillUrgentQueue();
    }
    if (!mounted || _urgentQueue.isEmpty) return;
    final ref = _viewerLatLng();
    if (ref.lat == null || ref.lng == null) return;

    final urgent = _urgentQueue.removeAt(0);
    final id = (urgent['_id'] ?? '').toString();
    _urgentCurrentId = id;
    _urgentDismissedVersion[id] = (urgent['updatedAt'] ?? '').toString();
    _urgentPopupShowing = true;
    try {
      final distKm = _distanceKmFrom(urgent);
      final result = await UrgentJobPopup.show(
        context,
        job: urgent,
        distanceKm: distKm,
        refLat: ref.lat,
        refLng: ref.lng,
      );
      if (!mounted || result == null) return;
      if (result.action == 'accept') {
        try {
          // Accepting an urgent job REGISTERS INTEREST — it does not hire
          // the worker. Hiring is the giver's decision on every job, so
          // this now lands exactly where the regular apply flow does:
          // request sent, giver reviews the applicants, worker waits.
          //
          // It used to jump straight to the Immediate Job Active reach
          // timer, because the old claim endpoint confirmed the job on the
          // spot. That auto-accept is gone; walking the worker into an
          // arrival countdown for a job nobody had awarded them would be
          // worse than the original bug.
          await ApiClient.post('/jobs/$id/claim-urgent', {
            'proposedPrice': result.price,
          });
          if (!mounted) return;
          await Navigator.pushNamed(
            context,
            '/request-sent',
            arguments: RequestSentArgs(customAmount: result.price),
          );
        } catch (e) {
          if (!mounted) return;
          // 409 = the job stopped accepting applications (the giver hired
          // someone, or it was cancelled) between the popup opening and
          // Accept being tapped.
          final closed = e is ApiException && e.status == 409;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                closed
                    ? 'This job is no longer accepting applications'
                    : 'Could not submit: $e',
              ),
            ),
          );
        }
      } else if (result.action == 'custom') {
        // Push the full-screen "Request Custom Amount" module — it
        // does its own POST + navigates to /application-sent on
        // success.
        final giver = urgent['jobgiver'];
        final clientName = giver is Map ? (giver['name'] ?? '').toString() : '';
        await Navigator.pushNamed(
          context,
          '/request-custom-amount',
          arguments: RequestCustomAmountArgs(
            jobId: id,
            jobTitle: (urgent['title'] ?? 'Job').toString(),
            originalAmount: result.price,
            category: (urgent['category'] ?? '').toString(),
            clientName: clientName.isEmpty ? null : clientName,
            isUrgent: urgent['isUrgent'] == true,
          ),
        );
      }
    } catch (_) {
      // Browse failure or network blip — popup is a nice-to-have.
    } finally {
      _urgentCurrentId = null;
      _urgentPopupShowing = false;
      // Give the taker a 5s breather between popups (whether this one was
      // accepted, sent as a custom offer, or just dismissed with X) instead
      // of stacking the next queued job instantly.
      if (mounted && _useCurrentLocation && !auth.isJobGiver) {
        _urgentCooldown = true;
        Future.delayed(const Duration(seconds: 5), () {
          _urgentCooldown = false;
          if (!mounted) return;
          final stillOnline =
              _useCurrentLocation && !context.read<AuthState>().isJobGiver;
          if (stillOnline) _maybeShowUrgentJobPopup();
        });
      }
    }
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
    // Prefer the user's work area (set on Find Work / Hire Workers setup)
    // when querying for nearby jobs / workers — that's the area they
    // explicitly chose to search. Fall back to the home/profile address
    // coords if no work area was picked yet.
    double? lat;
    double? lng;
    final workArea = auth.user?['workArea'] is Map
        ? auth.user!['workArea'] as Map
        : const {};
    final workCoords = workArea['coordinates'];
    if (workCoords is List && workCoords.length == 2) {
      lng = (workCoords[0] as num?)?.toDouble();
      lat = (workCoords[1] as num?)?.toDouble();
      if (lat == 0 && lng == 0) {
        lat = null;
        lng = null;
      }
    }
    if (lat == null || lng == null) {
      final loc = auth.user?['location'] is Map
          ? auth.user!['location'] as Map
          : const {};
      final coords = loc['coordinates'];
      if (coords is List && coords.length == 2) {
        lng = (coords[0] as num?)?.toDouble();
        lat = (coords[1] as num?)?.toDouble();
        if (lat == 0 && lng == 0) {
          lat = null;
          lng = null;
        }
      }
    }

    try {
      final isJobGiver = auth.isJobGiver;
      const emptyList = <Map<String, dynamic>>[];
      // Use the user's saved searchRadiusKm preference (set on Find Work /
      // Hire Workers Apply Location). Falls back to 10 km if unset. The
      // "Recommended for You" list uses 2x the chosen radius so users can
      // still discover jobs a bit further out.
      final radiusKm =
          ((auth.user?['searchRadiusKm'] as num?)?.toDouble() ?? 10.0).clamp(
            1.0,
            100.0,
          );
      final recommendedRadiusKm = (radiusKm * 2).clamp(1.0, 200.0);
      // Fetch in parallel. Hire view needs posted jobs + nearby workers
      // instead of categories + jobs feed. Each branch returns an explicitly
      // typed empty list so Future.wait can infer a homogeneous type.
      final categoriesF = !isJobGiver
          ? HomeApi.categories()
          : Future<List<Map<String, dynamic>>>.value(emptyList);
      final nearbyF = !isJobGiver
          ? HomeApi.browse(lat: lat, lng: lng, radiusKm: radiusKm, limit: 4)
          : Future<List<Map<String, dynamic>>>.value(emptyList);
      final recommendedF = !isJobGiver
          ? HomeApi.browse(
              lat: lat,
              lng: lng,
              radiusKm: recommendedRadiusKm,
              limit: 8,
            )
          : Future<List<Map<String, dynamic>>>.value(emptyList);
      final earningsF = HomeApi.earnings();
      final postedJobsF = isJobGiver
          ? HomeApi.myPostedJobs()
          : Future<List<Map<String, dynamic>>>.value(emptyList);
      final workersF = isJobGiver
          ? HomeApi.nearbyWorkers(
              lat: lat,
              lng: lng,
              radiusKm: radiusKm,
              limit: 12,
            )
          : Future<List<Map<String, dynamic>>>.value(emptyList);
      // The worker's own accepted work. Never fetched before, which is why
      // an in-progress job was invisible on their home screen.
      final myWorkF = isJobGiver
          ? Future<List<Map<String, dynamic>>>.value(emptyList)
          : HomeApi.myAppliedJobs();

      final results = await Future.wait<dynamic>([
        categoriesF,
        nearbyF,
        recommendedF,
        earningsF,
        postedJobsF,
        workersF,
        myWorkF,
      ]);
      if (!mounted) return;
      final categories = results[0] as List<Map<String, dynamic>>;
      final nearby = results[1] as List<Map<String, dynamic>>;
      final recommended = results[2] as List<Map<String, dynamic>>;
      final nearbyIds = nearby.map((j) => j['_id']).toSet();
      setState(() {
        _categoryCounts = {
          for (final c in categories)
            (c['category'] ?? '').toString():
                (c['count'] as num?)?.toInt() ?? 0,
        };
        _nearbyJobs = nearby;
        _recommendedJobs = recommended
            .where((j) => !nearbyIds.contains(j['_id']))
            .take(4)
            .toList();
        _earnings = results[3] as Map<String, dynamic>;
        _myPostedJobs = results[4] as List<Map<String, dynamic>>;
        _nearbyWorkers = results[5] as List<Map<String, dynamic>>;
        _myWorkJobs = (results[6] as List<Map<String, dynamic>>)
            .where((j) => isActiveForWorker(j, auth.user?['_id']?.toString()))
            .toList();
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

  Future<void> _toggleRole() async {
    final auth = context.read<AuthState>();
    final newRole = auth.isJobGiver ? 'jobtaker' : 'jobgiver';
    try {
      await auth.switchRole(newRole);
      if (mounted) _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Couldn't switch role: $e")));
    }
  }

  // Shown when the system back button is pressed on Home (the bottom of
  // the stack) — confirms the user actually wants to close the app.
  Future<bool> _confirmExit() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exit Pargig?'),
        content: const Text('Are you sure you want to close the app?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _onTabTapped(int i) async {
    if (i == _bottomIndex) return;
    setState(() => _bottomIndex = i);
    // Jobs tab → push the same results screen used by Search → Apply
    // Filters, but seeded with the user's profile (skills as categories,
    // searchRadiusKm as radius, workArea as the search center). When the
    // user comes back from /job-list-results we drop the highlight back
    // on Home.
    if (i == 1) {
      _openJobsTab();
      return;
    }
    // Messages tab → push the Messages screen.
    if (i == 2) {
      Navigator.pushNamed(context, '/messages').then((_) {
        if (!mounted) return;
        setState(() => _bottomIndex = 0);
        // User just came back from Messages — opening any chat
        // there marks the room read on the backend, so re-fetch
        // the unread count immediately instead of waiting 20s.
        context.read<AuthState>().refreshUnreadChats();
      });
      return;
    }
    // Wallet tab → push the Wallet screen.
    if (i == 3) {
      Navigator.pushNamed(context, '/wallet').then((_) {
        if (mounted) setState(() => _bottomIndex = 0);
      });
      return;
    }
    // Profile tab → push the profile screen, then reset the highlight back
    // to Home when the user comes back so the next tap on Home is a no-op
    // (not a re-push of the same route).
    if (i == 4) {
      await Navigator.pushNamed(context, '/profile');
      if (mounted) setState(() => _bottomIndex = 0);
      return;
    }
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

  Future<void> _openJobsTab() async {
    final auth = context.read<AuthState>();
    // Hire mode (jobgiver) → just the jobs THIS user has posted.
    if (auth.isJobGiver) {
      await Navigator.pushNamed(context, '/my-posted-jobs');
      if (mounted) setState(() => _bottomIndex = 0);
      return;
    }
    // Work mode (jobtaker) → "My Work" screen with Applied/Accepted/
    // Ongoing/Completed tabs. This is the "My Jobs" tab from the
    // Figma frame — distinct from the search/browse screen.
    await Navigator.pushNamed(context, '/my-jobs');
    if (mounted) setState(() => _bottomIndex = 0);
    return;
    // (Browse/Search now lives behind the search bar in the header.)
    // Below: legacy path that pre-seeds /job-list-results with the
    // user's profile filters — kept dead-coded for reference.
    // ignore: dead_code
    final user = auth.user ?? const <String, dynamic>{};
    double? lat;
    double? lng;
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
    if (c != null) {
      lng = (c[0] as num).toDouble();
      lat = (c[1] as num).toDouble();
    }
    final radiusKm = ((user['searchRadiusKm'] as num?)?.toDouble()) ?? 10.0;
    final skills = (user['skills'] is List)
        ? (user['skills'] as List).whereType<String>().toList()
        : <String>[];
    if (!mounted) return;
    await Navigator.pushNamed(
      context,
      '/job-list-results',
      arguments: JobListArgs(
        lat: lat,
        lng: lng,
        radiusKm: radiusKm,
        categories: skills,
        sortBy: 'nearest',
      ),
    );
    if (mounted) setState(() => _bottomIndex = 0);
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

  // Viewer's reference coords for distance math. Priority:
  //   1. currentLocation (when the home toggle is ON)
  //   2. workArea (Find Work / Hire Workers Apply pick)
  //   3. location (home/profile address)
  // Returns (null, null) when none have real coords.
  ({double? lat, double? lng}) _viewerLatLng() {
    final auth = context.read<AuthState>();
    Map origin = const {};
    if (_useCurrentLocation && auth.user?['currentLocation'] is Map) {
      origin = auth.user!['currentLocation'] as Map;
    } else if (auth.user?['workArea'] is Map) {
      origin = auth.user!['workArea'] as Map;
    } else if (auth.user?['location'] is Map) {
      origin = auth.user!['location'] as Map;
    }
    final c = origin['coordinates'];
    if (c is List && c.length == 2 && !(c[0] == 0 && c[1] == 0)) {
      return (lat: (c[1] as num).toDouble(), lng: (c[0] as num).toDouble());
    }
    return (lat: null, lng: null);
  }

  double _distanceKmFrom(Map<String, dynamic> job) {
    final auth = context.read<AuthState>();
    Map<String, dynamic> origin = const {};
    if (_useCurrentLocation && auth.user?['currentLocation'] is Map) {
      origin = Map<String, dynamic>.from(auth.user!['currentLocation'] as Map);
    } else if (auth.user?['workArea'] is Map) {
      origin = Map<String, dynamic>.from(auth.user!['workArea'] as Map);
    } else if (auth.user?['location'] is Map) {
      origin = Map<String, dynamic>.from(auth.user!['location'] as Map);
    }
    final myCoords = origin['coordinates'];
    final jobLoc = job['location'] is Map
        ? Map<String, dynamic>.from(job['location'] as Map)
        : const {};
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

  static double _haversineKm(
    double aLat,
    double aLng,
    double bLat,
    double bLng,
  ) {
    const r = 6371.0;
    double toRad(double v) => v * 3.141592653589793 / 180.0;
    final dLat = toRad(bLat - aLat);
    final dLng = toRad(bLng - aLng);
    final h =
        (1 - _cos(dLat)) / 2 +
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
    // Header label rules (per user spec):
    //   - toggle OFF → "Offline" (we deliberately HIDE the typed/work
    //     address; "offline" means we're not sharing live location)
    //   - toggle ON with a live GPS fix captured → show the live label
    //   - toggle ON but capture still in flight → "Locating…"
    //   - toggle ON but no fix yet (capture failed silently) →
    //     "Location unavailable"
    final liveLabel = (_liveLocationLabel ?? '').trim();
    String locationDisplay;
    if (!_useCurrentLocation) {
      locationDisplay = 'Offline';
    } else if (liveLabel.isNotEmpty) {
      locationDisplay = liveLabel;
    } else if (_gpsLoading) {
      locationDisplay = 'Locating…';
    } else {
      locationDisplay = 'Location unavailable';
    }

    // 5.0 until somebody actually rates them — a new user's stored
    // average is 0, which rendered as "0.0" and looked like a bad score.
    final rating = displayRating(user['rating']);
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

    return PopScope(
      // Home is the bottom of the stack for a signed-in user (every
      // post-auth flow lands here via pushNamedAndRemoveUntil), so the
      // system back button here would otherwise close the app outright.
      // Intercept it and ask first.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await _confirmExit();
        if (shouldExit && mounted) SystemNavigator.pop();
      },
      child: Scaffold(
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
                      onNotificationsTap: () {
                        // Capture auth before the async gap; refresh the count
                        // on return since the bell marks items read.
                        final auth = context.read<AuthState>();
                        Navigator.pushNamed(
                          context,
                          '/notifications',
                        ).then((_) => auth.refreshUnreadNotifications());
                      },
                      unreadNotifications: context
                          .watch<AuthState>()
                          .unreadNotifications,
                      onWishlistTap: () {
                        // TODO: replace with Navigator.pushNamed(context,
                        // '/wishlist') once the wishlist screen is built.
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Wishlist coming soon'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                    if (_loadError != null)
                      _ErrorBanner(message: _loadError!, onRetry: _refresh),
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
                          await Navigator.pushNamed(context, '/my-posted-jobs');
                          // Refresh unconditionally — an applicant could have
                          // been rejected/accepted or a job cancelled inside
                          // that flow, and those don't always pop `true`.
                          if (mounted) _refresh();
                        },
                        viewAllColor: const Color(0xFFFF6900),
                      ),
                      const SizedBox(height: 12),
                      _ActiveJobsList(
                        jobs: _myPostedJobs
                            .where(isActiveForGiver)
                            .take(3)
                            .toList(),
                        loading: _loading && _myPostedJobs.isEmpty,
                        onTapJob: (job) async {
                          final id = (job['_id'] ?? '').toString();
                          if (id.isEmpty) return;
                          await Navigator.pushNamed(
                            context,
                            '/job-details',
                            arguments: id,
                          );
                          // Always refresh on return — the job's interested
                          // count / status may have changed (an applicant was
                          // rejected or accepted, the job cancelled, etc.), and
                          // Job Details only pops `true` on acceptance, so a
                          // reject would otherwise leave "1 interested" stale.
                          if (mounted) _refresh();
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
                        onViewAll: () =>
                            Navigator.pushNamed(context, '/nearby-workers'),
                        viewAllColor: const Color(0xFFFF6900),
                      ),
                      const SizedBox(height: 12),
                      _NearbyWorkersRow(
                        workers: _nearbyWorkers,
                        loading: _loading && _nearbyWorkers.isEmpty,
                      ),
                      const SizedBox(height: 24),
                    ] else ...[
                      // The work this user is on right now, above the job
                      // feed — someone mid-job cares about that far more
                      // than about browsing for another one.
                      if (_myWorkJobs.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'Your Current Job',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF101828),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            children: _myWorkJobs
                                .take(2)
                                .map(
                                  (j) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _CurrentWorkCard(
                                      job: j,
                                      onTap: () async {
                                        final id = (j['_id'] ?? '').toString();
                                        if (id.isEmpty) return;
                                        await Navigator.pushNamed(
                                          context,
                                          '/job-status',
                                          arguments: JobStatusArgs(jobId: id),
                                        );
                                        if (mounted) _refresh();
                                      },
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      _SectionHeader(
                        title: 'Browse all categories',
                        onViewAll: () =>
                            Navigator.pushNamed(context, '/search'),
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
                        onViewAll: () =>
                            Navigator.pushNamed(context, '/search'),
                      ),
                      const SizedBox(height: 16),
                      if (_loading && _nearbyJobs.isEmpty)
                        const _LoadingBlock(height: 410)
                      else if (_nearbyJobs.isEmpty)
                        const _EmptyState(message: 'No jobs near you yet.')
                      else
                        Builder(
                          builder: (_) {
                            final ref = _viewerLatLng();
                            return _NearbyGrid(
                              items: _nearbyJobs,
                              photoUrl: _firstPhotoUrl,
                              fallbackForCategory: _fallbackForCategory,
                              distanceKm: _distanceKmFrom,
                              refLat: ref.lat,
                              refLng: ref.lng,
                            );
                          },
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
                          child: Builder(
                            builder: (_) {
                              final ref = _viewerLatLng();
                              return Column(
                                children: _recommendedJobs.map((j) {
                                  double? jLat;
                                  double? jLng;
                                  final c = (j['location'] is Map)
                                      ? (j['location'] as Map)['coordinates']
                                      : null;
                                  if (c is List &&
                                      c.length == 2 &&
                                      !(c[0] == 0 && c[1] == 0)) {
                                    jLng = (c[0] as num).toDouble();
                                    jLat = (c[1] as num).toDouble();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _RecommendedCard(
                                      job: j,
                                      photoUrl: _firstPhotoUrl(j),
                                      fallback: _fallbackForCategory(
                                        (j['category'] ?? '').toString(),
                                      ),
                                      distanceKm: _distanceKmFrom(j),
                                      jobLat: jLat,
                                      jobLng: jLng,
                                      refLat: ref.lat,
                                      refLng: ref.lng,
                                    ),
                                  );
                                }).toList(),
                              );
                            },
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
                  isWorkMode: !auth.isJobGiver,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CuratedCategory {
  final String name;

  /// Image asset path. When null, the item renders `icon` on an `accent`
  /// circle instead — used for categories without dedicated illustrations.
  final String? image;
  final IconData? icon;
  final Color? accent;

  const _CuratedCategory(this.name, {this.image, this.icon, this.accent})
    : assert(
        image != null || icon != null,
        'A _CuratedCategory needs either an image asset or an icon.',
      );
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
          style: const TextStyle(fontSize: 13, color: Color(0xFF6A7282)),
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
                style: const TextStyle(fontSize: 12, color: Color(0xFF991B1B)),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFDC2626),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
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
  final ValueChanged<bool> onToggleCurrentLocation;
  final int todayEarnings;
  final int weekEarnings;
  final int? deltaPct;
  final VoidCallback onSearchTap;
  final VoidCallback onNotificationsTap;
  final VoidCallback onWishlistTap;
  final int unreadNotifications;

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
    required this.onWishlistTap,
    this.unreadNotifications = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF408EE0),
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
                color: Color(0xFF408EE0),
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
                color: Color(0xFF408EE0),
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
                    _CurrentLocationToggle(
                      value: useCurrentLocation,
                      loading: gpsLoading,
                      onChanged: onToggleCurrentLocation,
                    ),
                    const SizedBox(width: 10),
                    Material(
                      color: const Color(0x0DFFFFFF),
                      shape: const CircleBorder(),
                      child: InkWell(
                        onTap: onWishlistTap,
                        customBorder: const CircleBorder(),
                        child: const SizedBox(
                          width: 32,
                          height: 32,
                          child: Icon(
                            Icons.favorite_border,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: const Color(0x0DFFFFFF),
                      shape: const CircleBorder(),
                      child: InkWell(
                        onTap: onNotificationsTap,
                        customBorder: const CircleBorder(),
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Center(
                                child: Icon(
                                  Icons.notifications_none,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              if (unreadNotifications > 0)
                                Positioned(
                                  top: 2,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 16,
                                      minHeight: 16,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE7000B),
                                      borderRadius: BorderRadius.circular(100),
                                      border: Border.all(
                                        color: const Color(0xFF408EE0),
                                        width: 1.2,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      unreadNotifications > 99
                                          ? '99+'
                                          : '$unreadNotifications',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        height: 1,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
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

class _CurrentLocationToggle extends StatelessWidget {
  final bool value;
  final bool loading;
  final ValueChanged<bool> onChanged;

  const _CurrentLocationToggle({
    required this.value,
    required this.loading,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 50,
        height: 28,
        decoration: BoxDecoration(
          color: value ? const Color(0xFF00C950) : const Color(0x4DFFFFFF),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 180),
              left: value ? 24 : 4,
              top: 3,
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x1A000000),
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: loading
                    ? const Padding(
                        padding: EdgeInsets.all(4),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF00C950),
                          ),
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
        children: [pill('Work', isWorking), pill('Hire', !isWorking)],
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
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0B1220),
                  letterSpacing: -0.4,
                  height: 1.25,
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
                  Icon(Icons.chevron_right, size: 14, color: viewAllColor),
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
            if (category.image != null)
              ClipOval(
                child: Image.asset(
                  category.image!,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                ),
              )
            else
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: category.accent ?? const Color(0xFFF3F4F6),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  category.icon,
                  size: 26,
                  color: const Color(0xFF364153),
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
  final double? refLat;
  final double? refLng;

  const _NearbyGrid({
    required this.items,
    required this.photoUrl,
    required this.fallbackForCategory,
    required this.distanceKm,
    required this.refLat,
    required this.refLng,
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
          final id = (job['_id'] ?? '').toString();
          // Pull job coords for the road-distance lookup (GeoJSON
          // order is [lng, lat]). Null if missing or null-island.
          double? jobLat;
          double? jobLng;
          final coords = (job['location'] is Map)
              ? (job['location'] as Map)['coordinates']
              : null;
          if (coords is List &&
              coords.length == 2 &&
              !(coords[0] == 0 && coords[1] == 0)) {
            jobLng = (coords[0] as num).toDouble();
            jobLat = (coords[1] as num).toDouble();
          }
          final nearbyBase =
              (job['finalPrice'] ?? job['proposedBudget'] ?? 0) as num;
          final nearbyTip = (job['tip'] ?? 0) as num;
          return _NearbyCard(
            title: (job['title'] ?? '').toString(),
            // Price shown everywhere always includes the tip (and the
            // boost fee, when boosted) as one combined total.
            priceInr:
                (job['isBoosted'] == true
                    ? nearbyBase + AppConfig.boostFee
                    : nearbyBase) +
                nearbyTip,
            distanceKm: distanceKm(job),
            photoUrl: photoUrl(job),
            fallback: fallbackForCategory((job['category'] ?? '').toString()),
            jobLat: jobLat,
            jobLng: jobLng,
            refLat: refLat,
            refLng: refLng,
            onTap: id.isEmpty
                ? null
                : () => Navigator.pushNamed(
                    context,
                    '/job-details',
                    arguments: id,
                  ),
          );
        },
      ),
    );
  }
}

class _NearbyCard extends StatefulWidget {
  final String title;
  final num priceInr; // already includes tip + boost fee
  final double distanceKm; // haversine fallback (km), straight-line
  final String? photoUrl;
  final String fallback;
  final VoidCallback? onTap;
  // Coords for the OSRM road-distance upgrade. When all four are
  // non-null we fetch the real driving distance and display that
  // instead of haversine.
  final double? jobLat;
  final double? jobLng;
  final double? refLat;
  final double? refLng;

  const _NearbyCard({
    required this.title,
    required this.priceInr,
    required this.distanceKm,
    required this.photoUrl,
    required this.fallback,
    required this.onTap,
    required this.jobLat,
    required this.jobLng,
    required this.refLat,
    required this.refLng,
  });

  @override
  State<_NearbyCard> createState() => _NearbyCardState();
}

class _NearbyCardState extends State<_NearbyCard> {
  double? _roadKm;

  @override
  void initState() {
    super.initState();
    final jl = widget.jobLat;
    final jg = widget.jobLng;
    final rl = widget.refLat;
    final rg = widget.refLng;
    if (jl != null && jg != null && rl != null && rg != null) {
      Routing.roadDistanceKm(rl, rg, jl, jg).then((km) {
        if (km != null && mounted) setState(() => _roadKm = km);
      });
    }
  }

  String _distanceLabel() {
    final km = _roadKm ?? widget.distanceKm;
    if (km <= 0) return '—';
    return '${km.toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: _JobImage(
              url: widget.photoUrl,
              fallback: widget.fallback,
              width: double.infinity,
              height: 131,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.title,
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
                    _distanceLabel(),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6A7282),
                    ),
                  ),
                ],
              ),
              Text(
                '₹${widget.priceInr.toInt()}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF101828),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecommendedCard extends StatefulWidget {
  final Map<String, dynamic> job;
  final String? photoUrl;
  final String fallback;
  final double distanceKm; // haversine fallback (km), straight-line
  // Coords for the OSRM road-distance upgrade. When all four are
  // non-null we fetch the real driving distance.
  final double? jobLat;
  final double? jobLng;
  final double? refLat;
  final double? refLng;

  const _RecommendedCard({
    required this.job,
    required this.photoUrl,
    required this.fallback,
    required this.distanceKm,
    required this.jobLat,
    required this.jobLng,
    required this.refLat,
    required this.refLng,
  });

  @override
  State<_RecommendedCard> createState() => _RecommendedCardState();
}

class _RecommendedCardState extends State<_RecommendedCard> {
  double? _roadKm;

  @override
  void initState() {
    super.initState();
    final jl = widget.jobLat;
    final jg = widget.jobLng;
    final rl = widget.refLat;
    final rg = widget.refLng;
    if (jl != null && jg != null && rl != null && rg != null) {
      Routing.roadDistanceKm(rl, rg, jl, jg).then((km) {
        if (km != null && mounted) setState(() => _roadKm = km);
      });
    }
  }

  String _distanceLabel() {
    final km = _roadKm ?? widget.distanceKm;
    if (km <= 0) return '—';
    return '${km.toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final title = (job['title'] ?? '').toString();
    final category = (job['category'] ?? 'Other').toString();
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

    final id = (job['_id'] ?? '').toString();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: id.isEmpty
            ? null
            : () => Navigator.pushNamed(context, '/job-details', arguments: id),
        child: Container(
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
                  url: widget.photoUrl,
                  fallback: widget.fallback,
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
                                  _distanceLabel(),
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
          child: Container(color: const Color(0xFFF3F4F6)),
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
              _Stat(
                value: jobsDone,
                label: 'Jobs Done',
                color: Color(0xFF155DFC),
              ),
              _Stat(value: rating, label: 'Rating', color: Color(0xFF00A63E)),
              _Stat(
                value: successPct,
                label: 'Success',
                color: Color(0xFFF54900),
              ),
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
  // Work-mode (jobtaker) uses "My Jobs" instead of "Jobs" — tab still
  // sits at index 1, just relabelled. Hire-mode (jobgiver) keeps "Jobs".
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
    // Watch unreadChats so the Messages icon flips on/off without a
    // local setState — when AuthState fires notifyListeners after
    // /chat/unread comes back, this widget rebuilds and the red dot
    // appears or disappears.
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
          // Messages tab sits at index 2. `unread` is a count of unread
          // MESSAGES from the other side, so the badge shows how many are
          // waiting rather than just that something is.
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

/// Worker's "currently on this job" card.
///
/// Tapping opens Job Status — the screen with the arrival / start / finish
/// actions — rather than the read-only Job Details, because from here the
/// worker's next step is always an action.
class _CurrentWorkCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final VoidCallback onTap;
  const _CurrentWorkCard({required this.job, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final title = (job['title'] ?? 'Job').toString();
    final status = (job['status'] ?? '').toString();
    final giver = job['jobgiver'] is Map ? job['jobgiver'] as Map : const {};
    final giverName = (giver['name'] ?? 'Client').toString();
    final price = (job['finalPrice'] ?? job['proposedBudget'] ?? 0) as num;
    final tip = (job['tip'] ?? 0) as num;
    // Awaiting payment is the one state where the worker is owed rather
    // than working, so it reads amber instead of blue.
    final awaitingPay = status == 'completed';
    final accent = awaitingPay
        ? const Color(0xFFF54900)
        : const Color(0xFF155DFC);
    final tint = awaitingPay
        ? const Color(0xFFFFF7ED)
        : const Color(0xFFEFF6FF);

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
                          'For $giverName',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF6A7282),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '₹${(price + tip).toInt()}',
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
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: tint,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: accent.withAlpha(60)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          awaitingPay
                              ? Icons.account_balance_wallet_outlined
                              : Icons.flash_on,
                          size: 12,
                          color: accent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          workerStatusLabel(job),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: Color(0xFF9CA3AF),
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
    'reached': _StatusStyle(
      label: 'Worker Arrived',
      icon: Icons.location_on,
      bg: Color(0xFFEFF6FF),
      border: Color(0xFFBEDBFF),
      fg: Color(0xFF155DFC),
    ),
    // Completed but unpaid. Without this the fallback is the 'open' style
    // ("Finding Workers"), which is flatly wrong on a finished job — and
    // the label doubles as the prompt to go and release the money.
    'completed': _StatusStyle(
      label: 'Payment Due',
      icon: Icons.account_balance_wallet_outlined,
      bg: Color(0xFFFFF7ED),
      border: Color(0xFFFFD6A8),
      fg: Color(0xFFF54900),
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
                  style:
                      _statusStyles[(j['status'] ?? '').toString()] ??
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

/// Small orange "Boosted" chip shown on a job the giver paid to boost.
class _BoostedBadge extends StatelessWidget {
  const _BoostedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEDD4),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.bolt, size: 13, color: Color(0xFFF54900)),
          SizedBox(width: 3),
          Text(
            'Boosted',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFFF54900),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveJobCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final _StatusStyle style;
  final VoidCallback? onTap;
  const _ActiveJobCard({required this.job, required this.style, this.onTap});

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
    final isBoosted = job['isBoosted'] == true;
    final basePrice = (job['finalPrice'] ?? job['proposedBudget'] ?? 0) as num;
    final tip = (job['tip'] ?? 0) as num;
    // Price shown everywhere always includes the tip (and the boost fee,
    // when boosted) as one combined total.
    final price =
        (isBoosted ? basePrice + AppConfig.boostFee : basePrice) + tip;
    final ago = _agoFromCreatedAt(job['createdAt']?.toString());
    final interested = job['interested'] is List
        ? (job['interested'] as List).length
        : 0;
    final status = (job['status'] ?? '').toString();
    // A worker is assigned from 'confirmed' onward, so show their rating
    // rather than "0 interested" — which read as nobody having applied to
    // a job that already has someone on the way.
    final isInProgress = const [
      'confirmed',
      'reached',
      'in_progress',
      'completed',
    ].contains(status);

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
                        if (isBoosted) ...[
                          const SizedBox(height: 6),
                          const _BoostedBadge(),
                        ],
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
                      children: [
                        const Icon(
                          Icons.star,
                          size: 16,
                          color: Color(0xFFFFB300),
                        ),
                        const SizedBox(width: 4),
                        // The assigned worker's real rating. This was a
                        // hardcoded "4.8" — every accepted job showed the
                        // same invented score regardless of who was hired.
                        // The endpoint already populates selectedJobtaker
                        // with their rating, so nothing extra is fetched.
                        Text(
                          displayRating(
                            job['selectedJobtaker'] is Map
                                ? (job['selectedJobtaker'] as Map)['rating']
                                : null,
                          ),
                          style: const TextStyle(
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
          activities.add(
            _ActivityItem(
              message: '$name applied for ${j['title'] ?? 'your job'}',
              createdAt: last['createdAt']?.toString(),
            ),
          );
        }
      }
      if (j['status'] == 'completed' && j['completedAt'] != null) {
        activities.add(
          _ActivityItem(
            message: '${j['title'] ?? 'Job'} completed',
            createdAt: j['completedAt']?.toString(),
          ),
        );
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

  // Pull the reference point we measure worker distances against, in
  // the same priority order the rest of the home screen uses:
  // currentLocation (if the user toggled it on) → workArea → home
  // location. Returns null when none of them have real coordinates.
  ({double lat, double lng})? _origin(BuildContext context) {
    final auth = context.read<AuthState>();
    for (final key in const ['currentLocation', 'workArea', 'location']) {
      final raw = auth.user?[key];
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

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const _LoadingBlock(height: 260);
    }
    if (workers.isEmpty) {
      return const _EmptyState(message: 'No verified workers near you yet.');
    }
    final origin = _origin(context);
    return SizedBox(
      height: 260,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: workers.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _WorkerCard(
          worker: workers[i],
          originLat: origin?.lat,
          originLng: origin?.lng,
        ),
      ),
    );
  }
}

class _WorkerCard extends StatelessWidget {
  final Map<String, dynamic> worker;
  // Caller's reference point, used for the per-card distance label.
  // Null when the user has no usable workArea / location yet — in
  // that case the distance row is just hidden.
  final double? originLat;
  final double? originLng;

  const _WorkerCard({
    required this.worker,
    required this.originLat,
    required this.originLng,
  });

  String _distanceLabel() {
    // Resolve a distance in km, trying each source in order:
    //   1. backend's roadDistanceKm (OSRM driving route)
    //   2. local haversine vs the jobgiver's reference point
    // Worker is in the Nearby list, so even when we can't compute a
    // number we surface a "Nearby" placeholder instead of hiding the
    // row — keeps the card layout consistent.
    double? km;
    final road = worker['roadDistanceKm'];
    if (road is num && road >= 0) {
      km = road.toDouble();
    } else if (originLat != null && originLng != null) {
      final raw = worker['currentLocation'] is Map
          ? worker['currentLocation']
          : (worker['location'] is Map ? worker['location'] : null);
      if (raw is Map) {
        final coords = raw['coordinates'];
        if (coords is List && coords.length >= 2) {
          final lng = (coords[0] as num?)?.toDouble();
          final lat = (coords[1] as num?)?.toDouble();
          if (lat != null && lng != null && !(lat == 0 && lng == 0)) {
            km = _HomeScreenState._haversineKm(
              originLat!,
              originLng!,
              lat,
              lng,
            );
          }
        }
      }
    }
    if (km == null) return 'Nearby';
    // Sub-100m reads as a bug (especially with co-located test
    // accounts), so collapse it to the same "Nearby" label.
    if (km < 0.1) return 'Nearby';
    if (km < 1) return '${(km * 1000).round()} m';
    return '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';
  }

  @override
  Widget build(BuildContext context) {
    final name = (worker['name'] ?? 'Worker').toString();
    final rating = displayRating(worker['rating']);
    // Kept as a string because the caller renders it inline; an unrated
    // worker shows "0" here, which is honest next to the default stars —
    // it says "no reviews yet" rather than claiming any.
    final ratingCount = ratingCountValue(worker['rating']).toString();
    final skills = worker['skills'] is List
        ? (worker['skills'] as List).cast<String>()
        : <String>[];
    final isOnline = worker['isAvailable'] == true;
    final photo = worker['photo']?.toString();
    final photoUrl = (photo != null && photo.isNotEmpty)
        ? (photo.startsWith('http') ? photo : '${AppConfig.apiBase}$photo')
        : null;
    final hourlyRate = worker['hourlyRate'];
    final fromPrice = hourlyRate is num ? 'From ₹${hourlyRate.toInt()}' : null;
    final distance = _distanceLabel();

    return Container(
      width: 168,
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
                  width: 144,
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
              if (isOnline)
                Positioned(
                  top: -3,
                  right: -3,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C950),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.6),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF101828),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.location_on_outlined,
                size: 11,
                color: Color(0xFF6B7280),
              ),
              const SizedBox(width: 2),
              Text(
                distance,
                style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
              ),
            ],
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
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF101828),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '($ratingCount)',
                style: const TextStyle(fontSize: 11, color: Color(0xFF6A7282)),
              ),
            ],
          ),
          if (fromPrice != null) ...[
            const SizedBox(height: 4),
            Text(
              fromPrice,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFFFF6900),
              ),
            ),
          ],
          if (skills.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              skills.take(2).join('  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF6B7280),
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
