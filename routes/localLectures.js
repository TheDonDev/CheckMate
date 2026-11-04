const crypto = require('node:crypto');
const express = require('express');
const { pool } = require('../db');
const checkAuth = require('../middleware/localCheckAuth');

const router = express.Router();
const lectureFields = `id, lecturer_id AS "lecturerId", lecturer_name AS "lecturerName", lecturer_phone AS "lecturerPhone",
  school, department, course, year_of_study AS "yearOfStudy", semester, unit_name AS "unitName", unit_code AS "unitCode",
  lecture_date AS "lectureDate", start_time AS "startTime", end_time AS "endTime", venue, online_link AS "onlineLink",
  reminder_sent AS "reminderSent", created_at AS "createdAt"`;
const joinedLectureFields = lectureFields.split(', ').map((field) => `l.${field}`).join(', ');

function sendError(res, error) {
  console.error(error);
  res.status(500).json({ error: 'Database request failed.' });
}

router.use(checkAuth);

router.post('/', async (req, res) => {
  const { school, department, course, yearOfStudy, semester, unitName, unitCode, lectureDate, startTime, endTime, venue, onlineLink, lecturerPhone } = req.body;
  if (![school, department, course, yearOfStudy, semester, unitName, unitCode, lectureDate, startTime, endTime, venue].every((value) => typeof value === 'string' && value.trim())) {
    return res.status(400).json({ error: 'All lecture fields except online link and phone are required.' });
  }
  const starts = new Date(startTime);
  const ends = new Date(endTime);
  const date = new Date(lectureDate);
  if ([starts, ends, date].some((value) => Number.isNaN(value.getTime())) || ends <= starts) {
    return res.status(400).json({ error: 'Invalid lecture date or time.' });
  }
  if (onlineLink) {
    try { new URL(onlineLink); } catch (_) { return res.status(400).json({ error: 'Online link must be a valid URL.' }); }
  }
  try {
    const user = await pool.query('SELECT name, phone_number, role, is_verified FROM users WHERE id = $1', [req.userData.userId]);
    if (!user.rows[0] || user.rows[0].role !== 'lecturer' || !user.rows[0].is_verified) {
      return res.status(403).json({ error: 'Only verified lecturers can create lectures.' });
    }
    const result = await pool.query(
      `INSERT INTO lectures (id, lecturer_id, lecturer_name, lecturer_phone, school, department, course, year_of_study, semester,
        unit_name, unit_code, lecture_date, start_time, end_time, venue, online_link)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
       RETURNING ${lectureFields}`,
      [crypto.randomUUID(), req.userData.userId, user.rows[0].name, lecturerPhone?.trim() || user.rows[0].phone_number,
        school, department, course, yearOfStudy, semester, unitName.trim(), unitCode.trim().toUpperCase(), date, starts, ends, venue.trim(), onlineLink || null],
    );
    res.status(201).json(result.rows[0]);
  } catch (error) { sendError(res, error); }
});

router.get('/lecturer/:lecturerId', async (req, res) => {
  if (req.params.lecturerId !== req.userData.userId) return res.status(403).json({ error: 'You can only access your own lectures.' });
  try {
    const result = await pool.query(`SELECT ${lectureFields} FROM lectures WHERE lecturer_id = $1 ORDER BY start_time DESC`, [req.params.lecturerId]);
    res.json(result.rows);
  } catch (error) { sendError(res, error); }
});

router.get('/student', async (req, res) => {
  const { school, department, course, year, semester } = req.query;
  if (![school, department, course, year, semester].every((value) => typeof value === 'string' && value)) {
    return res.status(400).json({ error: 'School, department, course, year, and semester filters are required.' });
  }
  try {
    const profile = await pool.query('SELECT * FROM users WHERE id = $1', [req.userData.userId]);
    const user = profile.rows[0];
    if (!user || user.role !== 'student') return res.status(403).json({ error: 'Only students can view the student lecture list.' });
    if ([school, department, course, year, semester].some((value, index) => value !== [user.school, user.department, user.course, user.year_of_study, user.semester][index])) {
      return res.status(403).json({ error: 'Lecture filters must match your profile.' });
    }
    const result = await pool.query(
      `SELECT ${lectureFields} FROM lectures WHERE school = $1 AND department = $2 AND course = $3 AND year_of_study = $4 AND semester = $5 AND lecture_date >= CURRENT_DATE ORDER BY start_time`,
      [school, department, course, year, semester],
    );
    res.json(result.rows);
  } catch (error) { sendError(res, error); }
});

