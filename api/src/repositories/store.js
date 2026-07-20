// JSON-file repository driver — the default when DATABASE_URL is unset.
// One file per collection under DATA_DIR, written atomically. Suited to
// the single-node internal-tool deployment; the pg driver implements the
// same interface for PostgreSQL (see repositories/pg.js).
const fs = require('fs');
const path = require('path');
const config = require('../config');

class JsonCollection {
  constructor(name) {
    this.file = path.join(config.dataDir, `${name}.json`);
    this.rows = [];
    if (fs.existsSync(this.file)) {
      try {
        this.rows = JSON.parse(fs.readFileSync(this.file, 'utf8'));
      } catch {
        this.rows = [];
      }
    }
  }

  persist() {
    const tmp = `${this.file}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(this.rows, null, 2), { mode: 0o600 });
    fs.renameSync(tmp, this.file);
  }

  async all() {
    return this.rows;
  }

  async findBy(field, value) {
    return this.rows.find((r) => r[field] === value) || null;
  }

  async filter(field, value) {
    return this.rows.filter((r) => r[field] === value);
  }

  async insert(row) {
    this.rows.push(row);
    this.persist();
    return row;
  }

  async update(id, patch) {
    const row = this.rows.find((r) => r.id === id);
    if (!row) return null;
    Object.assign(row, patch);
    this.persist();
    return row;
  }

  async remove(id) {
    const before = this.rows.length;
    this.rows = this.rows.filter((r) => r.id !== id);
    this.persist();
    return this.rows.length < before;
  }
}

module.exports = {
  users: new JsonCollection('users'),
  servers: new JsonCollection('servers'),
  auditLogs: new JsonCollection('audit-logs'),
  // Fleet control plane: enrolled deployments, the tokens that admit them,
  // and the command queue the agents drain on each heartbeat.
  fleetAgents: new JsonCollection('fleet-agents'),
  enrollmentTokens: new JsonCollection('enrollment-tokens'),
  fleetCommands: new JsonCollection('fleet-commands'),
};
