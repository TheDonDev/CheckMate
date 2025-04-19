// c:\Users\Test\FlutterProjects\checkmate\routes\firebaseLectures.js

const express = require('express');
// *** CORRECTED IMPORT: Ensure 'admin' is imported from your firebase setup ***
// This allows usage of admin.firestore.FieldValue.serverTimestamp()
const { db, admin } = require('../firebase'); // Assuming firebase.js exports both db and admin
const router = express.Router();
const checkAuth = require('../middleware/checkAuth'); // Ensure this path is correct and middleware works

// --- Constants ---
const LECTURES_COLLECTION = 'lectures'; // Standardize on lowercase
const USERS_COLLECTION = 'users';       // Standardize on lowercase

// --- Helper Function for Timestamp Conversion (Client -> Firestore) ---
// Converts ISO string or JS Date object to Firestore Timestamp compatible Date object
const parseDateForFirestore = (dateInput) => {
  if (!dateInput) return null;
  try {
    // Attempt to create a Date object. Handles ISO strings and existing Date objects.
    const date = new Date(dateInput);
    // Check if the date is valid
    if (isNaN(date.getTime())) {
      console.warn(`Invalid date input received: ${dateInput}`);
      return null; // Return null for invalid dates
    }
    return date; // Firestore Admin SDK handles JS Date objects correctly when writing
  } catch (e) {
    console.error(`Error parsing date input "${dateInput}":`, e);
    return null;
  }
};

// --- Helper Function for Timestamp Conversion (Firestore -> Client) ---
// Converts Firestore Timestamp object (or JS Date) to ISO string
const formatTimestampForClient = (timestamp) => {
  if (!timestamp) return null;
  // Check if it's a Firestore Timestamp object first (most common case when reading)
  if (timestamp && typeof timestamp.toDate === 'function') {
    return timestamp.toDate().toISOString();
  }
  // Check if it's already a JS Date object (e.g., from new Date() or parsing)
  if (timestamp instanceof Date && !isNaN(timestamp.getTime())) {
    return timestamp.toISOString();
  }
  // If it's already a string (potentially ISO), return as is (or validate)
  if (typeof timestamp === 'string') {
     // Basic check if it looks like an ISO string
     if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/.test(timestamp)) {
        return timestamp;
     }
  }
  console.warn(`Could not format timestamp for client:`, timestamp);
  return null; // Return null if formatting fails
};


