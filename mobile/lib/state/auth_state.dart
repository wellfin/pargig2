import 'package:flutter/foundation.dart';
import '../api/api_client.dart';

class AuthState extends ChangeNotifier {
  Map<String, dynamic>? user;
  String? pendingMobile;
  bool restoring = true;

  bool get isAuthed => ApiClient.token != null && user != null;

  Future<void> tryRestore() async {
    final token = await ApiClient.loadToken();
    if (token != null) {
      try {
        user = await ApiClient.get('/users/me');
      } catch (_) {
        await ApiClient.setToken(null);
      }
    }
    restoring = false;
    notifyListeners();
  }

  Future<String?> requestOtp(String mobile) async {
    final res = await ApiClient.post('/auth/otp/request', {'mobile': mobile});
    pendingMobile = mobile;
    notifyListeners();
    return res['devOtp'];
  }

  Future<void> verifyOtp(String otp) async {
    final res = await ApiClient.post('/auth/otp/verify', {
      'mobile': pendingMobile,
      'otp': otp,
    });
    await ApiClient.setToken(res['token']);
    user = res['user'];
    notifyListeners();
  }

  Future<void> updateProfile(Map<String, dynamic> patch) async {
    user = await ApiClient.put('/users/me', patch);
    notifyListeners();
  }

  Future<String?> uploadPhoto(String filePath) async {
    final res = await ApiClient.postFile(
      '/users/me/photo',
      field: 'photo',
      filePath: filePath,
    );
    if (res is Map && res['user'] is Map) {
      user = Map<String, dynamic>.from(res['user'] as Map);
      notifyListeners();
    }
    return res is Map ? res['photo'] as String? : null;
  }

  Future<void> updateLocation(
    double lat,
    double lng, {
    String? address,
    String? city,
    String? state,
    String? pincode,
  }) async {
    user = await ApiClient.put('/users/me/location', {
      'lat': lat,
      'lng': lng,
      'address': ?address,
      'city': ?city,
      'state': ?state,
      'pincode': ?pincode,
    });
    notifyListeners();
  }

  Future<void> acceptTerms() async {
    final res = await ApiClient.post('/users/me/accept-terms', {});
    if (res is Map && res['user'] is Map) {
      user = Map<String, dynamic>.from(res['user'] as Map);
      notifyListeners();
    }
  }

  Future<void> switchRole(String role) async {
    user = await ApiClient.put('/users/me/role', {'role': role});
    notifyListeners();
  }

  Future<void> refreshMe() async {
    user = await ApiClient.get('/users/me');
    notifyListeners();
  }

  Future<void> logout() async {
    await ApiClient.setToken(null);
    user = null;
    notifyListeners();
  }

  String get activeRole => (user?['activeRole'] ?? 'jobgiver') as String;
  bool get isJobGiver => activeRole == 'jobgiver';

  /// Returns the route the user should land on after auth restore or OTP
  /// verify. Walks the setup checklist and points to the first missing step.
  /// Returns `/home` once everything required is done.
  ///
  /// Required for everyone:
  ///   - acceptedTermsAt
  ///   - name
  ///   - location.coordinates != [0, 0]
  /// Required only for job takers:
  ///   - skills (non-empty list)
  ///   - yearsOfExperience
  String resumeRoute() {
    final u = user;
    if (u == null) return '/login';
    final acceptedTerms = (u['acceptedTermsAt'] ?? '').toString().isNotEmpty;
    if (!acceptedTerms) return '/terms';
    final name = (u['name'] ?? '').toString().trim();
    if (name.isEmpty) return '/onboarding';
    final loc = u['location'] is Map ? u['location'] as Map : const {};
    final coords = loc['coordinates'];
    var hasLocation = false;
    if (coords is List && coords.length == 2) {
      final lng = (coords[0] as num?)?.toDouble() ?? 0;
      final lat = (coords[1] as num?)?.toDouble() ?? 0;
      hasLocation = lat != 0 || lng != 0;
    }
    if (!hasLocation) return '/profile-setup/address';
    if (activeRole == 'jobtaker') {
      final skills = u['skills'];
      final yoe = (u['yearsOfExperience'] ?? '').toString().trim();
      if (skills is! List || skills.isEmpty || yoe.isEmpty) {
        return '/profile-setup/skills';
      }
    }
    return '/home';
  }
}
