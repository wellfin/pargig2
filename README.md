# Pargig

Gig-economy marketplace platform — Job Givers post tasks, Job Takers (nearby workers / professionals) bid, accept, work and get paid through escrow. The codebase has three deployable units:

| Layer | Stack | Path | Purpose |
| --- | --- | --- | --- |
| Backend API | Node.js + Express 5 + MongoDB + Socket.IO | `backend/` | REST + realtime chat, OTP auth, payments, admin |
| Admin Panel | React 19 + Vite + react-router-dom | `frontend/` | Web admin UI for users, jobs, payments, disputes |
| Mobile App | Flutter (Android + iOS) | `mobile/` | Customer-facing app for both roles |

The 10 functional modules from the spec — User Profile, Job Posting, Job Discovery, Chat & Negotiation, Job Management (OTP start/complete), Payment, Ratings, Notifications, Disputes, Admin Panel — are mapped to API routes under `backend/routes/`.

---

## 1. Backend

### Prerequisites
- Node.js 18+
- MongoDB (local or Atlas — `.env` already points to Atlas)

### Setup
```bash
cd backend
npm install          # already done — only run if node_modules deleted
# .env already exists with MONGO_URI, JWT_SECRET, etc.
npm run dev          # nodemon, hot-reload
# or: npm start
```

Server listens on `http://localhost:5014`.

### First-time admin
```bash
# creates a default super-admin (email: admin@pargig.com / password: admin@123)
curl http://localhost:5014/api/admin/seed
```

### API surface (high level)

| Group | Endpoint | Notes |
| --- | --- | --- |
| Auth | `POST /api/auth/otp/request` | Request OTP for a mobile number |
| Auth | `POST /api/auth/otp/verify` | Exchange OTP for JWT |
| Auth | `POST /api/auth/admin/login` | Email + password login for admin |
| User | `GET /api/users/me` / `PUT /api/users/me` | Profile R/W |
| User | `PUT /api/users/me/role` | Switch active role (jobgiver / jobtaker) |
| User | `POST /api/users/me/document` | Multipart upload of verification doc |
| Job | `POST /api/jobs` | Create job (giver) |
| Job | `GET /api/jobs/browse?lat&lng&radiusKm&q` | Geo + keyword feed |
| Job | `POST /api/jobs/:id/interest` | Apply (taker) — enforces wallet/free-job rules |
| Job | `POST /api/jobs/:id/confirm` | Hire selected jobtaker (giver) |
| Job | `POST /api/jobs/:id/reach` | Worker arrived → start OTP issued to giver |
| Job | `POST /api/jobs/:id/start/verify` | Worker enters OTP → status `in_progress` |
| Job | `POST /api/jobs/:id/complete` | Worker marks complete → completion OTP to giver |
| Job | `POST /api/jobs/:id/complete/verify` | Giver verifies OTP → status `completed` |
| Chat | `POST /api/chat/job/:jobId/open` | Open / get room with the other party |
| Chat | `POST /api/chat/rooms/:roomId/messages` | Send message (also broadcast on socket) |
| Payment | `POST /api/payments/initiate` | Create gateway order shell |
| Payment | `POST /api/payments/confirm` | Webhook-style confirm → escrow hold |
| Payment | `POST /api/payments/:id/release` | Release escrow after job completion |
| Rating | `POST /api/ratings` | Mutual rating (1–5 + review) |
| Dispute | `POST /api/disputes` | Either party raises dispute |
| Notif | `GET /api/notifications` | List + unread count |
| Admin | `GET /api/admin/dashboard` | Counts + revenue |
| Admin | `GET/PUT /api/admin/users` | List, block/unblock |
| Admin | `POST /api/admin/users/document/verify` | Approve / reject KYC |
| Admin | `GET/PUT /api/admin/disputes` | Resolve disputes (refund / release / split) |

### Realtime (Socket.IO)
- Connect with JWT in `auth.token`
- Auto-joins `user:<userId>` room → notifications pushed there as `notification` events
- Chat: `emit('chat:join', roomId)` then listen for `chat:message`

### Business rules implemented
- Two roles (`jobgiver`, `jobtaker`) — switchable
- Doc verification with admin approval → `verified` badge
- First job under ₹1000 free; jobs 1–3 require ₹20 wallet deposit
- OTP-based job start AND completion (separate codes)
- Escrow: payment held → released only after completion OTP verified
- Platform fee: ₹10 or 5% of amount, whichever is higher (skipped while `freeJobsRemaining > 0`)

