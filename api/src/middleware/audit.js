const crypto = require('crypto');
const repos = require('../repositories');

// Records every mutating request (who, what, when, from where) after the
// response is finished, so auditing never blocks or fails a request.
function audit(req, res, next) {
  if (!['POST', 'PUT', 'PATCH', 'DELETE'].includes(req.method)) return next();

  res.on('finish', () => {
    const entry = {
      id: crypto.randomUUID(),
      at: new Date().toISOString(),
      user: req.user ? req.user.email : 'anonymous',
      method: req.method,
      path: req.originalUrl,
      status: res.statusCode,
      ip: req.ip,
    };
    repos.auditLogs.insert(entry).catch(() => {
      /* auditing must never take the API down */
    });
  });

  return next();
}

module.exports = audit;
