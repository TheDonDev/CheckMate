const crypto = require('node:crypto');
const express = require('express');
const { pool } = require('../db');
const checkAuth = require('../middleware/localCheckAuth');

const router = express.Router();
const catalogs = {
  schools: { table: 'schools' },
  departments: { table: 'departments', parentColumn: 'school_id', parentKey: 'schoolId' },
  courses: { table: 'courses', parentColumn: 'department_id', parentKey: 'departmentId' },
  venues: { table: 'venues' },
  years_of_study: { table: 'years_of_study' },
  semesters: { table: 'semesters' },
};

function getCatalog(name, res) {
  const catalog = catalogs[name];
  if (!catalog) res.status(404).json({ error: 'Unknown catalog.' });
  return catalog;
}

async function requireAdmin(req, res) {
  const result = await pool.query('SELECT role FROM users WHERE id = $1', [req.userData.userId]);
  if (result.rows[0]?.role === 'admin') return true;
  res.status(403).json({ error: 'Administrator access required.' });
  return false;
}

function projection(catalog) {
  return `id, name, ${catalog.parentColumn ? `${catalog.parentColumn} AS "${catalog.parentKey}", ` : ''}created_at AS "createdAt"`;
}

router.get('/:collection', async (req, res) => {
  const catalog = getCatalog(req.params.collection, res);
  if (!catalog) return;
  try {
    const values = [];
    let where = '';
    if (catalog.parentColumn && req.query[catalog.parentKey]) {
      values.push(req.query[catalog.parentKey]);
      where = `WHERE ${catalog.parentColumn} = $1`;
    }
    const result = await pool.query(`SELECT ${projection(catalog)} FROM ${catalog.table} ${where} ORDER BY name`, values);
    res.json(result.rows);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Could not load catalog.' });
  }
});

router.get('/:collection/:id', async (req, res) => {
  const catalog = getCatalog(req.params.collection, res);
  if (!catalog) return;
  try {
    const result = await pool.query(`SELECT ${projection(catalog)} FROM ${catalog.table} WHERE id = $1`, [req.params.id]);
    if (!result.rows[0]) return res.status(404).json({ error: 'Catalog item not found.' });
    res.json(result.rows[0]);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Could not load catalog item.' });
  }
});

router.post('/:collection', checkAuth, async (req, res) => {
  const catalog = getCatalog(req.params.collection, res);
  if (!catalog) return;
  try {
    if (!(await requireAdmin(req, res))) return;
    const name = typeof req.body.name === 'string' ? req.body.name.trim() : '';
    if (!name) return res.status(400).json({ error: 'Name is required.' });
    let result;
    if (catalog.parentColumn) {
      const parentId = req.body[catalog.parentKey];
      if (typeof parentId !== 'string' || !parentId) return res.status(400).json({ error: `${catalog.parentKey} is required.` });
      result = await pool.query(
        `INSERT INTO ${catalog.table} (id, name, ${catalog.parentColumn}) VALUES ($1, $2, $3) RETURNING ${projection(catalog)}`,
        [crypto.randomUUID(), name, parentId],
      );
    } else {
      result = await pool.query(`INSERT INTO ${catalog.table} (id, name) VALUES ($1, $2) RETURNING ${projection(catalog)}`, [crypto.randomUUID(), name]);
    }
    res.status(201).json(result.rows[0]);
  } catch (error) {
    if (error.code === '23505') return res.status(409).json({ error: 'That catalog item already exists.' });
    if (error.code === '23503') return res.status(400).json({ error: 'The selected parent catalog item does not exist.' });
    console.error(error);
    res.status(500).json({ error: 'Could not create catalog item.' });
  }
});

router.put('/:collection/:id', checkAuth, async (req, res) => {
  const catalog = getCatalog(req.params.collection, res);
  if (!catalog) return;
  try {
    if (!(await requireAdmin(req, res))) return;
    const name = typeof req.body.name === 'string' ? req.body.name.trim() : '';
    if (!name) return res.status(400).json({ error: 'Name is required.' });
    const result = await pool.query(`UPDATE ${catalog.table} SET name = $1 WHERE id = $2 RETURNING ${projection(catalog)}`, [name, req.params.id]);
    if (!result.rows[0]) return res.status(404).json({ error: 'Catalog item not found.' });
    res.json(result.rows[0]);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Could not update catalog item.' });
  }
});

router.delete('/:collection/:id', checkAuth, async (req, res) => {
  const catalog = getCatalog(req.params.collection, res);
  if (!catalog) return;
  try {
    if (!(await requireAdmin(req, res))) return;
    await pool.query(`DELETE FROM ${catalog.table} WHERE id = $1`, [req.params.id]);
    res.sendStatus(204);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Could not delete catalog item.' });
  }
});

module.exports = router;