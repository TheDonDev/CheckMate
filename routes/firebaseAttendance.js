// c:\Users\Test\FlutterProjects\checkmate\routes\firebaseAttendance.js

const express = require('express');
const { db, admin } = require('../firebase'); // Ensure admin is required for FieldValue.serverTimestamp()
const router = express.Router();
const checkAuth = require('../middleware/checkAuth');

// --- Constants for Collection Names (Standardized to lowercase) ---
const ATTENDANCE_COLLECTION = 'attendance'; // Standardized
const USERS_COLLECTION = 'users';
const LECTURES_COLLECTION = 'lectures';

// --- Helper Function for Timestamp Conversion (Firestore -> Client ISO String) ---
const formatTimestamp = (timestamp) => {
  // Check if it's a Firestore Timestamp object
  if (timestamp && typeof timestamp.toDate === 'function') {
    return timestamp.toDate().toISOString();
  }
  // Check if it's already a JS Date object (might happen in some cases)
  if (timestamp instanceof Date && !isNaN(timestamp.getTime())) {
    return timestamp.toISOString();
  }
   // Handle case where it might already be an ISO string (e.g., from previous processing)
  if (typeof timestamp === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/.test(timestamp)) {
     return timestamp; // Return as is if it looks like an ISO string
  }
  // console.warn(`Could not format timestamp for client:`, timestamp); // Reduced verbosity
  return null; // Return null if format is unrecognized or null/undefined
};


