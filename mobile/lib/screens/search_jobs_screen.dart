import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/home_api.dart';
import '../config.dart';
import '../state/auth_state.dart';
import 'job_list_results_screen.dart';

class SearchJobsScreen extends StatefulWidget {
  const SearchJobsScreen({super.key});

  @override
  State<SearchJobsScreen> createState() => _SearchJobsScreenState();
}

class _SearchJobsScreenState extends State<SearchJobsScreen> {
  static const _genericFallback = 'assets/home/job_cleaning_house.png';
  static const _categoryFallback = <String, String>{
    'Cleaning': 'assets/home/rec_home_cleaning.png',
    'Plumbing': 'assets/home/rec_plumbing.png',
    'Painting': 'assets/home/rec_painting.png',
    'Carpentry': 'assets/home/rec_furniture.png',
    'Assembly': 'assets/home/rec_furniture.png',
    'Electrical': 'assets/home/rec_plumbing.png',
    'Babysitting': 'assets/home/cat_babysitting.png',
  };

  static const _radiusRanges = <_RadiusRange>[
    _RadiusRange('1-5 Kms', 5),
    _RadiusRange('5-10 Kms', 10),
    _RadiusRange('10-20 kms', 20),
    _RadiusRange('Above 20kms', 100),
  ];

  static const _availableCategories = <String>[
    'Cleaning',
    'Repair',
    'Delivery',
    'Helper',
    'Plumbing',
    'Painting',
    'Electrical',
    'Others',
  ];

  static const _sortOptions = <_SortOption>[
    _SortOption('nearest', 'Nearest First'),
    _SortOption('recent', 'Most Recent'),
    _SortOption('priceHigh', 'Highest Pay'),
    _SortOption('priceLow', 'Lowest Pay'),
  ];

  final _query = TextEditingController();
  final _focus = FocusNode();
  final _location = TextEditingController();
  final _minPrice = TextEditingController();
  final _maxPrice = TextEditingController();
  Timer? _debounce;

  // null = closed, 'location' = Location & Radius (244:593/676),
  // 'filters' = Filters (244:763).
  String? _panelMode;
  int _radiusRangeIndex = 0; // default 1-5 Kms
  bool _gpsLoading = false;

  // Pre-filled from route arguments when the user taps a category chip on
  // the home screen; can be edited via the Filters panel.
  Set<String> _selectedCategories = const {};
  // Default to newest-first so a just-posted job shows at the top of search.
  String _sortKey = 'recent';

  // Center for the geo search. Defaults to user's saved location.
  double? _lat;
  double? _lng;

  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _results = const [];
  bool _searchedAtLeastOnce = false;

  double get _radiusKm => _radiusRanges[_radiusRangeIndex].radiusKm;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthState>().user ?? const {};
    final workArea = user['workArea'] is Map
        ? user['workArea'] as Map
        : const {};
    final workCoords = workArea['coordinates'];
    if (workCoords is List && workCoords.length == 2) {
      final lng = (workCoords[0] as num?)?.toDouble();
      final lat = (workCoords[1] as num?)?.toDouble();
      if (lat != null && lng != null && (lat != 0 || lng != 0)) {
        _lat = lat;
        _lng = lng;
      }
    }
    final workAreaLabel = (user['workAreaLabel'] ?? '').toString();
    if (workAreaLabel.isNotEmpty) {
      _location.text = workAreaLabel;
    } else {
      final loc = user['location'] is Map ? user['location'] as Map : const {};
      final city = (loc['city'] ?? '').toString();
      _location.text = city.isNotEmpty ? city : '';
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Apply any incoming route arguments (e.g. category preselected from
      // tapping a chip on the home screen) before kicking off the first search.
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map) {
        final cat = args['category'];
        if (cat is String && cat.isNotEmpty) {
          setState(() => _selectedCategories = {cat});
        }
        final initialQuery = args['q'];
        if (initialQuery is String && initialQuery.isNotEmpty) {
          _query.text = initialQuery;
        }
      }
      _focus.requestFocus();
      _runSearch();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _focus.dispose();
    _location.dispose();
    _minPrice.dispose();
    _maxPrice.dispose();
    super.dispose();
  }

