// Fleet control plane — the brain behind "managed deployments".
//
// Every deployment enrolls with a one-time enrollment token and receives a
// long-lived agent token. From then on the agent heartbeats; on each beat
// the control plane hands back the deployment's license state and any
// queued commands. Operators drive the fleet from the dashboard: queue
// start/stop/restart/update/backup, or revoke a deployment's license
// (Model A kill switch — services stop, data is preserved).
//
// Secrets rule: enrollment and agent tokens are shown exactly once, at
// creation, and stored only as SHA-256 hashes.
const crypto = require('crypto');
const repo = require('../repositories');
const config = require('../config');
const { hashToken } = require('../middleware/agentAuth');

// Commands an operator may push to an agent. Deliberately excludes
// `remove`: a kill switch must never destroy an institution's data, so
// deregistration is a separate, explicit control-plane action and is never
// queued as a remote command.
const REMOTE_COMMANDS = new Set([
  'start',
  'stop',
  'restart',
  'update',
  'backup',
  'restore',
  'status',
  'logs',
]);

function newToken(prefix) {
  return `${prefix}_${crypto.randomBytes(24).toString('base64url')}`;
}

function now() {
  return new Date().toISOString();
}

// ── Enrollment tokens ───────────────────────────────────────────────────
async function issueEnrollmentToken({ label, ttlMinutes, singleUse = true, createdBy }) {
  const token = newToken('enr');
  const ttl = Number(ttlMinutes) || config.fleet.enrollmentTokenTtlMinutes;
  const record = {
    id: crypto.randomUUID(),
    tokenHash: hashToken(token),
    label: label || '',
    singleUse: singleUse !== false,
    createdBy: createdBy || null,
    createdAt: now(),
    expiresAt: new Date(Date.now() + ttl * 60 * 1000).toISOString(),
    usedByAgentId: null,
    usedAt: null,
  };
  await repo.enrollmentTokens.insert(record);
  // The plaintext token is returned once and never persisted.
  return { token, record: sanitizeToken(record) };
}

async function listEnrollmentTokens() {
  const rows = await repo.enrollmentTokens.all();
  return rows.map(sanitizeToken);
}

function sanitizeToken(t) {
  const { tokenHash, ...rest } = t;
  const expired = new Date(t.expiresAt).getTime() < Date.now();
  return { ...rest, status: t.usedByAgentId ? 'used' : expired ? 'expired' : 'active' };
}

// ── Enrollment ──────────────────────────────────────────────────────────
async function enroll({ enrollmentToken, name, platform, hostname, publicIp, version }) {
  if (!enrollmentToken) {
    const err = new Error('enrollmentToken is required');
    err.status = 400;
    throw err;
  }
  const tokenRecord = await repo.enrollmentTokens.findBy('tokenHash', hashToken(enrollmentToken));
  if (!tokenRecord) {
    const err = new Error('Invalid enrollment token');
    err.status = 401;
    throw err;
  }
  if (new Date(tokenRecord.expiresAt).getTime() < Date.now()) {
    const err = new Error('Enrollment token has expired');
    err.status = 401;
    throw err;
  }
  if (tokenRecord.singleUse && tokenRecord.usedByAgentId) {
    const err = new Error('Enrollment token has already been used');
    err.status = 409;
    throw err;
  }

  const agentToken = newToken('agt');
  const agent = {
    id: crypto.randomUUID(),
    name: name || hostname || 'unnamed',
    platform: platform || 'unknown',
    hostname: hostname || null,
    publicIp: publicIp || null,
    version: version || null,
    agentTokenHash: hashToken(agentToken),
    enrollmentTokenId: tokenRecord.id,
    license: 'active', // active | revoked
    licenseReason: null,
    enrolledAt: now(),
    lastHeartbeat: null,
    lastStatus: null,
    revokedAt: null,
  };
  await repo.fleetAgents.insert(agent);

  if (tokenRecord.singleUse) {
    await repo.enrollmentTokens.update(tokenRecord.id, {
      usedByAgentId: agent.id,
      usedAt: now(),
    });
  }

  return {
    agentId: agent.id,
    agentToken, // shown once
    heartbeatSeconds: config.fleet.heartbeatSeconds,
    license: agent.license,
  };
}

// ── Heartbeat ───────────────────────────────────────────────────────────
// Records the agent's health and returns license + pending commands. The
// returned commands are marked "sent" so they are handed out once.
async function heartbeat(agent, { health, deployments } = {}) {
  await repo.fleetAgents.update(agent.id, {
    lastHeartbeat: now(),
    lastStatus: { health: health || null, deployments: deployments || null, at: now() },
  });

  const pending = (await repo.fleetCommands.filter('agentId', agent.id)).filter(
    (c) => c.status === 'pending'
  );
  const handed = [];
  for (const cmd of pending) {
    await repo.fleetCommands.update(cmd.id, { status: 'sent', sentAt: now() });
    handed.push({ id: cmd.id, command: cmd.command, args: cmd.args || [] });
  }

  return {
    license: agent.license,
    licenseReason: agent.licenseReason,
    heartbeatSeconds: config.fleet.heartbeatSeconds,
    commands: handed,
  };
}

