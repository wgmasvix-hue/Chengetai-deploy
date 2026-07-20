// Per-deployment local manager UIs, started on demand from the dashboard.
// Each is the standalone `chengetai manager` server (lib/manager/server.js)
// spawned detached; we parse the URL + token it prints, keep a small
// registry, and hand the dashboard a link. Idempotent: a deployment whose
// manager is already alive is reused, not respawned.
const { spawn } = require('child_process');
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

function publicInfo(rec, hostname) {
  return {
    url: `http://${hostname}:${rec.port}/?t=${rec.token}`,
    port: rec.port,
    running: true,
    startedAt: rec.startedAt,
  };
}

// Start (or reuse) the manager for `name`. `hostname` is the host the
// dashboard was reached on, so the returned URL points at the same host as
// the manager's own port.
function start(name, hostname) {
  const existing = managers.get(name);
  if (existing && alive(existing.pid)) {
    return Promise.resolve(publicInfo(existing, hostname));
  }

  return new Promise((resolve, reject) => {
    // Bind 0.0.0.0 so the dashboard user's browser can reach it; the manager
    // is gated by the per-session token it prints.
    const child = spawn('bash', [cli.cliPath(), 'manager', name, '--bind', '0.0.0.0'], {
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
        resolve(publicInfo(rec, hostname));
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

function status(name, hostname) {
  const rec = managers.get(name);
  if (rec && alive(rec.pid)) return publicInfo(rec, hostname);
  return { running: false };
}

module.exports = { start, status };
