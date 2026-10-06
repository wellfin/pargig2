import '../config.dart';
import 'api_client.dart';

class HomeApi {
  HomeApi._();

  /// Resolves a backend-relative asset path (`/uploads/…`) against the
  /// active server. Absolute URLs are returned untouched.
  static String absoluteUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return '${AppConfig.apiBase}$url';
  }

  /// Returns a list of `{category, count}` for currently open jobs.
  static Future<List<Map<String, dynamic>>> categories() async {
    final res = await ApiClient.get('/jobs/categories');
    if (res is List) {
      return res
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    return const [];
  }

  /// Returns open jobs near `(lat,lng)` within `radiusKm`. When [lat] / [lng]
  /// are null the backend returns recent jobs without a geo filter.
  static Future<List<Map<String, dynamic>>> browse({
    double? lat,
    double? lng,
    double radiusKm = 5,
    int limit = 20,
    String? q,
    double? minPrice,
    double? maxPrice,
    List<String>? categories,
    String? sortBy,
  }) async {
    final query = <String, dynamic>{'limit': limit, 'radiusKm': radiusKm};
    if (lat != null && lng != null) {
      query['lat'] = lat;
      query['lng'] = lng;
    }
    if (q != null && q.isNotEmpty) query['q'] = q;
    if (minPrice != null) query['minPrice'] = minPrice;
    if (maxPrice != null) query['maxPrice'] = maxPrice;
    if (categories != null && categories.isNotEmpty) {
      query['categories'] = categories.join(',');
    }
    if (sortBy != null && sortBy.isNotEmpty) query['sortBy'] = sortBy;
    final res = await ApiClient.get('/jobs/browse', query: query);
    if (res is List) {
      return res
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    return const [];
  }

  /// Earnings summary: `{today, thisWeek, lastWeek, deltaPct}`.
  static Future<Map<String, dynamic>> earnings() async {
    final res = await ApiClient.get('/users/me/earnings');
    if (res is Map) return Map<String, dynamic>.from(res);
    return const {};
  }

  /// Wallet summary used by the Wallet tab — returns
  /// `{ walletBalance, totalEarnings, transactions: [...] }` straight
  /// from /payments/me/earnings. The Flutter side derives this/last
  /// month splits from the transactions array.
  static Future<Map<String, dynamic>> walletSummary() async {
    final res = await ApiClient.get('/payments/me/earnings');
    if (res is Map) return Map<String, dynamic>.from(res);
    return const {};
  }

  /// Release the payment for a completed job. Hit from the
  /// "Release Payment" button on the Hire-mode My Posted Jobs
  /// Completed card. Backend either releases the existing on_hold
  /// Payment or mock-creates a released one inline so the worker's
  /// wallet is credited end-to-end. Returns the timestamp so the
  /// caller can disable the button immediately.
  /// Releases the job's payment to the worker. [methodLabel] is the
  /// human name of whatever the giver picked on Select Payment Method
  /// and [isCod] splits cash from online — the response echoes both
  /// back plus a `transactionId` (null for cash) for the receipt.
  static Future<Map<String, dynamic>> releaseJobPayment(
    String jobId, {
    String? methodLabel,
    bool isCod = false,
  }) async {
    final res = await ApiClient.post('/payments/jobs/$jobId/release', {
      'methodLabel': methodLabel ?? (isCod ? 'Cash on Delivery' : 'Online'),
      'isCod': isCod,
    });
    if (res is Map) return Map<String, dynamic>.from(res);
    return const {};
  }

  /// Open or fetch the 1:1 direct chat room with another user. Used
  /// by the mobile chat screen so messages persist between sessions
  /// AND between the two users (Parveen ↔ Dev). Returns the full
  /// populated ChatRoom doc with embedded messages, lastMessageAt,
  /// and participants (name + photo).
  static Future<Map<String, dynamic>> openDirectChat(String userId) async {
    final res = await ApiClient.post(
      '/chat/direct/with/$userId/open',
      const {},
    );
    if (res is Map) return Map<String, dynamic>.from(res);
    return const {};
  }

  /// List of the caller's chat rooms — backend flattens each room
  /// into {_id, job, partner, lastMessage, lastMessageAt, unread} so
  /// the Messages tab can render directly without re-walking embedded
  /// messages on the client.
  static Future<List<Map<String, dynamic>>> chatRooms() async {
    final res = await ApiClient.get('/chat/rooms');
    if (res is List) {
      return res
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    return const [];
  }

  /// Refresh the room (poll for new messages from the other side).
  /// Same shape as openDirectChat.
  static Future<Map<String, dynamic>> fetchChatRoom(String roomId) async {
    final res = await ApiClient.get('/chat/rooms/$roomId');
    if (res is Map) return Map<String, dynamic>.from(res);
    return const {};
  }

  /// Send a text message into an existing room. Returns the freshly-
  /// appended message subdoc.
  static Future<Map<String, dynamic>> sendChatMessage(
    String roomId,
    String text,
  ) async {
    final res = await ApiClient.post('/chat/rooms/$roomId/messages', {
      'body': text,
      'type': 'text',
    });
    if (res is Map) return Map<String, dynamic>.from(res);
    return const {};
  }

  /// Jobs posted by the current user (any status). Used by the Hire view's
  /// "Active Jobs" section after filtering client-side for active statuses.
  static Future<List<Map<String, dynamic>>> myPostedJobs() async {
    final res = await ApiClient.get('/jobs/posted/me');
    if (res is List) {
      return res
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    return const [];
  }

  /// Jobs the current jobtaker has applied to (showed interest in).
  /// Backend: GET /jobs/applied/me — returns jobs where
  /// interested.jobtaker = current user.
  static Future<List<Map<String, dynamic>>> myAppliedJobs() async {
    final res = await ApiClient.get('/jobs/applied/me');
    if (res is List) {
      return res
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    return const [];
  }

  /// Job giver sets/updates the tip on their own post (kept separate from
  /// the job price). Backend: PUT /jobs/:id/tip.
  static Future<Map<String, dynamic>> setJobTip(String jobId, int tip) async {
    final res = await ApiClient.put('/jobs/$jobId/tip', {'tip': tip});
    return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
  }

  /// In-app notifications for the current user, newest first.
  /// Backend: GET /notifications.
  static Future<List<Map<String, dynamic>>> notifications() async {
    final res = await ApiClient.get('/notifications');
    if (res is List) {
      return res
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    return const [];
  }

  /// Mark the given notification ids as read. Backend: POST /notifications/read.
  static Future<void> markNotificationsRead(List<String> ids) async {
    if (ids.isEmpty) return;
    await ApiClient.post('/notifications/read', {'ids': ids});
  }

  /// Clears every unread notification, including ones older than the
  /// 50 the feed returns — otherwise the bell badge can't reach zero.
  static Future<void> markAllNotificationsRead() async {
    await ApiClient.post('/notifications/read', {'all': true});
  }

  /// Uploads a single image to the backend and returns its public URL
  /// (e.g. `/uploads/123-abc.jpg`). Resolve against `AppConfig.apiBase`
  /// for full URL.
  static Future<String?> uploadJobPhoto(String filePath) async {
    final res = await ApiClient.postFile(
      '/jobs/photo',
      field: 'photo',
      filePath: filePath,
    );
    if (res is Map && res['url'] is String) return res['url'] as String;
    return null;
  }

  /// Opens a gateway order for adding money to the wallet. Returns the
  /// order id and, while the stand-in gateway is running, `isDummy: true`
  /// so the app can complete the flow without a real PSP.
  static Future<Map<String, dynamic>> createWalletOrder(num amount) async {
    final res = await ApiClient.post('/payments/wallet/order', {
      'amount': amount,
    });
    if (res is Map) return Map<String, dynamic>.from(res);
    return const {};
  }

  /// Confirms a wallet top-up and returns the new balance. The credit
  /// only happens here, after the gateway verifies the payment — the app
  /// can't add money on its own say-so.
  static Future<Map<String, dynamic>> confirmWalletTopup({
    required num amount,
    required String orderId,
    String? paymentId,
    String? signature,
    String methodLabel = 'Online',
  }) async {
    final res = await ApiClient.post('/payments/wallet/confirm', {
      'amount': amount,
      'orderId': orderId,
      'paymentId': ?paymentId,
      'signature': ?signature,
      'methodLabel': methodLabel,
    });
    if (res is Map) return Map<String, dynamic>.from(res);
    return const {};
  }

  /// Opens a payment order for a completed job and returns what's needed
  /// to pay it: an order id, the amount, and a `payUri` (a `upi://pay`
  /// deeplink) to render as a QR or hand to a UPI app.
  ///
  /// `isDummy` is true while the backend runs the stand-in gateway, which
  /// is what lets the app offer a "mark as paid" control for testing.
  /// Swapping in a real PSP flips it to false and that control disappears
  /// on its own.
  static Future<Map<String, dynamic>> createPaymentOrder(String jobId) async {
    final res = await ApiClient.post('/payments/jobs/$jobId/order', const {});
    if (res is Map) return Map<String, dynamic>.from(res);
    return const {};
  }

  /// Confirms an order was paid, settling the job: the worker is credited
  /// and the job stamped as paid. Idempotent — confirming an already-paid
  /// job returns the original receipt rather than paying twice.
  static Future<Map<String, dynamic>> confirmPaymentOrder(
    String jobId, {
    required String orderId,
    String? paymentId,
    String? signature,
    String methodLabel = 'UPI',
  }) async {
    final res = await ApiClient.post('/payments/jobs/$jobId/confirm', {
      'orderId': orderId,
      'paymentId': ?paymentId,
      'signature': ?signature,
      'methodLabel': methodLabel,
    });
    if (res is Map) return Map<String, dynamic>.from(res);
    return const {};
  }

  /// Uploads a recorded voice note (16 kHz mono .wav) and returns its
  /// public URL, which goes onto the job as `voiceNoteUrl`. The file is
  /// stored and served back verbatim, so workers hear the giver's actual
  /// voice. Nothing is transcribed — speech-to-text is currently disabled
  /// in the recorder.
  /// Backend: POST /jobs/voice (multipart field `voice`).
  static Future<String?> uploadJobVoiceNote(String filePath) async {
    final res = await ApiClient.postFile(
      '/jobs/voice',
      field: 'voice',
      filePath: filePath,
    );
    if (res is Map && res['url'] is String) return res['url'] as String;
    return null;
  }

  /// Posts a new job. Returns the created job document.
  static Future<Map<String, dynamic>> createJob(
    Map<String, dynamic> body,
  ) async {
    final res = await ApiClient.post('/jobs', body);
    if (res is Map) return Map<String, dynamic>.from(res);
    return const {};
  }

  /// Edits an existing (still-open) job. Backend: PUT /jobs/:id. Only the
  /// jobgiver can edit, and only while the job is still open (no worker
  /// confirmed). Returns the updated job document.
  static Future<Map<String, dynamic>> updateJob(
    String jobId,
    Map<String, dynamic> body,
  ) async {
    final res = await ApiClient.put('/jobs/$jobId', body);
    if (res is Map) return Map<String, dynamic>.from(res);
    return const {};
  }

  /// Single job by id, with jobgiver / selectedJobtaker / interested populated.
  static Future<Map<String, dynamic>> jobById(String id) async {
    final res = await ApiClient.get('/jobs/$id');
    if (res is Map) return Map<String, dynamic>.from(res);
    return const {};
  }

  /// Cancels a job. Caller must be the jobgiver or the selectedJobtaker.
  static Future<Map<String, dynamic>> cancelJob(
    String id, {
    String? reason,
  }) async {
    final body = <String, dynamic>{};
    if (reason != null) {
      body['reason'] = reason;
    }
    final res = await ApiClient.post('/jobs/$id/cancel', body);
    if (res is Map) return Map<String, dynamic>.from(res);
    return const {};
  }

  /// Job-giver accepts a specific applicant. `finalPrice` defaults to the
  /// applicant's proposedPrice on the backend if omitted.
  static Future<Map<String, dynamic>> confirmApplicant(
    String jobId, {
    required String jobtakerId,
    num? finalPrice,
  }) async {
    final body = <String, dynamic>{'jobtakerId': jobtakerId};
    if (finalPrice != null) {
      body['finalPrice'] = finalPrice;
    }
    final res = await ApiClient.post('/jobs/$jobId/confirm', body);
    if (res is Map) return Map<String, dynamic>.from(res);
    return const {};
  }

  /// Job-giver rejects (declines) an applicant. Removes them from the
  /// job's `interested` list on the backend and blocks them from
  /// re-applying, so the rejection sticks across reloads and the job
  /// drops off that worker's "Applied Jobs" list.
  static Future<Map<String, dynamic>> rejectApplicant(
    String jobId, {
    required String jobtakerId,
  }) async {
    final res = await ApiClient.post('/jobs/$jobId/reject', {
      'jobtakerId': jobtakerId,
    });
    if (res is Map) return Map<String, dynamic>.from(res);
    return const {};
  }

  /// Job-takers near `(lat,lng)` within `radiusKm`. Returns name, photo,
  /// rating, distance source data, skills, etc.
  static Future<List<Map<String, dynamic>>> nearbyWorkers({
    double? lat,
    double? lng,
    double radiusKm = 5,
    int limit = 20,
  }) async {
    final query = <String, dynamic>{'limit': limit, 'radiusKm': radiusKm};
    if (lat != null && lng != null) {
      query['lat'] = lat;
      query['lng'] = lng;
    }
    final res = await ApiClient.get('/users/nearby-workers', query: query);
    if (res is List) {
      return res
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    return const [];
  }
}
