const express = require('express');
const { db } = require('../firebase');
const router = express.Router();

// Create a new course
router.post('/', async (req, res) => {
  try {
    const { name, departmentId } = req.body;
    const newCourse = {
      name,
      departmentId,
    };
    const docRef = await db.collection('Courses').add(newCourse);
    res.status(201).json({ id: docRef.id, ...newCourse });
  } catch (error) {
    console.error('Error creating course:', error);
    res.status(500).json({ error: 'Failed to create course' });
  }
});

// Get all courses
router.get('/', async (req, res) => {
  try {
    const snapshot = await db.collection('Courses').get();
    const courses = [];
    snapshot.forEach((doc) => {
      courses.push({ id: doc.id, ...doc.data() });
    });
    res.json(courses);
  } catch (error) {
    console.error('Error getting courses:', error);
    res.status(500).json({ error: 'Failed to get courses' });
  }
});

// Get course by ID
router.get('/:courseId', async (req, res) => {
  try {
    const courseId = req.params.courseId;
    const doc = await db.collection('Courses').doc(courseId).get();
    if (!doc.exists) {
      res.status(404).json({ error: 'Course not found' });
    } else {
      res.json({ id: doc.id, ...doc.data() });
    }
  } catch (error) {
    console.error('Error getting course:', error);
    res.status(500).json({ error: 'Failed to get course' });
  }
});

// Get courses by department ID
router.get('/department/:departmentId', async (req, res) => {
  try {
    const departmentId = req.params.departmentId;
    const coursesRef = db.collection('Courses');
    const snapshot = await coursesRef.where('departmentId', '==', departmentId).get();

    const courses = [];
    snapshot.forEach((doc) => {
      courses.push({ id: doc.id, ...doc.data() });
    });

    res.json(courses);
  } catch (error) {
    console.error('Error getting courses by department ID:', error);
    res.status(500).json({ error: 'Failed to get courses by department ID' });
  }
});

module.exports = router;