router.get('/student/dashboard/:studentId', async (req, res) => {
  if (req.params.studentId !== req.userData.userId) return res.status(403).json({ error: 'You can only access your own dashboard.' });
  try {
    const result = await pool.query(
      `SELECT DISTINCT ${joinedLectureFields} FROM lectures l
       LEFT JOIN attendance a ON a.lecture_id = l.id AND a.user_id = $1
       JOIN users u ON u.id = $1
       WHERE a.id IS NOT NULL OR (l.school = u.school AND l.department = u.department AND l.course = u.course
         AND l.year_of_study = u.year_of_study AND l.semester = u.semester AND l.lecture_date >= CURRENT_DATE)
       ORDER BY "startTime"`,
      [req.params.studentId],
    );
    res.json(result.rows);
  } catch (error) { sendError(res, error); }
});

router.get('/', async (req, res) => {
  try {
    const role = await pool.query('SELECT role FROM users WHERE id = $1', [req.userData.userId]);
    if (role.rows[0]?.role !== 'admin') return res.status(403).json({ error: 'Administrator access required.' });
    const result = await pool.query(`SELECT ${lectureFields} FROM lectures ORDER BY start_time DESC`);
    res.json(result.rows);
  } catch (error) { sendError(res, error); }
});

router.get('/:lectureId', async (req, res) => {
  try {
    const result = await pool.query(`SELECT ${lectureFields} FROM lectures WHERE id = $1`, [req.params.lectureId]);
    if (!result.rows[0]) return res.status(404).json({ error: 'Lecture not found.' });
    res.json(result.rows[0]);
  } catch (error) { sendError(res, error); }
});

router.put('/:lectureId', async (req, res) => {
  const allowedFields = {
    unitName: 'unit_name', unitCode: 'unit_code', school: 'school', department: 'department', course: 'course', venue: 'venue',
    yearOfStudy: 'year_of_study', semester: 'semester', lectureDate: 'lecture_date', startTime: 'start_time', endTime: 'end_time', onlineLink: 'online_link',
  };
  const fields = Object.keys(allowedFields).filter((field) => req.body[field] !== undefined);
  if (!fields.length) return res.status(400).json({ error: 'No editable fields provided.' });
  try {
    const current = await pool.query('SELECT lecturer_id FROM lectures WHERE id = $1', [req.params.lectureId]);
    if (!current.rows[0]) return res.status(404).json({ error: 'Lecture not found.' });
    const user = await pool.query('SELECT role FROM users WHERE id = $1', [req.userData.userId]);
    if (current.rows[0].lecturer_id !== req.userData.userId && user.rows[0]?.role !== 'admin') return res.status(403).json({ error: 'You cannot edit this lecture.' });
    const values = fields.map((field) => field === 'unitCode' ? String(req.body[field]).trim().toUpperCase() : req.body[field]);
    const assignments = fields.map((field, index) => `${allowedFields[field]} = $${index + 1}`);
    const result = await pool.query(`UPDATE lectures SET ${assignments.join(', ')} WHERE id = $${fields.length + 1} RETURNING ${lectureFields}`,
      [...values, req.params.lectureId]);
    res.json(result.rows[0]);
  } catch (error) { sendError(res, error); }
});

router.delete('/:lectureId', async (req, res) => {
  try {
    const current = await pool.query('SELECT lecturer_id FROM lectures WHERE id = $1', [req.params.lectureId]);
    if (!current.rows[0]) return res.sendStatus(204);
    const user = await pool.query('SELECT role FROM users WHERE id = $1', [req.userData.userId]);
    if (current.rows[0].lecturer_id !== req.userData.userId && user.rows[0]?.role !== 'admin') return res.status(403).json({ error: 'You cannot delete this lecture.' });
    await pool.query('DELETE FROM lectures WHERE id = $1', [req.params.lectureId]);
    res.sendStatus(204);
  } catch (error) { sendError(res, error); }
});

module.exports = router;