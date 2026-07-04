// API integration tests: boots the real app on an ephemeral port with an
// isolated data directory and exercises auth, RBAC, validation and the
// live endpoints over HTTP. Run: npm test
const { test, before, after } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'chengetai-api-test-'));
process.env.ADMIN_EMAIL = 'admin@test.local';
process.env.ADMIN_PASSWORD = 'test-password-123';
process.env.NODE_ENV = 'test';

const { createApp } = require('../src/app');
const { seedAdmin } = require('../src/controllers/auth');

let server;
let base;
let token;

before(async () => {
  await seedAdmin();
  const app = createApp();
  await new Promise((resolve) => {
    server = app.listen(0, () => resolve());
  });
  base = `http://127.0.0.1:${server.address().port}`;
});

after(() => {
  server.close();
  fs.rmSync(process.env.DATA_DIR, { recursive: true, force: true });
});

async function api(method, url, body, auth = true) {
  const res = await fetch(base + url, {
    method,
    headers: {
      'content-type': 'application/json',
      ...(auth && token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  let json = null;
  try {
    json = await res.json();
  } catch {
    /* 204 etc. */
  }
  return { status: res.status, json };
}

test('health endpoint is public', async () => {
  const { status, json } = await api('GET', '/api/health', null, false);
  assert.equal(status, 200);
  assert.equal(json.status, 'ok');
  assert.ok(json.version);
});

test('protected endpoints reject anonymous requests', async () => {
  const { status } = await api('GET', '/api/dashboard', null, false);
  assert.equal(status, 401);
});

test('login rejects bad credentials', async () => {
  const { status } = await api('POST', '/api/auth/login', {
    email: 'admin@test.local',
    password: 'wrong',
  }, false);
  assert.equal(status, 401);
});

test('login validates input', async () => {
  const { status, json } = await api('POST', '/api/auth/login', { email: 'not-an-email' }, false);
  assert.equal(status, 400);
  assert.ok(json.details.length >= 1);
});

test('login succeeds and returns a token', async () => {
  const { status, json } = await api('POST', '/api/auth/login', {
    email: 'admin@test.local',
    password: 'test-password-123',
  }, false);
  assert.equal(status, 200);
  assert.ok(json.token);
  assert.equal(json.user.role, 'admin');
  token = json.token;
});

test('dashboard returns real system stats', async () => {
  const { status, json } = await api('GET', '/api/dashboard');
  assert.equal(status, 200);
  assert.ok(typeof json.cpu === 'number' && json.cpu >= 0 && json.cpu <= 100);
  assert.ok(typeof json.memory === 'number' && json.memory > 0);
  assert.ok(json.uptime.length > 0);
});

test('plugins catalogue lists dspace as available', async () => {
  const { status, json } = await api('GET', '/api/plugins');
  assert.equal(status, 200);
  const dspace = json.find((p) => p.name === 'dspace');
  assert.ok(dspace);
  assert.equal(dspace.status, 'available');
});

test('server CRUD with validation and audit', async () => {
  const bad = await api('POST', '/api/servers', { name: 'x' });
  assert.equal(bad.status, 400);

  const created = await api('POST', '/api/servers', {
    name: 'campus-1',
    host: '10.0.0.10',
    port: 22,
    username: 'deploy',
    authMethod: 'ssh-key',
  });
  assert.equal(created.status, 201);

  const list = await api('GET', '/api/servers');
  assert.equal(list.json.length, 1);

  const patched = await api('PATCH', `/api/servers/${created.json.id}`, { group: 'harare' });
  assert.equal(patched.json.group, 'harare');

  const removed = await api('DELETE', `/api/servers/${created.json.id}`);
  assert.equal(removed.status, 204);
});

test('viewer role is denied mutations (RBAC)', async () => {
  const repos = require('../src/repositories');
  const bcrypt = require('bcryptjs');
  await repos.users.insert({
    id: 'viewer-1',
    email: 'viewer@test.local',
    passwordHash: bcrypt.hashSync('viewer-pass-123', 10),
    role: 'viewer',
  });
  const login = await api('POST', '/api/auth/login', {
    email: 'viewer@test.local',
    password: 'viewer-pass-123',
  }, false);
  const viewerToken = login.json.token;

  const res = await fetch(`${base}/api/servers`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${viewerToken}`,
    },
    body: JSON.stringify({ name: 'x', host: 'h', username: 'u' }),
  });
  assert.equal(res.status, 403);
});

test('mutations are audit-logged', async () => {
  const repos = require('../src/repositories');
  // give the fire-and-forget audit writes a moment
  await new Promise((r) => setTimeout(r, 100));
  const logs = await repos.auditLogs.all();
  assert.ok(logs.length >= 2);
  assert.ok(logs.every((l) => l.user && l.method && l.path));
});

test('admin can manage users; last admin is protected', async () => {
  const created = await api('POST', '/api/users', {
    email: 'neweng@test.local',
    password: 'engineer-pass-1',
    role: 'engineer',
  });
  assert.equal(created.status, 201);
  assert.equal(created.json.role, 'engineer');
  assert.equal(created.json.passwordHash, undefined); // never leak the hash

  const listed = await api('GET', '/api/users');
  assert.ok(listed.json.length >= 2);

  const promoted = await api('PATCH', `/api/users/${created.json.id}`, { role: 'viewer' });
  assert.equal(promoted.json.role, 'viewer');

  const removed = await api('DELETE', `/api/users/${created.json.id}`);
  assert.equal(removed.status, 204);

  // Only one admin exists (the seeded one) — deleting it must be refused.
  const admins = (await api('GET', '/api/users')).json.filter((u) => u.role === 'admin');
  const lastAdmin = await api('DELETE', `/api/users/${admins[0].id}`);
  assert.equal(lastAdmin.status, 409);
});

test('deployment creation validates the name', async () => {
  const bad = await api('POST', '/api/deployments', { name: 'Bad Name!' });
  assert.equal(bad.status, 400);
});

test('jobs endpoint is reachable', async () => {
  const { status, json } = await api('GET', '/api/jobs');
  assert.equal(status, 200);
  assert.ok(Array.isArray(json));
});

test('users endpoints require admin role', async () => {
  const repos = require('../src/repositories');
  const bcrypt = require('bcryptjs');
  await repos.users.insert({
    id: 'eng-rbac',
    email: 'eng-rbac@test.local',
    passwordHash: bcrypt.hashSync('eng-rbac-pass', 10),
    role: 'engineer',
  });
  const login = await api('POST', '/api/auth/login', {
    email: 'eng-rbac@test.local', password: 'eng-rbac-pass',
  }, false);
  const res = await fetch(`${base}/api/users`, {
    headers: { authorization: `Bearer ${login.json.token}` },
  });
  assert.equal(res.status, 403);
});
