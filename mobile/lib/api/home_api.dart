import 'api_client.dart';

class HomeApi {
  HomeApi._();

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
    final query = <String, dynamic>{
      'limit': limit,
      'radiusKm': radiusKm,
    };
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
  static Future<Map<String, dynamic>> releaseJobPayment(String jobId) async {
    final res =
        await ApiClient.post('/payments/jobs/$jobId/release', const {});
    if (res is Map) return Map<String, dynamic>.from(res);
    return const {};
  }

  /// Open or fetch the 1:1 direct chat room with another user. Used
  /// by the mobile chat screen so messages persist between sessions
  /// AND between the two users (Parveen ↔ Dev). Returns the full
  /// populated ChatRoom doc with embedded messages, lastMessageAt,
  /// and participants (name + photo).
  static Future<Map<String, dynamic>> openDirectChat(String userId) async {
    final res =
        await ApiClient.post('/chat/direct/with/$userId/open', const {});
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
    final res = await ApiClient.post(
      '/chat/rooms/$roomId/messages',
      {'body': text, 'type': 'text'},
    );
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

  /// Posts a new job. Returns the created job document.
  static Future<Map<String, dynamic>> createJob(Map<String, dynamic> body) async {
    final res = await ApiClient.post('/jobs', body);
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
  static Future<Map<String, dynamic>> cancelJob(String id, {String? reason}) async {
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

  /// Job-takers near `(lat,lng)` within `radiusKm`. Returns name, photo,
  /// rating, distance source data, skills, etc.
  static Future<List<Map<String, dynamic>>> nearbyWorkers({
    double? lat,
    double? lng,
    double radiusKm = 5,
    int limit = 20,
  }) async {
    final query = <String, dynamic>{
      'limit': limit,
      'radiusKm': radiusKm,
    };
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