---

## 2. Admin Panel (`frontend/`)

```bash
cd frontend
npm install        # already done
npm run dev        # http://localhost:5173/admin
# build: npm run build → backend serves it at /admin
```

Login at `/admin/login` with `admin@pargig.com / admin@123` (after running `/api/admin/seed`).

Pages:
- **Dashboard** — counts + platform revenue
- **Users** — search, view docs, approve/reject KYC, block/unblock
- **Jobs** — filter by status across all states
- **Payments** — escrow status, refund button
- **Disputes** — resolve with outcome (refund_giver / release_taker / split / no_action)
- **Reports** — totals + funds in escrow

Vite is configured to proxy `/api` and `/socket.io` to the backend during dev, and `base: '/admin/'` so the production build is served at `${API}/admin` by Express.

---

## 3. Mobile App (`mobile/`)

Flutter app for **Android + iOS**, packaged from one Dart codebase.

### Setup
```bash
cd mobile
flutter pub get
flutter run -d <device>           # Android emulator or iOS sim
# point to a remote backend:
flutter run --dart-define=API_BASE=https://api.pargig.example
```

> Default `API_BASE` is `http://10.0.2.2:5014` — Android emulator's loopback to host. For iOS sim use `--dart-define=API_BASE=http://127.0.0.1:5014`. For physical devices, use your LAN IP.

### Screens delivered
| Screen | Route | Module |
| --- | --- | --- |
| Splash | `/` | — |
| Mobile login | `/login` | User Profile (1.1) |
| OTP verify | `/otp` | User Profile (1.1) |
| Role select | `/role` | User Profile (1.1) |
| Home (feed / my jobs) | `/home` | Job Discovery (1.3) / Job Posting (1.2) |
| Post job | `/post-job` | Job Posting (1.2) |
| Job detail (with full lifecycle: interest → hire → reach → start OTP → complete → completion OTP) | `/job` | Job Posting + Discovery + Job Mgmt (1.5) |
| Chat list | `/chats` | Chat (1.4) |
| Chat room | `/chat-room` | Chat (1.4) — uses Socket.IO |
| Profile | `/profile` | User Profile (1.1) |
| Wallet | `/wallet` | Payment (1.6) |

### Where to extend
- **Ratings UI** — call `POST /api/ratings` after a job completes (backend ready)
- **Disputes UI** — call `POST /api/disputes` from job detail when status is past `confirmed`
- **Push notifications** — register FCM token via `PUT /api/users/me/fcm`, then handle `notification` socket events in `chat_room_screen.dart` pattern
- **Real payment gateway** — replace `payments/initiate` shell with Razorpay / Stripe SDK

---

## Project layout

```
pargig/
├── backend/                  # Node/Express API
│   ├── config/db.js
│   ├── controllers/          # auth, user, job, chat, payment, rating, dispute, notification, admin
│   ├── middleware/           # auth, error, upload
│   ├── models/               # 10 Mongoose models
│   ├── routes/               # one router file per module
│   ├── utils/                # generateToken, otp, feeCalculator, notify
│   ├── uploads/              # multer storage (gitignore in prod)
│   ├── app.js                # Express wiring + admin static serve
│   └── server.js             # HTTP + Socket.IO bootstrap
├── frontend/                 # React admin panel
│   └── src/
│       ├── App.jsx           # routes
│       ├── api.js            # axios + token interceptor
│       └── pages/            # Login, Layout, Dashboard, Users, Jobs, Payments, Disputes, Reports
├── mobile/                   # Flutter app (android + ios)
│   ├── pubspec.yaml
│   └── lib/
│       ├── main.dart         # MaterialApp + routes
│       ├── config.dart       # API_BASE, theme colors
│       ├── api/api_client.dart
│       ├── state/            # AuthState, JobState (provider)
│       └── screens/          # 12 screens
└── README.md                 # this file
```

## Roadmap (not in this scaffold yet)

- Real SMS gateway (Twilio / MSG91) wired into `authController.requestOtp`
- Razorpay Orders API + signature verification in `paymentController`
- Firebase Cloud Messaging for push (token already stored on user)
- File uploads to S3 / Cloudinary instead of local `uploads/`
- Pagination + infinite scroll on mobile feed
- Map view for jobs & "live ETA" for the worker reaching the location
- Multi-language (Hindi + English) — `intl` already in pubspec
- Background isolate for socket.io reconnect on Android
