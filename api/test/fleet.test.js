// Fleet control-plane integration tests: boots the real app on an ephemeral
// port with an isolated data dir and drives the full managed-deployment
// lifecycle over HTTP — enroll, heartbeat, command dispatch, result
// reporting, and the revoke/reactivate kill switch.
const { test, before, after } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'chengetai-fleet-test-'));
process.env.ADMIN_EMAIL = 'admin@test.local';
process.env.ADMIN_PASSWORD = 'test-password-123';
process.env.NODE_ENV = 'test';

const { createApp } = require('../src/app');
const { seedAdmin } = require('../src/controllers/auth');

let server;
let base;
let token; // operator JWT

before(async () => {
  await seedAdmin();
  const app = createApp();
  await new Promise((resolve) => {
    server = app.listen(0, () => resolve());
  });
  base = `http://127.0.0.1:${server.address().port}`;

  const res = await fetch(`${base}/api/auth/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: 'admin@test.local', password: 'test-password-123' }),
  });
  token = (await res.json()).token;
});

after(() => {
  server.close();
  fs.rmSync(process.env.DATA_DIR, { recursive: true, force: true });
});

function op(method, url, body) {
  return fetch(base + url, {
    method,
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${token}`,
    },
    body: body ? JSON.stringify(body) : undefined,
  });
}

function agent(method, url, agentToken, body) {
  return fetch(base + url, {
    method,
    headers: {
      'content-type': 'application/json',
      'x-agent-token': agentToken,
    },
    body: body ? JSON.stringify(body) : undefined,
  });
}

// Shared state across the ordered lifecycle tests.
const ctx = {};

test('operator issues a single-use enrollment token', async () => {
  const res = await op('POST', '/api/fleet/enrollment-tokens', { label: 'byo-poly' });
  assert.equal(res.status, 201);
  const body = await res.json();
  assert.match(body.token, /^enr_/);
  assert.equal(body.record.status, 'active');
  ctx.enrollmentToken = body.token;
});

test('agent enrolls and receives an agent token', async () => {
  const res = await fetch(`${base}/api/fleet/enroll`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      enrollmentToken: ctx.enrollmentToken,
      name: 'byo-poly',
      platform: 'dspace',
      hostname: 'byopoly.example',
      publicIp: '41.79.191.226',
      version: '2.3.0',
    }),
  });
  assert.equal(res.status, 201);
  const body = await res.json();
  assert.match(body.agentToken, /^agt_/);
  assert.ok(body.agentId);
  assert.equal(body.license, 'active');
  ctx.agentToken = body.agentToken;
  ctx.agentId = body.agentId;
});

test('a single-use enrollment token cannot be reused', async () => {
  const res = await fetch(`${base}/api/fleet/enroll`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ enrollmentToken: ctx.enrollmentToken, name: 'dupe' }),
  });
  assert.equal(res.status, 409);
});

test('enrolling with a bad token is rejected', async () => {
  const res = await fetch(`${base}/api/fleet/enroll`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ enrollmentToken: 'enr_nope', name: 'x' }),
  });
  assert.equal(res.status, 401);
});

test('heartbeat without an agent token is rejected', async () => {
  const res = await fetch(`${base}/api/fleet/heartbeat`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({}),
  });
  assert.equal(res.status, 401);
});

test('agent heartbeat returns active license and no commands', async () => {
  const res = await agent('POST', '/api/fleet/heartbeat', ctx.agentToken, {
    health: { cpu: 3, memory: '1.7/15GB' },
    deployments: [{ name: 'byo-poly', status: 'running' }],
  });
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.license, 'active');
  assert.deepEqual(body.commands, []);
});

test('operator can list the fleet without leaking the token hash', async () => {
  const res = await op('GET', '/api/fleet/agents');
  assert.equal(res.status, 200);
  const agents = await res.json();
  assert.equal(agents.length, 1);
  assert.equal(agents[0].id, ctx.agentId);
  assert.equal(agents[0].connectivity, 'online');
  assert.ok(!('agentTokenHash' in agents[0]));
});

test('operator queues a command and the agent receives it on heartbeat', async () => {
  const q = await op('POST', `/api/fleet/agents/${ctx.agentId}/commands`, {
    command: 'restart',
  });
  assert.equal(q.status, 201);
  const cmd = await q.json();
  assert.equal(cmd.status, 'pending');
  ctx.commandId = cmd.id;

  const hb = await agent('POST', '/api/fleet/heartbeat', ctx.agentToken, {});
  const body = await hb.json();
  assert.equal(body.commands.length, 1);
  assert.equal(body.commands[0].command, 'restart');
  assert.equal(body.commands[0].id, ctx.commandId);
});

test('a delivered command is not handed out again', async () => {
  const hb = await agent('POST', '/api/fleet/heartbeat', ctx.agentToken, {});
  const body = await hb.json();
  assert.deepEqual(body.commands, []);
});

test('agent reports a command result', async () => {
  const res = await agent(
    'POST',
    `/api/fleet/commands/${ctx.commandId}/result`,
    ctx.agentToken,
    { status: 'done', output: 'Services restarted.' }
  );
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.status, 'done');
});

test('unsupported commands are rejected', async () => {
  const res = await op('POST', `/api/fleet/agents/${ctx.agentId}/commands`, {
    command: 'remove',
  });
  assert.equal(res.status, 400);
});

test('revoke stops the deployment (queues stop) and flips the license', async () => {
  const res = await op('POST', `/api/fleet/agents/${ctx.agentId}/revoke`, {
    reason: 'unpaid',
  });
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.license, 'revoked');

  const hb = await agent('POST', '/api/fleet/heartbeat', ctx.agentToken, {});
  const beat = await hb.json();
  assert.equal(beat.license, 'revoked');
  assert.ok(beat.commands.some((c) => c.command === 'stop'));
});

test('reactivate restores the license and queues start', async () => {
  const res = await op('POST', `/api/fleet/agents/${ctx.agentId}/reactivate`, {});
  assert.equal(res.status, 200);
  assert.equal((await res.json()).license, 'active');

  const hb = await agent('POST', '/api/fleet/heartbeat', ctx.agentToken, {});
  const beat = await hb.json();
  assert.equal(beat.license, 'active');
  assert.ok(beat.commands.some((c) => c.command === 'start'));
});

test('a viewer cannot revoke (RBAC)', async () => {
  // Create a viewer and confirm the kill switch is admin-only.
  await op('POST', '/api/users', {
    email: 'viewer@test.local',
    password: 'viewer-pass-123',
    role: 'viewer',
  });
  const login = await fetch(`${base}/api/auth/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: 'viewer@test.local', password: 'viewer-pass-123' }),
  });
  const viewerToken = (await login.json()).token;
  const res = await fetch(`${base}/api/fleet/agents/${ctx.agentId}/revoke`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${viewerToken}` },
    body: JSON.stringify({}),
  });
  assert.equal(res.status, 403);
});

test('deregister removes the agent from the fleet', async () => {
  const res = await op('DELETE', `/api/fleet/agents/${ctx.agentId}`);
  assert.equal(res.status, 204);
  const list = await op('GET', '/api/fleet/agents');
  assert.equal((await list.json()).length, 0);
});
