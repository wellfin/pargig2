const notFound = (req, res, next) => {
  const error = new Error(`Not Found - ${req.originalUrl}`);
  res.status(404);
  next(error);
};

const errorHandler = (err, req, res, next) => {
  const statusCode = res.statusCode === 200 ? 500 : res.statusCode;

  // The stack goes to the server log, never to the client.
  //
  // It used to be sent in the response body unless NODE_ENV was
  // 'production', which meant any box where that variable was simply
  // unset — the live server among them — handed every caller absolute
  // paths like /home/ubuntu/pargig2/backend/..., the dependency layout
  // and the internal call chain. A client has no use for a stack in any
  // environment, so there is no environment where sending it is right;
  // tying it to a variable that is easy to forget just made the leak
  // silent. Logged here instead, where `pm2 logs` can read it.
  //
  // 5xx only: a 401 or a 409 is the API working as designed, and
  // logging a stack for each one buries the real failures.
  if (statusCode >= 500) {
    console.error(`[${req.method} ${req.originalUrl}] ${err.stack || err.message}`);
  }

  res.status(statusCode).json({
    message: err.message,
    // Carried through when a handler attaches it: the start PIN refused
    // before its scheduled time sends the time back so the app can say
    // exactly when to try again instead of repeating a generic message.
    scheduledAt: err.scheduledAt
  });
};

module.exports = { notFound, errorHandler };
