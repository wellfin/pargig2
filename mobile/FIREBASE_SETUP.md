# Firebase Setup for Pargig (chat + push)

The mobile app uses **Cloud Firestore** for chat (realtime, offline, scales for free) and **Firebase Auth (anonymous)** so Firestore security rules can require authenticated callers. This is a **one-time** setup per Firebase project.

Until you complete the steps below, the app still runs — but tapping "Open chat" will show **"Chat unavailable. Did you set up Firebase?"**. Everything else (login, jobs, payments) works without Firebase.

---

## 1. Create the Firebase project (once)

1. Go to https://console.firebase.google.com → **Add project** → name it `pargig` (or whatever you like)
2. Disable Google Analytics if you want — not required
3. In the project, **Build → Authentication → Get started → Sign-in method → enable "Anonymous"**
4. **Build → Firestore Database → Create database → Start in production mode → choose region (e.g. asia-south1)**
5. In **Firestore → Rules**, paste this and **Publish**:
   ```
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /chats/{roomId} {
         allow read, write: if request.auth != null
                            && request.auth.uid != null;
         match /messages/{messageId} {
           allow read, write: if request.auth != null
                              && request.auth.uid != null;
         }
       }
     }
   }
   ```
   (For tighter rules later, validate that the writer's app-side userId is in the room's `participants`. For dev, the rule above is fine.)

## 2. Add the Android app

1. In Firebase Console → **Project settings (⚙) → Your apps → Add app → Android**
2. Android package name: **`com.pargig.app`** (must match exactly — that's the org we used in `flutter create`)
3. Skip the SHA-1 (not needed for anon auth / Firestore)
4. **Download `google-services.json`** and copy it to:
   ```
   e:\node\pargig\mobile\android\app\google-services.json
   ```
5. Open `mobile\android\settings.gradle.kts` and ensure the Google services plugin is declared. Add this line inside the `plugins { ... }` block (alongside the existing `dev.flutter.flutter-plugin-loader` etc.):
   ```kotlin
   id("com.google.gms.google-services") version "4.4.2" apply false
   ```
6. Open `mobile\android\app\build.gradle.kts` and add to the `plugins { ... }` block at the top:
   ```kotlin
   id("com.google.gms.google-services")
   ```
7. Make sure `minSdk` is at least 23 in `mobile\android\app\build.gradle.kts`:
   ```kotlin
   defaultConfig {
       minSdk = 23
       …
   }
   ```

## 3. Add the iOS app (skip if you only need Android)

1. Firebase Console → **Add app → iOS**
2. Bundle ID: **`com.pargig.app`**
3. **Download `GoogleService-Info.plist`** → drag into Xcode under `Runner/Runner` (check "Copy items if needed", "Add to targets: Runner")
4. In `mobile/ios/Runner/AppDelegate.swift` add `import Firebase` and `FirebaseApp.configure()` at the top of `application(_:didFinishLaunchingWithOptions:)`
5. iOS deployment target ≥ 13.0 in `Podfile`

## 4. Run

```bash
cd e:\node\pargig\mobile
flutter clean
flutter pub get
flutter run --dart-define=API_BASE=http://192.168.1.11:5014
```

You should see in logs: `Firebase init skipped: ...` go away. The first chat will create the document in Firestore — open the Firebase console → Firestore → you'll see a `chats/job_<id>_<userA>_<userB>` document with a `messages` subcollection.

---

## How chat now works in the app

| Action | What happens |
| --- | --- |
| Job giver taps **chat** on an applicant | App computes deterministic `roomId = job_<jobId>_<sortedUserIds>`, creates the Firestore doc with both names, opens room |
| Either party sends a message | Written to `chats/{roomId}/messages` with server timestamp |
| Other side receives | Firestore stream pushes the new message instantly (offline → syncs on reconnect) |
| Chat list (`/chats`) | Streams `chats` where `participants` array contains current user, sorted by `lastMessageAt` |
| Identity | App-side identity is your backend Mongo `_id` (stored in message docs as `sender`). Firebase anonymous auth is only used to satisfy security rules. |

Backend Mongo chat routes (`/api/chat/...`) still exist — useful for admin / dispute review. The mobile app no longer uses them; you can keep, ignore, or remove them later.

---

## Push notifications (next)

The app already has `firebase_messaging` in pubspec. To wire push:

1. In Firebase Console → **Cloud Messaging** is on by default
2. In Flutter, after login: `final fcm = await FirebaseMessaging.instance.getToken();` and `PUT /api/users/me/fcm` with `{ fcmToken: fcm }` (route already exists)
3. Server-side: install `firebase-admin` in `backend/` and replace the in-app `_io.emit('notification')` with `admin.messaging().send({ token, notification })` for offline delivery

Code stub for the mobile side (drop in `main.dart` after auth):
```dart
final token = await FirebaseMessaging.instance.getToken();
if (token != null && ApiClient.token != null) {
  await ApiClient.put('/users/me/fcm', { 'fcmToken': token });
}
FirebaseMessaging.onMessage.listen((msg) {
  // show in-app banner; Firestore listener already updates the screen
});
```
