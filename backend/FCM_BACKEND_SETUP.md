# Backend FCM Push Setup

This wires the **backend** to send Firebase Cloud Messaging push notifications, so users receive alerts even when the app is closed or the device is offline-then-online.

## How the chat → push flow works now

```
┌─────────┐    1. Firestore add(message)       ┌───────────┐
│ Mobile  │ ──────────────────────────────────▶│ Firestore │
│ Sender  │                                     └─────┬─────┘
│         │                                           │ 2. realtime
│         │    3. POST /api/chat/notify               ▼
│         │ ──────────────────────────────────▶┌──────────────┐
└─────────┘     {recipientUserId, body…}       │   Receiver   │
                                                │   (in app)   │
            ┌─────────────────┐                 └──────────────┘
            │ Backend uses    │
            │ firebase-admin  │
            │  → FCM push     │
            └────────┬────────┘
                     │ 4. push (works when app is closed)
                     ▼
            ┌──────────────────┐
            │  Recipient phone │
            │  (system tray)   │
            └──────────────────┘
```

The same `pushToUser()` helper that already powers in-app notifications now also fires FCM, so **every** notification path (job interest, OTPs, payment release, etc.) will deliver as a push to the receiver — not just chat.

## Step 1 — Generate a service account key

1. Open https://console.firebase.google.com → your project (`pargig`)
2. Click **gear ⚙️ → Project settings**
3. Click the **Service accounts** tab (top)
4. Choose **Node.js** as the language (just affects the snippet shown — we'll use the JSON file directly)
5. Click **Generate new private key** → **Generate key**
6. A JSON file downloads (something like `pargig-firebase-adminsdk-xxxx.json`)

## Step 2 — Drop the key into the backend

Rename and move the downloaded file to:
```
e:\node\pargig\backend\firebase-service-account.json
```

That's it. The path is in `.gitignore` so it won't be committed.

If you'd rather keep it elsewhere, set in `backend\.env`:
```
FIREBASE_SERVICE_ACCOUNT_PATH=C:\path\to\my-key.json
```
or paste the entire JSON as one line in:
```
FIREBASE_SERVICE_ACCOUNT_JSON={"type":"service_account",...}
```
(useful for hosting platforms like Heroku / Render that don't have file storage)

## Step 3 — Restart backend

If you're running with `npm run dev` (nodemon), it reloads automatically. Otherwise:
```
npm start
```

You should see in logs:
```
Firebase Admin initialized for project pargig-xxxxx
```

If you see errors like `Failed to parse private key`, re-download the key — the file might have been corrupted in transit.

## Step 4 — Verify push delivery

1. **Get a fresh FCM token** — Open the app, log in. The mobile code now auto-registers the token via `PUT /api/users/me/fcm` on login. Check the user document in MongoDB; it should have a `fcmToken` field.

2. **Test from cURL** (replace `<jwt>` with any logged-in user's JWT, `<recipientId>` with their MongoDB `_id`):
   ```bash
   curl -X POST http://localhost:5014/api/chat/notify \
     -H "Authorization: Bearer <jwt>" \
     -H "Content-Type: application/json" \
     -d '{"recipientUserId":"<recipientId>","body":"Test from backend!","jobTitle":"Test"}'
   ```
   The recipient's phone should immediately receive a push notification.

3. **End-to-end** — On phone A (logged in as Suresh), send a chat message. Phone B (logged in as Rohan, app closed) should get a system-tray push within ~1 second. Tapping it opens that chat.

## What works after setup

| Scenario | Delivery |
| --- | --- |
| Receiver in same chat room | Realtime via Firestore stream |
| Receiver on another screen in app | Orange in-app banner (Firestore listener) + FCM push (if both fire, banner shows once) |
| Receiver in app but backgrounded | FCM tray notification + foreground handler in `main.dart` |
| Receiver app fully closed / phone locked | FCM tray notification — tap to open the chat |
| Other notifications (job interest, payment release, etc.) | All routed through `pushToUser()`, so they also become FCM pushes |

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| `FCM push failed: Firebase Admin not configured` in backend logs | Service account file missing or path wrong. Check `backend/firebase-service-account.json` exists. |
| Push works for in-app but not when app is closed | Android: ensure `google-services.json` is in `mobile/android/app/` and the Google Services Gradle plugin is applied (already done in `FIREBASE_SETUP.md`). iOS: needs an APNs key uploaded to Firebase Console → Cloud Messaging tab. |
| User has no `fcmToken` in DB | They must open the app at least once after login; the token registers on login + on token refresh. Make sure mobile build includes the firebase setup. |
| `messaging/registration-token-not-registered` | The token expired (uninstall, fresh install, etc.). Backend auto-clears stale tokens — next login on a real device re-registers. |
| Multiple devices per user | Currently we store only one `fcmToken` per user. To support multi-device, change the field to `fcmTokens: [String]` and adjust `sendPushToUserId`. |
