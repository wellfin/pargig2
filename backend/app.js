const express = require('express');
const cors = require('cors');
const path = require('path');

const { notFound, errorHandler } = require('./middleware/errorMiddleware');

const app = express();

app.use(cors());
app.use(express.json({ limit: '5mb' }));
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
app.use('/api/disputes', require('./routes/disputeRoutes'));
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

// also keep legacy backend/dist if present
app.use(express.static(path.join(__dirname, 'dist')));
app.get('/', (req, res) => {
  res.send(`<!doctype html><html><body style="font-family:sans-serif;padding:40px">
  <h1>Pargig API</h1>
  <p>API: <a href="/api">/api</a> · Admin Panel: <a href="/admin">/admin</a></p>
  </body></html>`);
});

app.use(notFound);
app.use(errorHandler);

module.exports = app;
