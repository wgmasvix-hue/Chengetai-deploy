// HTTP surface for the fleet control plane. Two audiences:
//   • agents  — enroll, heartbeat, report command results (agent-token auth)
//   • operators — issue tokens, list the fleet, queue commands, revoke
//     (JWT + RBAC, wired in routes/index.js)
const fleet = require('../services/fleet');

// ── Agent-facing ─────────────────────────────────────────────────────────
async function enroll(req, res, next) {
  try {
    const result = await fleet.enroll(req.body || {});
    res.status(201).json(result);
  } catch (err) {
    if (err.status) return res.status(err.status).json({ error: err.message });
    return next(err);
  }
}

async function heartbeat(req, res, next) {
  try {
    res.json(await fleet.heartbeat(req.agent, req.body || {}));
  } catch (err) {
    next(err);
  }
}

async function commandResult(req, res, next) {
  try {
    const updated = await fleet.reportResult(req.agent, req.params.id, req.body || {});
    res.json(updated);
  } catch (err) {
    if (err.status) return res.status(err.status).json({ error: err.message });
    return next(err);
  }
}

// ── Operator-facing ────────────────────────────────────────────────────────
async function issueToken(req, res, next) {
  try {
    const { label, ttlMinutes, singleUse } = req.body || {};
    const result = await fleet.issueEnrollmentToken({
      label,
      ttlMinutes,
      singleUse,
      createdBy: req.user && req.user.email,
    });
    res.status(201).json(result);
  } catch (err) {
    next(err);
  }
}

async function listTokens(req, res, next) {
  try {
    res.json(await fleet.listEnrollmentTokens());
  } catch (err) {
    next(err);
  }
}

async function listAgents(req, res, next) {
  try {
    res.json(await fleet.listAgents());
  } catch (err) {
    next(err);
  }
}

async function getAgent(req, res, next) {
  try {
    const agent = await fleet.getAgent(req.params.id);
    if (!agent) return res.status(404).json({ error: 'Agent not found' });
    return res.json(agent);
  } catch (err) {
    return next(err);
  }
}

async function listCommands(req, res, next) {
  try {
    res.json(await fleet.listCommands(req.params.id));
  } catch (err) {
    next(err);
  }
}

async function queueCommand(req, res, next) {
  try {
    const { command, args } = req.body || {};
    const cmd = await fleet.queueCommand(req.params.id, {
      command,
      args,
      createdBy: req.user && req.user.email,
    });
    res.status(201).json(cmd);
  } catch (err) {
    if (err.status) return res.status(err.status).json({ error: err.message });
    return next(err);
  }
}

async function revoke(req, res, next) {
  try {
    const agent = await fleet.revoke(req.params.id, {
      reason: (req.body || {}).reason,
      by: req.user && req.user.email,
    });
    res.json(agent);
  } catch (err) {
    if (err.status) return res.status(err.status).json({ error: err.message });
    return next(err);
  }
}

async function reactivate(req, res, next) {
  try {
    const agent = await fleet.reactivate(req.params.id, { by: req.user && req.user.email });
    res.json(agent);
  } catch (err) {
    if (err.status) return res.status(err.status).json({ error: err.message });
    return next(err);
  }
}

async function deregister(req, res, next) {
  try {
    const ok = await fleet.deregister(req.params.id);
    if (!ok) return res.status(404).json({ error: 'Agent not found' });
    return res.status(204).end();
  } catch (err) {
    return next(err);
  }
}

module.exports = {
  enroll,
  heartbeat,
  commandResult,
  issueToken,
  listTokens,
  listAgents,
  getAgent,
  listCommands,
  queueCommand,
  revoke,
  reactivate,
  deregister,
};
