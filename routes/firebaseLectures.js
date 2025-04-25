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
    // Handles both 'YYYY-MM-DD' and full ISO strings like '2024-07-15T10:30:00.000+03:00' or '...Z'
    const date = new Date(dateInput);
    if (isNaN(date.getTime())) {
      console.warn(`[ParseHelper BE] Invalid date input received: ${dateInput}`);
      return null;
    }
    // *** ADDED LOGGING ***
    console.log(`[ParseHelper BE] Parsed input '${dateInput}' to JS Date: ${date.toISOString()} (UTC)`);
    // Firestore Admin SDK handles JS Date objects directly, converting them to Timestamps
    return date;
  } catch (e) {
    console.error(`[ParseHelper BE] Error parsing date input "${dateInput}":`, e);
    return null;
  }
};

// --- Helper Function for Timestamp Conversion (Firestore -> Client) ---
const formatTimestampForClient = (timestamp) => {
  if (!timestamp) return null;
  let dateObj = null;
  if (timestamp && typeof timestamp.toDate === 'function') {
    dateObj = timestamp.toDate(); // Convert Firestore Timestamp to JS Date
  } else if (timestamp instanceof Date && !isNaN(timestamp.getTime())) {
    dateObj = timestamp; // Already a JS Date
  }

  if (dateObj) {
    const isoString = dateObj.toISOString(); // Convert to ISO string (UTC 'Z' format)
    // *** ADDED LOGGING ***
    console.log(`[FormatHelper BE] Formatting Timestamp/Date to ISO UTC string for client: ${isoString}`);
    return isoString;
  }

  // Handle case where it might already be an ISO string (less likely from Firestore directly)
  if (typeof timestamp === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/.test(timestamp)) {
     console.log(`[FormatHelper BE] Timestamp was already string, returning as is: ${timestamp}`);
     return timestamp;
  }
  console.warn(`[FormatHelper BE] Could not format timestamp for client:`, timestamp);
  return null; // Return null if format is unrecognized
};

// --- Helper Function for Formatting Date/Time for SMS ---
const formatDateTimeForSMS = (dateObj) => {
    if (!(dateObj instanceof Date) || isNaN(dateObj.getTime())) {
        return "Invalid Date";
    }
    // Format for readability in SMS
    return dateObj.toLocaleString('en-KE', { // Use appropriate locale like 'en-KE' for Kenya
        weekday: 'short', month: 'short', day: 'numeric',
        hour: 'numeric', minute: '2-digit', hour12: true,
        timeZone: 'Africa/Nairobi' // Explicitly set timezone for consistency in SMS
    });
};

