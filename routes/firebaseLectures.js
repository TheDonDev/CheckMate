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
  // Keep twilioClient as null, SMS sending will be skipped later
} else {
  try {
    twilioClient = twilio(accountSid, authToken);
    console.log("Twilio client initialized successfully.");
  } catch (error) {
    console.error("FATAL ERROR: Failed to initialize Twilio client:", error);
    // Keep twilioClient as null if initialization fails
  }
}

// --- Constants ---
const LECTURES_COLLECTION = 'lectures';
const USERS_COLLECTION = 'users';
const ATTENDANCE_COLLECTION = 'attendance'; // Added for deleting attendance records

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
  // Firestore Timestamp object
  if (timestamp && typeof timestamp.toDate === 'function') {
    return timestamp.toDate().toISOString();
  }
  // JS Date object
  if (timestamp instanceof Date && !isNaN(timestamp.getTime())) {
    return timestamp.toISOString();
  }
  // ISO String (basic check)
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
    // Using 'en-KE' locale for Kenyan English formatting
    return dateObj.toLocaleString('en-KE', {
        weekday: 'short',
        month: 'short',
        day: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
        hour12: true,
        // timeZone: 'Africa/Nairobi' // Optional: Explicitly set timezone if server isn't in EAT
    });
};


// --- Create a Lecture (with SMS Notification) ---
router.post('/', checkAuth, async (req, res) => {
  let createdLectureId = null;

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
        // Still fetch user data for name/phone fallback even for bypass user
        userDoc = await db.collection(USERS_COLLECTION).doc(authUserId).get();
        userData = userDoc.exists ? userDoc.data() : {};
        if (!userDoc.exists) console.warn(`Bypass user ${authUserEmail} document not found, proceeding with defaults.`);
    }
    if (!userData) { // Should ideally not happen after the checks above
        console.error(`Critical Error: User data unavailable after authorization check for user ${authUserId}.`);
        return res.status(500).json({ error: 'Internal Server Error: Failed to retrieve user details.' });
    }
    // --- End Auth ---

    // --- Extract & Validate Request Body ---
    const {
      lecturerPhone, school, department, course, yearOfStudy, semester,
      unitName, unitCode, lectureDate, startTime, endTime, venue,
    } = req.body;

    // Basic validation for required fields
    const requiredFields = { school, department, course, yearOfStudy, semester, unitName, unitCode, lectureDate, startTime, endTime, venue };
    for (const [key, value] of Object.entries(requiredFields)) {
        if (!value) {
            console.error(`Validation Error: Missing required field '${key}'`);
            return res.status(400).json({ error: `Missing required lecture field: ${key}` });
        }
    }

    // Date/Time Parsing and Validation
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
    const newLectureData = {
      lecturerId: authUserId,
      lecturerName: userData.name || 'N/A', // Get name from lecturer's profile
      lecturerPhone: lecturerPhone || userData.phoneNumber || null, // Use provided, fallback to profile
      school: school.trim(), // Trim whitespace just in case
      department: department.trim(),
      course: course.trim(),
      yearOfStudy: yearOfStudy.trim(),
      semester: semester.trim(),
      unitName: unitName.trim(),
      unitCode: unitCode.trim(),
      lectureDate: parsedLectureDate,
      startTime: parsedStartTime,
      endTime: parsedEndTime,
      venue: venue.trim(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(), // Use server timestamp
    };
    // --- End Prepare Data ---

    // --- *** 1. Add the lecture document to Firestore *** ---
    const docRef = await db.collection(LECTURES_COLLECTION).add(newLectureData);
    createdLectureId = docRef.id;
    console.log(`Lecture created successfully with ID: ${createdLectureId} by user ${authUserEmail}`);

    // --- Fetch the created doc to get accurate data (including server timestamp) ---
    const createdDoc = await docRef.get();
    const createdData = createdDoc.data();
    if (!createdData) {
        // This should ideally not happen if add() was successful, but good to check
        console.error(`Critical Error: Failed to fetch created lecture data for ID: ${createdLectureId}`);
        // Still proceed to send response, but log the error
    }

    // --- *** 2. Prepare and Send SMS Notifications *** ---
    // Only proceed if Twilio client was initialized successfully
    if (twilioClient && createdData) {
        console.log(`Preparing to send SMS notifications for lecture ${createdLectureId}...`);

        // --- Log the EXACT criteria being used for the student query ---
        console.log('--- Querying Students With Criteria ---');
        console.log(`Role:        'student'`);
        console.log(`School:      '${createdData.school}'`);
        console.log(`Department:  '${createdData.department}'`);
        console.log(`Course:      '${createdData.course}'`);
        console.log(`YearOfStudy: '${createdData.yearOfStudy}'`);
        console.log(`Semester:    '${createdData.semester}'`);
        console.log(`IsVerified:  true`);
        console.log('------------------------------------');
        console.log('>>> DEBUG: Compare these values EXACTLY (case, whitespace) with data in your Firestore `users` collection for students who *should* match. <<<');

        // Build the Firestore query to find matching students
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
                console.log(`QUERY RESULT: No matching students found for lecture ${createdLectureId}. No SMS sent. Check Firestore data consistency.`);
            } else {
                console.log(`QUERY RESULT: Found ${studentsSnapshot.size} potential student(s) for notification.`);

                // Format key details for the SMS message (only if students found)
                const smsStartTime = formatDateTimeForSMS(createdData.startTime.toDate()); // Convert Firestore Timestamp
                const smsMessageBody = `${smsSenderName} Alert: New lecture for ${createdData.unitName} (${createdData.unitCode}) ` +
                                       `by ${createdData.lecturerName} on ${smsStartTime} ` +
                                       `at ${createdData.venue}.`;

                const smsPromises = []; // Array to hold all SMS sending promises

                studentsSnapshot.forEach(studentDoc => {
                    const studentData = studentDoc.data();
                    const studentId = studentDoc.id;
                    const studentPhoneNumber = studentData.phoneNumber; // **VERIFY THIS FIELD NAME**

                    console.log(`Processing student ${studentId}: Phone='${studentPhoneNumber}', Verified='${studentData.isVerified}', Role='${studentData.role}'`);

                    // Validate phone number
                    if (studentPhoneNumber && typeof studentPhoneNumber === 'string' && studentPhoneNumber.startsWith('+') && studentPhoneNumber.length > 10) {
                        console.log(`Queueing SMS to student ${studentId} at ${studentPhoneNumber}`);
                        smsPromises.push(
                            twilioClient.messages.create({
                                body: smsMessageBody,
                                messagingServiceSid: messagingServiceSid,
                                to: studentPhoneNumber
                            })
                            .then(message => {
                                console.log(`SMS sent successfully to ${studentPhoneNumber} (Student ID: ${studentId}), SID: ${message.sid}`);
                                return { status: 'fulfilled', sid: message.sid, phone: studentPhoneNumber };
                            })
                            .catch(error => {
                                console.error(`Failed to send SMS to ${studentPhoneNumber} (Student ID: ${studentId}): ${error.message}`);
                                console.error(`Twilio Error Code: ${error.code || 'N/A'}, More Info: ${error.moreInfo || 'N/A'}`);
                                return { status: 'rejected', error: error.message, phone: studentPhoneNumber, code: error.code };
                            })
                        );
                    } else {
                        console.warn(`Skipping SMS for student ${studentId}: Invalid or missing phone number ('${studentPhoneNumber}')`);
                    }
                });

                // Send all SMS messages
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
            // Don't block the main response for SMS errors
        }

    } else if (!twilioClient) {
        console.warn(`Twilio client not initialized. Skipping SMS notifications for lecture ${createdLectureId}.`);
    } else if (!createdData) {
         console.warn(`Created lecture data was unavailable. Skipping SMS notifications for lecture ${createdLectureId}.`);
    }
    // --- *** End SMS Logic *** ---


    // --- *** 3. Return the success response to the client *** ---
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
    // --- Global Error Handling for the Route ---
    console.error(`Error processing POST /lectures request (Lecture ID if created: ${createdLectureId || 'N/A'}):`, error);
    console.error('Error Stack:', error.stack);

    let errorMessage = 'Internal Server Error: Failed to create lecture or process notifications';
    let statusCode = 500;

    if (error.code && error.message && error.message.includes('Twilio')) {
        errorMessage = 'Internal Server Error: Failed during SMS notification process.';
    } else if (error.code === 'permission-denied' || error.status === 403) {
        errorMessage = 'Forbidden: You do not have permission to perform this action.';
        statusCode = 403;
    } else if (error.status === 400) {
        errorMessage = error.message || 'Bad Request: Invalid input data.';
        statusCode = 400;
    } else if (error.code) {
        errorMessage = `Internal Server Error: Database operation failed (Code: ${error.code})`;
    }

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

        if (requestedLecturerId !== authUserId) {
            console.log(`Forbidden attempt: User ${authUserId} tried to access lectures for ${requestedLecturerId}`);
            return res.status(403).json({ error: 'Forbidden: You can only access your own lectures.' });
        }

        console.log(`Fetching lectures for lecturerId: ${requestedLecturerId}`);
        const lecturesRef = db.collection(LECTURES_COLLECTION);
        const snapshot = await lecturesRef
            .where('lecturerId', '==', requestedLecturerId)
            .orderBy('startTime', 'desc')
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

// --- Get lectures for a student (based on student's profile) ---
router.get('/student', checkAuth, async (req, res) => {
  try {
    const studentUserId = req.userData.userId;

    const studentDoc = await db.collection(USERS_COLLECTION).doc(studentUserId).get();
    if (!studentDoc.exists) {
        console.error(`Student profile not found for authenticated user ID: ${studentUserId}`);
        return res.status(404).json({ error: 'Your user profile could not be found.' });
    }
    const studentData = studentDoc.data();

    const { school, department, course, yearOfStudy, semester, role, isVerified } = studentData;

    if (role !== 'student') {
         console.error(`User ${studentUserId} is not a student (role: ${role}). Cannot fetch student lectures.`);
         return res.status(403).json({ error: 'Forbidden: Only students can access this lecture list.' });
    }
     if (!isVerified) {
         console.warn(`Student ${studentUserId} is not verified. They may not see all lectures.`);
    }
    if (!school || !department || !course || !yearOfStudy || !semester) {
        console.error(`Validation Error: Missing required profile fields for student ${studentUserId} to filter lectures.`);
        return res.status(400).json({ error: 'Your profile is missing required details (school, department, course, year, semester) to find lectures.' });
    }

    console.log(`Fetching lectures for student ${studentUserId} criteria:`, { school, department, course, yearOfStudy, semester });

    const lecturesRef = db.collection(LECTURES_COLLECTION);
    let query = lecturesRef;

    query = query.where('school', '==', school);
    query = query.where('department', '==', department);
    query = query.where('course', '==', course);
    query = query.where('yearOfStudy', '==', yearOfStudy);
    query = query.where('semester', '==', semester);

    const today = new Date();
    today.setHours(0, 0, 0, 0);
    query = query.where('startTime', '>=', today);

    query = query.orderBy('startTime', 'asc');

    const snapshot = await query.get();

    if (snapshot.empty) {
        console.log(`No upcoming student lectures found for student ${studentUserId} with filters: ${JSON.stringify({ school, department, course, yearOfStudy, semester })}`);
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

    console.log(`Found ${lectures.length} upcoming student lectures for student ${studentUserId}`);
    res.json(lectures);
  } catch (error) {
    console.error(`Error getting student lectures for user ${req.userData?.userId}:`, error);

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


// --- Add PUT (Update) endpoint if needed ---
// router.put('/:lectureId', checkAuth, async (req, res) => { ... });

// --- *** ADD DELETE LECTURE ENDPOINT *** ---
router.delete('/:lectureId', checkAuth, async (req, res) => {
    const lectureId = req.params.lectureId;
    const authenticatedUserId = req.userData.userId; // Get user ID from auth middleware

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
        // Ensure the authenticated user is the one who created the lecture
        // TODO: Add admin role check if admins should also be allowed to delete
        if (lectureData.lecturerId !== authenticatedUserId) {
            console.warn(`Unauthorized delete attempt: User ${authenticatedUserId} tried to delete lecture ${lectureId} owned by ${lectureData.lecturerId}`);
            return res.status(403).json({ message: 'Forbidden: You do not have permission to delete this lecture.' });
        }
        // --- END AUTHORIZATION CHECK ---

        // --- Deletion Logic (using Batch Write for atomicity) ---
        const batch = db.batch(); // Initialize batch write

        // 1. Delete the lecture document itself
        batch.delete(lectureRef);
        console.log(`Scheduled deletion for lecture document: ${lectureId}`);

        // 2. Find and schedule deletion for associated attendance records
        const attendanceQuery = db.collection(ATTENDANCE_COLLECTION).where('lectureId', '==', lectureId);
        const attendanceSnapshot = await attendanceQuery.get();

        if (!attendanceSnapshot.empty) {
            console.log(`Found ${attendanceSnapshot.size} attendance records associated with lecture ${lectureId}. Scheduling for deletion.`);
            attendanceSnapshot.docs.forEach(doc => {
                batch.delete(doc.ref); // Add each attendance record deletion to the batch
            });
        } else {
            console.log(`No attendance records found for lecture ${lectureId}.`);
        }

        // 3. Commit the batch write
        await batch.commit();
        // --- End Deletion Logic ---

        console.log(`Lecture ${lectureId} and associated attendance records deleted successfully by user ${authenticatedUserId}.`);
        // Send 204 No Content on successful deletion
        return res.status(204).send();

    } catch (error) {
        console.error(`Error deleting lecture ${lectureId}:`, error);
        console.error('Error Stack:', error.stack); // Log stack trace
        return res.status(500).json({
            message: 'Internal server error while deleting lecture.',
            details: process.env.NODE_ENV !== 'production' ? error.message : undefined
        });
    }
});
// --- *** END DELETE LECTURE ENDPOINT *** ---


module.exports = router; // Export the router
