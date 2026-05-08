const jwt = require('jsonwebtoken');

const generateToken = (id, kind = 'user') =>
  jwt.sign({ id, kind }, process.env.JWT_SECRET, {
    expiresIn: process.env.JWT_EXPIRES_IN || '30d'
  });

module.exports = generateToken;
