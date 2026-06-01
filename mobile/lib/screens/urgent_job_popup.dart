import 'package:flutter/material.dart';

import '../config.dart';
import '../services/routing.dart';

/// Modal popup shown when a job-taker goes online (flips the Home
/// "Current Location" toggle ON) and we find a new urgent job nearby.
///
/// Pops with [UrgentJobResult] when the user submits (Accept or Send a
/// custom amount). Pops with `null` if dismissed (X or backdrop).
class UrgentJobResult {
  /// 'accept' = quick-apply at the job's suggested price.
  /// 'custom' = caller should navigate to /request-custom-amount so
  ///   the user can set a custom price + message on a full screen.
  final String action;
  final num price;
  const UrgentJobResult({required this.action, required this.price});
}

class UrgentJobPopup extends StatefulWidget {
  final Map<String, dynamic> job;
  // Haversine fallback (km) — shown instantly. We upgrade this to
  // OSRM road distance in the background and re-render once the
  // routing service responds.
  final double distanceKm;
  // Optional ref coords — when provided we fetch road distance from
  // refLat/refLng → job's coords. Null disables the road upgrade.
  final double? refLat;
  final double? refLng;

  const UrgentJobPopup({
    super.key,
    required this.job,
    required this.distanceKm,
    this.refLat,
    this.refLng,
  });

  static Future<UrgentJobResult?> show(
    BuildContext context, {
    required Map<String, dynamic> job,
    required double distanceKm,
    double? refLat,
    double? refLng,
  }) {
    return showDialog<UrgentJobResult>(
      context: context,
      // Only the X button (top-right) dismisses the popup — tapping
      // outside the card does nothing. Prevents the user from
      // accidentally losing a job offer with a stray tap.
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => UrgentJobPopup(
        job: job,
        distanceKm: distanceKm,
        refLat: refLat,
        refLng: refLng,
      ),
    );
  }

  @override
  State<UrgentJobPopup> createState() => _UrgentJobPopupState();
}

class _UrgentJobPopupState extends State<UrgentJobPopup> {
  double? _roadKm; // OSRM road distance once it resolves

  @override
  void initState() {
    super.initState();
    final rl = widget.refLat;
    final rg = widget.refLng;
    // Pull job's coords (GeoJSON [lng, lat]) for the routing call.
    double? jLat;
    double? jLng;
    final loc = widget.job['location'];
    final c = (loc is Map) ? loc['coordinates'] : null;
    if (c is List &&
        c.length == 2 &&
        !(c[0] == 0 && c[1] == 0)) {
      jLng = (c[0] as num).toDouble();
      jLat = (c[1] as num).toDouble();
    }
    if (rl != null && rg != null && jLat != null && jLng != null) {
      Routing.roadDistanceKm(rl, rg, jLat, jLng).then((km) {
        if (km != null && mounted) setState(() => _roadKm = km);
      });
    }
  }

  num get _suggestedPrice =>
      (widget.job['finalPrice'] ?? widget.job['proposedBudget'] ?? 0) as num;

  void _onAccept() {
    Navigator.pop(
      context,
      UrgentJobResult(action: 'accept', price: _suggestedPrice),
    );
  }

