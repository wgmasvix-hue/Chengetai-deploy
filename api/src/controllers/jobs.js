const jobs = require('../services/jobs');

function list(req, res) {
  res.json(jobs.list());
}

// Job detail with its captured output. `?since=N` returns only log lines
// from index N onward, so the dashboard can tail incrementally.
function get(req, res) {
  const job = jobs.get(req.params.id);
  if (!job) return res.status(404).json({ error: 'Job not found' });

  const since = Math.max(0, parseInt(req.query.since, 10) || 0);
  res.json({
    ...jobs.summary(job),
    log: job.log.slice(since),
    nextCursor: job.log.length,
  });
}

module.exports = { list, get };