// --- Create a Lecture ---
// Apply checkAuth middleware first!
router.post('/', checkAuth, async (req, res) => {
  try {
    // --- Get authenticated user details from middleware ---
    if (!req.userData || !req.userData.userId || !req.userData.email) {
        console.error('Authentication data missing from request after checkAuth.');
        return res.status(401).json({ error: 'Authentication failed or data missing.' });
    }
    const authUserId = req.userData.userId;
    const authUserEmail = req.userData.email;

    // --- Authorization Check ---
    const isBypassUser = authUserEmail === 'muhambe@au.ac.ke'; // Bypass user
    let userData = null;
    let userDoc = null; // Define userDoc here to potentially reuse

    if (!isBypassUser) {
        // If not the bypass user, fetch profile and check role/verification
        userDoc = await db.collection(USERS_COLLECTION).doc(authUserId).get();

        if (!userDoc.exists) {
            console.error(`Authorization failed: User document not found for authenticated user ID: ${authUserId}`);
            return res.status(403).json({ error: 'Forbidden: User profile not found, cannot authorize lecture creation.' });
        }

        userData = userDoc.data();
        // Ensure userData has 'role' and 'isVerified' fields from Firestore
        const isVerifiedLecturer = userData.role === 'lecturer' && userData.isVerified === true;

        if (!isVerifiedLecturer) {
            console.log(`Authorization failed for lecture creation: User ${authUserEmail} (Verified: ${userData.isVerified ?? 'N/A'}, Role: ${userData.role ?? 'N/A'})`);
            return res.status(403).json({ error: 'Forbidden: User not authorized or verified to create lectures.' });
        }
        console.log(`Authorization successful for verified lecturer: ${authUserEmail}`);

    } else {
        // Log bypass and fetch user data for name/phone fallback
        console.log(`Authorization bypass: Allowing user ${authUserEmail} to create lecture.`);
        userDoc = await db.collection(USERS_COLLECTION).doc(authUserId).get();
        if (userDoc.exists) {
            userData = userDoc.data();
        } else {
             console.warn(`Bypass user ${authUserEmail} document not found, proceeding with defaults.`);
             userData = {}; // Use empty object to avoid errors accessing properties later
        }
    }
    // --- End Authorization Check ---

    // Ensure userData is available (even if empty for bypass user not found)
    if (!userData) {
        console.error(`Critical Error: User data unavailable after authorization check for user ${authUserId}.`);
        return res.status(500).json({ error: 'Internal Server Error: Failed to retrieve user details.' });
    }

    // --- Extract ALL fields sent by Flutter ---
    const {
      lecturerPhone, // Optional phone number provided during creation
      school,
      department,
      course,
      yearOfStudy, // Matches Flutter model/toApiJson
      semester,
      unitName,
      unitCode,
      lectureDate, // Expected as ISO String from Flutter
      startTime,   // Expected as ISO String from Flutter
      endTime,     // Expected as ISO String from Flutter
      venue,
    } = req.body;

    // --- Validate required fields from body ---
    const requiredFields = { school, department, course, yearOfStudy, semester, unitName, unitCode, lectureDate, startTime, endTime, venue };
    for (const [key, value] of Object.entries(requiredFields)) {
        if (!value) {
            console.error(`Validation Error: Missing required field '${key}'`);
            return res.status(400).json({ error: `Missing required lecture field: ${key}` });
        }
    }

    // --- Parse Dates ---
    const parsedLectureDate = parseDateForFirestore(lectureDate);
    const parsedStartTime = parseDateForFirestore(startTime);
    const parsedEndTime = parseDateForFirestore(endTime);

    if (!parsedLectureDate || !parsedStartTime || !parsedEndTime) {
        console.error('Validation Error: Invalid date/time format received.');
        return res.status(400).json({ error: 'Invalid date or time format provided.' });
    }
    // Validate that endTime is after startTime
    if (parsedEndTime <= parsedStartTime) {
        console.error('Validation Error: End time must be after start time.');
        return res.status(400).json({ error: 'End time must be after start time.' });
    }

    // --- Prepare data for Firestore ---
    const newLectureData = {
      lecturerId: authUserId, // Use authenticated user ID
      lecturerName: userData.name || 'N/A', // Use name from user document
      lecturerPhone: lecturerPhone || userData.phoneNumber || null, // Use provided phone, fallback to profile, then null
      school,
      department,
      course,
      yearOfStudy, // Store as sent (e.g., "1st Year")
      semester,    // Store as sent (e.g., "Semester 1")
      unitName,
      unitCode,
      lectureDate: parsedLectureDate, // Store as JS Date object
      startTime: parsedStartTime,     // Store as JS Date object
      endTime: parsedEndTime,         // Store as JS Date object
      venue,
      // *** Use the now imported 'admin' object for server timestamp ***
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    // --- Add the lecture document to Firestore ---
    const docRef = await db.collection(LECTURES_COLLECTION).add(newLectureData);
    console.log(`Lecture created successfully with ID: ${docRef.id} by user ${authUserEmail}`);

    // --- Return the created lecture data including its new ID ---
    // Fetch the newly created doc to get server timestamp correctly formatted
    const createdDoc = await docRef.get();
    const createdData = createdDoc.data();

    res.status(201).json({
        id: createdDoc.id,
        ...createdData,
        // Format timestamps for client consistency
        lectureDate: formatTimestampForClient(createdData.lectureDate),
        startTime: formatTimestampForClient(createdData.startTime),
        endTime: formatTimestampForClient(createdData.endTime),
        createdAt: formatTimestampForClient(createdData.createdAt),
     });

  } catch (error) {
    // --- Improved Error Logging ---
    console.error('Error creating lecture:', error); // Log the full error object
    console.error('Error Stack:', error.stack); // Log the stack trace
    res.status(500).json({
        error: 'Internal Server Error: Failed to create lecture',
        // Provide error details only in non-production environments for security
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});

// --- Get lectures for a specific lecturer ---
// Apply checkAuth middleware
router.get('/lecturer/:lecturerId', checkAuth, async (req, res) => {
    try {
        const requestedLecturerId = req.params.lecturerId;
        const authUserId = req.userData.userId; // ID of the user making the request

        // --- Security: Ensure the authenticated user is requesting their own lectures ---
        if (requestedLecturerId !== authUserId) {
            console.log(`Forbidden attempt: User ${authUserId} tried to access lectures for ${requestedLecturerId}`);
            return res.status(403).json({ error: 'Forbidden: You can only access your own lectures.' });
        }

        console.log(`Fetching lectures for lecturerId: ${requestedLecturerId}`);

        const lecturesRef = db.collection(LECTURES_COLLECTION);
        // Query lectures where lecturerId matches and order by start time descending
        const snapshot = await lecturesRef
            .where('lecturerId', '==', requestedLecturerId)
            .orderBy('startTime', 'desc')
            .get();

        if (snapshot.empty) {
            console.log(`No lectures found for lecturer ${requestedLecturerId}`);
            return res.json([]); // Return empty array if none found
        }

        const lectures = [];
        snapshot.forEach((doc) => {
            const data = doc.data();
            lectures.push({
                id: doc.id,
                ...data,
                // Format timestamps for client
                lectureDate: formatTimestampForClient(data.lectureDate),
                startTime: formatTimestampForClient(data.startTime),
                endTime: formatTimestampForClient(data.endTime),
                createdAt: formatTimestampForClient(data.createdAt),
             });
        });
        console.log(`Found ${lectures.length} lectures for lecturer ${requestedLecturerId}`);
        res.json(lectures);
    } catch (error) {
        console.error(`Error getting lectures for lecturer ${req.params.lecturerId}:`, error);
        console.error('Error Stack:', error.stack);
        res.status(500).json({
            error: 'Internal Server Error: Failed to get lectures for lecturer',
            details: process.env.NODE_ENV !== 'production' ? error.message : undefined
        });
    }
});


// --- Get lectures for a student (Filtered based on student's profile) ---
// Apply checkAuth middleware
router.get('/student', checkAuth, async (req, res) => {
  try {
    const studentUserId = req.userData.userId; // Get student's ID from token

    // --- Fetch student's profile data ---
    const studentDoc = await db.collection(USERS_COLLECTION).doc(studentUserId).get();
    if (!studentDoc.exists) {
        console.error(`Student profile not found for authenticated user ID: ${studentUserId}`);
        return res.status(404).json({ error: 'Your user profile could not be found.' });
    }
    const studentData = studentDoc.data();

    // --- Extract filter criteria FROM STUDENT PROFILE ---
    const { school, department, course, yearOfStudy, semester } = studentData;

    // --- Validate required filters from profile ---
    if (!school || !department || !course || !yearOfStudy || !semester) {
        console.error(`Validation Error: Missing required profile fields for student ${studentUserId} to filter lectures.`);
        return res.status(400).json({ error: 'Your profile is missing required details (school, department, course, year, semester) to find lectures.' });
    }

    console.log(`Fetching lectures for student ${studentUserId} criteria:`, { school, department, course, yearOfStudy, semester });

    const lecturesRef = db.collection(LECTURES_COLLECTION);
    let query = lecturesRef;

    // --- Apply filters using student's profile data ---
    query = query.where('school', '==', school);
    query = query.where('department', '==', department);
    query = query.where('course', '==', course);
    query = query.where('yearOfStudy', '==', yearOfStudy);
    query = query.where('semester', '==', semester);

    // --- Filter for lectures starting today or later ---
    const today = new Date();
    today.setHours(0, 0, 0, 0); // Set to the beginning of the day UTC
    query = query.where('startTime', '>=', today); // Filter based on startTime being today or later

    // --- Order results ---
    // IMPORTANT: This composite query requires a Firestore index!
    query = query.orderBy('startTime', 'asc'); // Order by start time, earliest first

    const snapshot = await query.get();

    if (snapshot.empty) {
        console.log(`No upcoming student lectures found for student ${studentUserId} with filters: ${JSON.stringify({ school, department, course, yearOfStudy, semester })}`);
        return res.json([]); // Return empty array
    }

    const lectures = [];
    snapshot.forEach((doc) => {
      const data = doc.data();
      lectures.push({
          id: doc.id,
          ...data,
          // Format timestamps for client
          lectureDate: formatTimestampForClient(data.lectureDate),
          startTime: formatTimestampForClient(data.startTime),
          endTime: formatTimestampForClient(data.endTime),
          createdAt: formatTimestampForClient(data.createdAt),
       });
    });
    console.log(`Found ${lectures.length} upcoming student lectures for student ${studentUserId}`);
    res.json(lectures);
  } catch (error) {
    console.error(`Error getting student lectures for user ${req.userData?.userId}:`, error);
    console.error('Error Stack:', error.stack);

    // Check specifically for Firestore index errors
    if (error.code === 'failed-precondition' || (error.message && error.message.includes('index'))) {
        console.error("Firestore Index Missing: The query requires an index. Check the error details for a link to create it in the Firebase console.");
        return res.status(500).json({
            error: 'Internal Server Error: Failed to get student lectures due to missing database index.',
            details: 'A required Firestore index is missing. Please check backend logs or Firebase console for a creation link.'
        });
    }

    res.status(500).json({
        error: 'Internal Server Error: Failed to get student lectures',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});

// --- Get all lectures (Admin Only) ---
// SECURITY: This should be protected, e.g., only for admins.
router.get('/', checkAuth, async (req, res) => {
  // --- Authorization Check (Example: Only allow admins) ---
  try {
    const userDoc = await db.collection(USERS_COLLECTION).doc(req.userData.userId).get();
    if (!userDoc.exists || userDoc.data().role !== 'admin') {
        console.log(`Forbidden attempt: Non-admin user ${req.userData.userId} tried to access all lectures.`);
        return res.status(403).json({ error: 'Forbidden: Only administrators can access all lectures.' });
    }
  } catch (authError) {
      console.error('Error checking admin role:', authError);
      return res.status(500).json({ error: 'Internal Server Error during authorization check.' });
  }
  // --- End Authorization Check ---

  try {
    console.log('Fetching all lectures (admin access)');
    const snapshot = await db.collection(LECTURES_COLLECTION).orderBy('startTime', 'desc').get();
    const lectures = [];
    snapshot.forEach((doc) => {
        const data = doc.data();
        lectures.push({
            id: doc.id,
            ...data,
            // Format timestamps for client
            lectureDate: formatTimestampForClient(data.lectureDate),
            startTime: formatTimestampForClient(data.startTime),
            endTime: formatTimestampForClient(data.endTime),
            createdAt: formatTimestampForClient(data.createdAt),
         });
    });
    console.log(`Found ${lectures.length} total lectures (admin).`);
    res.json(lectures);
  } catch (error) {
    console.error('Error getting all lectures (admin):', error);
    console.error('Error Stack:', error.stack);
    res.status(500).json({
        error: 'Internal Server Error: Failed to get all lectures',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});

// --- Get lecture by ID ---
// Apply checkAuth if details should only be visible to logged-in users.
router.get('/:lectureId', checkAuth, async (req, res) => {
  try {
    const lectureId = req.params.lectureId;
    console.log(`Fetching lecture by ID: ${lectureId}`);

    const doc = await db.collection(LECTURES_COLLECTION).doc(lectureId).get();
    if (!doc.exists) {
      console.log(`Lecture not found for ID: ${lectureId}`);
      return res.status(404).json({ error: 'Lecture not found' });
    } else {
      const data = doc.data();
      console.log(`Found lecture for ID: ${lectureId}`);
      res.json({
          id: doc.id,
          ...data,
          // Format timestamps for client
          lectureDate: formatTimestampForClient(data.lectureDate),
          startTime: formatTimestampForClient(data.startTime),
          endTime: formatTimestampForClient(data.endTime),
          createdAt: formatTimestampForClient(data.createdAt),
       });
    }
  } catch (error) {
    console.error(`Error getting lecture by ID ${req.params.lectureId}:`, error);
    console.error('Error Stack:', error.stack);
    res.status(500).json({
        error: 'Internal Server Error: Failed to get lecture',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});

// --- Add PUT (Update) and DELETE endpoints if needed ---
// Example:
// router.put('/:lectureId', checkAuth, async (req, res) => { /* ... update logic ... */ });
// router.delete('/:lectureId', checkAuth, async (req, res) => { /* ... delete logic ... */ });

module.exports = router; // This line exports the router for use in your main server file
