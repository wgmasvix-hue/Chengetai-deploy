const express = require('express');
const rateLimit = require('express-rate-limit');

const { authenticate, requireRole } = require('../middleware/auth');
const validate = require('../middleware/validate');
const audit = require('../middleware/audit');
const auth = require('../controllers/auth');
const dashboard = require('../controllers/dashboard');
const servers = require('../controllers/servers');
const pluginsService = require('../services/plugins');
const deploymentsService = require('../services/deployments');
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
router.get('/deployments', (req, res) => res.json(deploymentsService.list()));

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

module.exports = router;
