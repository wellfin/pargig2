import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../api/api_client.dart';
import '../config.dart';

class AuthState extends ChangeNotifier {
  Map<String, dynamic>? user;
  String? pendingMobile;
  // Role the user picked on the pre-auth onboarding screen ("Post Job" →
  // jobgiver / "Find Job" → jobtaker). Applied to the user record right
  // after verifyOtp succeeds so the wizard / home opens in the right mode.
  String? pendingRole;
  bool restoring = true;
  // Total unread chat messages addressed to this user across all rooms.
  // Drives the small red dot on the bottom-nav Messages icon. Polled
  // from /chat/unread by the home screen + refreshed after opening
  // any chat room (which marks the room read on the backend).
  int unreadChats = 0;
  // Set of partner userIds that have at least one unread message to
  // this user. Used to badge per-partner chat icons (in-progress card
  // chat button, applicants card, nearby workers etc.) so each chat
  // icon lights up independently when there's something to read.
  Set<String> unreadPartnerIds = const <String>{};
  // Unread in-app notifications (job alerts, new chat messages, payments…)
  // from GET /notifications/unread/count. Drives the numeric badge on the
  // home header bell icon, refreshed live over the socket.
  int unreadNotifications = 0;

  // Home header's "Current Location" / Online toggle. Lives here (not as
  // local State on HomeScreen) so it survives the many flows that rebuild
  // Home from scratch via pushNamedAndRemoveUntil (job accept, rating,
  // profile save, etc.) — those used to silently reset a local bool back
  // to off. Now it only changes when the user flips the switch, or on
  // logout.
  bool isOnline = false;

  // Real-time socket. The backend auto-joins `user:<id>` on connect and
  // emits 'notification' there whenever something is pushed to this user,
  // so the bell count updates the moment a message/alert lands.
  io.Socket? _socket;

  bool get isAuthed => ApiClient.token != null && user != null;

  /// Open the realtime socket (idempotent). Call once the JWT is set.
  void connectRealtime() {
    final token = ApiClient.token;
    if (token == null || _socket != null) return;
    final socket = io.io(
      AppConfig.apiBase,
      io.OptionBuilder()
          // Allow polling fallback so it still connects behind proxies that
          // don't upgrade websockets; the 20s poll is the final fallback.
          .setTransports(['websocket', 'polling'])
          .setAuth({'token': token})
          .enableReconnection()
          .build(),
    );
    socket.onConnect((_) {
      // Sync counts on (re)connect in case events were missed while offline.
      refreshUnreadNotifications();
      refreshUnreadChats();
    });
    socket.on('notification', (_) {
      // Something new landed for this user (chat message, job alert…).
      refreshUnreadNotifications();
      refreshUnreadChats();
    });
    _socket = socket;
  }

  void disconnectRealtime() {
    _socket?.dispose();
    _socket = null;
  }

  /// Re-fetch the unread in-app notification count. Non-fatal on error.
  Future<void> refreshUnreadNotifications() async {
    try {
      final res = await ApiClient.get('/notifications/unread/count');
      final n = (res is Map && res['count'] is num)
          ? (res['count'] as num).toInt()
          : 0;
      if (n != unreadNotifications) {
        unreadNotifications = n;
        notifyListeners();
      }
    } catch (_) {
      // ignore — badge stays at last known value
    }
  }

  void setOnline(bool value) {
    if (isOnline == value) return;
    isOnline = value;
    notifyListeners();
  }

  Future<void> tryRestore() async {
    final token = await ApiClient.loadToken();
    if (token != null) {
      try {
        // Short timeout so a dead/blocked server never hangs the splash.
        user = await ApiClient.get(
          '/users/me',
        ).timeout(const Duration(seconds: 4));
      } catch (_) {
        await ApiClient.setToken(null);
      }
    }
    restoring = false;
    if (isAuthed) connectRealtime();
    notifyListeners();
  }

  Future<String?> requestOtp(String mobile) async {
    // Forward the role the user picked on the onboarding screen so the
    // backend creates the new user record with the correct role from
    // the very first DB write — instead of always defaulting to
    // jobgiver and relying on a second switchRole call post-OTP.
    // pendingRole is left set so verifyOtp's switchRole safety-net
    // still re-applies it if anything went wrong on the create path.
    final body = <String, dynamic>{'mobile': mobile};
    if (pendingRole == 'jobgiver' || pendingRole == 'jobtaker') {
      body['role'] = pendingRole;
    }
    final res = await ApiClient.post('/auth/otp/request', body);
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
    // Apply the role the user picked on the pre-auth onboarding screen,
    // if any. switchRole REPLACES the roles array (see backend), so a
    // jobtaker pick clears the default jobgiver. Failure is non-fatal —
    // the user can flip role later from Profile → Switch Mode.
    if (pendingRole == 'jobgiver' || pendingRole == 'jobtaker') {
      final role = pendingRole!;
      pendingRole = null;
      try {
        await switchRole(role);
      } catch (_) {}
    }
    connectRealtime();
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
    double? lat,
    double? lng, {
    String? address,
    String? city,
    String? state,
    String? pincode,
  }) async {
    final body = <String, dynamic>{};
    if (lat != null && lng != null) {
      body['lat'] = lat;
      body['lng'] = lng;
    }
    if (address != null) {
      body['address'] = address;
    }
    if (city != null) {
      body['city'] = city;
    }
    if (state != null) {
      body['state'] = state;
    }
    if (pincode != null) {
      body['pincode'] = pincode;
    }
    user = await ApiClient.put('/users/me/location', body);
    notifyListeners();
  }

