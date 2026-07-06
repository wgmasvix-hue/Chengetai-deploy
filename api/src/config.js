const path = require('path');
const fs = require('fs');
const crypto = require('crypto');

const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, '..', 'data');
fs.mkdirSync(DATA_DIR, { recursive: true });

// The JWT secret survives restarts: env var wins, otherwise one is
// generated once and kept in the data directory (never in git).
function loadJwtSecret() {
  if (process.env.JWT_SECRET) return process.env.JWT_SECRET;
  const file = path.join(DATA_DIR, 'jwt-secret');
  if (!fs.existsSync(file)) {
    fs.writeFileSync(file, crypto.randomBytes(48).toString('hex'), { mode: 0o600 });
  }
  return fs.readFileSync(file, 'utf8').trim();
}

module.exports = {
  port: Number(process.env.PORT || 3000),
  dataDir: DATA_DIR,
  jwtSecret: loadJwtSecret(),
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || '12h',
  databaseUrl: process.env.DATABASE_URL || '',
  corsOrigin: process.env.CORS_ORIGIN ? process.env.CORS_ORIGIN.split(',') : true,
  // Where the CLI keeps deployment profiles on this server.
  deploymentsDir:
    process.env.CHENGETAI_DEPLOYMENTS_DIR ||
    '/opt/chengetai-deploy/deployments',
  templatesDir:
    process.env.CHENGETAI_TEMPLATES_DIR ||
    path.join(__dirname, '..', '..', 'templates'),
  adminEmail: process.env.ADMIN_EMAIL || 'admin@chengetai.local',
  adminPassword: process.env.ADMIN_PASSWORD || '',
};
