const express = require('express');
const { pool } = require('../db');
const checkAuth = require('../middleware/localCheckAuth');

const router = express.Router();

async function requireAdmin(req, res) {
  const result = await pool.query('SELECT role FROM users WHERE id = $1', [req.userData.userId]);
  if (result.rows[0]?.role === 'admin') return true;
  res.status(403).json({ error: 'Administrator access required.' });
  return false;
}

router.use(checkAuth);

router.get('/', async (req, res) => {
  try {
    if (!(await requireAdmin(req, res))) return;
    const result = await pool.query(
      `SELECT id, id AS uid, name, email, phone_number AS "phoneNumber", role, is_verified AS "isVerified",
       school, department, course, registration_number AS "registrationNumber", year_of_study AS "yearOfStudy",
       semester, created_at AS "createdAt" FROM users ORDER BY name`,
    );
    res.json(result.rows);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Could not load users.' });
  }
});

router.patch('/:userId/role', async (req, res) => {
  if (!['student', 'lecturer', 'admin'].includes(req.body.role)) return res.status(400).json({ error: 'Invalid user role.' });
  try {
    if (!(await requireAdmin(req, res))) return;
    const result = await pool.query('UPDATE users SET role = $1 WHERE id = $2 RETURNING id', [req.body.role, req.params.userId]);
    if (!result.rows[0]) return res.status(404).json({ error: 'User not found.' });
    res.sendStatus(204);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Could not update user role.' });
  }
});

router.delete('/:userId', async (req, res) => {
  try {
    if (!(await requireAdmin(req, res))) return;
    if (req.params.userId === req.userData.userId) return res.status(400).json({ error: 'You cannot delete your own account.' });
    await pool.query('DELETE FROM users WHERE id = $1', [req.params.userId]);
    res.sendStatus(204);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Could not delete user.' });
  }
});

module.exports = router;