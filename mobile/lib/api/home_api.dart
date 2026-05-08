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
    final res = await ApiClient.post('/jobs/$id/cancel', {
      'reason': ?reason,
    });
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
    final res = await ApiClient.post('/jobs/$jobId/confirm', {
      'jobtakerId': jobtakerId,
      'finalPrice': ?finalPrice,
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
