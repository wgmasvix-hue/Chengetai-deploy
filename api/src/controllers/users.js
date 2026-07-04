const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const repos = require('../repositories');

const ROLES = ['viewer', 'engineer', 'admin'];

function publicUser(u) {
  return { id: u.id, email: u.email, role: u.role, createdAt: u.createdAt };
}

async function list(req, res) {
  const users = await repos.users.all();
  res.json(users.map(publicUser));
}

async function create(req, res) {
  const { email, password, role = 'viewer' } = req.body;
  if (!ROLES.includes(role)) {
    return res.status(400).json({ error: `role must be one of: ${ROLES.join(', ')}` });
  }
  if (await repos.users.findBy('email', email)) {
    return res.status(409).json({ error: 'A user with that email already exists' });
  }
  const user = {
    id: crypto.randomUUID(),
    email,
    passwordHash: bcrypt.hashSync(password, 10),
    role,
    createdAt: new Date().toISOString(),
  };
  await repos.users.insert(user);
  res.status(201).json(publicUser(user));
}

async function update(req, res) {
  const patch = {};
  if (req.body.role !== undefined) {
    if (!ROLES.includes(req.body.role)) {
      return res.status(400).json({ error: `role must be one of: ${ROLES.join(', ')}` });
    }
    patch.role = req.body.role;
  }
  if (req.body.password) {
    patch.passwordHash = bcrypt.hashSync(req.body.password, 10);
  }
  const user = await repos.users.update(req.params.id, patch);
  if (!user) return res.status(404).json({ error: 'User not found' });
  return res.json(publicUser(user));
}

async function remove(req, res) {
  // Guard against deleting the last admin — that would lock everyone out.
  const users = await repos.users.all();
  const target = users.find((u) => u.id === req.params.id);
  if (!target) return res.status(404).json({ error: 'User not found' });
  if (target.role === 'admin' && users.filter((u) => u.role === 'admin').length === 1) {
    return res.status(409).json({ error: 'Cannot remove the last admin' });
  }
  await repos.users.remove(req.params.id);
  return res.status(204).end();
}

module.exports = { list, create, update, remove };
