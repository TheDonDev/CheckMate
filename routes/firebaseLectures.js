// c:\Users\Test\FlutterProjects\checkmate\routes\firebaseLectures.js

const express = require('express');
const { db, admin } = require('../firebase'); // Assuming firebase.js exports both db and admin
const router = express.Router();
const checkAuth = require('../middleware/checkAuth'); // Ensure this path is correct

// --- Load Environment Variables ---
require('dotenv').config(); // Load variables from .env file

// --- Twilio Setup ---
const twilio = require('twilio');
const accountSid = process.env.TWILIO_ACCOUNT_SID;
const authToken = process.env.TWILIO_AUTH_TOKEN;
const messagingServiceSid = process.env.TWILIO_MESSAGING_SERVICE_SID;
const smsSenderName = process.env.SMS_SENDER_NAME || 'CheckmateApp'; // Default sender name

let twilioClient = null; // Initialize as null

// Validate Twilio credentials are loaded and initialize client
if (!accountSid || !authToken || !messagingServiceSid) {
  console.error("FATAL ERROR: Twilio credentials (SID, Token, Messaging Service SID) are missing in environment variables. SMS notifications will be disabled.");
} else {
  try {
    twilioClient = twilio(accountSid, authToken);
    console.log("Twilio client initialized successfully.");
  } catch (error) {
    console.error("FATAL ERROR: Failed to initialize Twilio client:", error);
  }
}

// --- Constants ---
const LECTURES_COLLECTION = 'lectures';
const USERS_COLLECTION = 'users';
const ATTENDANCE_COLLECTION = 'attendance';

// --- Helper Function for Timestamp Conversion (Client -> Firestore) ---
const parseDateForFirestore = (dateInput) => {
  if (!dateInput) return null;
  try {
    const date = new Date(dateInput);
    if (isNaN(date.getTime())) {
      console.warn(`Invalid date input received: ${dateInput}`);
      return null;
    }
    return date; // Firestore Admin SDK handles JS Date objects
  } catch (e) {
    console.error(`Error parsing date input "${dateInput}":`, e);
    return null;
  }
};

// --- Helper Function for Timestamp Conversion (Firestore -> Client) ---
const formatTimestampForClient = (timestamp) => {
  if (!timestamp) return null;
  if (timestamp && typeof timestamp.toDate === 'function') {
    return timestamp.toDate().toISOString();
  }
  if (timestamp instanceof Date && !isNaN(timestamp.getTime())) {
    return timestamp.toISOString();
  }
  // Handle case where it might already be an ISO string (e.g., from previous processing)
  if (typeof timestamp === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/.test(timestamp)) {
     return timestamp;
  }
  console.warn(`Could not format timestamp for client:`, timestamp);
  return null;
};

// --- Helper Function for Formatting Date/Time for SMS ---
const formatDateTimeForSMS = (dateObj) => {
    if (!(dateObj instanceof Date) || isNaN(dateObj.getTime())) {
        return "Invalid Date";
    }
    return dateObj.toLocaleString('en-KE', { // Use appropriate locale
        weekday: 'short', month: 'short', day: 'numeric',
        hour: 'numeric', minute: '2-digit', hour12: true,
        // timeZone: 'Africa/Nairobi' // Optional: Specify timezone if needed
    });
};

// --- Helper Function for Consistent String Formatting (Trim + Uppercase) ---
const formatStringForQuery = (str) => {
    if (str && typeof str === 'string') {
        return str.trim().toUpperCase();
    }
    return str; // Return original if not a string or null/undefined
};


