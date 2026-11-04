const fs = require('node:fs/promises');
const path = require('node:path');
const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  host: process.env.PGHOST || '127.0.0.1',
  port: Number(process.env.PGPORT || 5432),
  database: process.env.PGDATABASE || 'checkmate',
  user: process.env.PGUSER || process.env.USER,
  password: process.env.PGPASSWORD,
});

async function initializeDatabase() {
  const schema = await fs.readFile(path.join(__dirname, 'database', 'schema.sql'), 'utf8');
  await pool.query(schema);
  await pool.query('SELECT 1');
}

module.exports = { pool, initializeDatabase };