const crypto = require('node:crypto');
const express = require('express');
const { pool } = require('../db');
const checkAuth = require('../middleware/localCheckAuth');

const router = express.Router();
const attendanceFields = `id, user_id AS "userId", student_name AS "studentName", registration_number AS "registrationNumber",
  lecture_id AS "lectureId", joined_at AS "joinedAt", checked_in AS "checkedIn", check_in_time AS "checkInTime", checked_in_by AS "checkedInBy"`;
const joinedAttendanceFields = attendanceFields.split(', ').map((field) => `a.${field}`).join(', ');

function sendError(res, error) {
  console.error(error);
  res.status(500).json({ error: 'Database request failed.' });
}

router.use(checkAuth);

router.post('/join/:lectureId', async (req, res) => {
  const { lectureId } = req.params;
  const userId = req.userData.userId;
  try {
    const student = await pool.query('SELECT * FROM users WHERE id = $1', [userId]);
    const lecture = await pool.query('SELECT * FROM lectures WHERE id = $1', [lectureId]);
    if (!student.rows[0]) return res.status(404).json({ message: 'Your user profile could not be found.' });
    if (!lecture.rows[0]) return res.status(404).json({ message: 'Lecture not found or is no longer available.' });
    const user = student.rows[0];
    const target = lecture.rows[0];
    if (user.role !== 'student') return res.status(403).json({ message: 'Only students can join lectures.' });
    if (!user.registration_number) return res.status(400).json({ message: 'Your profile is missing the registration number.' });
    if ([user.school, user.department, user.course, user.year_of_study, user.semester].some((value, i) => value !== [target.school, target.department, target.course, target.year_of_study, target.semester][i])) {
      return res.status(403).json({ message: 'Your profile details do not match this lecture.' });
    }
    const result = await pool.query(
      `INSERT INTO attendance (id, user_id, student_name, registration_number, lecture_id)
       VALUES ($1, $2, $3, $4, $5) ON CONFLICT (lecture_id, user_id) DO NOTHING RETURNING ${attendanceFields}`,
      [crypto.randomUUID(), userId, user.name, user.registration_number, lectureId],
    );
    if (result.rows[0]) return res.status(201).json({ message: 'Successfully joined lecture.', ...result.rows[0] });
    const existing = await pool.query(`SELECT ${attendanceFields} FROM attendance WHERE lecture_id = $1 AND user_id = $2`, [lectureId, userId]);
    return res.status(409).json({ message: existing.rows[0].checkedIn ? 'Already checked in for this lecture.' : 'Already joined this lecture.', ...existing.rows[0] });
  } catch (error) { sendError(res, error); }
});

async function checkIn(userId, lectureId, registrationNumber, checkedInBy) {
  const result = await pool.query(
    `UPDATE attendance SET checked_in = TRUE, check_in_time = NOW(), checked_in_by = $1
     WHERE lecture_id = $2 AND user_id = $3 AND checked_in = FALSE
       AND EXISTS (SELECT 1 FROM lectures WHERE id = $2 AND end_time >= NOW())
     RETURNING ${attendanceFields}`,
    [checkedInBy, lectureId, userId],
  );
  if (result.rows[0]) return result.rows[0];
  const lecture = await pool.query('SELECT end_time FROM lectures WHERE id = $1', [lectureId]);
  if (!lecture.rows[0]) return { error: 'Lecture not found.', status: 404 };
  if (new Date(lecture.rows[0].end_time) < new Date()) return { error: 'Check-in failed: The lecture has already ended.', status: 400 };
  const attendance = await pool.query(`SELECT ${attendanceFields} FROM attendance WHERE lecture_id = $1 AND user_id = $2`, [lectureId, userId]);
  if (!attendance.rows[0]) return { error: 'Check-in failed: You must join the lecture first.', status: 400 };
  if (registrationNumber && attendance.rows[0].registrationNumber !== registrationNumber) return { error: 'Student has not joined this lecture.', status: 400 };
  return { ...attendance.rows[0], error: 'Already checked in for this lecture.', status: 409 };
}

