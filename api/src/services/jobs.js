// In-memory job registry for long-running CLI operations (deploy, backup,
// remove, ...). Each job captures streamed output and a terminal status
// so the dashboard can poll progress. Jobs are ephemeral by design — they
// describe work in flight, not durable records (those are the deployment
// profiles on disk and the audit log).
const crypto = require('crypto');

const MAX_LOG = 2000; // lines kept per job
const RETAIN_MS = 60 * 60 * 1000; // finished jobs kept for an hour

const jobs = new Map();

function create(kind, meta = {}) {
  const job = {
    id: crypto.randomUUID(),
    kind,
    meta,
    status: 'running', // running | success | failed
    exitCode: null,
    log: [],
    startedAt: new Date().toISOString(),
    finishedAt: null,
  };
  jobs.set(job.id, job);
  return job;
}

function append(job, line) {
  job.log.push(line);
  if (job.log.length > MAX_LOG) job.log.shift();
}

function finish(job, exitCode) {
  job.status = exitCode === 0 ? 'success' : 'failed';
  job.exitCode = exitCode;
  job.finishedAt = new Date().toISOString();
  // Schedule cleanup without keeping the event loop alive.
  const t = setTimeout(() => jobs.delete(job.id), RETAIN_MS);
  if (t.unref) t.unref();
}

function get(id) {
  return jobs.get(id) || null;
}

function list() {
  return Array.from(jobs.values()).map(summary);
}

function summary(job) {
  return {
    id: job.id,
    kind: job.kind,
    meta: job.meta,
    status: job.status,
    exitCode: job.exitCode,
    startedAt: job.startedAt,
    finishedAt: job.finishedAt,
    lines: job.log.length,
  };
}

module.exports = { create, append, finish, get, list, summary };