  void _onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _runSearch);
  }

  Future<void> _runSearch() async {
    setState(() {
      _loading = true;
      _error = null;
      _searchedAtLeastOnce = true;
    });
    try {
      final minP = double.tryParse(_minPrice.text.trim());
      final maxP = double.tryParse(_maxPrice.text.trim());
      final res = await HomeApi.browse(
        lat: _lat,
        lng: _lng,
        radiusKm: _radiusKm,
        limit: 50,
        q: _query.text.trim().isEmpty ? null : _query.text.trim(),
        minPrice: minP,
        maxPrice: maxP,
        categories: _selectedCategories.isEmpty
            ? null
            : _selectedCategories.toList(),
        sortBy: _sortKey,
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

  void _toggleLocationPanel() {
    setState(() {
      _panelMode = _panelMode == 'location' ? null : 'location';
    });
  }

  void _toggleFiltersPanel() {
    setState(() {
      _panelMode = _panelMode == 'filters' ? null : 'filters';
    });
  }

  void _selectRadiusRange(int i) {
    if (_radiusRangeIndex == i) return;
    setState(() => _radiusRangeIndex = i);
  }

  void _toggleCategory(String c) {
    setState(() {
      final next = Set<String>.from(_selectedCategories);
      if (next.contains(c)) {
        next.remove(c);
      } else {
        next.add(c);
      }
      _selectedCategories = next;
    });
  }

  Future<void> _pickSort() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Sort by',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF101828),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (final opt in _sortOptions)
                ListTile(
                  title: Text(opt.label),
                  trailing: _sortKey == opt.key
                      ? const Icon(Icons.check, color: Color(0xFF155DFC))
                      : null,
                  onTap: () => Navigator.pop(sheet, opt.key),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && picked != _sortKey) {
      setState(() => _sortKey = picked);
    }
  }

  void _applyFilters() {
    setState(() => _panelMode = null);
    // Push the dedicated results screen instead of rendering inline.
    // Pass the current filter state through; the results screen does
    // its own HomeApi.browse fetch so it stays in sync after pull-to-
    // refresh and renders with the Figma "Cleaning — 12 jobs" header.
    final minP = double.tryParse(_minPrice.text.trim());
    final maxP = double.tryParse(_maxPrice.text.trim());
    Navigator.pushNamed(
      context,
      '/job-list-results',
      arguments: JobListArgs(
        lat: _lat,
        lng: _lng,
        radiusKm: _radiusKm,
        query: _query.text.trim().isEmpty ? null : _query.text.trim(),
        minPrice: minP,
        maxPrice: maxP,
        categories: _selectedCategories.toList(),
        sortBy: _sortKey,
      ),
    );
  }

  void _resetFiltersInPanel() {
    setState(() {
      _minPrice.clear();
      _maxPrice.clear();
      _selectedCategories = const {};
      _sortKey = 'recent';
    });
  }

  Future<void> _useGps() async {
    if (_gpsLoading) return;
    setState(() => _gpsLoading = true);
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
      _lat = pos.latitude;
      _lng = pos.longitude;
      try {
        final placemarks = await placemarkFromCoordinates(
          pos.latitude,
          pos.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          _location.text =
              [p.locality, p.subAdministrativeArea, p.administrativeArea]
                  .whereType<String>()
                  .where((s) => s.trim().isNotEmpty)
                  .toSet()
                  .join(', ');
        }
      } catch (_) {
        // Coordinates captured even if reverse geocoding failed.
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location captured'),
          duration: Duration(milliseconds: 800),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  Future<void> _applyLocation() async {
    final text = _location.text.trim();
    // If the user typed a location, forward-geocode it so the search recenters
    // on that place. Fail silently — search proceeds with whatever lat/lng we
    // currently have (saved profile or last GPS).
    if (text.isNotEmpty) {
      try {
        final results = await locationFromAddress(text);
        if (results.isNotEmpty) {
          _lat = results.first.latitude;
          _lng = results.first.longitude;
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _panelMode = null);
    _runSearch();
  }

  void _clearFilters() {
    final user = context.read<AuthState>().user ?? const {};
    final loc = user['location'] is Map ? user['location'] as Map : const {};
    final city = (loc['city'] ?? '').toString();
    final coords = loc['coordinates'];
    setState(() {
      _query.clear();
      _location.text = city;
      // Clear filters means "show everything nearby" — wipe the query and
      // category filters, and widen the radius to the largest bucket.
      _radiusRangeIndex = _radiusRanges.length - 1;
      _selectedCategories = const {};
      if (coords is List && coords.length == 2) {
        final lng = (coords[0] as num?)?.toDouble();
        final lat = (coords[1] as num?)?.toDouble();
        if (lat != null && lng != null && (lat != 0 || lng != 0)) {
          _lat = lat;
          _lng = lng;
        } else {
          _lat = null;
          _lng = null;
        }
      } else {
        _lat = null;
        _lng = null;
      }
    });
    _runSearch();
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

  String _fallbackForCategory(String? category) =>
      _categoryFallback[category ?? ''] ?? _genericFallback;

  double _distanceKmFrom(Map<String, dynamic> job) {
    if (_lat == null || _lng == null) return 0;
    final jobLoc = job['location'] is Map ? job['location'] as Map : const {};
    final jobCoords = jobLoc['coordinates'];
    if (jobCoords is! List || jobCoords.length != 2) return 0;
    final jLng = (jobCoords[0] as num?)?.toDouble() ?? 0;
    final jLat = (jobCoords[1] as num?)?.toDouble() ?? 0;
    if (jLat == 0 && jLng == 0) return 0;
    return _haversine(_lat!, _lng!, jLat, jLng);
  }

  static double _haversine(double aLat, double aLng, double bLat, double bLng) {
    const r = 6371.0;
    const pi = 3.141592653589793;
    double toRad(double v) => v * pi / 180.0;
    double cos(double v) {
      var x = v;
      while (x > pi) {
        x -= 2 * pi;
      }
      while (x < -pi) {
        x += 2 * pi;
      }
      final x2 = x * x;
      return 1 - x2 / 2 + x2 * x2 / 24 - x2 * x2 * x2 / 720;
    }

    double sqrt(double v) {
      if (v <= 0) return 0;
      var s = v;
      for (var i = 0; i < 20; i++) {
        s = (s + v / s) / 2;
      }
      return s;
    }

    double asin(double v) {
      if (v <= -1) return -pi / 2;
      if (v >= 1) return pi / 2;
      return v + (v * v * v) / 6 + (3 * v * v * v * v * v) / 40;
    }

    final dLat = toRad(bLat - aLat);
    final dLng = toRad(bLng - aLng);
    final h =
        (1 - cos(dLat)) / 2 +
        cos(toRad(aLat)) * cos(toRad(bLat)) * (1 - cos(dLng)) / 2;
    return 2 * r * asin(sqrt(h));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: Column(
          children: [
            _SearchHeader(
              query: _query,
              focus: _focus,
              onQueryChanged: _onQueryChanged,
              onSubmit: (_) => _runSearch(),
              locationLabel: _location.text.isEmpty
                  ? 'Current Location'
                  : _location.text,
              radiusKm: _radiusKm,
              panelMode: _panelMode,
              onLocationTap: _toggleLocationPanel,
              onFilterTap: _toggleFiltersPanel,
              onBack: () => Navigator.maybePop(context),
            ),
            // When a panel is open it takes the entire remaining body so it
            // can scroll internally and never overflow; the results area only
            // shows when no panel is up.
            if (_panelMode == 'location')
              Expanded(
                child: SingleChildScrollView(
                  child: _LocationPanel(
                    locationController: _location,
                    radiusIndex: _radiusRangeIndex,
                    ranges: _radiusRanges,
                    gpsLoading: _gpsLoading,
                    onUseGps: _useGps,
                    onSelectRange: _selectRadiusRange,
                    onApply: _applyLocation,
                  ),
                ),
              )
            else if (_panelMode == 'filters')
              Expanded(
                child: SingleChildScrollView(
                  child: _FiltersPanel(
                    minPrice: _minPrice,
                    maxPrice: _maxPrice,
                    categories: _availableCategories,
                    selectedCategories: _selectedCategories,
                    sortLabel: _sortOptions
                        .firstWhere(
                          (o) => o.key == _sortKey,
                          orElse: () => _sortOptions.first,
                        )
                        .label,
                    onToggleCategory: _toggleCategory,
                    onPickSort: _pickSort,
                    onClear: _resetFiltersInPanel,
                    onApply: _applyFilters,
                  ),
                ),
              )
            else
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _loading
                                ? 'Searching…'
                                : '${_results.length} jobs found within '
                                      '${_radiusKm.toInt()}km',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF4A5565),
                              height: 1.42,
                            ),
                          ),
                          GestureDetector(
                            onTap: _clearFilters,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                'Clear filters',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF155DFC),
                                  height: 1.42,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(child: _buildResultsBody()),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsBody() {
    if (_loading && _results.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6900)),
          ),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 32,
                color: Color(0xFFDC2626),
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Color(0xFF991B1B)),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _runSearch,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFDC2626),
                  side: const BorderSide(color: Color(0xFFDC2626)),
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          _searchedAtLeastOnce
              ? (_query.text.trim().isEmpty
                    ? 'No jobs in your area yet.'
                    : 'No matches for "${_query.text.trim()}".')
              : 'Search results will appear here',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            color: Color(0xFF6A7282),
            height: 1.5,
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: const Color(0xFFFF6900),
      onRefresh: _runSearch,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        itemCount: _results.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final j = _results[i];
          final id = (j['_id'] ?? '').toString();
          return _ResultCard(
            job: j,
            photoUrl: _firstPhotoUrl(j),
            fallback: _fallbackForCategory((j['category'] ?? '').toString()),
            distanceKm: _distanceKmFrom(j),
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

class _RadiusRange {
  final String label;
  final double radiusKm;
  const _RadiusRange(this.label, this.radiusKm);
}

class _SortOption {
  final String key;
  final String label;
  const _SortOption(this.key, this.label);
}

class _PriceField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  const _PriceField({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
      ),
      alignment: Alignment.center,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlignVertical: TextAlignVertical.center,
        style: const TextStyle(
          fontSize: 15,
          color: Color(0xFF1A1A1A),
          height: 1.2,
        ),
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          hintText: hint,
          hintStyle: const TextStyle(
            color: Color(0x801A1A1A),
            fontSize: 15,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

/// "Filters" panel — matches Figma 244:763. Price Range + Job Titles +
/// Sort By, with Clear and Apply Filters buttons at the bottom.
class _FiltersPanel extends StatelessWidget {
  final TextEditingController minPrice;
  final TextEditingController maxPrice;
  final List<String> categories;
  final Set<String> selectedCategories;
  final String sortLabel;
  final ValueChanged<String> onToggleCategory;
  final VoidCallback onPickSort;
  final VoidCallback onClear;
  final VoidCallback onApply;

  const _FiltersPanel({
    required this.minPrice,
    required this.maxPrice,
    required this.categories,
    required this.selectedCategories,
    required this.sortLabel,
    required this.onToggleCategory,
    required this.onPickSort,
    required this.onClear,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Filters',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF101828),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Price Range',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF4A5565),
              height: 1.43,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _PriceField(controller: minPrice, hint: 'Min ₹'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PriceField(controller: maxPrice, hint: 'Max ₹'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Job Titles',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF4A5565),
              height: 1.43,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: categories.map((c) {
              final selected = selectedCategories.contains(c);
              return GestureDetector(
                onTap: () => onToggleCategory(c),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF155DFC)
                          : const Color(0xFFE5E7EB),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    c,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: selected
                          ? const Color(0xFF155DFC)
                          : const Color(0xFF4A5565),
                      height: 1.43,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          const Text(
            'Sort By',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF4A5565),
              height: 1.43,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: onPickSort,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      sortLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF4A5565),
                        height: 1.43,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down,
                    size: 20,
                    color: Color(0xFF4A5565),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: onClear,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF3F4F6),
                      foregroundColor: const Color(0xFF364153),
                      elevation: 0,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Clear',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: onApply,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2B7FFF),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Apply Filters',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchHeader extends StatelessWidget {
  final TextEditingController query;
  final FocusNode focus;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onSubmit;
  final String locationLabel;
  final double radiusKm;
  final String? panelMode;
  final VoidCallback onLocationTap;
  final VoidCallback onFilterTap;
  final VoidCallback onBack;

  const _SearchHeader({
    required this.query,
    required this.focus,
    required this.onQueryChanged,
    required this.onSubmit,
    required this.locationLabel,
    required this.radiusKm,
    required this.panelMode,
    required this.onLocationTap,
    required this.onFilterTap,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: onBack,
                    child: const Icon(
                      Icons.arrow_back,
                      size: 24,
                      color: Color(0xFF101828),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search,
                        size: 20,
                        color: Color(0xFF6A7282),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: query,
                          focusNode: focus,
                          onChanged: onQueryChanged,
                          onSubmitted: onSubmit,
                          textInputAction: TextInputAction.search,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Color(0xFF1A1A1A),
                          ),
                          decoration: const InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            hintText: 'Search jobs...',
                            hintStyle: TextStyle(
                              color: Color(0x801A1A1A),
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Material(
                  color: panelMode == 'location'
                      ? const Color(0xFFDBEAFE)
                      : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: onLocationTap,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 18,
                            color: Color(0xFF155DFC),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Location',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF2B7FFF),
                                    height: 1.33,
                                  ),
                                ),
                                Text(
                                  locationLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF155DFC),
                                    height: 1.43,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDBEAFE),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              '${radiusKm.toInt()}km',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF155DFC),
                                height: 1.33,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: panelMode == 'filters'
                    ? const Color(0xFFDBEAFE)
                    : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: onFilterTap,
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      Icons.tune,
                      size: 20,
                      color: panelMode == 'filters'
                          ? const Color(0xFF155DFC)
                          : const Color(0xFF101828),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Select Location & Radius" panel — Apply Location button at the bottom.
class _LocationPanel extends StatelessWidget {
  final TextEditingController locationController;
  final int radiusIndex;
  final List<_RadiusRange> ranges;
  final bool gpsLoading;
  final VoidCallback onUseGps;
  final ValueChanged<int> onSelectRange;
  final VoidCallback onApply;

  const _LocationPanel({
    required this.locationController,
    required this.radiusIndex,
    required this.ranges,
    required this.gpsLoading,
    required this.onUseGps,
    required this.onSelectRange,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Select Location & Radius',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF101828),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Location',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF4A5565),
              height: 1.43,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFE5E7EB),
                      width: 1,
                    ),
                  ),
                  child: TextField(
                    controller: locationController,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF1A1A1A),
                    ),
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: 'Current Location',
                      hintStyle: TextStyle(
                        color: Color(0x801A1A1A),
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 88,
                height: 44,
                child: ElevatedButton(
                  onPressed: gpsLoading ? null : onUseGps,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2B7FFF),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(
                      0xFF2B7FFF,
                    ).withAlpha(140),
                    disabledForegroundColor: Colors.white,
                    elevation: 0,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: gpsLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.near_me, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'GPS',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Search Radius to do job',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF4A5565),
              height: 1.43,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(ranges.length, (i) {
              final selected = i == radiusIndex;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: i == ranges.length - 1 ? 0 : 6,
                  ),
                  child: GestureDetector(
                    onTap: () => onSelectRange(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      height: 36,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF2B7FFF)
                            : const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          ranges[i].label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: selected
                                ? Colors.white
                                : const Color(0xFF364153),
                            height: 1.43,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: onApply,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2B7FFF),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Apply Location',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final String? photoUrl;
  final String fallback;
  final double distanceKm;
  final VoidCallback? onTap;

  const _ResultCard({
    required this.job,
    required this.photoUrl,
    required this.fallback,
    required this.distanceKm,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
    final urgent =
        (job['preference'] ?? '') == 'experienced' ||
        job['priceMode'] == 'fixed';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
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