// --- Student JOINS a lecture (Manual Button) ---
// Endpoint: POST /api/firebase/attendance/join/:lectureId
// Creates a record with checkedIn: false.
router.post('/join/:lectureId', checkAuth, async (req, res) => {
  try {
    const lectureId = req.params.lectureId;
    const studentUserId = req.userData.userId; // Get user ID from authenticated token

    // --- Validate Lecture Exists ---
    const lectureRef = db.collection(LECTURES_COLLECTION).doc(lectureId);
    const lectureDoc = await lectureRef.get();
    if (!lectureDoc.exists) {
        console.log(`Join attempt failed: Lecture not found with ID: ${lectureId}`);
        return res.status(404).json({ message: 'Lecture not found or is no longer available.' });
    }
    const lectureData = lectureDoc.data();

    // --- Fetch Student Details ---
    const studentUserRef = db.collection(USERS_COLLECTION).doc(studentUserId);
    const studentUserDoc = await studentUserRef.get();
    if (!studentUserDoc.exists) {
        console.error(`Join attempt failed: User document not found for authenticated user ID: ${studentUserId}`);
        return res.status(404).json({ message: 'Your user profile could not be found.' });
    }
    const studentData = studentUserDoc.data();

    // --- Authorization & Validation ---
    if (studentData.role !== 'student') {
        console.log(`Join attempt failed: User ${studentUserId} is not a student (role: ${studentData.role}).`);
        return res.status(403).json({ message: 'Forbidden: Only students can join lectures.' });
    }
    const registrationNumber = studentData.registrationNumber;
    if (!registrationNumber) {
        console.log(`Join attempt failed: Student ${studentUserId} does not have a registration number in their profile.`);
        return res.status(400).json({ message: 'Your profile is missing the registration number. Cannot join.' });
    }
    const studentName = studentData.name || 'N/A';

    // --- Validate if student's profile matches lecture criteria ---
    // Ensure case-insensitive or consistent case comparison if needed
    if (studentData.school !== lectureData.school ||
        studentData.department !== lectureData.department ||
        studentData.course !== lectureData.course ||
        studentData.yearOfStudy !== lectureData.yearOfStudy ||
        studentData.semester !== lectureData.semester) {
        console.error(`Join attempt BLOCKED: Student ${studentUserId} profile details (Sch: ${studentData.school}, Dept: ${studentData.department}, Crs: ${studentData.course}, Yr: ${studentData.yearOfStudy}, Sem: ${studentData.semester}) do not match lecture ${lectureId} criteria (Sch: ${lectureData.school}, Dept: ${lectureData.department}, Crs: ${lectureData.course}, Yr: ${lectureData.yearOfStudy}, Sem: ${lectureData.semester}).`);
        return res.status(403).json({ message: 'Your profile details (School/Dept/Course/Year/Semester) do not match this lecture.' });
    }

    // --- Check if attendance record already exists ---
    const attendanceRef = db.collection(ATTENDANCE_COLLECTION);
    const existingJoinQuery = await attendanceRef
        .where('lectureId', '==', lectureId)
        .where('userId', '==', studentUserId)
        .limit(1)
        .get();

    let attendanceRecordData;
    let recordId;
    let statusCode = 200; // Default to OK
    let message = 'Already joined this lecture.'; // Default message

    if (!existingJoinQuery.empty) {
        // Record EXISTS - Return existing data
        console.log(`Student ${studentUserId} already has a record for lecture ${lectureId}. Returning existing record.`);
        const existingDoc = existingJoinQuery.docs[0];
        recordId = existingDoc.id;
        attendanceRecordData = existingDoc.data();
        if (attendanceRecordData.checkedIn === true) {
            message = 'Already checked in for this lecture.';
            statusCode = 409; // Conflict - Already checked in
        } else {
             statusCode = 409; // Conflict - Already joined but not checked in
        }

    } else {
        // Record DOES NOT EXIST - Create new record with checkedIn: false
        console.log(`Student ${studentUserId} joining lecture ${lectureId}. Creating new record.`);
        const serverTimestamp = admin.firestore.FieldValue.serverTimestamp();
        const newRecord = {
          userId: studentUserId,
          studentName: studentName,
          registrationNumber: registrationNumber,
          lectureId: lectureId,
          joinedAt: serverTimestamp, // Record when they joined
          checkedIn: false, // *** CRITICAL: Set to false for JOIN action ***
          checkInTime: null,
          checkedInBy: null,
        };
        const docRef = await attendanceRef.add(newRecord);
        recordId = docRef.id;
        // Fetch the newly created record to include the server timestamp
        const newDocSnapshot = await docRef.get();
        attendanceRecordData = newDocSnapshot.data();
        statusCode = 201; // Created
        message = 'Successfully joined lecture.'; // Update message
    }

    // Return the record (either existing or newly created)
    res.status(statusCode).json({
        message: message,
        id: recordId, // Include the document ID
        ...attendanceRecordData,
        // Ensure timestamps are formatted consistently
        joinedAt: formatTimestamp(attendanceRecordData.joinedAt),
        checkInTime: formatTimestamp(attendanceRecordData.checkInTime),
        // Ensure boolean value is returned correctly
        checkedIn: attendanceRecordData.checkedIn === true,
    });

  } catch (error) {
    console.error(`Error joining lecture ${req.params.lectureId} for user ${req.userData?.userId}:`, error);
    console.error('Error Stack:', error.stack);
    res.status(500).json({
        message: 'Internal Server Error: Failed to process join request',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});


// --- Student CHECKS IN for a lecture via Lecture QR Scan ---
// Endpoint: POST /api/firebase/attendance/checkin/student/:lectureId
// Requires the student to have ALREADY JOINED (checkedIn: false).
router.post('/checkin/student/:lectureId', checkAuth, async (req, res) => {
    try {
        const lectureId = req.params.lectureId;
        const studentUserId = req.userData.userId; // Get user ID from authenticated token

        // --- Validate Lecture Exists (Optional but good practice) ---
        const lectureRef = db.collection(LECTURES_COLLECTION).doc(lectureId);
        const lectureDoc = await lectureRef.get();
        if (!lectureDoc.exists) {
            console.log(`Student QR Check-in attempt failed: Lecture not found with ID: ${lectureId}`);
            return res.status(404).json({ message: 'Lecture not found or is no longer available.' });
        }

        // --- Find the existing "Joined" attendance record ---
        const attendanceRef = db.collection(ATTENDANCE_COLLECTION);
        const attendanceQuery = await attendanceRef
          .where('lectureId', '==', lectureId)
          .where('userId', '==', studentUserId)
          .limit(1)
          .get();

        if (attendanceQuery.empty) {
            // Record DOES NOT EXIST - Student hasn't joined yet
            console.log(`Student QR Check-in failed: Student ${studentUserId} has not joined lecture ${lectureId} yet.`);
            return res.status(400).json({ message: 'Check-in failed: You must join the lecture first.' }); // 400 Bad Request
        }

        // Record EXISTS - Check its status
        const attendanceDoc = attendanceQuery.docs[0];
        const attendanceData = attendanceDoc.data();

        if (attendanceData.checkedIn === true) {
            // Already checked in
            console.log(`Student QR Check-in skipped: Student ${studentUserId} already checked in for lecture ${lectureId}.`);
            return res.status(409).json({ // 409 Conflict
                message: 'Already checked in for this lecture.',
                id: attendanceDoc.id,
                ...attendanceData,
                joinedAt: formatTimestamp(attendanceData.joinedAt),
                checkInTime: formatTimestamp(attendanceData.checkInTime),
                checkedIn: true,
            });
        }

        // Record exists and checkedIn is false - PROCEED WITH CHECK-IN
        console.log(`Student QR Check-in: Updating record for student ${studentUserId} in lecture ${lectureId}.`);
        const serverTimestamp = admin.firestore.FieldValue.serverTimestamp();
        await attendanceDoc.ref.update({
            checkedIn: true,
            checkInTime: serverTimestamp,
            checkedInBy: 'student_self_qr', // Indicate self check-in via lecture QR
        });

        // Fetch the updated doc to return accurate data
        const updatedDoc = await attendanceDoc.ref.get();
        const updatedData = updatedDoc.data();

        res.status(200).json({ // 200 OK for successful update
            message: 'Successfully checked in.',
            id: updatedDoc.id,
            ...updatedData,
            joinedAt: formatTimestamp(updatedData.joinedAt),
            checkInTime: formatTimestamp(updatedData.checkInTime),
            checkedIn: true,
        });

    } catch (error) {
        console.error(`Error during student QR check-in for lecture ${req.params.lectureId} by user ${req.userData?.userId}:`, error);
        console.error('Error Stack:', error.stack);
        res.status(500).json({
            message: 'Internal Server Error: Failed to process QR check-in',
            details: process.env.NODE_ENV !== 'production' ? error.message : undefined
        });
    }
});


// --- Lecturer manually checks in a student (or via scanning student QR) ---
// Endpoint: POST /api/firebase/attendance/checkin
// *** Requires the student to have ALREADY JOINED (record exists with checkedIn: false) ***
router.post('/checkin', checkAuth, async (req, res) => {
  try {
    const lecturerUserId = req.userData.userId; // Get lecturer ID from token
    const { registrationNumber, lectureId } = req.body;

    // --- Validate Input ---
    if (!registrationNumber || typeof registrationNumber !== 'string' || registrationNumber.trim() === '') {
      console.log(`Lecturer Check-in failed: Missing or invalid registrationNumber.`);
      return res.status(400).json({ message: 'Student Registration Number is required.' });
    }
    if (!lectureId || typeof lectureId !== 'string' || lectureId.trim() === '') {
      console.log(`Lecturer Check-in failed: Missing or invalid lectureId.`);
      return res.status(400).json({ message: 'Lecture ID is required.' });
    }
    const trimmedRegNum = registrationNumber.trim().toUpperCase();
    const trimmedLectureId = lectureId.trim();

    // --- Verify Lecturer Role ---
    const lecturerUserRef = db.collection(USERS_COLLECTION).doc(lecturerUserId);
    const lecturerUserDoc = await lecturerUserRef.get();
    if (!lecturerUserDoc.exists || lecturerUserDoc.data().role !== 'lecturer') {
        console.log(`Lecturer Check-in failed: User ${lecturerUserId} is not authorized.`);
        return res.status(403).json({ message: 'Forbidden: Only lecturers can check students in.' });
    }

    // --- Verify the Lecture Exists ---
    const lectureRef = db.collection(LECTURES_COLLECTION).doc(trimmedLectureId);
    const lectureDoc = await lectureRef.get();
    if (!lectureDoc.exists) {
        console.log(`Lecturer Check-in failed: Lecture ${trimmedLectureId} not found.`);
        return res.status(404).json({ message: 'Lecture not found.' });
    }
    // --- Optional: Verify this lecturer is associated with the lecture ---
    // if (lectureDoc.data().lecturerId !== lecturerUserId) { ... }

    // --- Find the student's user document by registration number ---
    const studentQuery = await db.collection(USERS_COLLECTION)
        .where('registrationNumber', '==', trimmedRegNum)
        .where('role', '==', 'student')
        .limit(1)
        .get();

    if (studentQuery.empty) {
        console.log(`Lecturer Check-in failed: Student with registration number ${trimmedRegNum} not found.`);
        return res.status(404).json({ message: `Student with registration number ${trimmedRegNum} not found.` });
    }
    const studentDoc = studentQuery.docs[0];
    const studentUserId = studentDoc.id;
    const studentName = studentDoc.data().name || 'N/A';

    // --- Find the EXISTING attendance record for this student and lecture ---
    const attendanceRef = db.collection(ATTENDANCE_COLLECTION);
    const attendanceQuery = await attendanceRef
      .where('lectureId', '==', trimmedLectureId)
      .where('userId', '==', studentUserId) // Use the found studentUserId
      .limit(1)
      .get();

    // --- *** CORE LOGIC CHANGE: Reject if student hasn't joined *** ---
    if (attendanceQuery.empty) {
      // **REJECT** if no record exists - Student hasn't joined!
      console.warn(`Lecturer Check-in REJECTED: Student ${studentUserId} (${trimmedRegNum}) has not joined lecture ${trimmedLectureId}.`);
      // Return 400 Bad Request indicating the prerequisite (joining) is missing.
      return res.status(400).json({ message: 'Student has not joined this lecture yet.' });
    }
    // --- *** END CORE LOGIC CHANGE *** ---

    // If we reach here, a record exists (student has joined).
    const attendanceDocRef = attendanceQuery.docs[0].ref;
    const currentAttendanceData = attendanceQuery.docs[0].data();
    const serverTimestamp = admin.firestore.FieldValue.serverTimestamp();
    let statusCode = 200; // Default OK
    let responseMessage = '';

    // Check if already checked in
    if (currentAttendanceData.checkedIn === true) {
        console.log(`Lecturer Check-in skipped: Student ${trimmedRegNum} already checked into lecture ${trimmedLectureId}.`);
        responseMessage = 'Student already checked in.';
        statusCode = 409; // Conflict
    } else {
        // Record exists but not checked in, update it
        console.log(`Lecturer Check-in: Updating existing record for student ${studentUserId} in lecture ${trimmedLectureId}.`);
        await attendanceDocRef.update({
          checkedIn: true,
          checkInTime: serverTimestamp,
          checkedInBy: lecturerUserId, // Record lecturer who checked them in
        });
        responseMessage = `Student ${studentName} (${trimmedRegNum}) checked in successfully.`;
        statusCode = 200; // OK, updated
    }

    console.log(`Lecturer Check-in processed for student ${trimmedRegNum} in lecture ${trimmedLectureId} by lecturer ${lecturerUserId}. Status: ${statusCode}`);

    // Fetch the final data to return consistent timestamps
    const finalDoc = await attendanceDocRef.get();
    const finalData = finalDoc.data();

    // --- Return success/conflict message with student details ---
    res.status(statusCode).json({
        message: responseMessage,
        id: finalDoc.id,
        ...finalData,
        checkInTime: formatTimestamp(finalData.checkInTime),
        joinedAt: formatTimestamp(finalData.joinedAt),
        checkedIn: finalData.checkedIn === true, // Ensure boolean
    });

  } catch (error) {
    console.error(`Error during lecturer check-in (Reg#: ${req.body?.registrationNumber}, Lecture: ${req.body?.lectureId}) by lecturer ${req.userData?.userId}:`, error);
    console.error('Error Stack:', error.stack);
    if (error.code === 'failed-precondition' || (error.message && error.message.includes('index'))) {
        console.error("Firestore Index Missing: Check-in query might require an index.");
        return res.status(500).json({ message: 'Internal Server Error: Database index missing.', details: 'A required Firestore index is missing.' });
    }
    res.status(500).json({
        message: 'Internal Server Error: Failed to check in student',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});


// --- Student views their attendance history & summary ---
// Endpoint: GET /api/firebase/attendance/student/:userId?year=YYYY&semester=SEMESTER_NAME
// *** MODIFIED TO ACCEPT year & semester QUERY PARAMETERS FOR FILTERING ***
router.get('/student/:userId', checkAuth, async (req, res) => {
  try {
    const requestedUserId = req.params.userId;
    const authUserId = req.userData.userId; // User ID from the token

    // --- Authorization: Ensure users can only view their own attendance ---
    if (requestedUserId !== authUserId) {
        console.log(`Forbidden attempt: User ${authUserId} tried to access attendance for ${requestedUserId}`);
        return res.status(403).json({ message: 'Forbidden: You can only access your own attendance records.' });
    }

    // --- Get Year/Semester Filters from Query Params ---
    const queryYear = req.query.year;
    const querySemester = req.query.semester;
    console.log(`Fetching attendance summary for user ${requestedUserId}. Filters - Year: ${queryYear || 'None'}, Semester: ${querySemester || 'None'}`);

    // --- Initialize Summary Variables ---
    let percentage = 0;
    let totalRelevantLectures = 0;
    let attendedLecturesCount = 0;
    let relevantLectureIds = [];
    let filteredAttendanceRecords = []; // Store records filtered by year/semester

    // --- Fetch user profile to get base criteria (school, dept, course) ---
    const userDoc = await db.collection(USERS_COLLECTION).doc(requestedUserId).get();
    if (!userDoc.exists) {
        console.warn(`Cannot calculate attendance for user ${requestedUserId}: User document not found.`);
        // Return empty summary if user profile is missing
        return res.json({
            attendanceRecords: [],
            percentage: '0.00',
            totalLectures: 0,
            attendedLectures: 0,
        });
    }

    const userData = userDoc.data();
    const { school, department, course } = userData;

    // Determine the year and semester to use for filtering
    const filterYear = queryYear || userData.yearOfStudy; // Use query param or fallback to profile
    const filterSemester = querySemester || userData.semester; // Use query param or fallback to profile

    // Proceed only if we have the necessary criteria (school, dept, course, year, semester)
    if (school && department && course && filterYear && filterSemester) {
        try {
            // --- 1. Query Relevant Lectures for the specific year/semester ---
            const lecturesRef = db.collection(LECTURES_COLLECTION);
            const lecturesQuery = lecturesRef
                .where('school', '==', school)
                .where('department', '==', department)
                .where('course', '==', course)
                .where('yearOfStudy', '==', filterYear) // Use determined filter year
                .where('semester', '==', filterSemester); // Use determined filter semester

            const lecturesSnapshot = await lecturesQuery.get();
            relevantLectureIds = lecturesSnapshot.docs.map(doc => doc.id);
            totalRelevantLectures = relevantLectureIds.length;
            console.log(`Found ${totalRelevantLectures} relevant lectures for criteria: School=${school}, Dept=${department}, Course=${course}, Year=${filterYear}, Sem=${filterSemester}`);

            if (totalRelevantLectures > 0) {
                // --- 2. Fetch ALL attendance records for the student ---
                // Filtered these in memory later based on relevantLectureIds
                const allAttendanceSnapshot = await db.collection(ATTENDANCE_COLLECTION)
                                                    .where('userId', '==', requestedUserId)
                                                    .get();

                // --- 3. Filter attendance records by relevant lecture IDs ---
                const relevantAttendanceDocs = allAttendanceSnapshot.docs.filter(doc =>
                    relevantLectureIds.includes(doc.data().lectureId)
                );

                // --- 4. Format and Count Attended from Filtered Records ---
                filteredAttendanceRecords = relevantAttendanceDocs.map(doc => {
                    const data = doc.data();
                    return {
                        id: doc.id,
                        ...data,
                        checkInTime: formatTimestamp(data.checkInTime),
                        joinedAt: formatTimestamp(data.joinedAt),
                        checkedIn: data.checkedIn === true,
                    };
                }).sort((a, b) => (b.joinedAt || '').localeCompare(a.joinedAt || '')); // Sort descending by join time

                attendedLecturesCount = filteredAttendanceRecords.filter(record => record.checkedIn === true).length;

                // --- 5. Calculate Percentage ---
                percentage = (attendedLecturesCount / totalRelevantLectures) * 100;
                console.log(`Attendance calculation for ${requestedUserId} (Year: ${filterYear}, Sem: ${filterSemester}): Attended ${attendedLecturesCount} / Total ${totalRelevantLectures} relevant lectures.`);

            } else {
                // No relevant lectures found for the criteria
                console.log(`No relevant lectures found for user ${requestedUserId} with criteria (Year: ${filterYear}, Sem: ${filterSemester}). Percentage is 0.`);
                percentage = 0;
            }

        } catch (calcError) {
            console.error(`Error calculating attendance percentage for user ${requestedUserId} (Year: ${filterYear}, Sem: ${filterSemester}):`, calcError);
            if (calcError.code === 'failed-precondition' || (calcError.message && calcError.message.includes('index'))) {
                 console.error("Firestore Index Missing for Percentage Calculation. Check Firebase console for index creation link.");
            }
            console.warn(`Proceeding with potentially inaccurate summary due to calculation error.`);
            // Fallback: Return 0/empty if calculation failed severely
            percentage = 0;
            totalRelevantLectures = 0;
            attendedLecturesCount = 0;
            filteredAttendanceRecords = []; // Ensure empty on error
        }
    } else {
        // Missing necessary profile details or filter criteria
        console.warn(`Cannot calculate attendance for user ${requestedUserId}: Missing profile details (School/Dept/Course) or filter criteria (Year/Semester).`);
        // Return empty/zero summary
        percentage = 0;
        totalRelevantLectures = 0;
        attendedLecturesCount = 0;
        filteredAttendanceRecords = [];
    }

    // --- Prepare final response data ---
    const data = {
      // Return the records filtered by year/semester
      attendanceRecords: filteredAttendanceRecords,
      percentage: percentage.toFixed(2), // Ensure percentage is always a string with 2 decimal places
      totalLectures: totalRelevantLectures,
      attendedLectures: attendedLecturesCount,
    };
    res.json(data);

  } catch (error) {
    console.error(`Error getting student attendance for user ${req.params.userId}:`, error);
    console.error('Error Stack:', error.stack);
    res.status(500).json({
        message: 'Internal Server Error: Failed to get student attendance',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});


//--- Lecturer view student attendance for a particular lecture (WITH OVERALL PERCENTAGE) ---
// Endpoint: GET /api/firebase/attendance/lecture/:lectureId
// Calculates each student's OVERALL percentage based on their profile, not just this lecture.
router.get('/lecture/:lectureId', checkAuth, async (req, res) => {
  try {
    const lectureId = req.params.lectureId;
    const lecturerUserId = req.userData.userId; // User ID from the token

    // --- Authorization: Ensure user is a lecturer ---
    const lecturerUserRef = db.collection(USERS_COLLECTION).doc(lecturerUserId);
    const lecturerUserDoc = await lecturerUserRef.get();
    if (!lecturerUserDoc.exists || lecturerUserDoc.data().role !== 'lecturer') {
        console.log(`Attendance view failed: User ${lecturerUserId} is not authorized.`);
        return res.status(403).json({ message: 'Forbidden: Only lecturers can view lecture attendance.' });
    }

    // --- Verify the lecture exists ---
    const lectureRef = db.collection(LECTURES_COLLECTION).doc(lectureId);
    const lectureDoc = await lectureRef.get();
    if (!lectureDoc.exists) {
        console.log(`Attendance view failed: Lecture ${lectureId} not found.`);
        return res.status(404).json({ message: 'Lecture not found.' });
    }
    // --- Optional: Verify this lecturer owns the lecture ---
    // if (lectureDoc.data().lecturerId !== lecturerUserId) { ... }

    // --- Fetch Attendance Records for the specific lecture ---
    const attendanceRef = db.collection(ATTENDANCE_COLLECTION);
    const snapshot = await attendanceRef.where('lectureId', '==', lectureId).orderBy('studentName', 'asc').get();

    const attendanceRecordsRaw = snapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
    }));

    // --- Calculate OVERALL Percentage for Each Student Concurrently ---
    const percentageCalculationPromises = attendanceRecordsRaw.map(async (record) => {
        let percentage = "N/A"; // Default value if calculation fails or not applicable
        const studentUserId = record.userId;

        if (!studentUserId) {
            console.warn(`Skipping percentage calculation for record ${record.id}: Missing userId.`);
            return { ...record, percentage }; // Return record with default percentage
        }

        try {
            // 1. Fetch student profile
            const userDoc = await db.collection(USERS_COLLECTION).doc(studentUserId).get();
            if (userDoc.exists) {
                const userData = userDoc.data();
                // Use the student's PROFILE year/semester for OVERALL calculation
                const { school, department, course, yearOfStudy, semester } = userData;

                // 2. Check if profile details are complete
                if (school && department && course && yearOfStudy && semester) {
                    // 3. Query relevant lectures based on student's PROFILE (Requires composite index)
                    const lecturesQuery = db.collection(LECTURES_COLLECTION)
                        .where('school', '==', school)
                        .where('department', '==', department)
                        .where('course', '==', course)
                        .where('yearOfStudy', '==', yearOfStudy) // PROFILE year
                        .where('semester', '==', semester);      // PROFILE semester
                    const lecturesSnapshot = await lecturesQuery.get();
                    const totalRelevantLectures = lecturesSnapshot.size;

                    // 4. Query ALL attended lectures for this student (Requires index on userId + checkedIn)
                    const attendedQuery = db.collection(ATTENDANCE_COLLECTION)
                        .where('userId', '==', studentUserId)
                        .where('checkedIn', '==', true);
                    const attendedSnapshot = await attendedQuery.get();
                    const attendedLecturesCount = attendedSnapshot.size;

                    // 5. Calculate percentage
                    if (totalRelevantLectures > 0) {
                        percentage = ((attendedLecturesCount / totalRelevantLectures) * 100).toFixed(2);
                    } else {
                        percentage = "0.00"; // No relevant lectures found, so percentage is 0
                    }
                    // console.log(`Overall Percentage for ${studentUserId}: ${attendedLecturesCount}/${totalRelevantLectures} = ${percentage}%`); // Optional detailed log
                } else {
                     console.warn(`Cannot calculate overall percentage for user ${studentUserId}: Missing profile details. Setting percentage to N/A.`);
                     // Keep percentage as "N/A" if profile is incomplete
                }
            } else {
                 console.warn(`Cannot calculate overall percentage for user ${studentUserId}: User document not found. Setting percentage to N/A.`);
                 // Keep percentage as "N/A" if user doc not found
            }
        } catch (percError) {
            console.error(`Error calculating overall percentage for student ${studentUserId}:`, percError);
            // Check for index errors specifically
            if (percError.code === 'failed-precondition' || (percError.message && percError.message.includes('index'))) {
                 console.error(` -> Firestore Index Missing for Overall Percentage Calculation (Student: ${studentUserId}). Check Firebase console.`);
            }
            // Keep percentage as "N/A" on error
        }
        // Return the original record data merged with the calculated percentage
        return { ...record, percentage };
    });

    // Wait for all percentage calculations to complete
    const attendanceRecordsWithPercentage = await Promise.all(percentageCalculationPromises);
    // --- *** END PERCENTAGE CALCULATION *** ---


    // --- Format final response ---
    const finalResponseData = attendanceRecordsWithPercentage.map(data => ({
        id: data.id,
        registrationNumber: data.registrationNumber || 'N/A',
        studentName: data.studentName || 'N/A',
        lectureId: data.lectureId,
        userId: data.userId,
        checkedIn: data.checkedIn === true, // Ensure boolean
        checkInTime: formatTimestamp(data.checkInTime),
        joinedAt: formatTimestamp(data.joinedAt),
        checkedInBy: data.checkedInBy || null,
        percentage: data.percentage, // Include the calculated or default OVERALL percentage
    }));

    console.log(`Fetched ${finalResponseData.length} attendance records (with overall percentages) for lecture ${lectureId} by request from lecturer ${lecturerUserId}.`);
    res.json(finalResponseData); // Return the array of records with percentages

  } catch (error) {
    console.error(`Error getting lecture attendance for lecture ${req.params.lectureId}:`, error);
    console.error('Error Stack:', error.stack);
    // Check specifically for Firestore index errors if ordering was added
    if (error.code === 'failed-precondition' || (error.message && error.message.includes('index'))) {
        console.error("Firestore Index Missing: The query requires an index (likely on lectureId and studentName). Check the error details for a link to create it.");
        return res.status(500).json({
            message: 'Internal Server Error: Failed to get lecture attendance due to missing database index.', // Use message
            details: 'A required Firestore index is missing.'
        });
    }
    res.status(500).json({
        message: 'Internal Server Error: Failed to get lecture attendance', // Use message
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});


module.exports = router;
