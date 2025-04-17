const express = require('express');
const { db, admin } = require('../firebase');
const router = express.Router();

//Create a Lecture
router.post('/', async (req, res) => {
  try {
    const { courseId, lecturerId, date, year, semester, schoolId, departmentId } = req.body;
    const newLecture = {
      courseId,
      lecturerId,
      date,
      year,
      semester,
      schoolId,
      departmentId,
    };
    const docRef = await db.collection('Lectures').add(newLecture);
    res.status(201).json({ id: docRef.id, ...newLecture });
  } catch (error) {
    console.error('Error creating lecture:', error);
    res.status(500).json({ error: 'Failed to create lecture' });
  }
});

// Get lectures for a student
router.get('/student', async (req, res) => {
  try {
    const { schoolId, departmentId, courseId, year, semester } = req.query;

    const lecturesRef = db.collection('Lectures');
    const snapshot = await lecturesRef
      .where('schoolId', '==', schoolId)
      .where('departmentId', '==', departmentId)
      .where('courseId', '==', courseId)
      .where('year', '==', parseInt(year))
      .where('semester', '==', parseInt(semester))
      .get();

    const lectures = [];
    snapshot.forEach((doc) => {
      lectures.push({ id: doc.id, ...doc.data() });
    });

    res.json(lectures);
  } catch (error) {
    console.error('Error getting lectures:', error);
    res.status(500).json({ error: 'Failed to get lectures' });
  }
});

// Get all lectures
router.get('/', async (req, res) => {
  try {
    const snapshot = await db.collection('Lectures').get();
    const lectures = [];
    snapshot.forEach((doc) => {
      lectures.push({ id: doc.id, ...doc.data() });
    });
    res.json(lectures);
  } catch (error) {
    console.error('Error getting lectures:', error);
    res.status(500).json({ error: 'Failed to get lectures' });
  }
});

// Get lecture by ID
router.get('/:lectureId', async (req, res) => {
  try {
    const lectureId = req.params.lectureId;
    const doc = await db.collection('Lectures').doc(lectureId).get();
    if (!doc.exists) {
      res.status(404).json({ error: 'Lecture not found' });
    } else {
      res.json({ id: doc.id, ...doc.data() });
    }
  } catch (error) {
    console.error('Error getting lecture:', error);
    res.status(500).json({ error: 'Failed to get lecture' });
  }
});

module.exports = router;