router.post('/checkin/student/:lectureId', async (req, res) => {
  try {
    const outcome = await checkIn(req.userData.userId, req.params.lectureId, null, 'student_self_qr');
    if (outcome.error) return res.status(outcome.status).json({ message: outcome.error, ...outcome });
    res.json({ message: 'Successfully checked in.', ...outcome });
  } catch (error) { sendError(res, error); }
});

router.post('/checkin', async (req, res) => {
  const { lectureId, registrationNumber } = req.body;
  if (typeof lectureId !== 'string' || typeof registrationNumber !== 'string' || !registrationNumber.trim()) {
    return res.status(400).json({ message: 'Lecture ID and student registration number are required.' });
  }
  try {
    const lecturer = await pool.query('SELECT role FROM users WHERE id = $1', [req.userData.userId]);
    if (lecturer.rows[0]?.role !== 'lecturer') return res.status(403).json({ message: 'Only lecturers can check students in.' });
    const lecture = await pool.query('SELECT lecturer_id FROM lectures WHERE id = $1', [lectureId]);
    if (!lecture.rows[0]) return res.status(404).json({ message: 'Lecture not found.' });
    if (lecture.rows[0].lecturer_id !== req.userData.userId) return res.status(403).json({ message: 'You can only check in students for your own lecture.' });
    const student = await pool.query('SELECT id FROM users WHERE role = $1 AND registration_number = $2', ['student', registrationNumber.trim().toUpperCase()]);
    if (!student.rows[0]) return res.status(404).json({ message: 'Student registration number not found.' });
    const outcome = await checkIn(student.rows[0].id, lectureId, registrationNumber.trim().toUpperCase(), req.userData.userId);
    if (outcome.error) return res.status(outcome.status).json({ message: outcome.error, ...outcome });
    res.json({ message: 'Successfully checked in.', ...outcome });
  } catch (error) { sendError(res, error); }
});

router.get('/lecture/:lectureId', async (req, res) => {
  try {
    const lecture = await pool.query('SELECT lecturer_id FROM lectures WHERE id = $1', [req.params.lectureId]);
    if (!lecture.rows[0]) return res.status(404).json({ error: 'Lecture not found.' });
    if (lecture.rows[0].lecturer_id !== req.userData.userId) return res.status(403).json({ error: 'Only the lecture owner can view its roster.' });
    const result = await pool.query(`SELECT ${attendanceFields} FROM attendance WHERE lecture_id = $1 ORDER BY joined_at`, [req.params.lectureId]);
    res.json(result.rows);
  } catch (error) { sendError(res, error); }
});

router.get('/student/:userId', async (req, res) => {
  if (req.params.userId !== req.userData.userId) return res.status(403).json({ error: 'You can only access your own attendance.' });
  try {
    const filters = ['a.user_id = $1'];
    const values = [req.params.userId];
    if (req.query.year) { values.push(req.query.year); filters.push(`l.year_of_study = $${values.length}`); }
    if (req.query.semester) { values.push(req.query.semester); filters.push(`l.semester = $${values.length}`); }
    const records = await pool.query(
      `SELECT ${joinedAttendanceFields}, l.unit_name AS "unitName", l.unit_code AS "unitCode"
       FROM attendance a JOIN lectures l ON l.id = a.lecture_id WHERE ${filters.join(' AND ')} ORDER BY a.joined_at DESC`, values,
    );
    const attended = records.rows.filter((row) => row.checkedIn).length;
    const total = records.rows.length;
    res.json({ attendanceRecords: records.rows, percentage: total ? ((attended / total) * 100).toFixed(2) : '0.00', totalLectures: total, attendedLectures: attended });
  } catch (error) { sendError(res, error); }
});

module.exports = router;