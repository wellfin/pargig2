import 'package:flutter/material.dart';
import '../widgets/job_map.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/home_api.dart';
import '../config.dart';
import '../state/auth_state.dart';
import 'complete_job_screen.dart';
import 'enter_otp_screen.dart';

/// Args for Navigator.pushNamed('/job-status', arguments: ...)
class JobStatusArgs {
  final String jobId;
  const JobStatusArgs({required this.jobId});
}

/// Job-in-progress tracking screen. Shows a vertical status timeline
/// (Pending → Confirmed → In Progress → Completed), the client's
/// contact card, a map placeholder with ETA, and an Arrived button
/// that POSTs to /jobs/:id/reach to mark the worker on-site.
class JobStatusScreen extends StatefulWidget {
  const JobStatusScreen({super.key});

  @override
  State<JobStatusScreen> createState() => _JobStatusScreenState();
}

class _JobStatusScreenState extends State<JobStatusScreen> {
  String? _jobId;
  Map<String, dynamic>? _job;
  bool _loading = true;
  String? _error;
  bool _arriving = false;

  String? _clientName() {
    final giver = _job?['jobgiver'];
    if (giver is Map) {
      final n = (giver['name'] ?? '').toString().trim();
      if (n.isNotEmpty) return n;
    }
    return null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_jobId != null) return;
    final raw = ModalRoute.of(context)?.settings.arguments;
    if (raw is JobStatusArgs) {
      _jobId = raw.jobId;
      _fetch();
    }
  }

  Future<void> _fetch() async {
    final id = _jobId;
    if (id == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final job = await HomeApi.jobById(id);
      if (!mounted) return;
      setState(() {
        _job = job;
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

  Future<void> _markCompleted() async {
    final id = _jobId;
    if (id == null) return;
    // Hand off to the Complete Job screen — it owns the proof-of-
    // completion upload (photos + note) and the final POST to
    // /jobs/:id/complete. We re-fetch on return so the bottom button
    // reflects the new state (still in_progress until the client's
    // completion OTP is verified, but the proof is now on the job).
    final ok = await Navigator.pushNamed(
      context,
      '/complete-job',
      arguments: CompleteJobArgs(
        jobId: id,
        jobTitle: (_job?['title'] ?? '').toString(),
      ),
    );
    if (!mounted) return;
    if (ok == true) _fetch();
  }

  Future<void> _markArrived() async {
    final id = _jobId;
    if (id == null || _arriving) return;
    final status = (_job?['status'] ?? '').toString();
    // Issue the 6-digit start PIN and notify the jobgiver if it hasn't been
    // sent yet (job still 'confirmed'). If the job is already 'reached', the
    // code was sent earlier (Start Navigation / Confirm & Continue) — skip
    // re-issuing and go straight to entering it. The worker collects the
    // code from the client on the OTP screen and verifies it there.
    if (status != 'reached') {
      setState(() => _arriving = true);
      try {
        await ApiClient.post('/jobs/$id/reach', {});
      } catch (e) {
        if (!mounted) return;
        setState(() => _arriving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ApiException
                  ? e.message
                  : "Couldn't notify the client. Try again.",
            ),
          ),
        );
        return;
      }
      if (!mounted) return;
      setState(() => _arriving = false);
    }
    if (!mounted) return;
    // Re-fetch on return so the timeline reflects the new status.
    await Navigator.pushNamed(
      context,
      '/enter-otp',
      arguments: EnterOtpArgs(jobId: id, clientName: _clientName()),
    );
    if (!mounted) return;
    _fetch();
  }

  // True when the signed-in user is the job giver (viewing via Track Job),
  // false when they're the assigned worker. Drives whether we show the
  // start PIN + worker details (giver) or the client card + Arrived (worker).
  bool _amJobGiver() {
    final me = context.read<AuthState>().user?['_id']?.toString();
    if (me == null || me.isEmpty) return false;
    final giver = _job?['jobgiver'];
    final giverId = giver is Map
        ? (giver['_id'] ?? '').toString()
        : (giver ?? '').toString();
    return me == giverId;
  }

  void _callClient() {
    // url_launcher isn't in pubspec yet; surface the phone in a
    // snackbar for now. Wire `launchUrl(Uri.parse("tel:$phone"))`
    // once that package is added. The giver calls the worker and the
    // worker calls the client, so pick the other party.
    final amGiver = _amJobGiver();
    final j = _job ?? const <String, dynamic>{};
    final person = amGiver ? j['selectedJobtaker'] : j['jobgiver'];
    final phone = person is Map ? (person['mobile'] ?? '').toString() : '';
    final who = amGiver ? 'Worker' : 'Client';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          phone.isEmpty ? '$who phone not available' : 'Calling $phone…',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _Header(onBack: () => Navigator.maybePop(context)),
          Expanded(child: _body()),
          // The Arrived / Mark-Completed actions belong to the worker. The
          // job giver only tracks the job (and reads the PIN), so no bar.
          if (_job != null && !_loading && !_amJobGiver()) _bottomBar(),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6900)),
        ),
      );
    }
    if (_error != null || _job == null) {
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
              const SizedBox(height: 10),
              Text(
                _error ?? 'Job not found',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 14),
              OutlinedButton(onPressed: _fetch, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final job = _job!;
    final title = (job['title'] ?? 'Job').toString();
    final status = (job['status'] ?? '').toString();
    final createdAt = job['createdAt']?.toString();
    final scheduledAt = job['scheduledAt']?.toString();
    final startedAt = job['startedAt']?.toString();
    final completedAt = job['completedAt']?.toString();
    final startOtp = job['startOtp'];
    final reachedAt = startOtp is Map
        ? (startOtp['issuedAt']?.toString())
        : null;
    final amGiver = _amJobGiver();
    // The job giver (Track Job) sees the 6-digit start PIN to read out to
    // the worker, who enters it at the Arrived → OTP step. Only while the
    // PIN is live (status 'reached', not yet verified into in_progress).
    final startPin = (amGiver && status == 'reached' && startOtp is Map)
        ? (startOtp['code'] ?? '').toString()
        : '';

    return RefreshIndicator(
      color: const Color(0xFFFF6900),
      onRefresh: _fetch,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101828),
            ),
          ),
          const SizedBox(height: 14),
          _StatusTimelineCard(
            status: status,
            createdAt: createdAt,
            confirmedAt: scheduledAt,
            inProgressAt: startedAt ?? reachedAt,
            completedAt: completedAt,
          ),
          const SizedBox(height: 14),
          if (startPin.isNotEmpty) ...[
            _StartPinCard(code: startPin),
            const SizedBox(height: 14),
          ],
          _PersonDetailsCard(
            person: amGiver ? job['selectedJobtaker'] : job['jobgiver'],
            label: amGiver ? 'Worker Details' : 'Clint Details',
            onCall: _callClient,
          ),
          const SizedBox(height: 14),
          _LiveLocationCard(
            locationText: _jobLocationText(job),
            point: _jobLatLng(job),
          ),
        ],
      ),
    );
  }

  /// Human address of the job, for the line under the map.
  ///
  /// Address and city are joined because either alone is often too
  /// vague to place ("Shop 4" / "Gurugram"). Returns null when the job
  /// carries no address at all, so the card can say so rather than
  /// printing an empty line.
  String? _jobLocationText(Map<String, dynamic> job) {
    final loc = job['location'];
    if (loc is! Map) return null;
    final parts = [loc['address'], loc['city']]
        .map((s) => (s ?? '').toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  // GeoJSON Point on the job doc is { coordinates: [lng, lat] }.
  // Returns null when coords are absent or the default [0, 0] sentinel.
  // Returns a plain pair rather than a map-library type, so swapping the
  // map implementation doesn't ripple back into this screen.
  ({double lat, double lng})? _jobLatLng(Map<String, dynamic> job) {
    final loc = job['location'];
    if (loc is! Map) return null;
    final coords = loc['coordinates'];
    if (coords is! List || coords.length < 2) return null;
    final lng = (coords[0] as num?)?.toDouble();
    final lat = (coords[1] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    if (lat == 0 && lng == 0) return null;
    return (lat: lat, lng: lng);
  }

  Widget _bottomBar() {
    final status = (_job?['status'] ?? '').toString();
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE5E7EB), width: 0.8)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: SizedBox(
          height: 52,
          width: double.infinity,
          child: _bottomButton(status),
        ),
      ),
    );
  }

  Widget _bottomButton(String status) {
    // in_progress → orange-filled Mark as Completed; opens the
    // Complete Job module (photo + note proof, final /complete POST).
    if (status == 'in_progress') {
      return ElevatedButton(
        onPressed: _markCompleted,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF6900),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: const Text(
          'Mark as Completed',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      );
    }
    // completed / cancelled → disabled neutral label.
    if (status == 'completed' || status == 'cancelled') {
      return OutlinedButton(
        onPressed: null,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFD1D5DB), width: 1.2),
          foregroundColor: const Color(0xFF6B7280),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          status == 'completed' ? 'Job Completed' : 'Job Cancelled',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      );
    }
    // reached (PIN already issued) / open / confirmed (default) → tap
    // Arrived to start verification. For a reached job we go straight to
    // PIN entry; otherwise the PIN is issued first (see _markArrived).
    return OutlinedButton(
      onPressed: _arriving ? null : _markArrived,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFFFF6900), width: 1.4),
        foregroundColor: const Color(0xFFFF6900),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: _arriving
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6900)),
              ),
            )
          : const Text(
              'Arrived',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
        12,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
            onPressed: onBack,
          ),
          const SizedBox(width: 4),
          const Text(
            'Job Status',
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

class _StatusTimelineCard extends StatelessWidget {
  final String status;
  final String? createdAt;
  final String? confirmedAt;
  final String? inProgressAt;
  final String? completedAt;

  const _StatusTimelineCard({
    required this.status,
    required this.createdAt,
    required this.confirmedAt,
    required this.inProgressAt,
    required this.completedAt,
  });

  String _fmt(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    const months = [
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
    final h12 = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final mm = dt.minute.toString().padLeft(2, '0');
    final ap = dt.hour < 12 ? 'AM' : 'PM';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} • $h12:$mm $ap';
  }

  // Each step has 3 states: done (green check), current (orange clock),
  // future (gray empty circle).
  int _activeIndex() {
    switch (status) {
      case 'open':
        return 0; // Pending → Confirmed step is the active one
      case 'confirmed':
        return 2; // arrived/in-progress is next
      case 'reached':
      case 'in_progress':
        return 2;
      case 'completed':
        return 4; // all done
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeIdx = _activeIndex();
    final steps = <_TimelineStep>[
      _TimelineStep(
        title: 'Pending',
        sub: _fmt(createdAt),
        state: activeIdx > 0 ? _StepState.done : _StepState.current,
      ),
      _TimelineStep(
        title: 'Confirmed',
        sub: _fmt(confirmedAt),
        state: activeIdx > 1
            ? _StepState.done
            : activeIdx == 1
            ? _StepState.current
            : _StepState.future,
      ),
      _TimelineStep(
        title: 'In Progress',
        sub: _fmt(inProgressAt),
        state: activeIdx > 2
            ? _StepState.done
            : activeIdx == 2
            ? _StepState.current
            : _StepState.future,
      ),
      _TimelineStep(
        title: 'Completed',
        sub: _fmt(completedAt),
        state: activeIdx >= 4 ? _StepState.done : _StepState.future,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Job Status',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101828),
            ),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < steps.length; i++) ...[
            _stepRow(steps[i], isLast: i == steps.length - 1),
          ],
        ],
      ),
    );
  }

  Widget _stepRow(_TimelineStep s, {required bool isLast}) {
    final Color color = s.state == _StepState.done
        ? const Color(0xFF16A34A)
        : s.state == _StepState.current
        ? const Color(0xFFFF6900)
        : const Color(0xFFD1D5DB);
    final IconData icon = s.state == _StepState.done
        ? Icons.check_circle
        : s.state == _StepState.current
        ? Icons.access_time
        : Icons.radio_button_unchecked;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Icon(icon, size: 22, color: color),
            if (!isLast)
              Container(width: 2, height: 24, color: const Color(0xFFE5E7EB)),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: s.state == _StepState.future
                        ? const Color(0xFF9CA3AF)
                        : color,
                  ),
                ),
                if (s.sub.isNotEmpty && s.state != _StepState.future) ...[
                  const SizedBox(height: 2),
                  Text(
                    s.sub,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum _StepState { done, current, future }

class _TimelineStep {
  final String title;
  final String sub;
  final _StepState state;
  const _TimelineStep({
    required this.title,
    required this.sub,
    required this.state,
  });
}

/// Shown to the job giver on Track Job: the 6-digit start PIN the worker
/// needs to begin the job. The giver reads it out to the worker, who types
/// it on the Arrived → OTP screen.
class _StartPinCard extends StatelessWidget {
  final String code;
  const _StartPinCard({required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFDBFE), width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        children: [
          Row(
            children: const [
              Icon(Icons.lock_outline, size: 18, color: Color(0xFF1D4ED8)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Job Start PIN',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1D4ED8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            code,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: 8,
              color: Color(0xFF101828),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Share this PIN with the worker to start the job',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: Color(0xFF1E3A8A),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonDetailsCard extends StatelessWidget {
  // The other party on the job: the client (job giver) when the worker is
  // viewing, or the assigned worker when the job giver is viewing.
  final Object? person;
  final String label;
  final VoidCallback onCall;
  const _PersonDetailsCard({
    required this.person,
    required this.label,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    final giver = person is Map ? person as Map : const {};
    final name = (giver['name'] ?? 'Client').toString();
    final photoRaw = (giver['photo'] ?? '').toString();
    final photo = photoRaw.isEmpty
        ? null
        : (photoRaw.startsWith('http')
              ? photoRaw
              : '${AppConfig.apiBase}$photoRaw');

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101828),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFE5E7EB),
                backgroundImage: photo != null ? NetworkImage(photo) : null,
                child: photo == null
                    ? const Icon(
                        Icons.person,
                        color: Color(0xFF9CA3AF),
                        size: 26,
                      )
                    : null,
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Material(
                color: const Color(0xFFFF6900),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onCall,
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(Icons.call, color: Colors.white, size: 18),
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

class _LiveLocationCard extends StatelessWidget {
  /// Address of the job, shown under the map. Null when the job has no
  /// address recorded.
  final String? locationText;
  final ({double lat, double lng})? point;
  const _LiveLocationCard({required this.locationText, required this.point});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 160,
            width: double.infinity,
            // Google Maps replaces the OpenStreetMap tile layer here.
            //
            // Gestures OFF even though this is the live-tracking card: it
            // sits in the page's ListView, and an interactive map wins the
            // vertical drag, so scrolling with a finger on the map pans
            // the map and the page appears frozen. The camera still
            // follows the worker on its own, and tapping opens the real
            // Google Maps app where panning and navigation belong.
            child: JobMap(
              lat: point?.lat,
              lng: point?.lng,
              height: 160,
              label: 'Job location',
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Job Location',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF408EE0),
                  ),
                ),
                const SizedBox(height: 2),
                // The address, not an ETA. The pin is the job site, and
                // the app has no live worker position to measure from,
                // so the old "Worker is 10 mins away" was a fixed number
                // dressed up as live tracking.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.place_outlined,
                        size: 13,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        locationText ?? 'Location not shared for this job',
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: Color(0xFF6B7280),
                        ),
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
