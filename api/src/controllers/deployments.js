const deploymentsService = require('../services/deployments');
const cli = require('../services/cli');
const jobs = require('../services/jobs');

const NAME_RE = /^[a-z0-9][a-z0-9-]*$/;

function list(req, res) {
  res.json(deploymentsService.list());
}

// Create a deployment profile and kick off the deploy as a tracked job.
// Mirrors `chengetai create` + `chengetai deploy`; the CLI remains the
// single actuator of deployment logic.
function create(req, res) {
  const {
    name,
    platform = 'dspace',
    institution,
    repository,
    adminEmail,
    adminFirstName,
    adminLastName,
    adminPassword,
    uiPort = 4000,
    restPort = 8080,
  } = req.body;

  if (!NAME_RE.test(name || '')) {
    return res.status(400).json({ error: 'name must be lowercase letters, digits and hyphens' });
  }
  if (deploymentsService.list().some((d) => d.name === name)) {
    return res.status(409).json({ error: `Deployment '${name}' already exists` });
  }

  const env = {
    PLATFORM: platform,
    INSTITUTION: institution || '',
    REPOSITORY: repository || '',
    ADMIN_EMAIL: adminEmail || '',
    ADMIN_FIRST_NAME: adminFirstName || '',
    ADMIN_LAST_NAME: adminLastName || '',
    ADMIN_PASS: adminPassword || '',
    UI_PORT: String(uiPort),
    REST_PORT: String(restPort),
    // create.sh reads these from the env and skips the matching prompts.
    DEPLOYMENT_NAME: name,
  };

  // Step 1: create the profile synchronously (fast, no docker).
  cli
    .runSync(['create', platform, name], { env })
    .then((created) => {
      if (created.code !== 0) {
        // Surface create failures directly.
        return res.status(400).json({ error: 'Failed to create profile', output: created.output });
      }
      // Step 2: deploy as a background job.
      const job = cli.runJob('deploy', ['deploy', name], {
        meta: { deployment: name, platform },
        env,
      });
      return res.status(202).json({ jobId: job.id, deployment: name });
    })
    .catch((err) => res.status(500).json({ error: err.message }));
}

// Lifecycle actions that shell out to the CLI. start/restart/backup/update
// are safe to run as jobs; status is synchronous.
const JOB_ACTIONS = {
  deploy: (name) => ['deploy', name],
  start: (name) => ['start', name],
  stop: (name) => ['stop', name],
  restart: (name) => ['restart', name],
  backup: (name) => ['backup', name],
  update: (name) => ['update', name],
};

function action(req, res) {
  const { name, action: act } = req.params;
  if (!deploymentsService.list().some((d) => d.name === name)) {
    return res.status(404).json({ error: `Deployment '${name}' not found` });
  }
  const build = JOB_ACTIONS[act];
  if (!build) return res.status(400).json({ error: `Unknown action '${act}'` });

  const job = cli.runJob(act, build(name), { meta: { deployment: name, action: act } });
  return res.status(202).json({ jobId: job.id, deployment: name, action: act });
}

async function status(req, res) {
  const { name } = req.params;
  if (!deploymentsService.list().some((d) => d.name === name)) {
    return res.status(404).json({ error: `Deployment '${name}' not found` });
  }
  const result = await cli.runSync(['status', name]);
  res.json({ deployment: name, output: result.output });
}

// Removal requires admin and is confirmed by the caller; the CLI's
// interactive confirmation is answered non-interactively.
function remove(req, res) {
  const { name } = req.params;
  if (!deploymentsService.list().some((d) => d.name === name)) {
    return res.status(404).json({ error: `Deployment '${name}' not found` });
  }
  const purge = req.query.purge === 'true';
  // remove.sh asks: remove? then delete-data? — answer Y then Y/N.
  const input = purge ? 'Y\nY\n' : 'Y\nN\n';
  const job = cli.runJob('remove', ['remove', name], {
    meta: { deployment: name, purge },
    input,
  });
  res.status(202).json({ jobId: job.id, deployment: name });
}

module.exports = { list, create, action, status, remove };
