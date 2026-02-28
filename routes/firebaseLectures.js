// c:\Users\Test\FlutterProjects\checkmate\routes\firebaseLectures.js

const express = require('express');
const { db, admin } = require('../firebase'); // Assuming firebase.js exports both db and admin
const router = express.Router();
const checkAuth = require('../middleware/checkAuth'); // Ensure this path is correct

// --- Load Environment Variables ---
require('dotenv').config(); // Load variables from .env file

// --- Constants ---
const LECTURES_COLLECTION = 'lectures';
const USERS_COLLECTION = 'users';
const ATTENDANCE_COLLECTION = 'attendance';

// --- Helper Function for Timestamp Conversion (Client -> Firestore) ---
const parseDateForFirestore = (dateInput) => {
  if (!dateInput) return null;
  try {
    const date = new Date(dateInput); // JS Date constructor handles ISO 8601 strings
    if (isNaN(date.getTime())) {
      console.warn(`[ParseHelper BE] Invalid date input received: ${dateInput}`);
      return null;
    }
    console.log(`[ParseHelper BE] Parsed input '${dateInput}' to JS Date: ${date.toISOString()} (UTC)`);
    return date; // Return JS Date object
  } catch (e) {
    console.error(`[ParseHelper BE] Error parsing date input "${dateInput}":`, e);
    return null;
  }
};

// --- Helper Function for Timestamp Conversion (Firestore -> Client) ---
const formatTimestampForClient = (timestamp) => {
  // ... (this helper remains the same) ...
  if (!timestamp) return null;
  let dateObj = null;
  if (timestamp && typeof timestamp.toDate === 'function') {
    dateObj = timestamp.toDate(); // Convert Firestore Timestamp to JS Date
  } else if (timestamp instanceof Date && !isNaN(timestamp.getTime())) {
    dateObj = timestamp; // Already a JS Date
  }

  if (dateObj) {
    const isoString = dateObj.toISOString(); // Convert to ISO string (UTC 'Z' format)
    console.log(`[FormatHelper BE] Formatting Timestamp/Date to ISO UTC string for client: ${isoString}`);
    return isoString;
  }

  if (typeof timestamp === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/.test(timestamp)) {
     console.log(`[FormatHelper BE] Timestamp was already string, returning as is: ${timestamp}`);
     return timestamp;
  }
  console.warn(`[FormatHelper BE] Could not format timestamp for client:`, timestamp);
  return null;
};

// --- Helper Function for Formatting Date/Time for SMS ---
const formatDateTimeForSMS = (dateObj) => {
    // ... (this helper remains the same) ...
    if (!(dateObj instanceof Date) || isNaN(dateObj.getTime())) {
        return "Invalid Date";
    }
    return dateObj.toLocaleString('en-KE', {
        weekday: 'short', month: 'short', day: 'numeric',
        hour: 'numeric', minute: '2-digit', hour12: true,
        timeZone: 'Africa/Nairobi'
    });
};

// --- Helper Function for Consistent String Formatting (Trim + Uppercase) ---
const formatStringForQuery = (str) => {
    // ... (this helper remains the same) ...
    if (str && typeof str === 'string') {
        return str.trim().toUpperCase();
    }
    return str;
};


