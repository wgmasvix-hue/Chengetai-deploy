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

  // Fleet control plane (managed deployments). How often agents should
  // check in, and how long an agent may keep serving after losing contact
  // before it treats itself as unmanaged. Model A: a running site keeps
  // serving through short control-plane outages; only an explicit revoke
  // stops it.
  fleet: {
    heartbeatSeconds: Number(process.env.FLEET_HEARTBEAT_SECONDS || 60),
    // Agents that miss heartbeats for longer than this are shown "offline".
    offlineAfterSeconds: Number(process.env.FLEET_OFFLINE_AFTER_SECONDS || 180),
    // Default lifetime of an enrollment token (minutes) before it expires.
    enrollmentTokenTtlMinutes: Number(process.env.FLEET_ENROLL_TTL_MINUTES || 1440),
  },
};
