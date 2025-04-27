// c:\Users\Test\FlutterProjects\checkmate\routes\firebaseUsers.js
const express = require('express');
const { db, admin } = require('../firebase'); 
const router = express.Router();
const checkAuth = require('../middleware/checkAuth'); 

// --- Constants ---
const USERS_COLLECTION = 'users'; // Standardize on lowercase 'users' as used in AuthService and other routes

// --- Helper Function for Timestamp Conversion ---
// (Consistent with firebaseAttendance.js)
const formatTimestamp = (timestamp) => {
  // Check if it's a Firestore Timestamp object and has the toDate method
  if (timestamp && typeof timestamp.toDate === 'function') {
    return timestamp.toDate().toISOString();
  }
  // If it's already null, undefined, or some other type, return null
  return null;
};

// --- Get all users ---
// SECURITY: This endpoint exposes all user data. It should be protected
router.get('/', checkAuth, async (req, res) => { // checkAuth for basic login requirement
  try {
    // --- Authorization Check (Example: Check if user is admin) ---
    // const requestingUserId = req.userData.userId;
    // const userDoc = await db.collection(USERS_COLLECTION).doc(requestingUserId).get();
    // if (!userDoc.exists || userDoc.data().role !== 'admin') {
    //   console.warn(`Unauthorized attempt to fetch all users by user: ${requestingUserId}`);
    //   return res.status(403).json({ error: 'Forbidden: Only administrators can access all users.' });
    // }
    // --- End Authorization Check ---

    console.log('Fetching all users (Admin access)'); 
    const snapshot = await db.collection(USERS_COLLECTION).get();
    const users = [];
    snapshot.forEach((doc) => {
      const data = doc.data();
      users.push({
        id: doc.id, // The document ID (which is the Firebase Auth UID)
        uid: data.uid, // Include uid field if stored explicitly
        name: data.name,
        email: data.email,
        phoneNumber: data.phoneNumber, 
        role: data.role,
        school: data.school,
        department: data.department,
        course: data.course,
        registrationNumber: data.registrationNumber, 
        yearOfStudy: data.yearOfStudy,
        semester: data.semester,
        isVerified: data.isVerified,
        createdAt: formatTimestamp(data.createdAt), // Format timestamp
      });
    });
    res.json(users);
  } catch (error) {
    console.error('Error getting all users:', error);
    console.error('Error Stack:', error.stack);
    res.status(500).json({
        error: 'Internal Server Error: Failed to get users',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});

// --- Get user by ID (UID) ---
router.get('/:userId', checkAuth, async (req, res) => { 
  try {
    const requestedUserId = req.params.userId; // This is the Firebase Auth UID
    const authUserId = req.userData.userId; // User making the request

    // --- Authorization Check (Example: Allow self or admin) ---
    // const requestingUserDoc = await db.collection(USERS_COLLECTION).doc(authUserId).get();
    // const isAdmin = requestingUserDoc.exists && requestingUserDoc.data().role === 'admin';
    // if (requestedUserId !== authUserId && !isAdmin) {
    //    console.warn(`Unauthorized attempt to fetch profile for ${requestedUserId} by user: ${authUserId}`);
    //    return res.status(403).json({ error: 'Forbidden: You can only access your own profile or require admin privileges.' });
    // }
    // --- End Authorization Check ---

    console.log(`Fetching user profile for UID: ${requestedUserId}`);
    const doc = await db.collection(USERS_COLLECTION).doc(requestedUserId).get();

    if (!doc.exists) {
      console.log(`User not found for UID: ${requestedUserId}`);
      return res.status(404).json({ error: 'User not found' });
    } else {
      const data = doc.data();
      res.json({
        id: doc.id, // Document ID (UID)
        uid: data.uid,
        name: data.name,
        email: data.email,
        phoneNumber: data.phoneNumber,
        role: data.role,
        school: data.school,
        department: data.department,
        course: data.course,
        registrationNumber: data.registrationNumber,
        yearOfStudy: data.yearOfStudy,
        semester: data.semester,
        isVerified: data.isVerified,
        createdAt: formatTimestamp(data.createdAt),
       
      });
    }
  } catch (error) {
    console.error(`Error getting user ${req.params.userId}:`, error);
    console.error('Error Stack:', error.stack);
    res.status(500).json({
        error: 'Internal Server Error: Failed to get user',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});

module.exports = router;