  void _onRequestCustom() {
    // Caller handles navigation to /request-custom-amount. Price 0
    // because the actual amount will be picked on that screen.
    Navigator.pop(
      context,
      UrgentJobResult(action: 'custom', price: _suggestedPrice),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final isToday = dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day;
    if (isToday) return 'Today';
    final tomorrow = now.add(const Duration(days: 1));
    if (dt.year == tomorrow.year &&
        dt.month == tomorrow.month &&
        dt.day == tomorrow.day) {
      return 'Tomorrow';
    }
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _formatTime(DateTime dt) {
    final h12 = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final mm = dt.minute.toString().padLeft(2, '0');
    final ap = dt.hour < 12 ? 'AM' : 'PM';
    return '$h12:$mm $ap';
  }

  String _distanceText() {
    // Prefer OSRM road distance when we have it, fall back to the
    // haversine estimate passed in by the caller.
    final km = _roadKm ?? widget.distanceKm;
    if (km <= 0) return 'Nearby';
    if (km < 1) return '${(km * 1000).round()} m away';
    if (km < 10) return '${km.toStringAsFixed(1)} km away';
    return '${km.round()} km away';
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final title = (job['title'] ?? 'New Job').toString();
    final category = (job['category'] ?? '').toString();
    final price = _suggestedPrice;
    final scheduledAt = job['scheduledAt']?.toString();
    final scheduledDt =
        scheduledAt != null ? DateTime.tryParse(scheduledAt)?.toLocal() : null;
    final loc = job['location'] is Map ? job['location'] as Map : const {};
    final locText = [loc['address'], loc['city']]
        .map((s) => (s ?? '').toString())
        .where((s) => s.trim().isNotEmpty)
        .join(', ');
    final giver = job['jobgiver'] is Map ? job['jobgiver'] as Map : const {};
    final giverName = (giver['name'] ?? '').toString();
    final giverPhotoRaw = (giver['photo'] ?? '').toString();
    final giverPhoto = giverPhotoRaw.isEmpty
        ? null
        : (giverPhotoRaw.startsWith('http')
            ? giverPhotoRaw
            : '${AppConfig.apiBase}$giverPhotoRaw');
    double? giverRating;
    final r = giver['rating'];
    if (r is Map) {
      final v = r['average'];
      if (v is num) giverRating = v.toDouble();
    } else if (r is num) {
      giverRating = r.toDouble();
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _headerStrip(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Text(
                  'Urgent: $title',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFF6900),
                    height: 1.3,
                  ),
                ),
              ),
              if (category.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    category,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
              _postedByCard(giverName, giverPhoto, giverRating),
              _detailRows(locText, scheduledDt, price),

              _twoButtonsLayout(price),

              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Text(
                  'Respond quickly to increase your chances of getting hired',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerStrip() {
    return Container(
      decoration: const BoxDecoration(color: Color(0xFFFF6900)),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Row(
        children: [
          const Icon(Icons.bolt, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'New Job Available',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          InkWell(
            onTap: () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.close, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _postedByCard(String name, String? photoUrl, double? rating) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFFE5E7EB),
              backgroundImage:
                  photoUrl != null ? NetworkImage(photoUrl) : null,
              child: photoUrl == null
                  ? const Icon(Icons.person,
                      color: Color(0xFF9CA3AF), size: 26)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? 'Job Poster' : name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF101828),
                    ),
                  ),
                  if (rating != null && rating > 0)
                    Row(
                      children: [
                        const Icon(Icons.star,
                            size: 14, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 4),
                        Text(
                          rating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF6B7280),
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
    );
  }

  Widget _detailRows(String locText, DateTime? scheduledDt, num price) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        children: [
          if (locText.isNotEmpty)
            _DetailRow(
              icon: Icons.location_on_outlined,
              text: locText,
              trailing: (_roadKm ?? widget.distanceKm) > 0
                  ? Text(
                      _distanceText(),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                      ),
                    )
                  : null,
            ),
          if (scheduledDt != null) ...[
            const SizedBox(height: 10),
            _DetailRow(
              icon: Icons.calendar_today_outlined,
              text: _formatDate(scheduledDt),
            ),
            const SizedBox(height: 10),
            _DetailRow(
              icon: Icons.access_time,
              text: _formatTime(scheduledDt),
            ),
          ],
          const SizedBox(height: 10),
          _DetailRow(
            icon: Icons.attach_money,
            text: '₹${price.toInt()}',
            valueColor: const Color(0xFF16A34A),
          ),
        ],
      ),
    );
  }

  Widget _twoButtonsLayout(num price) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        children: [
          SizedBox(
            height: 52,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _onAccept,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6900),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                'Accept Job - ₹${price.toInt()}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _onRequestCustom,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(
                  color: Color(0xFF408EE0),
                  width: 1.4,
                ),
                foregroundColor: const Color(0xFF408EE0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Request Custom Amount',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? valueColor;
  final Widget? trailing;

  const _DetailRow({
    required this.icon,
    required this.text,
    this.valueColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF6B7280)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: valueColor ?? const Color(0xFF101828),
              fontWeight:
                  valueColor != null ? FontWeight.w600 : FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ],
      ],
    );
  }
}
