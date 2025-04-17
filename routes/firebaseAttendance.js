const express = require('express');
const { db, admin } = require('../firebase');
const router = express.Router();

// Student joins a lecture
router.post('/join/:lectureId', async (req, res) => {
  try {
    const { userId } = req.body;
    const lectureId = req.params.lectureId;
    const visitNumber = Math.random().toString(36).substring(2, 8).toUpperCase();

    const attendanceData = {
      lectureId,
      userId,
      visitNumber,
      checkInTime: null, // Initially null
      CheckedIn: false,
    };

    const docRef = await db.collection('Attendance').add(attendanceData);
    res.status(201).json({ id: docRef.id, ...attendanceData });
  } catch (error) {
    console.error('Error joining lecture:', error);
    res.status(500).json({ error: 'Failed to join lecture' });
  }
});

// Lecturer checks in a student
router.post('/checkin', async (req, res) => {
  try {
    const { visitNumber } = req.body;

    const attendanceRef = db.collection('Attendance');
    const snapshot = await attendanceRef.where('visitNumber', '==', visitNumber).get();

    if (snapshot.empty) {
      return res.status(404).json({ error: 'Invalid visit number' });
    }

    let attendanceDoc;
    snapshot.forEach((doc) => {
      attendanceDoc = doc;
    });

    await attendanceDoc.ref.update({
      checkInTime: admin.firestore.FieldValue.serverTimestamp(),
      CheckedIn: true,
    });

    res.json({ message: 'Student checked in successfully' });
  } catch (error) {
    console.error('Error checking in student:', error);
    res.status(500).json({ error: 'Failed to check in student' });
  }
});

// Student views their attendance history
router.get('/student/:userId', async (req, res) => {
  try {
    const userId = req.params.userId;
    const attendanceRef = db.collection('Attendance');
    const snapshot = await attendanceRef.where('userId', '==', userId).get();

    const attendanceRecords = [];
    snapshot.forEach((doc) => {
      attendanceRecords.push({ id: doc.id, ...doc.data() });
    });

    // Calculate attendance percentage
    const attendedLectures = attendanceRecords.filter((record) => record.checkInTime).length;
    //Get the total number of lectures they have for the semester
    const userDoc = await db.collection('Users').doc(userId).get()
    if (!userDoc.exists) {
      return res.status(404).json({ error: 'User not found' });
    }

    const userData = userDoc.data();

    const { schoolId, departmentId, courseId, year, semester } = userData;
    const lecturesRef = db.collection('Lectures');
    const lecturesSnapshot = await lecturesRef
      .where('schoolId', '==', schoolId)
      .where('departmentId', '==', departmentId)
      .where('courseId', '==', courseId)
      .where('year', '==', parseInt(year))
      .where('semester', '==', parseInt(semester))
      .get();

    const totalLectures = lecturesSnapshot.size;
    const percentage = totalLectures > 0 ? (attendedLectures / totalLectures) * 100 : 0;
    const data = {
      attendanceRecords,
      percentage: percentage.toFixed(2),
    };
    res.json(data);
  } catch (error) {
    console.error('Error getting student attendance:', error);
    res.status(500).json({ error: 'Failed to get student attendance' });
  }
});

//Lecturer view student overall attendance for a particular lecture
router.get('/lecture/:lectureId', async (req, res) => {
  try {
    const lectureId = req.params.lectureId;
    const attendanceRef = db.collection('Attendance');
    const snapshot = await attendanceRef.where('lectureId', '==', lectureId).get();

    const attendanceRecords = [];
    snapshot.forEach((doc) => {
      attendanceRecords.push({ id: doc.id, ...doc.data() });
    });

    res.json(attendanceRecords);
  } catch (error) {
    console.error('Error getting student attendance:', error);
    res.status(500).json({ error: 'Failed to get student attendance' });
  }
});

module.exports = router;
