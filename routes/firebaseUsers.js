const express = require('express');
const { db, admin } = require('../firebase');
const router = express.Router();

// Get all users
router.get('/', async (req, res) => {
  try {
    const snapshot = await db.collection('Users').get();
    const users = [];
    snapshot.forEach((doc) => {
      users.push({ id: doc.id, ...doc.data() });
    });
    res.json(users);
  } catch (error) {
    console.error('Error getting users:', error);
    res.status(500).json({ error: 'Failed to get users' });
  }
});

// Get user by ID
router.get('/:userId', async (req, res) => {
  try {
    const userId = req.params.userId;
    const doc = await db.collection('Users').doc(userId).get();
    if (!doc.exists) {
      res.status(404).json({ error: 'User not found' });
    } else {
      res.json({ id: doc.id, ...doc.data() });
    }
  } catch (error) {
    console.error('Error getting user:', error);
    res.status(500).json({ error: 'Failed to get user' });
  }
});

module.exports = router;
