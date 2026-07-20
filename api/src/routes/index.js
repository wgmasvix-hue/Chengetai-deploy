const express = require('express');
const rateLimit = require('express-rate-limit');

const { authenticate, requireRole } = require('../middleware/auth');
const { authenticateAgent } = require('../middleware/agentAuth');
const validate = require('../middleware/validate');
const audit = require('../middleware/audit');
const auth = require('../controllers/auth');
const dashboard = require('../controllers/dashboard');
const servers = require('../controllers/servers');
const deployments = require('../controllers/deployments');
const jobsCtrl = require('../controllers/jobs');
const users = require('../controllers/users');
const fleet = require('../controllers/fleet');
const pluginsService = require('../services/plugins');
const pkg = require('../../package.json');

const router = express.Router();

// ── Public ────────────────────────────────────────────────────────────────
router.get('/health', (req, res) => {
  res.json({ status: 'ok', version: pkg.version, uptime: process.uptime() });
});

const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many login attempts — try again later' },
});

router.post(
  '/auth/login',
  loginLimiter,
  validate({
    email: { required: true, type: 'email', maxLength: 200 },
    password: { required: true, type: 'string', maxLength: 200 },
  }),
  auth.login
);

// ── Fleet agents (agent-token auth, not JWT) ───────────────────────────────
// Servers enroll and then heartbeat here. These sit before the JWT gate
// because agents authenticate with their own token, not a user session.
const enrollLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 60,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many enrollment attempts — try again later' },
});
router.post(
  '/fleet/enroll',
  enrollLimiter,
  validate({
    enrollmentToken: { required: true, type: 'string', maxLength: 200 },
    name: { type: 'string', maxLength: 100 },
    platform: { type: 'string', maxLength: 40 },
    hostname: { type: 'string', maxLength: 200 },
    publicIp: { type: 'string', maxLength: 60 },
    version: { type: 'string', maxLength: 40 },
  }),
  fleet.enroll
);
router.post('/fleet/heartbeat', authenticateAgent, fleet.heartbeat);
router.post('/fleet/commands/:id/result', authenticateAgent, fleet.commandResult);

// ── Authenticated ─────────────────────────────────────────────────────────
router.use(authenticate, audit);

router.get('/auth/me', auth.me);
router.post(
  '/auth/change-password',
  validate({
    currentPassword: { required: true, type: 'string', maxLength: 200 },
    newPassword: { required: true, type: 'string', maxLength: 200 },
  }),
  auth.changePassword
);

router.get('/dashboard', dashboard.stats);

router.get('/plugins', (req, res) => res.json(pluginsService.list()));

// ── Deployments (Task 5 lifecycle, driven through the CLI) ─────────────────
router.get('/deployments', deployments.list);
router.post(
  '/deployments',
  requireRole('engineer'),
  validate({
    name: { required: true, type: 'string', maxLength: 100 },
    platform: { type: 'string', maxLength: 40 },
    institution: { type: 'string', maxLength: 200 },
    repository: { type: 'string', maxLength: 200 },
    adminEmail: { type: 'email', maxLength: 200 },
    uiPort: { type: 'port' },
    restPort: { type: 'port' },
  }),
  deployments.create
);
router.get('/deployments/:name/status', deployments.status);
router.post('/deployments/:name/actions/:action', requireRole('engineer'), deployments.action);
router.post('/deployments/:name/manager', requireRole('engineer'), deployments.manager);
router.delete('/deployments/:name', requireRole('admin'), deployments.remove);

// ── Jobs (progress of long-running CLI operations) ─────────────────────────
router.get('/jobs', jobsCtrl.list);
router.get('/jobs/:id', jobsCtrl.get);

// ── Servers (Task 6) ───────────────────────────────────────────────────────
router.get('/servers', servers.list);
router.post(
  '/servers',
  requireRole('engineer'),
  validate({
    name: { required: true, type: 'string', maxLength: 100 },
    host: { required: true, type: 'string', maxLength: 200 },
    port: { type: 'port' },
    username: { required: true, type: 'string', maxLength: 100 },
    authMethod: { enum: ['ssh-key', 'password'] },
  }),
  servers.create
);
router.patch('/servers/:id', requireRole('engineer'), servers.update);
router.delete('/servers/:id', requireRole('admin'), servers.remove);

// ── Users (RBAC administration) ────────────────────────────────────────────
router.get('/users', requireRole('admin'), users.list);
router.post(
  '/users',
  requireRole('admin'),
  validate({
    email: { required: true, type: 'email', maxLength: 200 },
    password: { required: true, type: 'string', maxLength: 200 },
    role: { enum: ['viewer', 'engineer', 'admin'] },
  }),
  users.create
);
router.patch('/users/:id', requireRole('admin'), users.update);
router.delete('/users/:id', requireRole('admin'), users.remove);

// ── Fleet control plane (operators) ────────────────────────────────────────
// Managed deployments: issue enrollment tokens, view the fleet, push
// commands, and revoke/reactivate a deployment's license (Model A kill
// switch — stops services, preserves data).
router.get('/fleet/agents', fleet.listAgents);
router.get('/fleet/agents/:id', fleet.getAgent);
router.get('/fleet/agents/:id/commands', fleet.listCommands);
router.post(
  '/fleet/agents/:id/commands',
  requireRole('engineer'),
  validate({
    command: { required: true, type: 'string', maxLength: 40 },
  }),
  fleet.queueCommand
);
router.post('/fleet/agents/:id/revoke', requireRole('admin'), fleet.revoke);
router.post('/fleet/agents/:id/reactivate', requireRole('admin'), fleet.reactivate);
router.delete('/fleet/agents/:id', requireRole('admin'), fleet.deregister);

router.get('/fleet/enrollment-tokens', requireRole('engineer'), fleet.listTokens);
router.post(
  '/fleet/enrollment-tokens',
  requireRole('engineer'),
  validate({
    label: { type: 'string', maxLength: 100 },
    ttlMinutes: { type: 'number' },
  }),
  fleet.issueToken
);

module.exports = router;
