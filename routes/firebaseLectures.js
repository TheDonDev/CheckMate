// c:\Users\Test\FlutterProjects\checkmate\routes\firebaseLectures.js

const express = require('express');
const { db } = require('../firebase'); // Assuming firebase.js exports db initialized with admin SDK
const router = express.Router();
const checkAuth = require('../middleware/checkAuth'); // <--- MAKE SURE YOU HAVE THIS MIDDLEWARE

// --- Create a Lecture ---
// Apply checkAuth middleware first!
router.post('/', checkAuth, async (req, res) => {
  try {
    // --- Extract ALL fields sent by Flutter ---
    const {
      // lecturerId is taken from auth token below
      // lecturerName is taken from auth token/user doc below
      lecturerPhone,
      school,
      department,
      course,
      yearOfStudy, // Matches Flutter model/toApiJson
      semester,
      unitName,
      unitCode,
      lectureDate, // ISO String from Flutter
      startTime,   // ISO String from Flutter
      endTime,     // ISO String from Flutter
      venue,
    } = req.body;

    // --- Get authenticated user details from middleware ---
    // Ensure checkAuth middleware adds userId and email to req.userData
    if (!req.userData || !req.userData.userId || !req.userData.email) {
        console.error('Authentication data missing from request after checkAuth.');
        return res.status(401).json({ error: 'Authentication failed or data missing.' });
    }
    const authUserId = req.userData.userId;
    const authUserEmail = req.userData.email;

    // Fetch user details for role/verification/name
    const userDoc = await db.collection('users').doc(authUserId).get();
    const userData = userDoc.exists ? userDoc.data() : null;

    if (!userData) {
        console.error(`User document not found for authenticated user ID: ${authUserId}`);
        return res.status(404).json({ error: 'Authenticated user profile not found.' });
    }

    // --- Authorization Check with Bypass ---
    const isAllowedUser = authUserEmail === 'muhambe@au.ac.ke';
    // Ensure userData has 'role' and 'isVerified' fields
    const isVerifiedLecturer = userData.role === 'lecturer' && userData.isVerified === true;

    if (!isAllowedUser && !isVerifiedLecturer) {
      console.log(`Authorization failed for lecture creation: User ${authUserEmail} (Verified: ${userData.isVerified}, Role: ${userData.role})`);
      return res.status(403).json({ error: 'Forbidden: User not authorized or verified to create lectures.' });
    }

    if (isAllowedUser) {
        console.log(`DEV_BYPASS: Allowing user ${authUserEmail} to create lecture.`);
    }
    // --- End Authorization Check ---

    // --- Validate required fields from body ---
    const requiredFields = { school, department, course, yearOfStudy, semester, unitName, unitCode, lectureDate, startTime, endTime, venue };
    for (const [key, value] of Object.entries(requiredFields)) {
        if (!value) {
            console.error(`Validation Error: Missing required field '${key}'`);
            return res.status(400).json({ error: `Missing required lecture field: ${key}` });
        }
    }

    // --- Prepare data for Firestore ---
    const newLectureData = {
      lecturerId: authUserId, // Use authenticated user ID
      lecturerName: userData.name || 'N/A', // Use name from user document
      lecturerPhone: lecturerPhone || null,
      school,
      department,
      course,
      yearOfStudy, // Use correct field name
      semester,
      unitName,
      unitCode,
      // Convert ISO strings from Flutter to Firestore Timestamps
      // Firestore Admin SDK handles JS Date objects correctly
      lectureDate: new Date(lectureDate),
      startTime: new Date(startTime),
      endTime: new Date(endTime),
      venue,
      createdAt: new Date(), // Server-side timestamp
    };

    // Add the lecture document to Firestore using lowercase 'lectures'
    const docRef = await db.collection('lectures').add(newLectureData);
    console.log(`Lecture created successfully with ID: ${docRef.id}`);

    // Return the created lecture data including its new ID
    res.status(201).json({ id: docRef.id, ...newLectureData });

  } catch (error) {
    console.error('Error creating lecture:', error);
    // Check for specific error types if needed
    res.status(500).json({ error: 'Internal Server Error: Failed to create lecture' });
  }
});

// --- Get lectures for a specific lecturer --- ADDED ROUTE ---
// Apply checkAuth middleware
router.get('/lecturer/:lecturerId', checkAuth, async (req, res) => {
    try {
        const requestedLecturerId = req.params.lecturerId;
        const authUserId = req.userData.userId; // ID of the user making the request

        // Security: Ensure the authenticated user is requesting their own lectures
        if (requestedLecturerId !== authUserId) {
            console.log(`Forbidden attempt: User ${authUserId} tried to access lectures for ${requestedLecturerId}`);
            return res.status(403).json({ error: 'Forbidden: You can only access your own lectures.' });
        }

        const lecturesRef = db.collection('lectures'); // Use lowercase 'lectures'
        const snapshot = await lecturesRef
            .where('lecturerId', '==', requestedLecturerId)
            .orderBy('createdAt', 'desc') // Order by creation time, newest first
            .get();

        if (snapshot.empty) {
            console.log(`No lectures found for lecturer ${requestedLecturerId}`);
            return res.json([]); // Return empty array if none found
        }

        const lectures = [];
        snapshot.forEach((doc) => {
            // Convert Firestore Timestamps back to a format Flutter understands (e.g., ISO string)
            const data = doc.data();
            lectures.push({
                id: doc.id,
                ...data,
                // Ensure Timestamps are converted if necessary for the client
                lectureDate: data.lectureDate?.toDate ? data.lectureDate.toDate().toISOString() : null,
                startTime: data.startTime?.toDate ? data.startTime.toDate().toISOString() : null,
                endTime: data.endTime?.toDate ? data.endTime.toDate().toISOString() : null,
                createdAt: data.createdAt?.toDate ? data.createdAt.toDate().toISOString() : null,
             });
        });
        console.log(`Found ${lectures.length} lectures for lecturer ${requestedLecturerId}`);
        res.json(lectures);
    } catch (error) {
        console.error(`Error getting lectures for lecturer ${req.params.lecturerId}:`, error);
        res.status(500).json({ error: 'Internal Server Error: Failed to get lectures for lecturer' });
    }
});


