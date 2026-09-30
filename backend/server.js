const dotenv = require('dotenv');
dotenv.config();

const http = require('http');
const { Server } = require('socket.io');
const jwt = require('jsonwebtoken');

const app = require('./app');
const connectDB = require('./config/db');

connectDB();

const PORT = process.env.PORT || 5014;
const server = http.createServer(app);

const io = new Server(server, {
  cors: { origin: '*' }
});

// auth middleware for sockets - allow JWT in handshake
io.use((socket, next) => {
  const token = socket.handshake.auth?.token || socket.handshake.query?.token;
  if (!token) return next(); // allow anonymous, but features will be limited
  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    socket.userId = decoded.id;
    socket.kind = decoded.kind;
  } catch (e) {
    // ignore — keep anonymous
  }
  next();
});

io.on('connection', (socket) => {
  if (socket.userId) socket.join(`user:${socket.userId}`);

  socket.on('chat:join', (roomId) => socket.join(`room:${roomId}`));
  socket.on('chat:leave', (roomId) => socket.leave(`room:${roomId}`));
  socket.on('chat:typing', ({ roomId, isTyping }) =>
    socket.to(`room:${roomId}`).emit('chat:typing', { userId: socket.userId, isTyping })
  );
});

global._io = io;


server.listen(PORT, '0.0.0.0', () => {
  console.log(`Server (HTTP + Socket.IO) running on port ${PORT}`);
  // Say which storage uploads will use. Silent disk fallback after a
  // deploy that was meant to switch to S3 is otherwise only noticed when
  // the files vanish with the instance.
  const s3 = require('./config/s3');
  console.log(
    s3.isEnabled
      ? `Uploads -> S3 bucket "${s3.bucket}" (${s3.region}) via ${s3.publicBase}`
      : 'Uploads -> local disk ./uploads (set AWS_S3_BUCKET, AWS_REGION, ' +
        'AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY to use S3)'
  );
});