/**
 * Firebase Admin SDK bootstrap.
 *
 * Service-account credentials are loaded from one of (in order):
 *   1. process.env.FIREBASE_SERVICE_ACCOUNT_JSON  — the raw JSON string (good for hosting platforms)
 *   2. process.env.FIREBASE_SERVICE_ACCOUNT_PATH  — absolute path to a JSON file
 *   3. ./firebase-service-account.json (relative to backend root)
 *
 * If none are found, the export is null and FCM-dependent endpoints
 * return a clear error instead of crashing the whole server.
 */
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

let app = null;

function loadCreds() {
  if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
    try {
      return JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
    } catch (e) {
      console.warn('FIREBASE_SERVICE_ACCOUNT_JSON not valid JSON:', e.message);
    }
  }
  const candidate = process.env.FIREBASE_SERVICE_ACCOUNT_PATH ||
    path.join(__dirname, '..', 'firebase-service-account.json');
  if (fs.existsSync(candidate)) {
    return JSON.parse(fs.readFileSync(candidate, 'utf8'));
  }
  return null;
}

function getAdmin() {
  if (app) return admin;
  const creds = loadCreds();
  if (!creds) return null;
  app = admin.initializeApp({
    credential: admin.credential.cert(creds),
    projectId: creds.project_id
  });
  console.log(`Firebase Admin initialized for project ${creds.project_id}`);
  return admin;
}

async function sendPushToToken(token, { title, body, data }) {
  const a = getAdmin();
  if (!a) throw new Error('Firebase Admin not configured (missing service account)');
  if (!token) throw new Error('No FCM token for recipient');
  return a.messaging().send({
    token,
    notification: { title, body },
    data: data ? Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])) : {},
    android: { priority: 'high' },
    apns: { headers: { 'apns-priority': '10' } }
  });
}

async function sendPushToUserId(userId, payload) {
  const User = require('../models/userModel');
  const user = await User.findById(userId).select('fcmToken');
  if (!user || !user.fcmToken) {
    return { skipped: true, reason: 'no fcm token' };
  }
  try {
    const messageId = await sendPushToToken(user.fcmToken, payload);
    return { sent: true, messageId };
  } catch (e) {
    // If token is invalid (registration-token-not-registered), clear it
    if (e.code === 'messaging/registration-token-not-registered') {
      await User.findByIdAndUpdate(userId, { $unset: { fcmToken: 1 } });
    }
    return { sent: false, error: e.message };
  }
}

module.exports = { getAdmin, sendPushToToken, sendPushToUserId };
