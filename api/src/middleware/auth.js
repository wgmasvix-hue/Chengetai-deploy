const jwt = require('jsonwebtoken');
const config = require('../config');

// Verifies the Bearer token and attaches req.user = { id, email, role }.
function authenticate(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) {
    return res.status(401).json({ error: 'Authentication required' });
  }
  try {
    req.user = jwt.verify(token, config.jwtSecret);
    return next();
  } catch {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
}

// Role-based access control. Roles: admin > engineer > viewer.
const RANK = { viewer: 0, engineer: 1, admin: 2 };

function requireRole(minimum) {
  return (req, res, next) => {
    const rank = RANK[req.user && req.user.role];
    if (rank === undefined || rank < RANK[minimum]) {
      return res.status(403).json({ error: `Requires ${minimum} role` });
    }
    return next();
  };
}

function sign(user) {
  return jwt.sign(
    { id: user.id, email: user.email, role: user.role },
    config.jwtSecret,
    { expiresIn: config.jwtExpiresIn }
  );
}

module.exports = { authenticate, requireRole, sign };
