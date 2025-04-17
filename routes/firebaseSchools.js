const express = require('express');
const { db } = require('../firebase');
const router = express.Router();

// Create a new school
router.post('/', async (req, res) => {
  try {
    const { name } = req.body;
    const newSchool = {
      name,
    };
    const docRef = await db.collection('Schools').add(newSchool);
    res.status(201).json({ id: docRef.id, ...newSchool });
  } catch (error) {
    console.error('Error creating school:', error);
    res.status(500).json({ error: 'Failed to create school' });
  }
});

// Get all schools
router.get('/', async (req, res) => {
  try {
    const snapshot = await db.collection('Schools').get();
    const schools = [];
    snapshot.forEach((doc) => {
      schools.push({ id: doc.id, ...doc.data() });
    });
    res.json(schools);
  } catch (error) {
    console.error('Error getting schools:', error);
    res.status(500).json({ error: 'Failed to get schools' });
  }
});

// Get school by ID
router.get('/:schoolId', async (req, res) => {
  try {
    const schoolId = req.params.schoolId;
    const doc = await db.collection('Schools').doc(schoolId).get();
    if (!doc.exists) {
      res.status(404).json({ error: 'School not found' });
    } else {
      res.json({ id: doc.id, ...doc.data() });
    }
  } catch (error) {
    console.error('Error getting school:', error);
    res.status(500).json({ error: 'Failed to get school' });
  }
});

module.exports = router;
