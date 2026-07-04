const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const repos = require('../repositories');
const config = require('../config');
const { sign } = require('../middleware/auth');

// Ensures an admin account exists on first boot. Password comes from
// ADMIN_PASSWORD, or is generated and printed exactly once.
async function seedAdmin() {
  const users = await repos.users.all();
  if (users.length > 0) return;

  const password = config.adminPassword || crypto.randomBytes(9).toString('base64url');
  await repos.users.insert({
    id: crypto.randomUUID(),
    email: config.adminEmail,
    passwordHash: bcrypt.hashSync(password, 10),
    role: 'admin',
    createdAt: new Date().toISOString(),
  });
  if (!config.adminPassword) {
    console.log('──────────────────────────────────────────────────');
    console.log(` Initial admin account: ${config.adminEmail}`);
    console.log(` Initial admin password: ${password}`);
    console.log(' (change it after first login; set ADMIN_PASSWORD to seed your own)');
    console.log('──────────────────────────────────────────────────');
  }
}

async function login(req, res) {
  const { email, password } = req.body;
  const user = await repos.users.findBy('email', email);
  if (!user || !bcrypt.compareSync(password, user.passwordHash)) {
    return res.status(401).json({ error: 'Invalid email or password' });
  }
  return res.json({
    token: sign(user),
    user: { id: user.id, email: user.email, role: user.role },
  });
}

async function me(req, res) {
  res.json({ user: req.user });
}

async function changePassword(req, res) {
  const { currentPassword, newPassword } = req.body;
  const user = await repos.users.findBy('email', req.user.email);
  if (!user || !bcrypt.compareSync(currentPassword, user.passwordHash)) {
    return res.status(401).json({ error: 'Current password is incorrect' });
  }
  await repos.users.update(user.id, { passwordHash: bcrypt.hashSync(newPassword, 10) });
  return res.json({ ok: true });
}

module.exports = { seedAdmin, login, me, changePassword };
