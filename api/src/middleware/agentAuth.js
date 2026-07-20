// Authenticates a fleet agent by its agent token. Agents are servers, not
// people, so they never carry a JWT — they present the opaque token issued
// at enrollment, which we store only as a SHA-256 hash. On success
// req.agent is the enrolled deployment record.
const crypto = require('crypto');
const repo = require('../repositories');

function hashToken(token) {
  return crypto.createHash('sha256').update(String(token)).digest('hex');
}

async function authenticateAgent(req, res, next) {
  const header = req.headers.authorization || '';
  const token =
    req.headers['x-agent-token'] ||
    (header.startsWith('Bearer ') ? header.slice(7) : null);

  if (!token) {
    return res.status(401).json({ error: 'Agent token required' });
  }

  try {
    const agent = await repo.fleetAgents.findBy('agentTokenHash', hashToken(token));
    if (!agent) {
      return res.status(401).json({ error: 'Unknown or revoked agent token' });
    }
    req.agent = agent;
    return next();
  } catch (err) {
    return next(err);
  }
}

module.exports = { authenticateAgent, hashToken };