async function reportResult(agent, commandId, { status, output }) {
  const cmd = await repo.fleetCommands.findBy('id', commandId);
  if (!cmd || cmd.agentId !== agent.id) {
    const err = new Error('Command not found for this agent');
    err.status = 404;
    throw err;
  }
  const final = status === 'done' ? 'done' : 'failed';
  return sanitizeCommand(
    await repo.fleetCommands.update(commandId, {
      status: final,
      output: typeof output === 'string' ? output.slice(0, 20000) : null,
      finishedAt: now(),
    })
  );
}

// ── Operator actions ────────────────────────────────────────────────────
async function queueCommand(agentId, { command, args = [], createdBy }) {
  const agent = await repo.fleetAgents.findBy('id', agentId);
  if (!agent) {
    const err = new Error('Agent not found');
    err.status = 404;
    throw err;
  }
  if (!REMOTE_COMMANDS.has(command)) {
    const err = new Error(
      `Unsupported command '${command}'. Allowed: ${[...REMOTE_COMMANDS].join(', ')}`
    );
    err.status = 400;
    throw err;
  }
  const record = {
    id: crypto.randomUUID(),
    agentId,
    command,
    args: Array.isArray(args) ? args.map(String) : [],
    status: 'pending', // pending | sent | done | failed
    createdBy: createdBy || null,
    createdAt: now(),
    sentAt: null,
    finishedAt: null,
    output: null,
  };
  await repo.fleetCommands.insert(record);
  return sanitizeCommand(record);
}

async function listCommands(agentId) {
  const rows = await repo.fleetCommands.filter('agentId', agentId);
  return rows.map(sanitizeCommand).sort((a, b) => (a.createdAt < b.createdAt ? 1 : -1));
}

// Revoke a deployment's license: the kill switch. Services stop on the next
// heartbeat (a stop command is queued) but no data is ever deleted, so the
// deployment can be reactivated later intact.
async function revoke(agentId, { reason, by } = {}) {
  const agent = await repo.fleetAgents.findBy('id', agentId);
  if (!agent) {
    const err = new Error('Agent not found');
    err.status = 404;
    throw err;
  }
  const updated = await repo.fleetAgents.update(agentId, {
    license: 'revoked',
    licenseReason: reason || 'Revoked by operator',
    revokedAt: now(),
  });
  // Queue a stop so the site goes dark promptly; data volumes are preserved.
  await queueCommand(agentId, { command: 'stop', createdBy: by || null });
  return sanitizeAgent(updated);
}

async function reactivate(agentId, { by } = {}) {
  const agent = await repo.fleetAgents.findBy('id', agentId);
  if (!agent) {
    const err = new Error('Agent not found');
    err.status = 404;
    throw err;
  }
  const updated = await repo.fleetAgents.update(agentId, {
    license: 'active',
    licenseReason: null,
    revokedAt: null,
  });
  await queueCommand(agentId, { command: 'start', createdBy: by || null });
  return sanitizeAgent(updated);
}

// Remove an agent from the fleet (control-plane record only). This does not
// touch the remote server or its data — it just stops managing it.
async function deregister(agentId) {
  const agent = await repo.fleetAgents.findBy('id', agentId);
  if (!agent) return false;
  const cmds = await repo.fleetCommands.filter('agentId', agentId);
  for (const c of cmds) await repo.fleetCommands.remove(c.id);
  return repo.fleetAgents.remove(agentId);
}

async function listAgents() {
  const rows = await repo.fleetAgents.all();
  return rows.map(sanitizeAgent);
}

async function getAgent(id) {
  const agent = await repo.fleetAgents.findBy('id', id);
  return agent ? sanitizeAgent(agent) : null;
}

function sanitizeAgent(a) {
  if (!a) return a;
  const { agentTokenHash, ...rest } = a;
  const last = a.lastHeartbeat ? new Date(a.lastHeartbeat).getTime() : 0;
  const online = last > 0 && Date.now() - last < config.fleet.offlineAfterSeconds * 1000;
  return { ...rest, connectivity: online ? 'online' : 'offline' };
}

function sanitizeCommand(c) {
  return c;
}

module.exports = {
  REMOTE_COMMANDS,
  issueEnrollmentToken,
  listEnrollmentTokens,
  enroll,
  heartbeat,
  reportResult,
  queueCommand,
  listCommands,
  revoke,
  reactivate,
  deregister,
  listAgents,
  getAgent,
};
