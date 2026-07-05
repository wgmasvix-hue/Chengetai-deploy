// Deployments on this server, read from the CLI's deployments directory
// (deployments/<name>/profile.env). The API reads what the CLI manages —
// one source of truth on disk, no duplicated state.
const fs = require("fs");
const path = require("path");

const ROOT = "/opt/deployments";

function createDeployment(name) {
    const slug = name
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, "-");

    const base = path.join(ROOT, slug);

    const folders = [
        "",
        "config",
        "docker",
        "branding",
        "ssl",
        "logs",
        "backups",
        "data"
    ];

    folders.forEach(folder => {
        fs.mkdirSync(path.join(base, folder), {
            recursive: true
        });
    });

    return {
        slug,
        path: base
    };
}

module.exports = {
    createDeployment
};const fs = require('fs');
const path = require('path');
const config = require('../config');

function parseProfile(file) {
  const profile = {};
  for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
    const m = line.match(/^([A-Z_]+)=(.*)$/);
    if (!m) continue;
    // Values are written with printf %q; unescape the common cases.
    profile[m[1]] = m[2].replace(/\\(.)/g, '$1').replace(/^'(.*)'$/, '$1');
  }
  return profile;
}

function list() {
  let entries = [];
  try {
    entries = fs.readdirSync(config.deploymentsDir, { withFileTypes: true });
  } catch {
    return [];
  }
  const deployments = [];
  for (const e of entries) {
    if (!e.isDirectory()) continue;
    const profileFile = path.join(config.deploymentsDir, e.name, 'profile.env');
    if (!fs.existsSync(profileFile)) continue;
    const p = parseProfile(profileFile);
    deployments.push({
      name: e.name,
      platform: p.PLATFORM || 'unknown',
      institution: p.INSTITUTION || '',
      repository: p.REPOSITORY || '',
      uiPort: Number(p.UI_PORT || 4000),
      restPort: Number(p.REST_PORT || 8080),
      createdAt: p.CREATED_AT || null,
      engineReady: fs.existsSync(path.join(config.deploymentsDir, e.name, 'engine', '.git')),
    });
  }
  return deployments;
}

module.exports = { list };