  Future<void> acceptTerms() async {
    final res = await ApiClient.post('/users/me/accept-terms', {});
    if (res is Map && res['user'] is Map) {
      user = Map<String, dynamic>.from(res['user'] as Map);
      notifyListeners();
    }
  }

  Future<void> switchRole(String role, {String? mode}) async {
    // mode is forwarded to the backend:
    //   - omitted / 'replace' → first-time role pick. roles array
    //     becomes [role] only.
    //   - 'add' → Profile "Switch Mode" toggle. backend appends the
    //     role so the user keeps BOTH roles in the array (activeRole
    //     still flips to the new one).
    final body = <String, dynamic>{'role': role};
    if (mode != null) {
      body['mode'] = mode;
    }
    user = await ApiClient.put('/users/me/role', body);
    notifyListeners();
  }

  Future<void> refreshMe() async {
    user = await ApiClient.get('/users/me');
    notifyListeners();
  }

  /// Re-fetch unread-chat count from /chat/unread. Failure is
  /// non-fatal — leaving the old value beats clearing the dot on a
  /// transient network blip.
  Future<void> refreshUnreadChats() async {
    try {
      final res = await ApiClient.get('/chat/unread');
      final n = (res is Map && res['count'] is num)
          ? (res['count'] as num).toInt()
          : 0;
      final partnerList = (res is Map && res['partnerIds'] is List)
          ? (res['partnerIds'] as List).whereType<String>().toSet()
          : const <String>{};
      final changed = n != unreadChats ||
          !_setsEqual(partnerList, unreadPartnerIds);
      if (changed) {
        unreadChats = n;
        unreadPartnerIds = partnerList;
        notifyListeners();
      }
    } catch (_) {
      // ignore — dot stays at last known value
    }
  }

  bool _setsEqual(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final x in a) {
      if (!b.contains(x)) return false;
    }
    return true;
  }

  Future<void> logout() async {
    disconnectRealtime();
    await ApiClient.setToken(null);
    user = null;
    unreadChats = 0;
    unreadPartnerIds = const <String>{};
    unreadNotifications = 0;
    isOnline = false;
    notifyListeners();
  }

  String get activeRole => (user?['activeRole'] ?? 'jobgiver') as String;
  bool get isJobGiver => activeRole == 'jobgiver';

  /// Returns the route the user should land on after auth restore or OTP
  /// verify. Walks the setup checklist and points to the first missing
  /// step. Returns `/home` once everything required is done.
  ///
  /// Required for everyone:
  ///   - acceptedTermsAt
  ///   - name (entered on /profile-setup step 1)
  ///   - location.address (entered on /profile-setup/address — typed text
  ///     is enough; GPS coordinates are a bonus, not a gate)
  /// Required only for job takers:
  ///   - skills (non-empty list)
  ///   - yearsOfExperience
  ///
  /// NOTE: the profile PHOTO is intentionally NOT checked here. Step 1 of
  /// the wizard already blocks "Next" until a photo is uploaded, and it
  /// only saves the name AFTER the photo succeeds — so any user with a
  /// saved name necessarily has a photo. Gating on photo here would also
  /// wrongly bounce EXISTING accounts created before the photo was made
  /// mandatory (they have name + address but no photo) back into setup on
  /// every launch. `name` is the correct "finished step 1" signal.
  String resumeRoute() {
    final u = user;
    if (u == null) return '/login';
    final acceptedTerms = (u['acceptedTermsAt'] ?? '').toString().isNotEmpty;
    if (!acceptedTerms) return '/terms';
    final name = (u['name'] ?? '').toString().trim();
    // The role-pick onboarding is shown pre-auth from the splash; once the
    // user is authed they should never see it again. Jump straight into
    // the wizard's step 1 instead. Role was already applied to the user
    // record from AuthState.pendingRole during verifyOtp.
    if (name.isEmpty) return '/profile-setup';
    final loc = u['location'] is Map ? u['location'] as Map : const {};
    // Use the typed address as the "I have a home address" signal —
    // not the GPS coords. The wizard now allows submitting a typed
    // address without GPS (coords stay at [0,0] in that case), and we
    // don't want those users to be punished by being sent back to the
    // address step on every login.
    final address = (loc['address'] ?? '').toString().trim();
    final city = (loc['city'] ?? '').toString().trim();
    if (address.isEmpty && city.isEmpty) {
      return '/profile-setup/address';
    }
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
