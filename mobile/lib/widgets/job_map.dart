import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// A small Google Map showing one pinned location.
///
/// Used for job locations on Job Details and for live tracking on Job
/// Status. The API key is supplied by the platform, not by Dart — see
/// android/app/build.gradle.kts and ios/Runner/AppDelegate.swift. When no
/// key is configured the Google SDK renders an empty grid rather than
/// throwing, so a missing key degrades to a blank card, never a crash.
///
/// Gestures are off by default. These maps sit inside scrolling pages, and
/// an interactive map swallows vertical drags — the user tries to scroll
/// the page, the map pans instead, and the screen feels stuck. Tapping
/// opens the real Google Maps app, which is what someone wants from a job
/// address anyway (turn-by-turn, not a 160px viewport).
class JobMap extends StatefulWidget {
  final double? lat;
  final double? lng;
  final double height;

  /// Pin caption in the external maps app.
  final String label;

  /// Allow pinch/drag on the embedded map. Only turn this on when the map
  /// is NOT inside a scrollable, or the page will fight the map for drags.
  final bool interactive;

  /// Show the "Open in Google Maps" affordance and handle taps.
  final bool allowOpenExternal;

  const JobMap({
    super.key,
    required this.lat,
    required this.lng,
    this.height = 170,
    this.label = 'Job location',
    this.interactive = false,
    this.allowOpenExternal = true,
  });

  @override
  State<JobMap> createState() => _JobMapState();
}

class _JobMapState extends State<JobMap> {
  GoogleMapController? _controller;

  bool get _hasPoint {
    final lat = widget.lat;
    final lng = widget.lng;
    // (0,0) is the "no location" sentinel written by the backend when a
    // job carries only a text address — it's a real point in the Atlantic,
    // so rendering it would drop a pin in the ocean.
    return lat != null && lng != null && (lat != 0 || lng != 0);
  }

  @override
  void didUpdateWidget(covariant JobMap old) {
    super.didUpdateWidget(old);
    // Live tracking moves the worker's pin — follow it instead of leaving
    // the camera where it was first built.
    if (_hasPoint && (old.lat != widget.lat || old.lng != widget.lng)) {
      _controller?.animateCamera(
        CameraUpdate.newLatLng(LatLng(widget.lat!, widget.lng!)),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _openExternal() async {
    if (!_hasPoint) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1'
      '&query=${widget.lat},${widget.lng}',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Google Maps')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasPoint) {
      return Container(
        height: widget.height,
        width: double.infinity,
        color: const Color(0xFFEAF2FE),
        alignment: Alignment.center,
        child: const Text(
          'Location unavailable',
          style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
        ),
      );
    }

    final point = LatLng(widget.lat!, widget.lng!);
    final map = GoogleMap(
      initialCameraPosition: CameraPosition(target: point, zoom: 15),
      onMapCreated: (c) => _controller = c,
      markers: {
        Marker(
          markerId: const MarkerId('job'),
          position: point,
          infoWindow: InfoWindow(title: widget.label),
        ),
      },
      myLocationButtonEnabled: false,
      zoomControlsEnabled: widget.interactive,
      mapToolbarEnabled: false,
      compassEnabled: false,
      scrollGesturesEnabled: widget.interactive,
      zoomGesturesEnabled: widget.interactive,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      liteModeEnabled: false,
    );

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Stack(
        children: [
          Positioned.fill(child: map),
          if (widget.allowOpenExternal) ...[
            // A transparent tap target above a non-interactive map. With
            // gestures disabled the map itself never sees the tap, so this
            // is what makes the card actionable.
            if (!widget.interactive)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _openExternal,
                ),
              ),
            Positioned(
              right: 10,
              bottom: 10,
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                elevation: 2,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _openExternal,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.directions, size: 15, color: Color(0xFFFF6900)),
                        SizedBox(width: 5),
                        Text(
                          'Directions',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFFF6900),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