// --- Get lectures for a student (Filtered) --- CORRECTED ---
// Apply checkAuth middleware (if students must be logged in)
router.get('/student', checkAuth, async (req, res) => {
  try {
    // Extract query parameters sent by Flutter
    // Use the field names matching the data saved in Firestore
    const { school, department, course, yearOfStudy, semester } = req.query;

    // --- Validate required filters ---
    if (!school || !department || !course || !yearOfStudy || !semester) {
        console.error('Validation Error: Missing required student filter parameters.');
        return res.status(400).json({ error: 'Missing required filter parameters (school, department, course, yearOfStudy, semester).' });
    }

    const lecturesRef = db.collection('lectures'); // Use lowercase 'lectures'
    let query = lecturesRef;

    // Apply filters using correct field names
    query = query.where('school', '==', school);
    query = query.where('department', '==', department);
    query = query.where('course', '==', course);
    query = query.where('yearOfStudy', '==', yearOfStudy); // Compare string value
    query = query.where('semester', '==', semester);     // Compare string value

    // Optional: Filter for lectures starting today or later
    // const today = new Date();
    // today.setHours(0, 0, 0, 0); // Start of day
    // query = query.where('lectureDate', '>=', today);

    // Order results
    query = query.orderBy('lectureDate', 'asc').orderBy('startTime', 'asc');

    const snapshot = await query.get();

    if (snapshot.empty) {
        console.log(`No student lectures found for filters: ${JSON.stringify(req.query)}`);
        return res.json([]);
    }

    const lectures = [];
    snapshot.forEach((doc) => {
      const data = doc.data();
      lectures.push({
          id: doc.id,
          ...data,
          // Convert Timestamps for client
          lectureDate: data.lectureDate?.toDate ? data.lectureDate.toDate().toISOString() : null,
          startTime: data.startTime?.toDate ? data.startTime.toDate().toISOString() : null,
          endTime: data.endTime?.toDate ? data.endTime.toDate().toISOString() : null,
          createdAt: data.createdAt?.toDate ? data.createdAt.toDate().toISOString() : null,
       });
    });
    console.log(`Found ${lectures.length} student lectures for filters: ${JSON.stringify(req.query)}`);
    res.json(lectures);
  } catch (error) {
    console.error('Error getting student lectures:', error);
    res.status(500).json({ error: 'Internal Server Error: Failed to get student lectures' });
  }
});

// --- Get all lectures (Keep as is, but ensure auth/admin check if needed) ---
router.get('/', checkAuth, async (req, res) => {
  // Add authorization check if only admins should see all lectures
  // const userDoc = await db.collection('users').doc(req.userData.userId).get();
  // const isAdmin = userDoc.exists && userDoc.data().role === 'admin';
  // if (!isAdmin) return res.status(403).json({ error: 'Forbidden' });

  try {
    const snapshot = await db.collection('lectures').orderBy('createdAt', 'desc').get(); // Use lowercase 'lectures'
    const lectures = [];
    snapshot.forEach((doc) => {
        const data = doc.data();
        lectures.push({
            id: doc.id,
            ...data,
            lectureDate: data.lectureDate?.toDate ? data.lectureDate.toDate().toISOString() : null,
            startTime: data.startTime?.toDate ? data.startTime.toDate().toISOString() : null,
            endTime: data.endTime?.toDate ? data.endTime.toDate().toISOString() : null,
            createdAt: data.createdAt?.toDate ? data.createdAt.toDate().toISOString() : null,
         });
    });
    res.json(lectures);
  } catch (error) {
    console.error('Error getting all lectures:', error);
    res.status(500).json({ error: 'Internal Server Error: Failed to get all lectures' });
  }
});

// --- Get lecture by ID (Keep as is) ---
router.get('/:lectureId', checkAuth, async (req, res) => {
  try {
    const lectureId = req.params.lectureId;
    const doc = await db.collection('lectures').doc(lectureId).get(); // Use lowercase 'lectures'
    if (!doc.exists) {
      res.status(404).json({ error: 'Lecture not found' });
    } else {
      const data = doc.data();
      res.json({
          id: doc.id,
          ...data,
          lectureDate: data.lectureDate?.toDate ? data.lectureDate.toDate().toISOString() : null,
          startTime: data.startTime?.toDate ? data.startTime.toDate().toISOString() : null,
          endTime: data.endTime?.toDate ? data.endTime.toDate().toISOString() : null,
          createdAt: data.createdAt?.toDate ? data.createdAt.toDate().toISOString() : null,
       });
    }
  } catch (error) {
    console.error('Error getting lecture by ID:', error);
    res.status(500).json({ error: 'Internal Server Error: Failed to get lecture' });
  }
});

module.exports = router;