// --- Helper Function for Consistent String Formatting (Trim + Uppercase) ---
const formatStringForQuery = (str) => {
    if (str && typeof str === 'string') {
        // Trim whitespace and convert to uppercase for consistent querying/storage
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
      onlineLink
    } = req.body;

    // Check for missing required fields
    const requiredFields = { school, department, course, yearOfStudy, semester, unitName, unitCode, lectureDate, startTime, endTime, venue };
    for (const [key, value] of Object.entries(requiredFields)) {
        if (!value) {
            console.error(`Validation Error: Missing required field '${key}'`);
            return res.status(400).json({ error: `Missing required lecture field: ${key}` });
        }
    }

    // Parse and validate dates/times
    const parsedLectureDate = parseDateForFirestore(lectureDate); // Expects 'YYYY-MM-DD' from client
    const parsedStartTime = parseDateForFirestore(startTime);     // Expects ISO string (with offset) from client
    const parsedEndTime = parseDateForFirestore(endTime);         // Expects ISO string (with offset) from client
    if (!parsedLectureDate || !parsedStartTime || !parsedEndTime) {
        console.error('Validation Error: Invalid date/time format received.');
        return res.status(400).json({ error: 'Invalid date or time format provided.' });
    }
    if (parsedEndTime <= parsedStartTime) {
        console.error('Validation Error: End time must be after start time.');
        return res.status(400).json({ error: 'End time must be after start time.' });
    }

    // Validate onlineLink if venue is ONLINE
    const formattedVenue = venue.trim(); // Use trimmed venue for check
    let finalOnlineLink = null; // Initialize link as null

    if (formattedVenue.toUpperCase() === 'ONLINE') {
        if (!onlineLink || onlineLink.trim().length === 0) {
            console.error('Validation Error: Online link is required when venue is ONLINE.');
            return res.status(400).json({ error: 'Online lecture link is required when venue is set to ONLINE.' });
        }
        // Optional: Basic URL validation
        try {
            const trimmedLink = onlineLink.trim();
            new URL(trimmedLink); // Check if it's a parsable URL
            finalOnlineLink = trimmedLink; // Assign trimmed link if valid
        } catch (_) {
            console.error('Validation Error: Invalid URL format for online link.');
            return res.status(400).json({ error: 'Please provide a valid URL for the online lecture link (e.g., https://...).' });
        }
    }

    // --- Prepare Lecture Data for Firestore ---
    const newLectureData = {
      lecturerId: authUserId,
      lecturerName: userData.name || 'N/A',
      lecturerPhone: lecturerPhone || userData.phoneNumber || null, // Use provided or fallback to profile
      school: formatStringForQuery(school),
      department: formatStringForQuery(department),
      course: formatStringForQuery(course),
      yearOfStudy: formatStringForQuery(yearOfStudy),
      semester: formatStringForQuery(semester),
      unitName: unitName.trim(),
      unitCode: unitCode.trim().toUpperCase(),
      lectureDate: parsedLectureDate, // Store as JS Date (becomes Timestamp)
      startTime: parsedStartTime,     // Store as JS Date (becomes Timestamp)
      endTime: parsedEndTime,         // Store as JS Date (becomes Timestamp)
      venue: formattedVenue, // Store trimmed venue
      createdAt: admin.firestore.FieldValue.serverTimestamp(), // Let Firestore set creation time
      onlineLink: finalOnlineLink,
    };
    // --- End Prepare Data ---

    // --- 1. Add the lecture document to Firestore ---
    const docRef = await db.collection(LECTURES_COLLECTION).add(newLectureData);
    createdLectureId = docRef.id;
    console.log(`Lecture created successfully with ID: ${createdLectureId} by user ${authUserEmail}`);

    // Fetch the newly created document to get all data including server timestamp
    const createdDoc = await docRef.get();
    const createdData = createdDoc.data();
    if (!createdData) {
        console.error(`Critical Error: Failed to fetch created lecture data for ID: ${createdLectureId}`);
    }

    // --- 2. Prepare and Send SMS Notifications (for CREATE) ---
    if (twilioClient && createdData) {
        console.log(`Preparing to send CREATE SMS notifications for lecture ${createdLectureId}...`);
        const studentsQuery = db.collection(USERS_COLLECTION)
            .where('role', '==', 'student')
            .where('school', '==', createdData.school)
            .where('department', '==', createdData.department)
            .where('course', '==', createdData.course)
            .where('yearOfStudy', '==', createdData.yearOfStudy)
            .where('semester', '==', createdData.semester)
            .where('isVerified', '==', true);

        try {
            const studentsSnapshot = await studentsQuery.get();
            if (studentsSnapshot.empty) {
                console.log(`CREATE SMS: No matching students found for lecture ${createdLectureId}.`);
            } else {
                console.log(`CREATE SMS: Found ${studentsSnapshot.size} potential student(s) for notification.`);
                const smsStartTime = formatDateTimeForSMS(createdData.startTime.toDate());
                let smsVenueInfo = `at ${createdData.venue}`;
                if (createdData.venue.toUpperCase() === 'ONLINE' && createdData.onlineLink) {
                    smsVenueInfo = `online. Link: ${createdData.onlineLink}`;
                }
                const smsMessageBody = `${smsSenderName} Alert: New lecture for ${createdData.unitName} (${createdData.unitCode}) by ${createdData.lecturerName} on ${smsStartTime} ${smsVenueInfo}.`;
                const smsPromises = [];

                studentsSnapshot.forEach(studentDoc => {
                    const studentData = studentDoc.data();
                    const studentId = studentDoc.id;
                    const studentPhoneNumber = studentData.phoneNumber;
                    if (studentPhoneNumber && typeof studentPhoneNumber === 'string' && studentPhoneNumber.startsWith('+') && studentPhoneNumber.length > 10) {
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
                        console.warn(`CREATE SMS: Skipping student ${studentId}: Invalid phone ('${studentPhoneNumber}')`);
                    }
                });

                if (smsPromises.length > 0) {
                    console.log(`CREATE SMS: Attempting to send ${smsPromises.length} messages...`);
                    const results = await Promise.allSettled(smsPromises);
                    const successfulSends = results.filter(r => r.status === 'fulfilled').length;
                    const failedSends = results.filter(r => r.status === 'rejected').length;
                    console.log(`CREATE SMS: Sending complete: ${successfulSends} succeeded, ${failedSends} failed.`);
                    results.filter(r => r.status === 'rejected').forEach(failure => {
                         console.warn(` -> CREATE SMS Failed Detail: Phone: ${failure.reason.phone}, Code: ${failure.reason.code || 'N/A'}, Error: ${failure.reason.error}`);
                    });
                } else {
                     console.log("CREATE SMS: No valid student phone numbers found.");
                }
            }
        } catch (queryError) {
            console.error(`CREATE SMS: Error querying students or sending SMS for lecture ${createdLectureId}:`, queryError);
             if (queryError.code === 'failed-precondition' || (queryError.message && queryError.message.includes('index'))) {
                 console.error("CREATE SMS: Firestore Index Missing for Student Query.");
             }
        }
    } else if (!twilioClient) {
        console.warn(`Twilio client not initialized. Skipping CREATE SMS notifications for lecture ${createdLectureId}.`);
    } else if (!createdData) {
         console.warn(`Created lecture data was unavailable. Skipping CREATE SMS notifications for lecture ${createdLectureId}.`);
    }
    // --- End SMS Logic for CREATE ---

    // --- 3. Return the success response to the client ---
    const responseData = createdData ? {
        id: createdDoc.id,
        ...createdData,
        lectureDate: formatTimestampForClient(createdData.lectureDate),
        startTime: formatTimestampForClient(createdData.startTime),
        endTime: formatTimestampForClient(createdData.endTime),
        createdAt: formatTimestampForClient(createdData.createdAt),
     } : { id: createdLectureId, message: "Lecture created, but failed to fetch full data for response." };

    res.status(201).json(responseData);

  } catch (error) {
    console.error(`Error processing POST /lectures request (Lecture ID if created: ${createdLectureId || 'N/A'}):`, error);
    console.error('Error Stack:', error.stack);
    res.status(500).json({
        error: 'Internal Server Error: Failed to create lecture or process notifications',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});

// --- Get lectures for a specific lecturer ---
router.get('/lecturer/:lecturerId', checkAuth, async (req, res) => {
    try {
        const requestedLecturerId = req.params.lecturerId;
        const authUserId = req.userData.userId;

        if (requestedLecturerId !== authUserId) {
            console.log(`Forbidden attempt: User ${authUserId} tried to access lectures for ${requestedLecturerId}`);
            return res.status(403).json({ error: 'Forbidden: You can only access your own lectures.' });
        }

        console.log(`Fetching lectures for lecturerId: ${requestedLecturerId}`);
        const lecturesRef = db.collection(LECTURES_COLLECTION);
        const snapshot = await lecturesRef
            .where('lecturerId', '==', requestedLecturerId)
            .orderBy('startTime', 'desc') // Order by start time, descending (most recent first)
            .get();

        if (snapshot.empty) {
            console.log(`No lectures found for lecturer ${requestedLecturerId}`);
            return res.json([]);
        }

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

// --- Get lectures for a student ---
router.get('/student', checkAuth, async (req, res) => {
  try {
    const studentUserId = req.userData.userId;

    const studentDoc = await db.collection(USERS_COLLECTION).doc(studentUserId).get();
    if (!studentDoc.exists) {
        console.error(`Student profile not found for authenticated user ID: ${studentUserId}`);
        return res.status(404).json({ error: 'Your user profile could not be found.' });
    }
    const studentData = studentDoc.data();
    const profileSchool = formatStringForQuery(studentData.school);
    const profileDepartment = formatStringForQuery(studentData.department);
    const profileCourse = formatStringForQuery(studentData.course);
    const profileRole = studentData.role;
    const profileIsVerified = studentData.isVerified;

    if (profileRole !== 'student') {
         console.error(`User ${studentUserId} is not a student (role: ${profileRole}). Cannot fetch student lectures.`);
         return res.status(403).json({ error: 'Forbidden: Only students can access this lecture list.' });
    }
    if (!profileSchool || !profileDepartment || !profileCourse) {
        console.error(`Validation Error: Student ${studentUserId} profile is missing required fields (school, dept, course).`);
        return res.status(400).json({ error: 'Your profile is missing required details (school, department, course) needed to find lectures.' });
    }
     if (!profileIsVerified) {
         console.warn(`Student ${studentUserId} is not verified. They may not see all lectures.`);
    }

    const { school: requestedSchool, department: requestedDepartment, course: requestedCourse, year: requestedYear, semester: requestedSemester } = req.query;
    if (!requestedSchool || !requestedDepartment || !requestedCourse || !requestedYear || !requestedSemester) {
        console.error(`Validation Error: Missing required query parameters (school, dept, course, year, semester) for student ${studentUserId}.`);
        return res.status(400).json({ error: 'Required filter parameters (school, department, course, year, semester) were not provided in the request.' });
    }

    const querySchool = formatStringForQuery(requestedSchool);
    const queryDepartment = formatStringForQuery(requestedDepartment);
    const queryCourse = formatStringForQuery(requestedCourse);

    if (profileSchool !== querySchool || profileDepartment !== queryDepartment || profileCourse !== queryCourse) {
        console.error(`Forbidden: Student ${studentUserId} requested filters (${querySchool}/${queryDepartment}/${queryCourse}) that do not match their profile (${profileSchool}/${profileDepartment}/${profileCourse}).`);
        return res.status(403).json({ error: 'Forbidden: You can only filter lectures for your registered school, department, and course.' });
    }

    const queryYear = formatStringForQuery(requestedYear);
    const querySemester = formatStringForQuery(requestedSemester);

    console.log(`Firestore Query Parameters for student ${studentUserId}:`);
    console.log(`  school: '${querySchool}', department: '${queryDepartment}', course: '${queryCourse}', yearOfStudy: '${queryYear}', semester: '${querySemester}'`);

    const lecturesRef = db.collection(LECTURES_COLLECTION);
    let query = lecturesRef
        .where('school', '==', querySchool)
        .where('department', '==', queryDepartment)
        .where('course', '==', queryCourse)
        .where('yearOfStudy', '==', queryYear)
        .where('semester', '==', querySemester);

    const today = new Date();
    today.setHours(0, 0, 0, 0);
    query = query.where('startTime', '>=', today);
    console.log(`  startTime: >= ${today.toISOString()}`);

    query = query.orderBy('startTime', 'asc');
    console.log(`  orderBy: startTime asc`);

    console.log("Executing Firestore query...");
    const snapshot = await query.get();
    console.log(`Firestore query executed. Found ${snapshot.size} documents.`);

    if (snapshot.empty) {
        console.log(`No upcoming student lectures found for student ${studentUserId} with the specified filters.`);
        return res.json([]);
    }

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

    console.log(`Successfully processed ${lectures.length} upcoming student lectures for student ${studentUserId}`);
    res.json(lectures);

  } catch (error) {
    console.error(`Error getting student lectures for user ${req.userData?.userId}:`, error);
    console.error('Error Stack:', error.stack);

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
router.get('/', checkAuth, async (req, res) => {
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

// --- Update Lecture (PUT /:lectureId) ---
router.put('/:lectureId', checkAuth, async (req, res) => {
    const lectureId = req.params.lectureId;
    const authenticatedUserId = req.userData.userId;
    const updateData = req.body; // Data sent from Flutter

    if (!lectureId) {
        console.log('Update request failed: Missing lectureId parameter.');
        return res.status(400).json({ message: 'Lecture ID is required.' });
    }

    console.log(`[BE Update ${lectureId}] Attempting update by user ${authenticatedUserId}`);
    console.log(`[BE Update ${lectureId}] Received update data:`, updateData); // Log incoming data

    try {
        const lectureRef = db.collection(LECTURES_COLLECTION).doc(lectureId);
        const lectureDoc = await lectureRef.get();

        if (!lectureDoc.exists) {
            console.log(`[BE Update ${lectureId}] Update failed: Lecture not found.`);
            return res.status(404).json({ message: 'Lecture not found.' });
        }

        const lectureData = lectureDoc.data(); // Original lecture data

        // --- AUTHORIZATION CHECK ---
        const userRoleDoc = await db.collection(USERS_COLLECTION).doc(authenticatedUserId).get();
        const userRole = userRoleDoc.exists ? userRoleDoc.data().role : null;
        const isAdmin = userRole === 'admin';

        if (lectureData.lecturerId !== authenticatedUserId && !isAdmin) {
            console.warn(`[BE Update ${lectureId}] Unauthorized update attempt: User ${authenticatedUserId} (Role: ${userRole || 'N/A'}) tried to update lecture owned by ${lectureData.lecturerId}`);
            return res.status(403).json({ message: 'Forbidden: You do not have permission to update this lecture.' });
        }
        console.log(`[BE Update ${lectureId}] Authorization successful: User ${authenticatedUserId} (Role: ${userRole || 'N/A'}).`);
        // --- END AUTHORIZATION CHECK ---

        // --- VALIDATE AND PREPARE UPDATE DATA ---
        const allowedUpdates = {};
        const editableFields = ['unitName', 'unitCode', 'venue', 'yearOfStudy', 'semester', 'lectureDate', 'startTime', 'endTime', 'onlineLink'];

        for (const field of editableFields) {
            if (updateData.hasOwnProperty(field)) {
                if (field === 'lectureDate' || field === 'startTime' || field === 'endTime') {
                    // Use the helper which handles ISO strings with offsets
                    const parsedDate = parseDateForFirestore(updateData[field]); // This logs internally now
                    if (!parsedDate && updateData[field] != null) {
                         console.error(`[BE Update ${lectureId}] Validation Error: Invalid date format for ${field}: ${updateData[field]}`);
                         return res.status(400).json({ error: `Invalid date format provided for ${field}. Expected YYYY-MM-DD or ISO string.` });
                    }
                    allowedUpdates[field] = parsedDate; // Store the parsed JS Date or null
                }
                else if (field === 'onlineLink') {
                    allowedUpdates[field] = updateData[field]?.trim() || null;
                }
                else if (['unitCode', 'yearOfStudy', 'semester'].includes(field)) {
                     allowedUpdates[field] = formatStringForQuery(updateData[field]);
                }
                else if (typeof updateData[field] === 'string') {
                    allowedUpdates[field] = updateData[field].trim();
                }
                 else {
                     allowedUpdates[field] = updateData[field];
                 }
            }
        }

        // Validate onlineLink based on FINAL venue
        const finalVenue = allowedUpdates.hasOwnProperty('venue') ? allowedUpdates.venue : lectureData.venue;
        const finalOnlineLink = allowedUpdates.hasOwnProperty('onlineLink') ? allowedUpdates.onlineLink : lectureData.onlineLink;

        if (finalVenue?.toUpperCase() === 'ONLINE') {
            if (!finalOnlineLink || finalOnlineLink.trim().length === 0) {
                console.error(`[BE Update ${lectureId}] Validation Error: Online link required for ONLINE venue.`);
                return res.status(400).json({ error: 'Online lecture link is required when venue is set to ONLINE.' });
            }
            try { new URL(finalOnlineLink.trim()); } catch (_) {
                console.error(`[BE Update ${lectureId}] Validation Error: Invalid URL format for online link.`);
                return res.status(400).json({ error: 'Please provide a valid URL for the online lecture link.' });
            }
        }
        if (finalVenue?.toUpperCase() !== 'ONLINE' && (allowedUpdates.hasOwnProperty('venue') || allowedUpdates.hasOwnProperty('onlineLink'))) {
             allowedUpdates.onlineLink = null;
        }

        // Validate start/end time
        // Use .getTime() for comparison after ensuring they are Date objects
        const finalStartTimeMs = allowedUpdates.hasOwnProperty('startTime') ? allowedUpdates.startTime?.getTime() : lectureData.startTime?.toDate().getTime();
        const finalEndTimeMs = allowedUpdates.hasOwnProperty('endTime') ? allowedUpdates.endTime?.getTime() : lectureData.endTime?.toDate().getTime();

        if (finalStartTimeMs != null && finalEndTimeMs != null && finalEndTimeMs <= finalStartTimeMs) {
             console.error(`[BE Update ${lectureId}] Validation Error: End time must be after start time.`);
             return res.status(400).json({ error: 'End time must be after start time.' });
        }
        // --- END VALIDATION ---


        // --- Perform Update in Firestore ---
        if (Object.keys(allowedUpdates).length > 0) {
            console.log(`[BE Update ${lectureId}] Applying updates to Firestore:`, allowedUpdates); // Log data being sent to Firestore
            await lectureRef.update(allowedUpdates);
            console.log(`[BE Update ${lectureId}] Lecture updated successfully with fields:`, Object.keys(allowedUpdates));
        } else {
            console.log(`[BE Update ${lectureId}] No valid fields provided for update.`);
        }
        // --- End Firestore Update ---

        // --- Fetch Updated Data ---
        const updatedDoc = await lectureRef.get();
        const updatedLecture = updatedDoc.data();
        if (!updatedLecture) {
             console.error(`[BE Update ${lectureId}] Critical Error: Failed to fetch updated lecture data after update.`);
        } else {
             console.log(`[BE Update ${lectureId}] Fetched updated lecture data successfully.`);
        }
        // --- End Fetch Updated Data ---


        // --- Prepare and Send SMS Notifications (for UPDATE) ---
        if (twilioClient && updatedLecture) {
            console.log(`[BE Update ${lectureId}] Preparing to send UPDATE SMS notifications...`);
            console.log('--- Querying Students With Criteria (Using UPDATED values) ---');
            console.log(`Role: 'student', School: '${updatedLecture.school}', Dept: '${updatedLecture.department}', Course: '${updatedLecture.course}', Year: '${updatedLecture.yearOfStudy}', Sem: '${updatedLecture.semester}', Verified: true`);

            const studentsQuery = db.collection(USERS_COLLECTION)
                .where('role', '==', 'student')
                .where('school', '==', updatedLecture.school)
                .where('department', '==', updatedLecture.department)
                .where('course', '==', updatedLecture.course)
                .where('yearOfStudy', '==', updatedLecture.yearOfStudy)
                .where('semester', '==', updatedLecture.semester)
                .where('isVerified', '==', true);

            try {
                const studentsSnapshot = await studentsQuery.get();
                if (studentsSnapshot.empty) {
                    console.log(`[BE Update ${lectureId}] UPDATE SMS: No matching students found.`);
                } else {
                    console.log(`[BE Update ${lectureId}] UPDATE SMS: Found ${studentsSnapshot.size} potential student(s) for notification.`);
                    const smsStartTime = formatDateTimeForSMS(updatedLecture.startTime.toDate());
                    let smsVenueInfo = `at ${updatedLecture.venue}`;
                    if (updatedLecture.venue.toUpperCase() === 'ONLINE' && updatedLecture.onlineLink) {
                        smsVenueInfo = `online. Link: ${updatedLecture.onlineLink}`;
                    }
                    const smsMessageBody = `${smsSenderName} Update: Lecture for ${updatedLecture.unitName} (${updatedLecture.unitCode}) by ${updatedLecture.lecturerName} is now scheduled for ${smsStartTime} ${smsVenueInfo}.`;
                    const smsPromises = [];

                    studentsSnapshot.forEach(studentDoc => {
                        const studentData = studentDoc.data();
                        const studentId = studentDoc.id;
                        const studentPhoneNumber = studentData.phoneNumber;
                        if (studentPhoneNumber && typeof studentPhoneNumber === 'string' && studentPhoneNumber.startsWith('+') && studentPhoneNumber.length > 10) {
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
                            console.warn(`[BE Update ${lectureId}] UPDATE SMS: Skipping student ${studentId}: Invalid phone ('${studentPhoneNumber}')`);
                        }
                    });

                    if (smsPromises.length > 0) {
                        console.log(`[BE Update ${lectureId}] UPDATE SMS: Attempting to send ${smsPromises.length} messages...`);
                        const results = await Promise.allSettled(smsPromises);
                        const successfulSends = results.filter(r => r.status === 'fulfilled').length;
                        const failedSends = results.filter(r => r.status === 'rejected').length;
                        console.log(`[BE Update ${lectureId}] UPDATE SMS: Sending complete: ${successfulSends} succeeded, ${failedSends} failed.`);
                        results.filter(r => r.status === 'rejected').forEach(failure => {
                             console.warn(` -> [BE Update ${lectureId}] UPDATE SMS Failed Detail: Phone: ${failure.reason.phone}, Code: ${failure.reason.code || 'N/A'}, Error: ${failure.reason.error}`);
                        });
                    } else {
                         console.log(`[BE Update ${lectureId}] UPDATE SMS: No valid student phone numbers found.`);
                    }
                }
            } catch (smsQueryError) {
                console.error(`[BE Update ${lectureId}] UPDATE SMS: Error querying students or sending SMS:`, smsQueryError);
                 if (smsQueryError.code === 'failed-precondition' || (smsQueryError.message && smsQueryError.message.includes('index'))) {
                     console.error("[BE Update ${lectureId}] UPDATE SMS: Firestore Index Missing for Student Query.");
                 }
            }
        } else if (!twilioClient) {
            console.warn(`[BE Update ${lectureId}] Twilio client not initialized. Skipping UPDATE SMS notifications.`);
        } else if (!updatedLecture) {
             console.warn(`[BE Update ${lectureId}] Updated lecture data was unavailable. Skipping UPDATE SMS notifications.`);
        }
        // --- END SMS Logic for UPDATE ---


        // --- Return Success Response ---
        // Ensure the response uses the helper to format timestamps correctly for the client
        console.log(`[BE Update ${lectureId}] Sending success response to client.`);
        res.status(200).json({
            id: updatedDoc.id,
            ...(updatedLecture || {}), // Send empty object if fetch failed
            lectureDate: formatTimestampForClient(updatedLecture?.lectureDate),
            startTime: formatTimestampForClient(updatedLecture?.startTime),
            endTime: formatTimestampForClient(updatedLecture?.endTime),
            createdAt: formatTimestampForClient(updatedLecture?.createdAt),
        });

    } catch (error) {
        console.error(`[BE Update ${lectureId}] Error updating lecture:`, error);
        console.error('Error Stack:', error.stack);
        res.status(500).json({
            message: 'Internal server error while updating lecture.',
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
        const userRoleDoc = await db.collection(USERS_COLLECTION).doc(authenticatedUserId).get();
        const userRole = userRoleDoc.exists ? userRoleDoc.data().role : null;
        const isAdmin = userRole === 'admin';

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