// --- Create a Lecture (with SMS Notification) ---
router.post('/', checkAuth, async (req, res) => {
  // --- *** ADDED LOG: Request Entry *** ---
  console.log(`[POST /lectures] Request received at ${new Date().toISOString()}`);
  let createdLectureId = null;

  try {
    // --- Authentication & Authorization ---
    console.log('[POST /lectures] Running Authentication/Authorization check...');
    if (!req.userData || !req.userData.userId || !req.userData.email) {
        console.error('[POST /lectures] Auth Error: Authentication data missing from request after checkAuth.');
        return res.status(401).json({ error: 'Authentication failed or data missing.' });
    }
    const authUserId = req.userData.userId;
    const authUserEmail = req.userData.email;
    console.log(`[POST /lectures] Authenticated User: ${authUserEmail} (ID: ${authUserId})`);

    const isBypassUser = authUserEmail === 'muhambe@au.ac.ke'; // configurable
    let userData = null;
    let userDoc = null;

    if (!isBypassUser) {
        console.log(`[POST /lectures] Fetching user document for authorization: ${authUserId}`);
        userDoc = await db.collection(USERS_COLLECTION).doc(authUserId).get();
        if (!userDoc.exists) {
            console.error(`[POST /lectures] Auth Error: User document not found for ID: ${authUserId}`);
            return res.status(403).json({ error: 'Forbidden: User profile not found, cannot authorize lecture creation.' });
        }
        userData = userDoc.data();
        const isVerifiedLecturer = userData.role === 'lecturer' && userData.isVerified === true;
        if (!isVerifiedLecturer) {
            console.warn(`[POST /lectures] Auth Failed: User ${authUserEmail} is not a verified lecturer (Verified: ${userData.isVerified ?? 'N/A'}, Role: ${userData.role ?? 'N/A'})`);
            return res.status(403).json({ error: 'Forbidden: User not authorized or verified to create lectures.' });
        }
        console.log(`[POST /lectures] Authorization successful for verified lecturer: ${authUserEmail}`);
    } else {
        console.log(`[POST /lectures] Authorization bypass for user: ${authUserEmail}`);
        userDoc = await db.collection(USERS_COLLECTION).doc(authUserId).get();
        userData = userDoc.exists ? userDoc.data() : {};
        if (!userDoc.exists) console.warn(`[POST /lectures] Bypass user ${authUserEmail} document not found, proceeding with defaults.`);
    }
    if (!userData) { // Should ideally not happen if checks above are correct
        console.error(`[POST /lectures] Critical Error: User data unavailable after authorization check for user ${authUserId}.`);
        return res.status(500).json({ error: 'Internal Server Error: Failed to retrieve user details.' });
    }
    // --- End Auth ---

    // --- Extract & Validate Request Body ---
    // --- *** ADDED LOG: Request Body *** ---
    console.log('[POST /lectures] Request Body Received:', JSON.stringify(req.body, null, 2)); // Log the parsed body

    const {
      lecturerPhone, school, department, course, yearOfStudy, semester,
      unitName, unitCode, lectureDate, startTime, endTime, venue,
      onlineLink
    } = req.body;

    console.log('[POST /lectures] Validating required fields...');
    const requiredFields = { school, department, course, yearOfStudy, semester, unitName, unitCode, lectureDate, startTime, endTime, venue };
    for (const [key, value] of Object.entries(requiredFields)) {
        // Check for null, undefined, or empty string after trimming
        const isMissing = value == null || (typeof value === 'string' && value.trim() === '');
        if (isMissing) {
            console.error(`[POST /lectures] Validation Error: Missing or empty required field '${key}'`);
            return res.status(400).json({ error: `Missing required lecture field: ${key}` });
        }
    }
    console.log('[POST /lectures] Required fields validation passed.');

    console.log('[POST /lectures] Parsing date/time fields...');
    // Use the helper which logs internally
    const parsedLectureDate = parseDateForFirestore(lectureDate); // Expects ISO string from Flutter
    const parsedStartTime = parseDateForFirestore(startTime);     // Expects ISO string from Flutter
    const parsedEndTime = parseDateForFirestore(endTime);         // Expects ISO string from Flutter

    if (!parsedLectureDate || !parsedStartTime || !parsedEndTime) {
        console.error('[POST /lectures] Validation Error: Invalid date/time format received after parsing.');
        return res.status(400).json({ error: 'Invalid date or time format provided.' });
    }
    if (parsedEndTime <= parsedStartTime) {
        console.error('[POST /lectures] Validation Error: End time must be after start time.');
        return res.status(400).json({ error: 'End time must be after start time.' });
    }
    console.log('[POST /lectures] Date/time parsing and validation passed.');

    console.log('[POST /lectures] Validating venue and online link...');
    let finalOnlineLink = null;

    // If an onlineLink is provided in the request body, validate it.
    // The frontend logic ensures this is only sent when the venue is 'ONLINE'.
    if (onlineLink && typeof onlineLink === 'string' && onlineLink.trim().length > 0) {
        try {
            const trimmedLink = onlineLink.trim();
            new URL(trimmedLink); // This will throw an error if the URL is invalid
            finalOnlineLink = trimmedLink;
            console.log('[POST /lectures] Online link validated successfully.');
        } catch (_) {
            console.error('[POST /lectures] Validation Error: Invalid URL format for online link:', onlineLink);
            return res.status(400).json({ error: 'Please provide a valid URL for the online lecture link (e.g., https://...).' });
        }
    } else {
        console.log(`[POST /lectures] No onlineLink provided in the request, or it was empty.`);
    }
    console.log('[POST /lectures] Venue and online link validation passed.');
    // --- End Validation ---

    // --- Prepare Lecture Data for Firestore ---
    const newLectureData = {
      lecturerId: authUserId,
      lecturerName: userData.name || 'N/A', // Use fetched user data
      lecturerPhone: lecturerPhone?.trim() || userData.phoneNumber || null, // Prefer provided, fallback to profile
      school: school, // Use data from request body
      department: department, // Use data from request body
      course: course, // Use data from request body
      yearOfStudy: yearOfStudy,
      semester: semester,
      unitName: unitName.trim(),
      unitCode: unitCode.trim().toUpperCase(),
      lectureDate: parsedLectureDate, // Use parsed JS Date
      startTime: parsedStartTime,     // Use parsed JS Date
      endTime: parsedEndTime,         // Use parsed JS Date
      venue: venue.trim(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      onlineLink: finalOnlineLink,
      reminderSent: false, // Initialize reminder flag
    };
    // --- *** ADDED LOG: Data before Firestore *** ---
    console.log('[POST /lectures] Prepared lecture data for Firestore:', JSON.stringify(newLectureData, null, 2));
    // --- End Prepare Data ---

    // --- 1. Add the lecture document to Firestore ---
    console.log(`[POST /lectures] Adding lecture document to Firestore collection '${LECTURES_COLLECTION}'...`);
    const docRef = await db.collection(LECTURES_COLLECTION).add(newLectureData);
    createdLectureId = docRef.id;
    console.log(`[POST /lectures] Lecture created successfully in Firestore with ID: ${createdLectureId}`);

    // Fetch the newly created document to get all data including server timestamp
    console.log(`[POST /lectures] Fetching created document ${createdLectureId} for response and SMS...`);
    const createdDoc = await docRef.get();
    const createdData = createdDoc.data();
    if (!createdData) {
        // This is unlikely but good to handle
        console.error(`[POST /lectures] CRITICAL ERROR: Failed to fetch created lecture data immediately after creation (ID: ${createdLectureId}). SMS may fail.`);
        // Proceed, but SMS might not work correctly.
    } else {
        console.log(`[POST /lectures] Successfully fetched created document data.`);
    }

    // --- 3. Return the success response to the client ---
    // Use fetched data (createdData) if available, format timestamps for client
    const responseData = createdData ? {
        id: createdDoc.id,
        ...createdData,
        // Use formatTimestampForClient which logs internally
        lectureDate: formatTimestampForClient(createdData.lectureDate),
        startTime: formatTimestampForClient(createdData.startTime),
        endTime: formatTimestampForClient(createdData.endTime),
        createdAt: formatTimestampForClient(createdData.createdAt),
     } : { id: createdLectureId, message: "Lecture created, but failed to fetch full data for response." }; // Fallback if fetch failed

    console.log(`[POST /lectures] Sending 201 Created response for lecture ${createdLectureId}.`);
    res.status(201).json(responseData);

  } catch (error) {
    // --- *** Enhanced Error Logging *** ---
    console.error(`[POST /lectures] UNHANDLED ERROR in route handler (Lecture ID if created: ${createdLectureId || 'N/A'}):`, error);
    console.error('[POST /lectures] Error Stack:', error.stack); // Log the full stack trace
    res.status(500).json({
        error: 'Internal Server Error: Failed to create lecture or process notifications',
        // Provide more details in non-production environments
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});

// --- Get lectures for a specific lecturer ---
router.get('/lecturer/:lecturerId', checkAuth, async (req, res) => {
    // ... (GET /lecturer/:lecturerId code remains the same, logging is already decent) ...
    try {
        const requestedLecturerId = req.params.lecturerId;
        const authUserId = req.userData.userId;
        const authUserEmail = req.userData.email; // Get email for logging

        console.log(`[GET /lecturer/${requestedLecturerId}] Request received from user ${authUserEmail} (ID: ${authUserId})`);

        if (requestedLecturerId !== authUserId) {
            console.warn(`[GET /lecturer/${requestedLecturerId}] Forbidden attempt: User ${authUserId} tried to access lectures for ${requestedLecturerId}`);
            return res.status(403).json({ error: 'Forbidden: You can only access your own lectures.' });
        }

        console.log(`[GET /lecturer/${requestedLecturerId}] Fetching lectures from Firestore...`);
        const lecturesRef = db.collection(LECTURES_COLLECTION);
        const snapshot = await lecturesRef
            .where('lecturerId', '==', requestedLecturerId)
            .orderBy('startTime', 'desc') // Most recent first
            .get();

        if (snapshot.empty) {
            console.log(`[GET /lecturer/${requestedLecturerId}] No lectures found.`);
            return res.json([]); // Return empty array, not an error
        }

        const lectures = snapshot.docs.map(doc => {
            const data = doc.data();
            // Use formatTimestampForClient which logs internally
            return {
                id: doc.id,
                ...data,
                lectureDate: formatTimestampForClient(data.lectureDate),
                startTime: formatTimestampForClient(data.startTime),
                endTime: formatTimestampForClient(data.endTime),
                createdAt: formatTimestampForClient(data.createdAt),
            };
        });

        console.log(`[GET /lecturer/${requestedLecturerId}] Found ${lectures.length} lectures. Sending response.`);
        res.json(lectures);
    } catch (error) {
        console.error(`[GET /lecturer/${req.params.lecturerId}] Error getting lectures:`, error);
        res.status(500).json({
            error: 'Internal Server Error: Failed to get lectures for lecturer',
            details: process.env.NODE_ENV !== 'production' ? error.message : undefined
        });
    }
});

// --- Get lectures for a student ---
router.get('/student', checkAuth, async (req, res) => {
    // ... (GET /student code remains the same, logging is already decent) ...
    try {
        const studentUserId = req.userData.userId;
        const authUserEmail = req.userData.email;
        console.log(`[GET /student] Request received from user ${authUserEmail} (ID: ${studentUserId})`);
        console.log(`[GET /student] Query Params:`, req.query);

        const studentDoc = await db.collection(USERS_COLLECTION).doc(studentUserId).get();
        if (!studentDoc.exists) {
            console.error(`[GET /student] User profile not found for authenticated user ID: ${studentUserId}`);
            return res.status(404).json({ error: 'Your user profile could not be found.' });
        }
        const studentData = studentDoc.data();
        const profileSchool = formatStringForQuery(studentData.school);
        const profileDepartment = formatStringForQuery(studentData.department);
        const profileCourse = formatStringForQuery(studentData.course);
        const profileRole = studentData.role;
        const profileIsVerified = studentData.isVerified;

        if (profileRole !== 'student') {
             console.error(`[GET /student] User ${studentUserId} is not a student (role: ${profileRole}). Cannot fetch student lectures.`);
             return res.status(403).json({ error: 'Forbidden: Only students can access this lecture list.' });
        }
        if (!profileSchool || !profileDepartment || !profileCourse) {
            console.error(`[GET /student] Validation Error: Student ${studentUserId} profile is missing required fields (school, dept, course).`);
            return res.status(400).json({ error: 'Your profile is missing required details (school, department, course) needed to find lectures.' });
        }
         if (!profileIsVerified) {
             console.warn(`[GET /student] Student ${studentUserId} is not verified. They may not see all lectures.`);
             // Allow unverified students to see lectures, but log it.
        }

        const { school: requestedSchool, department: requestedDepartment, course: requestedCourse, year: requestedYear, semester: requestedSemester } = req.query;
        if (!requestedSchool || !requestedDepartment || !requestedCourse || !requestedYear || !requestedSemester) {
            console.error(`[GET /student] Validation Error: Missing required query parameters (school, dept, course, year, semester) for student ${studentUserId}.`);
            return res.status(400).json({ error: 'Required filter parameters (school, department, course, year, semester) were not provided in the request.' });
        }

        const querySchool = formatStringForQuery(requestedSchool);
        const queryDepartment = formatStringForQuery(requestedDepartment);
        const queryCourse = formatStringForQuery(requestedCourse);

        // Allow filtering only based on the student's own profile details
        if (profileSchool !== querySchool || profileDepartment !== queryDepartment || profileCourse !== queryCourse) {
            console.error(`[GET /student] Forbidden: Student ${studentUserId} requested filters (${querySchool}/${queryDepartment}/${queryCourse}) that do not match their profile (${profileSchool}/${profileDepartment}/${profileCourse}).`);
            return res.status(403).json({ error: 'Forbidden: You can only filter lectures for your registered school, department, and course.' });
        }

        const queryYear = requestedYear; // Use ID directly
        const querySemester = requestedSemester; // Use ID directly

        console.log(`[GET /student] Firestore Query Parameters for student ${studentUserId}:`);
        console.log(`  school: '${requestedSchool}', department: '${requestedDepartment}', course: '${requestedCourse}', yearOfStudy: '${queryYear}', semester: '${querySemester}'`);

        const lecturesRef = db.collection(LECTURES_COLLECTION);
        let query = lecturesRef
            .where('school', '==', requestedSchool) // Query by ID
            .where('department', '==', requestedDepartment) // Query by ID
            .where('course', '==', requestedCourse) // Query by ID
            .where('yearOfStudy', '==', queryYear)
            .where('semester', '==', querySemester);

        // Filter for lectures from the start of today onwards.
        // This correctly includes lectures happening today, regardless of server timezone.
        const today = new Date();
        today.setHours(0, 0, 0, 0); // Set to midnight start of today
        // Use 'lectureDate' for the query, as 'startTime' includes time and can be tricky with timezones.
        query = query.where('lectureDate', '>=', today);
        console.log(`  lectureDate: >= ${today.toISOString()}`);

        query = query.orderBy('startTime', 'asc'); // Order upcoming lectures chronologically
        console.log(`  orderBy: startTime asc`);

        console.log("[GET /student] Executing Firestore query...");
        const snapshot = await query.get();
        console.log(`[GET /student] Firestore query executed. Found ${snapshot.size} documents.`);

        if (snapshot.empty) {
            console.log(`[GET /student] No upcoming student lectures found for student ${studentUserId} with the specified filters.`);
            return res.json([]);
        }

        const lectures = snapshot.docs.map(doc => {
            const data = doc.data();
            // Use formatTimestampForClient which logs internally
            return {
                id: doc.id,
                ...data,
                lectureDate: formatTimestampForClient(data.lectureDate),
                startTime: formatTimestampForClient(data.startTime),
                endTime: formatTimestampForClient(data.endTime),
                createdAt: formatTimestampForClient(data.createdAt),
            };
        });

        console.log(`[GET /student] Successfully processed ${lectures.length} upcoming student lectures for student ${studentUserId}. Sending response.`);
        res.json(lectures);

      } catch (error) {
        console.error(`[GET /student] Error getting student lectures for user ${req.userData?.userId}:`, error);
        console.error('[GET /student] Error Stack:', error.stack);

        if (error.code === 'failed-precondition' || (error.message && error.message.includes('index'))) {
            console.error("[GET /student] Firestore Index Missing: The query requires an index. Check the error details for a link to create it in the Firebase console.");
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

// --- Get lectures for a student's dashboard (based on their attendance records) ---
router.get('/student/dashboard/:studentId', checkAuth, async (req, res) => {
    const requestedStudentId = req.params.studentId;
    const authUserId = req.userData.userId;
    const authUserEmail = req.userData.email;

    console.log(`[GET /student/dashboard/${requestedStudentId}] Request received from user ${authUserEmail} (ID: ${authUserId})`);

    // Authorization: Ensure the authenticated user is requesting their own data
    if (requestedStudentId !== authUserId) {
        console.warn(`[GET /student/dashboard/${requestedStudentId}] Forbidden attempt: User ${authUserId} tried to access dashboard for ${requestedStudentId}`);
        return res.status(403).json({ error: 'Forbidden: You can only access your own lecture dashboard.' });
    }

    try {
        // 1. Find all attendance records for the student
        console.log(`[GET /student/dashboard/${requestedStudentId}] Querying attendance records for user ID: ${requestedStudentId}`);
        const attendanceQuery = db.collection(ATTENDANCE_COLLECTION).where('userId', '==', requestedStudentId);
        const attendanceSnapshot = await attendanceQuery.get();

        if (attendanceSnapshot.empty) {
            console.log(`[GET /student/dashboard/${requestedStudentId}] No attendance records found for this student. Returning empty list.`);
            return res.json([]);
        }

        // 2. Extract unique lecture IDs from the attendance records
        const lectureIds = [...new Set(attendanceSnapshot.docs.map(doc => doc.data().lectureId))];
        console.log(`[GET /student/dashboard/${requestedStudentId}] Found ${lectureIds.length} unique lecture IDs from attendance records.`);

        if (lectureIds.length === 0) {
            return res.json([]);
        }

        // 3. Fetch all lecture documents corresponding to those IDs
        // Firestore 'in' query is limited to 30 items per query.
        // We need to chunk the requests if there are more than 30 lecture IDs.
        const lecturePromises = [];
        for (let i = 0; i < lectureIds.length; i += 30) {
            const chunk = lectureIds.slice(i, i + 30);
            console.log(`[GET /student/dashboard/${requestedStudentId}] Fetching chunk of ${chunk.length} lectures...`);
            lecturePromises.push(
                db.collection(LECTURES_COLLECTION).where(admin.firestore.FieldPath.documentId(), 'in', chunk).get()
            );
        }

        const lectureSnapshots = await Promise.all(lecturePromises);

        const lectures = [];
        lectureSnapshots.forEach(snapshot => {
            snapshot.docs.forEach(doc => {
                const data = doc.data();
                lectures.push({
                    id: doc.id,
                    ...data,
                    lectureDate: formatTimestampForClient(data.lectureDate),
                    startTime: formatTimestampForClient(data.startTime),
                    endTime: formatTimestampForClient(data.endTime),
                    createdAt: formatTimestampForClient(data.createdAt),
                });
            });
        });

        console.log(`[GET /student/dashboard/${requestedStudentId}] Successfully fetched ${lectures.length} lectures. Sending response.`);
        res.json(lectures);

    } catch (error) {
        console.error(`[GET /student/dashboard/${requestedStudentId}] Error getting student dashboard lectures:`, error);
        console.error(`[GET /student/dashboard/${requestedStudentId}] Error Stack:`, error.stack);
        res.status(500).json({
            error: 'Internal Server Error: Failed to get student dashboard lectures',
            details: process.env.NODE_ENV !== 'production' ? error.message : undefined
        });
    }
});


// --- Get all lectures (Admin Only) ---
router.get('/', checkAuth, async (req, res) => {
    // ... (GET / code remains the same, logging is already decent) ...
    try {
        const authUserId = req.userData.userId;
        const authUserEmail = req.userData.email;
        console.log(`[GET / (Admin)] Request received from user ${authUserEmail} (ID: ${authUserId})`);

        const userDoc = await db.collection(USERS_COLLECTION).doc(authUserId).get();
        if (!userDoc.exists || userDoc.data().role !== 'admin') {
            console.warn(`[GET / (Admin)] Forbidden attempt: Non-admin user ${authUserId} (${authUserEmail}) tried to access all lectures.`);
            return res.status(403).json({ error: 'Forbidden: Only administrators can access all lectures.' });
        }
        console.log(`[GET / (Admin)] Admin access granted for user ${authUserEmail}.`);
      } catch (authError) {
          console.error('[GET / (Admin)] Error checking admin role:', authError);
          return res.status(500).json({ error: 'Internal Server Error during authorization check.' });
      }

      try {
        console.log('[GET / (Admin)] Fetching all lectures from Firestore, ordered by startTime desc...');
        const snapshot = await db.collection(LECTURES_COLLECTION).orderBy('startTime', 'desc').get();
        const lectures = snapshot.docs.map(doc => {
            const data = doc.data();
            // Use formatTimestampForClient which logs internally
            return {
                id: doc.id,
                ...data,
                lectureDate: formatTimestampForClient(data.lectureDate),
                startTime: formatTimestampForClient(data.startTime),
                endTime: formatTimestampForClient(data.endTime),
                createdAt: formatTimestampForClient(data.createdAt),
            };
        });
        console.log(`[GET / (Admin)] Found ${lectures.length} total lectures. Sending response.`);
        res.json(lectures);
      } catch (error) {
        console.error('[GET / (Admin)] Error getting all lectures:', error);
        res.status(500).json({
            error: 'Internal Server Error: Failed to get all lectures',
            details: process.env.NODE_ENV !== 'production' ? error.message : undefined
        });
      }
});

// --- Get lecture by ID ---
router.get('/:lectureId', checkAuth, async (req, res) => {
    // ... (GET /:lectureId code remains the same, logging is already decent) ...
    try {
        const lectureId = req.params.lectureId;
        const authUserEmail = req.userData.email;
        console.log(`[GET /${lectureId}] Request received from user ${authUserEmail}`);

        const doc = await db.collection(LECTURES_COLLECTION).doc(lectureId).get();
        if (!doc.exists) {
          console.log(`[GET /${lectureId}] Lecture not found.`);
          return res.status(404).json({ error: 'Lecture not found' });
        } else {
          const data = doc.data();
          console.log(`[GET /${lectureId}] Found lecture. Sending response.`);
          // Use formatTimestampForClient which logs internally
          res.json({
              id: doc.id,
              ...data,
              lectureDate: formatTimestampForClient(data.lectureDate),
              startTime: formatTimestampForClient(data.startTime),
              endTime: formatTimestampForClient(data.endTime),
              createdAt: formatTimestampForClient(data.createdAt),
           });
        }
      } catch (error) {
        console.error(`[GET /${req.params.lectureId}] Error getting lecture by ID:`, error);
        res.status(500).json({
            error: 'Internal Server Error: Failed to get lecture',
            details: process.env.NODE_ENV !== 'production' ? error.message : undefined
        });
      }
});

// --- Update Lecture (PUT /:lectureId) ---
router.put('/:lectureId', checkAuth, async (req, res) => {
    // ... (PUT /:lectureId code remains the same, logging is already decent) ...
    const lectureId = req.params.lectureId;
    const authenticatedUserId = req.userData.userId;
    const authUserEmail = req.userData.email;
    const updateData = req.body;

    if (!lectureId) {
        console.log('[PUT /:lectureId] Update request failed: Missing lectureId parameter.');
        return res.status(400).json({ message: 'Lecture ID is required.' });
    }

    console.log(`[PUT /${lectureId}] Attempting update by user ${authUserEmail} (ID: ${authenticatedUserId})`);
    console.log(`[PUT /${lectureId}] Received update data:`, JSON.stringify(updateData, null, 2));

    try {
        const lectureRef = db.collection(LECTURES_COLLECTION).doc(lectureId);
        const lectureDoc = await lectureRef.get();

        if (!lectureDoc.exists) {
            console.log(`[PUT /${lectureId}] Update failed: Lecture not found.`);
            return res.status(404).json({ message: 'Lecture not found.' });
        }

        const lectureData = lectureDoc.data(); // Original lecture data

        // --- AUTHORIZATION CHECK ---
        console.log(`[PUT /${lectureId}] Checking authorization...`);
        const userRoleDoc = await db.collection(USERS_COLLECTION).doc(authenticatedUserId).get();
        const userRole = userRoleDoc.exists ? userRoleDoc.data().role : null;
        const isAdmin = userRole === 'admin';

        if (lectureData.lecturerId !== authenticatedUserId && !isAdmin) {
            console.warn(`[PUT /${lectureId}] Unauthorized update attempt: User ${authenticatedUserId} (Role: ${userRole || 'N/A'}) tried to update lecture owned by ${lectureData.lecturerId}`);
            return res.status(403).json({ message: 'Forbidden: You do not have permission to update this lecture.' });
        }
        console.log(`[PUT /${lectureId}] Authorization successful: User ${authenticatedUserId} (Role: ${userRole || 'N/A'}).`);
        // --- END AUTHORIZATION CHECK ---

        // --- VALIDATE AND PREPARE UPDATE DATA ---
        console.log(`[PUT /${lectureId}] Validating and preparing update fields...`);
        const allowedUpdates = {};
        const editableFields = ['unitName', 'unitCode', 'school', 'department', 'course', 'venue', 'yearOfStudy', 'semester', 'lectureDate', 'startTime', 'endTime', 'onlineLink'];

        for (const field of editableFields) {
            if (updateData.hasOwnProperty(field)) {
                if (field === 'lectureDate' || field === 'startTime' || field === 'endTime') {
                    // Use the helper which handles ISO strings and logs internally
                    const parsedDate = parseDateForFirestore(updateData[field]);
                    if (!parsedDate && updateData[field] != null) { // Check if parsing failed but input wasn't null
                         console.error(`[PUT /${lectureId}] Validation Error: Invalid date format for ${field}: ${updateData[field]}`);
                         return res.status(400).json({ error: `Invalid date format provided for ${field}. Expected ISO string.` });
                    }
                    allowedUpdates[field] = parsedDate; // Store the parsed JS Date or null
                    if (field === 'startTime') allowedUpdates.reminderSent = false; // Reset reminder if time changes
                }
                else if (field === 'onlineLink') {
                    allowedUpdates[field] = updateData[field]?.trim() || null; // Trim or set to null
                }
                else if (['unitCode'].includes(field)) {
                     allowedUpdates[field] = formatStringForQuery(updateData[field]); // Trim and uppercase
                }
                else if (typeof updateData[field] === 'string') {
                    allowedUpdates[field] = updateData[field].trim(); // Trim other strings
                }
                 else {
                     allowedUpdates[field] = updateData[field]; // Keep other types as is (e.g., numbers, booleans if added later)
                 }
            }
        }

        // Validate onlineLink based on FINAL venue (original or updated)
        const finalOnlineLink = allowedUpdates.hasOwnProperty('onlineLink') ? allowedUpdates.onlineLink : lectureData.onlineLink;

        // If an onlineLink is provided in the update payload, validate it.
        // The frontend logic ensures this is only sent when the venue is 'ONLINE'.
        if (allowedUpdates.hasOwnProperty('onlineLink')) {
            if (allowedUpdates.onlineLink && typeof allowedUpdates.onlineLink === 'string' && allowedUpdates.onlineLink.trim().length > 0) {
                try {
                    const trimmedLink = allowedUpdates.onlineLink.trim();
                    new URL(trimmedLink); // This will throw an error if the URL is invalid
                    allowedUpdates.onlineLink = trimmedLink; // Ensure it's the trimmed version
                    console.log(`[PUT /${lectureId}] Online link validated successfully.`);
                } catch (_) {
                    console.error(`[PUT /${lectureId}] Validation Error: Invalid URL format for online link: ${allowedUpdates.onlineLink}`);
                    return res.status(400).json({ error: 'Please provide a valid URL for the online lecture link.' });
                }
            } else {
                // If the link is sent as empty string or null, ensure it's saved as null.
                allowedUpdates.onlineLink = null;
                console.log(`[PUT /${lectureId}] onlineLink was provided but empty, setting to null.`);
            }
        }


        // Validate start/end time order using final values
        const finalStartTime = allowedUpdates.hasOwnProperty('startTime') ? allowedUpdates.startTime : lectureData.startTime?.toDate();
        const finalEndTime = allowedUpdates.hasOwnProperty('endTime') ? allowedUpdates.endTime : lectureData.endTime?.toDate();

        if (finalStartTime instanceof Date && finalEndTime instanceof Date && finalEndTime <= finalStartTime) {
             console.error(`[PUT /${lectureId}] Validation Error: End time must be after start time.`);
             return res.status(400).json({ error: 'End time must be after start time.' });
        }
        console.log(`[PUT /${lectureId}] Update fields validation passed.`);
        // --- END VALIDATION ---


        // --- Perform Update in Firestore ---
        if (Object.keys(allowedUpdates).length > 0) {
            console.log(`[PUT /${lectureId}] Applying updates to Firestore:`, JSON.stringify(allowedUpdates, null, 2));
            await lectureRef.update(allowedUpdates);
            console.log(`[PUT /${lectureId}] Lecture updated successfully in Firestore with fields:`, Object.keys(allowedUpdates));
        } else {
            console.log(`[PUT /${lectureId}] No valid fields provided for update. No changes made to Firestore.`);
        }
        // --- End Firestore Update ---

        // --- Fetch Updated Data ---
        console.log(`[PUT /${lectureId}] Fetching updated document data...`);
        const updatedDoc = await lectureRef.get();
        const updatedLecture = updatedDoc.data();
        if (!updatedLecture) {
             console.error(`[PUT /${lectureId}] CRITICAL ERROR: Failed to fetch updated lecture data after update. SMS may use stale data or fail.`);
        } else {
             console.log(`[PUT /${lectureId}] Fetched updated lecture data successfully.`);
        }
        // --- End Fetch Updated Data ---


        // --- Return Success Response ---
        const responseData = updatedLecture ? {
            id: updatedDoc.id,
            ...updatedLecture,
            // Use formatTimestampForClient which logs internally
            lectureDate: formatTimestampForClient(updatedLecture.lectureDate),
            startTime: formatTimestampForClient(updatedLecture.startTime),
            endTime: formatTimestampForClient(updatedLecture.endTime),
            createdAt: formatTimestampForClient(updatedLecture.createdAt),
        } : { id: lectureId, message: "Lecture updated, but failed to fetch full data for response." };

        console.log(`[PUT /${lectureId}] Sending 200 OK response.`);
        res.status(200).json(responseData);

    } catch (error) {
        console.error(`[PUT /${lectureId}] UNHANDLED ERROR updating lecture:`, error);
        console.error('[PUT /:lectureId] Error Stack:', error.stack);
        res.status(500).json({
            message: 'Internal server error while updating lecture.',
            details: process.env.NODE_ENV !== 'production' ? error.message : undefined
        });
    }
});


// --- Delete Lecture and Associated Attendance ---
router.delete('/:lectureId', checkAuth, async (req, res) => {
    // ... (DELETE /:lectureId code remains the same, logging is already decent) ...
    const lectureId = req.params.lectureId;
    const authenticatedUserId = req.userData.userId;
    const authUserEmail = req.userData.email;

    if (!lectureId) {
        console.log('[DELETE /:lectureId] Delete request failed: Missing lectureId parameter.');
        return res.status(400).json({ message: 'Lecture ID is required.' });
    }

    console.log(`[DELETE /${lectureId}] Attempting to delete lecture by user ${authUserEmail} (ID: ${authenticatedUserId})`);

    try {
        const lectureRef = db.collection(LECTURES_COLLECTION).doc(lectureId);
        const lectureDoc = await lectureRef.get();

        if (!lectureDoc.exists) {
            console.log(`[DELETE /${lectureId}] Delete failed: Lecture not found.`);
            return res.status(404).json({ message: 'Lecture not found.' });
        }

        const lectureData = lectureDoc.data();

        // --- AUTHORIZATION CHECK ---
        console.log(`[DELETE /${lectureId}] Checking authorization...`);
        const userRoleDoc = await db.collection(USERS_COLLECTION).doc(authenticatedUserId).get();
        const userRole = userRoleDoc.exists ? userRoleDoc.data().role : null;
        const isAdmin = userRole === 'admin';

        if (lectureData.lecturerId !== authenticatedUserId && !isAdmin) {
            console.warn(`[DELETE /${lectureId}] Unauthorized delete attempt: User ${authenticatedUserId} (Role: ${userRole || 'N/A'}) tried to delete lecture owned by ${lectureData.lecturerId}`);
            return res.status(403).json({ message: 'Forbidden: You do not have permission to delete this lecture.' });
        }
        console.log(`[DELETE /${lectureId}] Authorization successful: User ${authenticatedUserId} (Role: ${userRole || 'N/A'}).`);
        // --- END AUTHORIZATION CHECK ---

        // --- Deletion Logic (using Batch Write) ---
        console.log(`[DELETE /${lectureId}] Starting batch delete process...`);
        const batch = db.batch();
        batch.delete(lectureRef);
        console.log(`[DELETE /${lectureId}] Scheduled deletion for lecture document.`);

        console.log(`[DELETE /${lectureId}] Querying attendance records where lectureId == ${lectureId}...`);
        const attendanceQuery = db.collection(ATTENDANCE_COLLECTION).where('lectureId', '==', lectureId);
        const attendanceSnapshot = await attendanceQuery.get();

        if (!attendanceSnapshot.empty) {
            console.log(`[DELETE /${lectureId}] Found ${attendanceSnapshot.size} attendance records. Scheduling for deletion.`);
            attendanceSnapshot.docs.forEach(doc => {
                console.log(`  - Scheduling delete for attendance record: ${doc.id}`);
                batch.delete(doc.ref);
            });
        } else {
            console.log(`[DELETE /${lectureId}] No attendance records found.`);
        }

        console.log(`[DELETE /${lectureId}] Committing batch delete...`);
        await batch.commit();
        // --- End Deletion Logic ---

        console.log(`[DELETE /${lectureId}] Lecture and associated attendance records deleted successfully.`);
        return res.status(204).send(); // 204 No Content

    } catch (error) {
        console.error(`[DELETE /${lectureId}] UNHANDLED ERROR deleting lecture:`, error);
        console.error('[DELETE /:lectureId] Error Stack:', error.stack);
        if (error.code === 'failed-precondition' || (error.message && error.message.includes('index'))) {
             console.error(`[DELETE /${lectureId}] Firestore Index Missing for Deletion: The query to find attendance records requires an index on 'lectureId'. Check Firebase console.`);
        }
        return res.status(500).json({
            message: 'Internal server error while deleting lecture.',
            details: process.env.NODE_ENV !== 'production' ? error.message : undefined
        });
    }
});


module.exports = router; // Export the router
