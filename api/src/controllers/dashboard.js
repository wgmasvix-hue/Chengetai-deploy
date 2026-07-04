const system = require('../services/system');
const deployments = require('../services/deployments');

async function stats(req, res) {
  const deployed = deployments.list();
  res.json(await system.stats(deployed.length));
}

module.exports = { stats };
