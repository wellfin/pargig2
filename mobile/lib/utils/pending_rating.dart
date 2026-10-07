import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../screens/rate_experience_screen.dart';

/// Takes the job giver back to a rating they owe.
///
/// Rating the worker is required once a job is finished and paid, but
/// nothing stops someone closing the app on the rating screen. The
/// obligation therefore cannot live only in the navigation stack — it is
/// re-read from the server whenever the app opens, so closing the app is
/// a postponement rather than an escape.
///
/// Derived server-side from "paid and not yet rated" rather than stored
/// as a flag on the device, which means it also survives a reinstall or a
/// move to a new phone.
class PendingRating {
  PendingRating._();

  /// True while a check is in flight or the screen is already open, so a
  /// second call cannot stack two rating screens on top of each other.
  static bool _busy = false;

  /// Checks for an owed rating and, if there is one, opens it.
  ///
  /// Never throws and never blocks the caller's own work: a failed check
  /// leaves the user on the screen they opened, and the next launch asks
  /// again. Being unable to reach the server is not a reason to keep
  /// someone out of the app.
  static Future<void> resumeIfOwed(BuildContext context) async {
    if (_busy) return;
    _busy = true;
    try {
      final res = await ApiClient.get('/ratings/pending');
      final pending = res is Map ? res['pending'] : null;
      if (pending is! Map) return;

      final jobId = (pending['jobId'] ?? '').toString();
      if (jobId.isEmpty) return;
      if (!context.mounted) return;

      await Navigator.of(context).pushNamed(
        '/rate-experience',
        arguments: RateExperienceArgs(
          jobId: jobId,
          jobTitle: (pending['jobTitle'] ?? 'Job').toString(),
          clientName: (pending['workerName'] ?? 'the worker').toString(),
          nextRoute: '/home',
          // The whole point: no skip link, no back button, no back
          // gesture. The same screen they left, in the same state.
          mandatory: true,
        ),
      );
    } catch (_) {
      // Offline, or the server is down. Silent on purpose — this runs on
      // launch, and an error toast about a rating would be the first
      // thing a user sees for a problem they cannot act on.
    } finally {
      _busy = false;
    }
  }
}
