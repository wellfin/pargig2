const express = require('express');
const cors = require('cors');
const path = require('path');

const { notFound, errorHandler } = require('./middleware/errorMiddleware');

const app = express();

app.use(cors());
// The raw body is kept alongside the parsed one: gateway webhooks are
// signed over the exact bytes sent, so re-serialising the parsed object
// would change key order or spacing and fail every signature check.
app.use(express.json({
  limit: '5mb',
  verify: (req, _res, buf) => { req.rawBody = buf; }
}));
app.use(express.urlencoded({ extended: true }));

app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

app.get('/api', (req, res) => {
  res.json({ message: 'Pargig API is running', version: '1.0.0' });
});

// Lightweight discovery probe used by the mobile app to auto-detect the
// backend host on the LAN. Must stay public, fast, and identifiable so
// scanning clients can be sure they reached *our* server.
app.get('/api/health', (req, res) => {
  res.json({ ok: true, app: 'pargig', version: '1.0.0' });
});

app.use('/api/auth', require('./routes/authRoutes'));
app.use('/api/users', require('./routes/userRoutes'));
app.use('/api/jobs', require('./routes/jobRoutes'));
app.use('/api/chat', require('./routes/chatRoutes'));
app.use('/api/payments', require('./routes/paymentRoutes'));
app.use('/api/ratings', require('./routes/ratingRoutes'));
app.use('/api/issues', require('./routes/issueRoutes'));
app.use('/api/notifications', require('./routes/notificationRoutes'));
app.use('/api/admin', require('./routes/adminRoutes'));

// serve admin frontend build (frontend/dist) at /admin
const adminDist = path.join(__dirname, '..', 'frontend', 'dist');
app.use('/admin', express.static(adminDist));
app.get(/^\/admin(\/.*)?$/, (req, res, next) => {
  res.sendFile(path.join(adminDist, 'index.html'), (err) => {
    if (err) next();
  });
});

// Admin panel build copied into backend/dist and served at the site root.
app.use(express.static(path.join(__dirname, 'dist')));
app.get('/', (req, res) => {
  res.send(`<!doctype html><html><body style="font-family:sans-serif;padding:40px">
  <h1>Pargig API</h1>
  <p>API: <a href="/api">/api</a> · Admin Panel: <a href="/admin">/admin</a></p>
  </body></html>`);
});

// SPA fallback for that build. The admin uses BrowserRouter, so a full
// page load on /users — a refresh, a bookmark, or the 401 handler's
// location.assign('/login') — arrives here as a real HTTP request with no
// file behind it. Without this it 404s, which is what the panel does
// today whenever a session expires.
//
// /api and /uploads are excluded deliberately: those must keep returning
// a real 404 (JSON / missing file) so the mobile app and fetch() callers
// get an error instead of a page of HTML. Non-GET verbs never reach here.
// If dist/index.html is absent (API-only deploy), sendFile errors and we
// fall through to the normal 404.
const spaIndex = path.join(__dirname, 'dist', 'index.html');
app.get(/^\/(?!api(?:\/|$)|uploads(?:\/|$)).*/, (req, res, next) => {
  // Anything that looks like a file must 404 rather than be handed
  // index.html. dist/ filenames are content-hashed, so a browser holding
  // a cached page asks for /assets/index-OLD.js after a redeploy; getting
  // HTML back fails as 'MIME type text/html' with a blank screen, while a
  // clean 404 makes the stale-cache cause obvious.
  if (path.extname(req.path)) return next();
  res.sendFile(spaIndex, (err) => {
    if (err) next();
  });
});

app.use(notFound);
app.use(errorHandler);

module.exports = app;
