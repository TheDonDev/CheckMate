const express = require('express');
const { db } = require('../firebase');
const router = express.Router();

// Create a new department
router.post('/', async (req, res) => {
  try {
    const { name, schoolId } = req.body;
    const newDepartment = {
      name,
      schoolId,
    };
    const docRef = await db.collection('Departments').add(newDepartment);
    res.status(201).json({ id: docRef.id, ...newDepartment });
  } catch (error) {
    console.error('Error creating department:', error);
    res.status(500).json({ error: 'Failed to create department' });
  }
});

// Get all departments
router.get('/', async (req, res) => {
  try {
    const snapshot = await db.collection('Departments').get();
    const departments = [];
    snapshot.forEach((doc) => {
      departments.push({ id: doc.id, ...doc.data() });
    });
    res.json(departments);
  } catch (error) {
    console.error('Error getting departments:', error);
    res.status(500).json({ error: 'Failed to get departments' });
  }
});

// Get department by ID
router.get('/:departmentId', async (req, res) => {
  try {
    const departmentId = req.params.departmentId;
    const doc = await db.collection('Departments').doc(departmentId).get();
    if (!doc.exists) {
      res.status(404).json({ error: 'Department not found' });
    } else {
      res.json({ id: doc.id, ...doc.data() });
    }
  } catch (error) {
    console.error('Error getting department:', error);
    res.status(500).json({ error: 'Failed to get department' });
  }
});

// Get departments by school ID
router.get('/school/:schoolId', async (req, res) => {
  try {
    const schoolId = req.params.schoolId;
    const departmentsRef = db.collection('Departments');
    const snapshot = await departmentsRef.where('schoolId', '==', schoolId).get();

    const departments = [];
    snapshot.forEach((doc) => {
      departments.push({ id: doc.id, ...doc.data() });
    });

    res.json(departments);
  } catch (error) {
    console.error('Error getting departments by school ID:', error);
    res.status(500).json({ error: 'Failed to get departments by school ID' });
  }
});

module.exports = router;
