// PostgreSQL repository driver — active when DATABASE_URL is set.
// Implements the same interface as store.js. Apply db/schema.sql once:
//   psql "$DATABASE_URL" -f db/schema.sql
const { Pool } = require('pg');
const config = require('../config');

const pool = new Pool({ connectionString: config.databaseUrl });

class PgCollection {
  constructor(table) {
    this.table = table;
  }

  async all() {
    const { rows } = await pool.query(`SELECT data FROM ${this.table} ORDER BY created_at`);
    return rows.map((r) => r.data);
  }

  async findBy(field, value) {
    const { rows } = await pool.query(
      `SELECT data FROM ${this.table} WHERE data->>$1 = $2 LIMIT 1`,
      [field, String(value)]
    );
    return rows[0] ? rows[0].data : null;
  }

  async insert(row) {
    await pool.query(`INSERT INTO ${this.table} (id, data) VALUES ($1, $2)`, [row.id, row]);
    return row;
  }

  async update(id, patch) {
    const { rows } = await pool.query(
      `UPDATE ${this.table} SET data = data || $2 WHERE id = $1 RETURNING data`,
      [id, patch]
    );
    return rows[0] ? rows[0].data : null;
  }

  async remove(id) {
    const { rowCount } = await pool.query(`DELETE FROM ${this.table} WHERE id = $1`, [id]);
    return rowCount > 0;
  }
}

module.exports = {
  users: new PgCollection('users'),
  servers: new PgCollection('servers'),
  auditLogs: new PgCollection('audit_logs'),
  pool,
};
