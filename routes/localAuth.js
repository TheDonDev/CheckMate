const crypto = require('node:crypto');
const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { pool } = require('../db');
const checkAuth = require('../middleware/localCheckAuth');

const router = express.Router();
const tokenSecret = process.env.JWT_SECRET || (process.env.NODE_ENV === 'production' ? null : 'checkmate-local-development-secret-change-me');

function userResponse(row) {
  return {
    id: row.id,
    uid: row.id,
    name: row.name,
    email: row.email,
    phoneNumber: row.phone_number,
    role: row.role,
    isVerified: row.is_verified,
    school: row.school,
    department: row.department,
    course: row.course,
    registrationNumber: row.registration_number,
    yearOfStudy: row.year_of_study,
    semester: row.semester,
    createdAt: row.created_at,
  };
}

function issueToken(user) {
  if (!tokenSecret) throw new Error('JWT_SECRET must be set outside development mode.');
  return jwt.sign({ sub: user.id, email: user.email }, tokenSecret, { expiresIn: '7d' });
}

router.post('/register', async (req, res, next) => {
  const { name, email, password, phoneNumber, school, department, course, registrationNumber, yearOfStudy, semester } = req.body;
  if (![name, email, password, phoneNumber].every((value) => typeof value === 'string' && value.trim())) {
    return res.status(400).json({ error: 'Name, email, password, and phone number are required.' });
  }
  if (password.length < 8) return res.status(400).json({ error: 'Password must be at least 8 characters.' });

  const normalizedEmail = email.trim().toLowerCase();
  const role = normalizedEmail.endsWith('@student.au.ac.ke') ? 'student' : 'lecturer';
  if (role === 'student' && ![school, department, course, registrationNumber, yearOfStudy, semester].every((value) => typeof value === 'string' && value.trim())) {
    return res.status(400).json({ error: 'Student registration requires school, department, course, registration number, year, and semester.' });
  }

  try {
    const passwordHash = await bcrypt.hash(password, 12);
    const result = await pool.query(
      `INSERT INTO users (id, name, email, password_hash, phone_number, role, is_verified, school, department, course, registration_number, year_of_study, semester)
       VALUES ($1, $2, $3, $4, $5, $6, TRUE, $7, $8, $9, $10, $11, $12) RETURNING *`,
      [crypto.randomUUID(), name.trim().toUpperCase(), normalizedEmail, passwordHash, phoneNumber.trim(), role, school || null, department || null, course || null, registrationNumber?.trim().toUpperCase() || null, yearOfStudy || null, semester || null],
    );
    const user = userResponse(result.rows[0]);
    res.status(201).json({ user, token: issueToken(user) });
  } catch (error) {
    if (error.code === '23505') return res.status(409).json({ error: 'An account with that email or registration number already exists.' });
    next(error);
  }
});

router.post('/login', async (req, res, next) => {
  const { email, password } = req.body;
  if (typeof email !== 'string' || typeof password !== 'string') {
    return res.status(400).json({ error: 'Email and password are required.' });
  }
  try {
    const result = await pool.query('SELECT * FROM users WHERE email = $1', [email.trim().toLowerCase()]);
    const row = result.rows[0];
    if (!row || !(await bcrypt.compare(password, row.password_hash))) {
      return res.status(401).json({ error: 'Invalid email or password.' });
    }
    const user = userResponse(row);
    res.json({ user, token: issueToken(user) });
  } catch (error) {
    next(error);
  }
});

router.get('/me', checkAuth, async (req, res, next) => {
  try {
    const result = await pool.query('SELECT * FROM users WHERE id = $1', [req.userData.userId]);
    if (!result.rows[0]) return res.status(404).json({ error: 'User profile not found.' });
    res.json(userResponse(result.rows[0]));
  } catch (error) {
    next(error);
  }
});

module.exports = router;