// Platform plugin catalogue, read from templates/<name>/plugin.json.
const fs = require('fs');
const path = require('path');
const config = require('../config');

function list() {
  let entries = [];
  try {
    entries = fs.readdirSync(config.templatesDir, { withFileTypes: true });
  } catch {
    return [];
  }
  const plugins = [];
  for (const e of entries) {
    if (!e.isDirectory()) continue;
    const metaFile = path.join(config.templatesDir, e.name, 'plugin.json');
    try {
      plugins.push(JSON.parse(fs.readFileSync(metaFile, 'utf8')));
    } catch {
      /* templates without metadata are simply not listed */
    }
  }
  return plugins;
}

module.exports = { list };
