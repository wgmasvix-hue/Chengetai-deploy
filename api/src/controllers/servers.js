const crypto = require('crypto');
const repos = require('../repositories');

async function list(req, res) {
  res.json(await repos.servers.all());
}

async function create(req, res) {
  const { name, host, port, username, authMethod, os: serverOs, group } = req.body;
  const server = {
    id: crypto.randomUUID(),
    name,
    host,
    port: port || 22,
    username,
    authMethod: authMethod || 'ssh-key',
    os: serverOs || '',
    group: group || 'default',
    status: 'unknown',
    createdAt: new Date().toISOString(),
    createdBy: req.user.email,
  };
  await repos.servers.insert(server);
  res.status(201).json(server);
}

async function update(req, res) {
  const allowed = ['name', 'host', 'port', 'username', 'authMethod', 'os', 'group', 'status'];
  const patch = {};
  for (const k of allowed) if (req.body[k] !== undefined) patch[k] = req.body[k];
  const server = await repos.servers.update(req.params.id, patch);
  if (!server) return res.status(404).json({ error: 'Server not found' });
  return res.json(server);
}

async function remove(req, res) {
  const removed = await repos.servers.remove(req.params.id);
  if (!removed) return res.status(404).json({ error: 'Server not found' });
  return res.status(204).end();
}

module.exports = { list, create, update, remove };