// --- Create a Lecture (with SMS Notification) ---
router.post('/', checkAuth, async (req, res) => {
  let createdLectureId = null; // Define here for broader scope in error handling

  try {
    // --- Authentication & Authorization ---
    if (!req.userData || !req.userData.userId || !req.userData.email) {
        console.error('Authentication data missing from request after checkAuth.');
        return res.status(401).json({ error: 'Authentication failed or data missing.' });
    }
    const authUserId = req.userData.userId;
    const authUserEmail = req.userData.email;
    const isBypassUser = authUserEmail === 'muhambe@au.ac.ke'; // Consider making this configurable
    let userData = null;
    let userDoc = null;

    // Authorization Check (Lecturer role or bypass user)
    if (!isBypassUser) {
        userDoc = await db.collection(USERS_COLLECTION).doc(authUserId).get();
        if (!userDoc.exists) {
            console.error(`Authorization failed: User document not found for authenticated user ID: ${authUserId}`);
            return res.status(403).json({ error: 'Forbidden: User profile not found, cannot authorize lecture creation.' });
        }
        userData = userDoc.data();
        const isVerifiedLecturer = userData.role === 'lecturer' && userData.isVerified === true;
        if (!isVerifiedLecturer) {
            console.log(`Authorization failed for lecture creation: User ${authUserEmail} (Verified: ${userData.isVerified ?? 'N/A'}, Role: ${userData.role ?? 'N/A'})`);
            return res.status(403).json({ error: 'Forbidden: User not authorized or verified to create lectures.' });
        }
        console.log(`Authorization successful for verified lecturer: ${authUserEmail}`);
    } else {
        console.log(`Authorization bypass: Allowing user ${authUserEmail} to create lecture.`);
        userDoc = await db.collection(USERS_COLLECTION).doc(authUserId).get();
        userData = userDoc.exists ? userDoc.data() : {};
        if (!userDoc.exists) console.warn(`Bypass user ${authUserEmail} document not found, proceeding with defaults.`);
    }
    if (!userData) {
        console.error(`Critical Error: User data unavailable after authorization check for user ${authUserId}.`);
        return res.status(500).json({ error: 'Internal Server Error: Failed to retrieve user details.' });
    }
    // --- End Auth ---

    // --- Extract & Validate Request Body ---
    const {
      lecturerPhone, school, department, course, yearOfStudy, semester,
      unitName, unitCode, lectureDate, startTime, endTime, venue,
    } = req.body;

    const requiredFields = { school, department, course, yearOfStudy, semester, unitName, unitCode, lectureDate, startTime, endTime, venue };
    for (const [key, value] of Object.entries(requiredFields)) {
        if (!value) {
            console.error(`Validation Error: Missing required field '${key}'`);
            return res.status(400).json({ error: `Missing required lecture field: ${key}` });
        }
    }

    const parsedLectureDate = parseDateForFirestore(lectureDate);
    const parsedStartTime = parseDateForFirestore(startTime);
    const parsedEndTime = parseDateForFirestore(endTime);
    if (!parsedLectureDate || !parsedStartTime || !parsedEndTime) {
        console.error('Validation Error: Invalid date/time format received.');
        return res.status(400).json({ error: 'Invalid date or time format provided.' });
    }
    if (parsedEndTime <= parsedStartTime) {
        console.error('Validation Error: End time must be after start time.');
        return res.status(400).json({ error: 'End time must be after start time.' });
    }
    // --- End Validation ---

    // --- Prepare Lecture Data for Firestore ---
    // Use helper for consistent formatting
    const newLectureData = {
      lecturerId: authUserId,
      lecturerName: userData.name || 'N/A',
      lecturerPhone: lecturerPhone || userData.phoneNumber || null,
      // Store consistently (e.g., uppercase)
      school: formatStringForQuery(school),
      department: formatStringForQuery(department),
      course: formatStringForQuery(course),
      yearOfStudy: formatStringForQuery(yearOfStudy), // Ensure consistency with how student profile stores it
      semester: formatStringForQuery(semester),     // Ensure consistency with how student profile stores it
      unitName: unitName.trim(), // Unit name might preserve case
      unitCode: unitCode.trim().toUpperCase(), // Unit code often uppercase
      lectureDate: parsedLectureDate,
      startTime: parsedStartTime,
      endTime: parsedEndTime,
      venue: venue.trim(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    // --- End Prepare Data ---

    // --- 1. Add the lecture document to Firestore ---
    const docRef = await db.collection(LECTURES_COLLECTION).add(newLectureData);
    createdLectureId = docRef.id; // Assign ID here
    console.log(`Lecture created successfully with ID: ${createdLectureId} by user ${authUserEmail}`);

    const createdDoc = await docRef.get();
    const createdData = createdDoc.data();
    if (!createdData) {
        console.error(`Critical Error: Failed to fetch created lecture data for ID: ${createdLectureId}`);
        // Don't stop execution, but SMS might fail or be inaccurate
    }

    // --- 2. Prepare and Send SMS Notifications ---
    if (twilioClient && createdData) {
        console.log(`Preparing to send SMS notifications for lecture ${createdLectureId}...`);
        console.log('--- Querying Students With Criteria (Using formatted values) ---');
        console.log(`Role:        'student'`);
        console.log(`School:      '${createdData.school}'`); // Value used in query
        console.log(`Department:  '${createdData.department}'`); // Value used in query
        console.log(`Course:      '${createdData.course}'`); // Value used in query
        console.log(`YearOfStudy: '${createdData.yearOfStudy}'`); // Value used in query
        console.log(`Semester:    '${createdData.semester}'`); // Value used in query
        console.log(`IsVerified:  true`);
        console.log('------------------------------------');

        // Query needs to match how data is stored (e.g., uppercase if stored uppercase)
        // Ensure the fields in the user profile are also stored consistently (e.g., uppercase)
        const studentsQuery = db.collection(USERS_COLLECTION)
            .where('role', '==', 'student')
            .where('school', '==', createdData.school) // Assumes user profile also stores uppercase
            .where('department', '==', createdData.department) // Assumes user profile also stores uppercase
            .where('course', '==', createdData.course) // Assumes user profile also stores uppercase
            .where('yearOfStudy', '==', createdData.yearOfStudy) // Assumes user profile also stores uppercase
            .where('semester', '==', createdData.semester) // Assumes user profile also stores uppercase
            .where('isVerified', '==', true);

        try {
            const studentsSnapshot = await studentsQuery.get();
            if (studentsSnapshot.empty) {
                console.log(`QUERY RESULT: No matching students found for lecture ${createdLectureId}. No SMS sent.`);
            } else {
                console.log(`QUERY RESULT: Found ${studentsSnapshot.size} potential student(s) for notification.`);
                const smsStartTime = formatDateTimeForSMS(createdData.startTime.toDate());
                const smsMessageBody = `${smsSenderName} Alert: New lecture for ${createdData.unitName} (${createdData.unitCode}) by ${createdData.lecturerName} on ${smsStartTime} at ${createdData.venue}.`;
                const smsPromises = [];

                studentsSnapshot.forEach(studentDoc => {
                    const studentData = studentDoc.data();
                    const studentId = studentDoc.id;
                    const studentPhoneNumber = studentData.phoneNumber;

                    console.log(`Processing student ${studentId}: Phone='${studentPhoneNumber}', Verified='${studentData.isVerified}', Role='${studentData.role}'`);
                    if (studentPhoneNumber && typeof studentPhoneNumber === 'string' && studentPhoneNumber.startsWith('+') && studentPhoneNumber.length > 10) {
                        console.log(`Queueing SMS to student ${studentId} at ${studentPhoneNumber}`);
                        smsPromises.push(
                            twilioClient.messages.create({
                                body: smsMessageBody,
                                messagingServiceSid: messagingServiceSid,
                                to: studentPhoneNumber
                            })
                            .then(message => ({ status: 'fulfilled', sid: message.sid, phone: studentPhoneNumber }))
                            .catch(error => ({ status: 'rejected', error: error.message, phone: studentPhoneNumber, code: error.code }))
                        );
                    } else {
                        console.warn(`Skipping SMS for student ${studentId}: Invalid or missing phone number ('${studentPhoneNumber}')`);
                    }
                });

                if (smsPromises.length > 0) {
                    console.log(`Attempting to send ${smsPromises.length} SMS messages...`);
                    const results = await Promise.allSettled(smsPromises);
                    const successfulSends = results.filter(r => r.status === 'fulfilled').length;
                    const failedSends = results.filter(r => r.status === 'rejected').length;
                    console.log(`SMS sending complete: ${successfulSends} succeeded, ${failedSends} failed.`);
                    results.filter(r => r.status === 'rejected').forEach(failure => {
                         console.warn(` -> Failed SMS Detail: Phone: ${failure.reason.phone}, Code: ${failure.reason.code || 'N/A'}, Error: ${failure.reason.error}`);
                    });
                } else {
                     console.log("No valid student phone numbers found among the matched students.");
                }
            }
        } catch (queryError) {
            console.error(`Error querying students or sending SMS for lecture ${createdLectureId}:`, queryError);
            // Check for index errors during student query
             if (queryError.code === 'failed-precondition' || (queryError.message && queryError.message.includes('index'))) {
                 console.error("Firestore Index Missing for Student Query: The query to find students requires a composite index. Check the error details for a link to create it in the Firebase console.");
             }
        }
    } else if (!twilioClient) {
        console.warn(`Twilio client not initialized. Skipping SMS notifications for lecture ${createdLectureId}.`);
    } else if (!createdData) {
         console.warn(`Created lecture data was unavailable. Skipping SMS notifications for lecture ${createdLectureId}.`);
    }
    // --- End SMS Logic ---

    // --- 3. Return the success response to the client ---
    const responseData = createdData ? {
        id: createdDoc.id,
        ...createdData,
        // Ensure timestamps are formatted correctly for the client
        lectureDate: formatTimestampForClient(createdData.lectureDate),
        startTime: formatTimestampForClient(createdData.startTime),
        endTime: formatTimestampForClient(createdData.endTime),
        createdAt: formatTimestampForClient(createdData.createdAt),
     } : { id: createdLectureId, message: "Lecture created, but failed to fetch full data for response." };

    res.status(201).json(responseData);

  } catch (error) {
    console.error(`Error processing POST /lectures request (Lecture ID if created: ${createdLectureId || 'N/A'}):`, error);
    console.error('Error Stack:', error.stack);
    let errorMessage = 'Internal Server Error: Failed to create lecture or process notifications';
    let statusCode = 500;
    // Add more specific error handling if needed
    res.status(statusCode).json({
        error: errorMessage,
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});

// --- Get lectures for a specific lecturer ---
router.get('/lecturer/:lecturerId', checkAuth, async (req, res) => {
    try {
        const requestedLecturerId = req.params.lecturerId;
        const authUserId = req.userData.userId;

        // Authorization: Ensure the authenticated user is requesting their own lectures
        if (requestedLecturerId !== authUserId) {
            console.log(`Forbidden attempt: User ${authUserId} tried to access lectures for ${requestedLecturerId}`);
            return res.status(403).json({ error: 'Forbidden: You can only access your own lectures.' });
        }

        console.log(`Fetching lectures for lecturerId: ${requestedLecturerId}`);
        const lecturesRef = db.collection(LECTURES_COLLECTION);
        // Query for lectures created by this lecturer
        const snapshot = await lecturesRef
            .where('lecturerId', '==', requestedLecturerId)
            .orderBy('startTime', 'desc') // Order by start time, descending (most recent first)
            .get();

        if (snapshot.empty) {
            console.log(`No lectures found for lecturer ${requestedLecturerId}`);
            return res.json([]); // Return empty array if no lectures found
        }

        // Map Firestore documents to lecture objects for the response
        const lectures = snapshot.docs.map(doc => {
            const data = doc.data();
            return {
                id: doc.id,
                ...data,
                // Format timestamps for client consistency
                lectureDate: formatTimestampForClient(data.lectureDate),
                startTime: formatTimestampForClient(data.startTime),
                endTime: formatTimestampForClient(data.endTime),
                createdAt: formatTimestampForClient(data.createdAt),
            };
        });

        console.log(`Found ${lectures.length} lectures for lecturer ${requestedLecturerId}`);
        res.json(lectures);
    } catch (error) {
        console.error(`Error getting lectures for lecturer ${req.params.lecturerId}:`, error);
        res.status(500).json({
            error: 'Internal Server Error: Failed to get lectures for lecturer',
            details: process.env.NODE_ENV !== 'production' ? error.message : undefined
        });
    }
});

// --- Get lectures for a student (based on student's profile AND query filters) ---
router.get('/student', checkAuth, async (req, res) => {
  try {
    const studentUserId = req.userData.userId;

    // 1. Get Student Profile Data
    const studentDoc = await db.collection(USERS_COLLECTION).doc(studentUserId).get();
    if (!studentDoc.exists) {
        console.error(`Student profile not found for authenticated user ID: ${studentUserId}`);
        return res.status(404).json({ error: 'Your user profile could not be found.' });
    }
    const studentData = studentDoc.data();
    // Use helper to ensure consistent formatting for comparison
    const profileSchool = formatStringForQuery(studentData.school);
    const profileDepartment = formatStringForQuery(studentData.department);
    const profileCourse = formatStringForQuery(studentData.course);
    // Note: yearOfStudy and semester from profile are NOT used for filtering lectures directly,
    // only for the percentage calculation. The filters come from req.query.
    const profileRole = studentData.role;
    const profileIsVerified = studentData.isVerified;

    // 2. Validate Student Role and Profile Fields Needed for Base Filtering
    if (profileRole !== 'student') {
         console.error(`User ${studentUserId} is not a student (role: ${profileRole}). Cannot fetch student lectures.`);
         return res.status(403).json({ error: 'Forbidden: Only students can access this lecture list.' });
    }
    if (!profileSchool || !profileDepartment || !profileCourse) { // Base fields needed for any query
        console.error(`Validation Error: Student ${studentUserId} profile is missing required fields (school, dept, course). Profile values: School=${profileSchool}, Dept=${profileDepartment}, Course=${profileCourse}`);
        return res.status(400).json({ error: 'Your profile is missing required details (school, department, course) needed to find lectures.' });
    }
     if (!profileIsVerified) {
         console.warn(`Student ${studentUserId} is not verified. They may not see all lectures.`);
         // Decide if unverified students should see lectures - currently allowing but warning.
    }

    // 3. Get and Validate Query Parameters (Year and Semester for filtering)
    const { school: requestedSchool, department: requestedDepartment, course: requestedCourse, year: requestedYear, semester: requestedSemester } = req.query;
    if (!requestedSchool || !requestedDepartment || !requestedCourse || !requestedYear || !requestedSemester) {
        console.error(`Validation Error: Missing required query parameters (school, dept, course, year, semester) for student ${studentUserId}. Received: school=${requestedSchool}, dept=${requestedDepartment}, course=${requestedCourse}, year=${requestedYear}, semester=${requestedSemester}`);
        return res.status(400).json({ error: 'Required filter parameters (school, department, course, year, semester) were not provided in the request.' });
    }

    // 4. Security Check & Data Consistency Check: Ensure requested school/dept/course match student's profile
    //    Compare consistently (e.g., uppercase)
    const querySchool = formatStringForQuery(requestedSchool);
    const queryDepartment = formatStringForQuery(requestedDepartment);
    const queryCourse = formatStringForQuery(requestedCourse);

    if (profileSchool !== querySchool || profileDepartment !== queryDepartment || profileCourse !== queryCourse) {
        console.error(`Forbidden: Student ${studentUserId} requested filters (${querySchool}/${queryDepartment}/${queryCourse}) that do not match their profile (${profileSchool}/${profileDepartment}/${profileCourse}).`);
        return res.status(403).json({ error: 'Forbidden: You can only filter lectures for your registered school, department, and course.' });
    }

    // 5. Build Firestore Query
    // Use consistent values for querying (e.g., uppercase)
    const queryYear = formatStringForQuery(requestedYear); // Use the requested year filter
    const querySemester = formatStringForQuery(requestedSemester); // Use the requested semester filter

    console.log(`Firestore Query Parameters for student ${studentUserId}:`);
    console.log(`  school:      '${querySchool}'`);
    console.log(`  department:  '${queryDepartment}'`);
    console.log(`  course:      '${queryCourse}'`);
    console.log(`  yearOfStudy: '${queryYear}'`);
    console.log(`  semester:    '${querySemester}'`);

    const lecturesRef = db.collection(LECTURES_COLLECTION);
    let query = lecturesRef;

    // Filter by student's base profile AND the requested year/semester
    // Ensure the fields in the 'where' clauses EXACTLY match the field names in your Firestore 'lectures' collection
    // AND that the data was stored consistently (e.g., uppercase)
    query = query.where('school', '==', querySchool);
    query = query.where('department', '==', queryDepartment);
    query = query.where('course', '==', queryCourse);
    query = query.where('yearOfStudy', '==', queryYear); // Compare lecture's yearOfStudy with the requested year
    query = query.where('semester', '==', querySemester); // Compare lecture's semester with the requested semester

    // Filter for upcoming lectures (lectures starting from the beginning of today onwards)
    const today = new Date();
    today.setHours(0, 0, 0, 0); // Start of today
    query = query.where('startTime', '>=', today); // Only lectures starting today or later
    console.log(`  startTime:   >= ${today.toISOString()}`);

    // Order results by start time ascending
    query = query.orderBy('startTime', 'asc'); // Show earliest upcoming first
    console.log(`  orderBy:     startTime asc`);

    // 6. Execute Query and Process Results
    console.log("Executing Firestore query...");
    const snapshot = await query.get();
    console.log(`Firestore query executed. Found ${snapshot.size} documents.`);

    if (snapshot.empty) {
        console.log(`No upcoming student lectures found for student ${studentUserId} with the specified filters.`);
        return res.json([]); // Return empty array, not an error
    }

    const lectures = snapshot.docs.map(doc => {
        const data = doc.data();
        return {
            id: doc.id,
            ...data,
            // Format timestamps for client consistency
            lectureDate: formatTimestampForClient(data.lectureDate),
            startTime: formatTimestampForClient(data.startTime),
            endTime: formatTimestampForClient(data.endTime),
            createdAt: formatTimestampForClient(data.createdAt),
        };
    });

    console.log(`Successfully processed ${lectures.length} upcoming student lectures for student ${studentUserId}`);
    res.json(lectures);

  } catch (error) {
    console.error(`Error getting student lectures for user ${req.userData?.userId}:`, error);
    console.error('Error Stack:', error.stack); // Log stack trace for detailed debugging

    // Check specifically for Firestore index errors
    if (error.code === 'failed-precondition' || (error.message && error.message.includes('index'))) {
        console.error("Firestore Index Missing: The query requires an index. Check the error details for a link to create it in the Firebase console. Index likely needs fields: school (ASC), department (ASC), course (ASC), yearOfStudy (ASC), semester (ASC), startTime (ASC)");
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
router.get('/', checkAuth, async (req, res) => {
  // Authorization Check: Ensure user has 'admin' role
  try {
    const userDoc = await db.collection(USERS_COLLECTION).doc(req.userData.userId).get();
    if (!userDoc.exists || userDoc.data().role !== 'admin') {
        console.log(`Forbidden attempt: Non-admin user ${req.userData.userId} (${req.userData.email}) tried to access all lectures.`);
        return res.status(403).json({ error: 'Forbidden: Only administrators can access all lectures.' });
    }
    console.log(`Admin access granted for user ${req.userData.email} to fetch all lectures.`);
  } catch (authError) {
      console.error('Error checking admin role:', authError);
      return res.status(500).json({ error: 'Internal Server Error during authorization check.' });
  }

  // Fetch all lectures if authorized
  try {
    console.log('Fetching all lectures (admin access)');
    const snapshot = await db.collection(LECTURES_COLLECTION).orderBy('startTime', 'desc').get();
    const lectures = snapshot.docs.map(doc => {
        const data = doc.data();
        return {
            id: doc.id,
            ...data,
            lectureDate: formatTimestampForClient(data.lectureDate),
            startTime: formatTimestampForClient(data.startTime),
            endTime: formatTimestampForClient(data.endTime),
            createdAt: formatTimestampForClient(data.createdAt),
        };
    });
    console.log(`Found ${lectures.length} total lectures (admin).`);
    res.json(lectures);
  } catch (error) {
    console.error('Error getting all lectures (admin):', error);
    res.status(500).json({
        error: 'Internal Server Error: Failed to get all lectures',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});

// --- Get lecture by ID ---
router.get('/:lectureId', checkAuth, async (req, res) => {
  try {
    const lectureId = req.params.lectureId;
    console.log(`Fetching lecture by ID: ${lectureId} (User: ${req.userData.email})`);

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
          lectureDate: formatTimestampForClient(data.lectureDate),
          startTime: formatTimestampForClient(data.startTime),
          endTime: formatTimestampForClient(data.endTime),
          createdAt: formatTimestampForClient(data.createdAt),
       });
    }
  } catch (error) {
    console.error(`Error getting lecture by ID ${req.params.lectureId}:`, error);
    res.status(500).json({
        error: 'Internal Server Error: Failed to get lecture',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});


// --- Delete Lecture and Associated Attendance ---
router.delete('/:lectureId', checkAuth, async (req, res) => {
    const lectureId = req.params.lectureId;
    const authenticatedUserId = req.userData.userId;

    if (!lectureId) {
        console.log('Delete request failed: Missing lectureId parameter.');
        return res.status(400).json({ message: 'Lecture ID is required.' });
    }

    console.log(`Attempting to delete lecture ${lectureId} by user ${authenticatedUserId}`);

    try {
        const lectureRef = db.collection(LECTURES_COLLECTION).doc(lectureId);
        const lectureDoc = await lectureRef.get();

        if (!lectureDoc.exists) {
            console.log(`Delete failed: Lecture ${lectureId} not found.`);
            return res.status(404).json({ message: 'Lecture not found.' });
        }

        const lectureData = lectureDoc.data();

        // --- AUTHORIZATION CHECK ---
        // Allow deletion if user is the lecturer OR if user is an admin (assuming admin role exists)
        const userRoleDoc = await db.collection(USERS_COLLECTION).doc(authenticatedUserId).get();
        const userRole = userRoleDoc.exists ? userRoleDoc.data().role : null;
        const isAdmin = userRole === 'admin'; // Check if user is admin

        if (lectureData.lecturerId !== authenticatedUserId && !isAdmin) {
            console.warn(`Unauthorized delete attempt: User ${authenticatedUserId} (Role: ${userRole || 'N/A'}) tried to delete lecture ${lectureId} owned by ${lectureData.lecturerId}`);
            return res.status(403).json({ message: 'Forbidden: You do not have permission to delete this lecture.' });
        }
        console.log(`Authorization successful for delete: User ${authenticatedUserId} (Role: ${userRole || 'N/A'}) deleting lecture ${lectureId}.`);
        // --- END AUTHORIZATION CHECK ---

        // --- Deletion Logic (using Batch Write) ---
        const batch = db.batch();
        batch.delete(lectureRef);
        console.log(`Scheduled deletion for lecture document: ${lectureId}`);

        // Find and schedule deletion for associated attendance records
        // This query requires an index on lectureId in the attendance collection
        const attendanceQuery = db.collection(ATTENDANCE_COLLECTION).where('lectureId', '==', lectureId);
        const attendanceSnapshot = await attendanceQuery.get();

        if (!attendanceSnapshot.empty) {
            console.log(`Found ${attendanceSnapshot.size} attendance records for lecture ${lectureId}. Scheduling for deletion.`);
            attendanceSnapshot.docs.forEach(doc => { batch.delete(doc.ref); });
        } else {
            console.log(`No attendance records found for lecture ${lectureId}.`);
        }

        await batch.commit();
        // --- End Deletion Logic ---

        console.log(`Lecture ${lectureId} and associated attendance records deleted successfully by user ${authenticatedUserId}.`);
        return res.status(204).send(); // 204 No Content

    } catch (error) {
        console.error(`Error deleting lecture ${lectureId}:`, error);
        console.error('Error Stack:', error.stack);
        // Check specifically for Firestore index errors if attendance query fails
        if (error.code === 'failed-precondition' || (error.message && error.message.includes('index'))) {
             console.error("Firestore Index Missing for Deletion: The query to find attendance records requires an index on 'lectureId'. Check the error details for a link to create it.");
        }
        return res.status(500).json({
            message: 'Internal server error while deleting lecture.',
            details: process.env.NODE_ENV !== 'production' ? error.message : undefined
        });
    }
});


module.exports = router; // Export the router
