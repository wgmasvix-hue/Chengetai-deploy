// Bridge to the ChengetAi CLI. The API never reimplements deployment
// logic — it shells out to the same `chengetai` commands an engineer runs,
// so there is exactly one code path for operations. Long-running commands
// are tracked as jobs (services/jobs.js); their output is streamed in.
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const config = require('../config');
const jobs = require('./jobs');

// Resolve the CLI entrypoint: explicit env override, the installed
// location, or the repo root relative to this file.
function cliPath() {
  const candidates = [
    process.env.CHENGETAI_CLI,
    '/opt/chengetai-deploy/chengetai',
    path.join(__dirname, '..', '..', '..', 'chengetai'),
  ].filter(Boolean);
  return candidates.find((p) => fs.existsSync(p)) || 'chengetai';
}

// Environment passed to every CLI invocation so it targets the same
// deployments directory the API reads, and never blocks on a prompt.
function cliEnv(extra = {}) {
  return {
    ...process.env,
    CHENGETAI_DEPLOYMENTS_DIR: config.deploymentsDir,
    ...extra,
  };
}

// Run a CLI command as a tracked job. Returns the job immediately; the
// caller polls jobs.get(id). `input` supplies answers for any prompt the
// non-interactive path can't avoid (e.g. remove confirmation).
function runJob(kind, args, { meta = {}, env = {}, input } = {}) {
  const job = jobs.create(kind, meta);
  const child = spawn(cliPath(), args, { env: cliEnv(env) });

  const onData = (buf) => {
    for (const line of buf.toString().split('\n')) {
      if (line.length) jobs.append(job, line);
    }
  };
  child.stdout.on('data', onData);
  child.stderr.on('data', onData);

  child.on('error', (err) => {
    jobs.append(job, `spawn error: ${err.message}`);
    jobs.finish(job, 1);
  });
  child.on('close', (code) => jobs.finish(job, code == null ? 1 : code));

  if (input !== undefined) {
    child.stdin.write(input);
    child.stdin.end();
  } else {
    child.stdin.end();
  }

  return job;
}

// Run a short CLI command and resolve with its combined output. Used for
// quick, synchronous operations (status).
function runSync(args, { env = {}, timeout = 15000 } = {}) {
  return new Promise((resolve) => {
    const child = spawn(cliPath(), args, { env: cliEnv(env) });
    let out = '';
    const t = setTimeout(() => child.kill('SIGTERM'), timeout);
    child.stdout.on('data', (b) => (out += b));
    child.stderr.on('data', (b) => (out += b));
    child.on('error', (err) => {
      clearTimeout(t);
      resolve({ code: 1, output: err.message });
    });
    child.on('close', (code) => {
      clearTimeout(t);
      resolve({ code, output: out });
    });
  });
}

module.exports = { runJob, runSync, cliPath };
