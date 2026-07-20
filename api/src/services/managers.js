// Per-deployment local manager UIs, started on demand from the dashboard.
// Each is the standalone `chengetai manager` server (lib/manager/server.js)
// spawned detached; we parse the URL + token it prints, keep a small
// registry, and hand the dashboard a link. Idempotent: a deployment whose
// manager is already alive is reused, not respawned.
const { spawn } = require('child_process');
const net = require('net');
const fs = require('fs');
const path = require('path');
const cli = require('./cli');
const config = require('../config');

const managers = new Map(); // name -> { port, token, pid, startedAt }

function alive(pid) {
  if (!pid) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

// Persisted per-deployment manager settings (written by lib/manager.sh),
// present when a manager has been run or installed as a service.
function readPersisted(name) {
  try {
    const txt = fs.readFileSync(path.join(config.deploymentsDir, name, 'manager.env'), 'utf8');
    const get = (k) => {
      const m = txt.match(new RegExp(`^${k}=(.*)$`, 'm'));
      return m ? m[1].trim() : '';
    };
    const port = Number(get('MANAGER_PORT'));
    const token = get('MANAGER_TOKEN');
    if (port && token) return { port, token };
  } catch {
    /* no persisted manager */
  }
  return null;
}

// Is something actually listening on the manager port? (An always-on service
// keeps it up; a stale manager.env from a past foreground run does not.)
function portAlive(port, host = '127.0.0.1', timeout = 800) {
  return new Promise((resolve) => {
    const sock = net.connect({ port, host });
    let done = false;
    const finish = (v) => {
      if (done) return;
      done = true;
      sock.destroy();
      resolve(v);
    };
    sock.setTimeout(timeout);
    sock.once('connect', () => finish(true));
    sock.once('timeout', () => finish(false));
    sock.once('error', () => finish(false));
  });
}

function publicInfo(rec) {
  // Raw connection facts; the controller builds the reverse-proxy URL.
  return {
    port: rec.port,
    token: rec.token,
    running: true,
    startedAt: rec.startedAt || null,
  };
}

// Synchronous lookup of a deployment's manager (registry, else persisted).
// Used by the reverse proxy to validate the token and find the port.
function lookup(name) {
  const rec = managers.get(name);
  if (rec) return { port: rec.port, token: rec.token };
  const persisted = readPersisted(name);
  return persisted ? { port: persisted.port, token: persisted.token } : null;
}

// Start (or reuse) the manager for `name`. `hostname` is the host the
// dashboard was reached on, so the returned URL points at the same host as
// the manager's own port.
async function start(name) {
  // 1. An always-on service (or any manager already listening on the
  //    persisted port) — just hand back its stable URL.
  const persisted = readPersisted(name);
  if (persisted && (await portAlive(persisted.port))) {
    return publicInfo({ ...persisted, startedAt: null });
  }

  // 2. A manager this process spawned earlier and is still alive.
  const existing = managers.get(name);
  if (existing && alive(existing.pid)) {
    return publicInfo(existing);
  }

  // 3. Cold-start one on demand.
  return new Promise((resolve, reject) => {
    // Bind 127.0.0.1: the manager is never openly exposed. The dashboard
    // reaches it through the API's authenticated reverse proxy.
    const child = spawn('bash', [cli.cliPath(), 'manager', name, '--bind', '127.0.0.1'], {
      env: { ...process.env, CHENGETAI_DEPLOYMENTS_DIR: config.deploymentsDir },
      detached: true,
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    let buf = '';
    let settled = false;

    const onData = (d) => {
      buf += d.toString();
      const m = buf.match(/http:\/\/[^:\s]+:(\d+)\/\?t=([a-f0-9]+)/);
      if (m && !settled) {
        settled = true;
        const rec = {
          port: Number(m[1]),
          token: m[2],
          pid: child.pid,
          startedAt: new Date().toISOString(),
        };
        managers.set(name, rec);
        cleanup();
        child.unref();
        resolve(publicInfo(rec));
      }
    };

    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      cleanup();
      try {
        process.kill(-child.pid);
      } catch {
        /* already gone */
      }
      reject(new Error('manager did not report a URL in time'));
    }, 15000);

    function cleanup() {
      clearTimeout(timer);
      child.stdout.removeListener('data', onData);
      child.stderr.removeListener('data', onData);
      // Keep the pipes flowing (discarded) so the detached child never
      // blocks on a full stdout buffer.
      child.stdout.resume();
      child.stderr.resume();
    }

    child.stdout.on('data', onData);
    child.stderr.on('data', onData);
    child.on('error', (e) => {
      if (settled) return;
      settled = true;
      cleanup();
      reject(e);
    });
  });
}

function status(name) {
  const rec = managers.get(name);
  if (rec && alive(rec.pid)) return publicInfo(rec);
  return { running: false };
}

module.exports = { start, status, lookup };
