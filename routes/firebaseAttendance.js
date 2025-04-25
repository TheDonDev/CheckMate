// c:\Users\Test\FlutterProjects\checkmate\routes\firebaseAttendance.js

const express = require('express');
const { db, admin } = require('../firebase');
const router = express.Router();
const checkAuth = require('../middleware/checkAuth');

// --- Constants ---
const ATTENDANCE_COLLECTION = 'attendance';
const USERS_COLLECTION = 'users';
const LECTURES_COLLECTION = 'lectures';

// --- Helper Function ---
const formatTimestamp = (timestamp) => {
  if (timestamp && typeof timestamp.toDate === 'function') {
    return timestamp.toDate().toISOString();
  }
  if (timestamp instanceof Date && !isNaN(timestamp.getTime())) {
    return timestamp.toISOString();
  }
  if (typeof timestamp === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/.test(timestamp)) {
     return timestamp;
  }
  return null;
};

// --- Student JOINS a lecture ---
router.post('/join/:lectureId', checkAuth, async (req, res) => {
  const lectureId = req.params.lectureId;
  const studentUserId = req.userData.userId;
  console.log(`Student ${studentUserId} attempting to join lecture ${lectureId}`); // Log start

  try {
    // --- Validate Lecture Exists ---
    console.log(`[Join ${lectureId}] Fetching lecture details...`);
    const lectureRef = db.collection(LECTURES_COLLECTION).doc(lectureId);
    const lectureDoc = await lectureRef.get();
    if (!lectureDoc.exists) {
        console.log(`[Join ${lectureId}] Lecture not found.`);
        return res.status(404).json({ message: 'Lecture not found or is no longer available.' });
    }
    const lectureData = lectureDoc.data();
    console.log(`[Join ${lectureId}] Lecture found.`);

    // --- Fetch Student Details ---
    console.log(`[Join ${lectureId}] Fetching student profile ${studentUserId}...`);
    const studentUserRef = db.collection(USERS_COLLECTION).doc(studentUserId);
    const studentUserDoc = await studentUserRef.get();
    if (!studentUserDoc.exists) {
        console.log(`[Join ${lectureId}] Student profile ${studentUserId} not found.`);
        return res.status(404).json({ message: 'Your user profile could not be found.' });
    }
    const studentData = studentUserDoc.data();
    console.log(`[Join ${lectureId}] Student profile found.`);

    // --- Authorization & Validation ---
    if (studentData.role !== 'student') {
        console.log(`[Join ${lectureId}] Forbidden: User ${studentUserId} is not a student.`);
        return res.status(403).json({ message: 'Forbidden: Only students can join lectures.' });
    }
    const registrationNumber = studentData.registrationNumber;
    if (!registrationNumber) {
        console.log(`[Join ${lectureId}] Bad Request: Student ${studentUserId} missing registration number.`);
        return res.status(400).json({ message: 'Your profile is missing the registration number. Cannot join.' });
    }
    const studentName = studentData.name || 'N/A';

    // --- Validate if student's profile matches lecture criteria ---
    if (studentData.school !== lectureData.school ||
        studentData.department !== lectureData.department ||
        studentData.course !== lectureData.course ||
        studentData.yearOfStudy !== lectureData.yearOfStudy ||
        studentData.semester !== lectureData.semester) {
        console.error(`[Join ${lectureId}] Join attempt BLOCKED: Student ${studentUserId} profile details do not match lecture criteria.`);
        return res.status(403).json({ message: 'Your profile details (School/Dept/Course/Year/Semester) do not match this lecture.' });
    }
    console.log(`[Join ${lectureId}] Student profile matches lecture criteria.`);

    // --- Check if attendance record already exists ---
    const attendanceRef = db.collection(ATTENDANCE_COLLECTION); // Defined here
    let existingJoinQuery;
    try {
        console.log(`[Join ${lectureId}] Querying existing attendance record...`);
        existingJoinQuery = await attendanceRef
            .where('lectureId', '==', lectureId)
            .where('userId', '==', studentUserId)
            .limit(1)
            .get();
        console.log(`[Join ${lectureId}] Existing attendance query completed. Found: ${!existingJoinQuery.empty}`);
    } catch (queryError) {
        console.error(`[Join ${lectureId}] Error querying existing attendance:`, queryError);
        // Check for index error specifically
        if (queryError.code === 'failed-precondition' || (queryError.message && queryError.message.includes('index'))) {
            console.error(`[Join ${lectureId}] Firestore index missing for attendance query (lectureId, userId).`);
            return res.status(500).json({ message: 'Internal Server Error: Database configuration issue (index missing). Please contact support.', details: 'Index missing for attendance query.' });
        }
        throw queryError; // Re-throw other errors
    }


    let attendanceRecordData;
    let recordId;
    let statusCode = 200;
    let message = 'Already joined this lecture.';

    if (!existingJoinQuery.empty) {
        const existingDoc = existingJoinQuery.docs[0];
        recordId = existingDoc.id;
        attendanceRecordData = existingDoc.data();
        if (attendanceRecordData.checkedIn === true) {
            message = 'Already checked in for this lecture.';
            statusCode = 409; // Conflict
        } else {
             statusCode = 409; // Conflict
        }
        console.log(`[Join ${lectureId}] Student already present in attendance (Status: ${statusCode}).`);
    } else {
        console.log(`[Join ${lectureId}] Creating new attendance record...`);
        const serverTimestamp = admin.firestore.FieldValue.serverTimestamp();
        const newRecord = {
          userId: studentUserId, studentName, registrationNumber, lectureId,
          joinedAt: serverTimestamp, checkedIn: false, checkInTime: null, checkedInBy: null,
        };
        const docRef = await attendanceRef.add(newRecord);
        recordId = docRef.id;
        const newDocSnapshot = await docRef.get(); // Fetch to get server timestamp if needed immediately
        attendanceRecordData = newDocSnapshot.data();
        statusCode = 201; // Created
        message = 'Successfully joined lecture.';
        console.log(`[Join ${lectureId}] New attendance record created (ID: ${recordId}).`);
    }

    console.log(`[Join ${lectureId}] Responding with status ${statusCode}.`);
    res.status(statusCode).json({
        message: message,
        id: recordId,
        ...attendanceRecordData,
        joinedAt: formatTimestamp(attendanceRecordData.joinedAt),
        checkInTime: formatTimestamp(attendanceRecordData.checkInTime),
        checkedIn: attendanceRecordData.checkedIn === true,
    });

  } catch (error) {
    console.error(`[Join ${lectureId}] UNHANDLED Error joining lecture for user ${studentUserId}:`, error);
    res.status(500).json({
        message: 'Internal Server Error: Failed to process join request',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});


// --- Student CHECKS IN via QR --- (Added Time Check)
router.post('/checkin/student/:lectureId', checkAuth, async (req, res) => {
    const lectureId = req.params.lectureId;
    const studentUserId = req.userData.userId;
    console.log(`Student ${studentUserId} attempting QR check-in for lecture ${lectureId}`);

    try {
        // --- Fetch Lecture and Check End Time ---
        console.log(`[QR Check-In ${lectureId}] Fetching lecture details...`);
        const lectureRef = db.collection(LECTURES_COLLECTION).doc(lectureId);
        const lectureDoc = await lectureRef.get();
        if (!lectureDoc.exists) {
            console.log(`[QR Check-In ${lectureId}] Lecture not found.`);
            return res.status(404).json({ message: 'Lecture not found or is no longer available.' });
        }
        const lectureData = lectureDoc.data();
        const lectureEndTime = lectureData.endTime; // Firestore Timestamp
        const now = admin.firestore.Timestamp.now(); // Current server time
        console.log(`[QR Check-In ${lectureId}] Lecture found.`);

        // Validate lecture end time
        if (!lectureEndTime || !(lectureEndTime instanceof admin.firestore.Timestamp)) {
            console.error(`[QR Check-In ${lectureId}] Invalid or missing endTime.`);
            return res.status(500).json({ message: 'Internal Server Error: Lecture data incomplete (endTime).' });
        }

        // *** TIME CHECK ***
        if (now.toMillis() > lectureEndTime.toMillis()) { // Compare milliseconds for accuracy
            console.log(`[QR Check-In ${lectureId}] Failed: Lecture has ended (End: ${lectureEndTime.toDate()}, Now: ${now.toDate()}).`);
            return res.status(400).json({ message: 'Check-in failed: The lecture has already ended.' }); // 400 Bad Request
        }
        console.log(`[QR Check-In ${lectureId}] Time check passed.`);
        // *** END TIME CHECK ***

        // --- Find the existing "Joined" attendance record ---
        const attendanceRef = db.collection(ATTENDANCE_COLLECTION); // Defined here
        let attendanceQuery;
        try {
            console.log(`[QR Check-In ${lectureId}] Querying existing attendance record...`);
            attendanceQuery = await attendanceRef
              .where('lectureId', '==', lectureId)
              .where('userId', '==', studentUserId)
              .limit(1)
              .get();
             console.log(`[QR Check-In ${lectureId}] Existing attendance query completed. Found: ${!attendanceQuery.empty}`);
        } catch (queryError) {
            console.error(`[QR Check-In ${lectureId}] Error querying existing attendance:`, queryError);
            if (queryError.code === 'failed-precondition' || (queryError.message && queryError.message.includes('index'))) {
                 console.error(`[QR Check-In ${lectureId}] Firestore index missing for attendance query (lectureId, userId).`);
                return res.status(500).json({ message: 'Internal Server Error: Database configuration issue (index missing). Please contact support.', details: 'Index missing for attendance query.' });
            }
            throw queryError; // Re-throw other errors
        }


        if (attendanceQuery.empty) {
            console.log(`[QR Check-In ${lectureId}] Failed: Student ${studentUserId} has not joined yet.`);
            return res.status(400).json({ message: 'Check-in failed: You must join the lecture first.' });
        }

        const attendanceDoc = attendanceQuery.docs[0];
        const attendanceData = attendanceDoc.data();

        if (attendanceData.checkedIn === true) {
            console.log(`[QR Check-In ${lectureId}] Skipped: Student ${studentUserId} already checked in.`);
            return res.status(409).json({
                message: 'Already checked in for this lecture.',
                id: attendanceDoc.id,
                ...attendanceData,
                joinedAt: formatTimestamp(attendanceData.joinedAt),
                checkInTime: formatTimestamp(attendanceData.checkInTime),
                checkedIn: true,
            });
        }

        // Proceed with check-in
        console.log(`[QR Check-In ${lectureId}] Updating attendance record for student ${studentUserId}...`);
        const serverTimestamp = admin.firestore.FieldValue.serverTimestamp();
        await attendanceDoc.ref.update({
            checkedIn: true,
            checkInTime: serverTimestamp,
            checkedInBy: 'student_self_qr',
        });
        console.log(`[QR Check-In ${lectureId}] Attendance record updated.`);

        const updatedDoc = await attendanceDoc.ref.get();
        const updatedData = updatedDoc.data();

        console.log(`[QR Check-In ${lectureId}] Responding with status 200.`);
        res.status(200).json({
            message: 'Successfully checked in.',
            id: updatedDoc.id,
            ...updatedData,
            joinedAt: formatTimestamp(updatedData.joinedAt),
            checkInTime: formatTimestamp(updatedData.checkInTime),
            checkedIn: true,
        });

    } catch (error) {
        console.error(`[QR Check-In ${lectureId}] UNHANDLED Error during student QR check-in by user ${studentUserId}:`, error);
        res.status(500).json({
            message: 'Internal Server Error: Failed to process QR check-in',
            details: process.env.NODE_ENV !== 'production' ? error.message : undefined
        });
    }
});


// --- Lecturer manually checks in a student --- (Added Time Check)
router.post('/checkin', checkAuth, async (req, res) => {
  const lecturerUserId = req.userData.userId;
  const { registrationNumber, lectureId } = req.body;
  console.log(`Lecturer ${lecturerUserId} attempting manual check-in for Reg# ${registrationNumber} in lecture ${lectureId}`);

  try {
    // --- Validate Input ---
    if (!registrationNumber || typeof registrationNumber !== 'string' || registrationNumber.trim() === '') {
      return res.status(400).json({ message: 'Student Registration Number is required.' });
    }
    if (!lectureId || typeof lectureId !== 'string' || lectureId.trim() === '') {
      return res.status(400).json({ message: 'Lecture ID is required.' });
    }
    const trimmedRegNum = registrationNumber.trim().toUpperCase();
    const trimmedLectureId = lectureId.trim();
    console.log(`[Manual Check-In ${trimmedLectureId}] Validated input.`);

    // --- Verify Lecturer Role ---
    console.log(`[Manual Check-In ${trimmedLectureId}] Verifying lecturer role ${lecturerUserId}...`);
    const lecturerUserRef = db.collection(USERS_COLLECTION).doc(lecturerUserId);
    const lecturerUserDoc = await lecturerUserRef.get();
    if (!lecturerUserDoc.exists || lecturerUserDoc.data().role !== 'lecturer') {
        console.log(`[Manual Check-In ${trimmedLectureId}] Forbidden: User ${lecturerUserId} is not a lecturer.`);
        return res.status(403).json({ message: 'Forbidden: Only lecturers can check students in.' });
    }
    console.log(`[Manual Check-In ${trimmedLectureId}] Lecturer role verified.`);

    // --- Verify Lecture Exists AND Check End Time ---
    console.log(`[Manual Check-In ${trimmedLectureId}] Fetching lecture details...`);
    const lectureRef = db.collection(LECTURES_COLLECTION).doc(trimmedLectureId);
    const lectureDoc = await lectureRef.get();
    if (!lectureDoc.exists) {
        console.log(`[Manual Check-In ${trimmedLectureId}] Lecture not found.`);
        return res.status(404).json({ message: 'Lecture not found.' });
    }
    const lectureData = lectureDoc.data();
    const lectureEndTime = lectureData.endTime; // Firestore Timestamp
    const now = admin.firestore.Timestamp.now(); // Current server time
    console.log(`[Manual Check-In ${trimmedLectureId}] Lecture found.`);

    // Validate lecture end time
    if (!lectureEndTime || !(lectureEndTime instanceof admin.firestore.Timestamp)) {
        console.error(`[Manual Check-In ${trimmedLectureId}] Invalid or missing endTime.`);
        return res.status(500).json({ message: 'Internal Server Error: Lecture data incomplete (endTime).' });
    }

    // *** TIME CHECK ***
    if (now.toMillis() > lectureEndTime.toMillis()) { // Compare milliseconds
        console.log(`[Manual Check-In ${trimmedLectureId}] Failed: Lecture has ended (End: ${lectureEndTime.toDate()}, Now: ${now.toDate()}).`);
        return res.status(400).json({ message: 'Check-in failed: The lecture has already ended.' }); // 400 Bad Request
    }
    console.log(`[Manual Check-In ${trimmedLectureId}] Time check passed.`);
    // *** END TIME CHECK ***

    // --- Find Student ---
    let studentQuery;
    let studentDoc;
    try {
        console.log(`[Manual Check-In ${trimmedLectureId}] Querying student by Reg# ${trimmedRegNum}...`);
        studentQuery = await db.collection(USERS_COLLECTION)
            .where('registrationNumber', '==', trimmedRegNum)
            .where('role', '==', 'student')
            .limit(1)
            .get();
        console.log(`[Manual Check-In ${trimmedLectureId}] Student query completed. Found: ${!studentQuery.empty}`);
    } catch (queryError) {
        console.error(`[Manual Check-In ${trimmedLectureId}] Error querying student by registration number:`, queryError);
        if (queryError.code === 'failed-precondition' || (queryError.message && queryError.message.includes('index'))) {
            console.error(`[Manual Check-In ${trimmedLectureId}] Firestore index missing for users query (registrationNumber, role).`);
            return res.status(500).json({ message: 'Internal Server Error: Database configuration issue (index missing). Please contact support.', details: 'Index missing for users query.' });
        }
        throw queryError; // Re-throw other errors
    }

    if (studentQuery.empty) {
        console.log(`[Manual Check-In ${trimmedLectureId}] Student with Reg# ${trimmedRegNum} not found.`);
        return res.status(404).json({ message: `Student with registration number ${trimmedRegNum} not found.` });
    }
    studentDoc = studentQuery.docs[0];
    const studentUserId = studentDoc.id;
    const studentName = studentDoc.data().name || 'N/A';
    console.log(`[Manual Check-In ${trimmedLectureId}] Found student ${studentName} (ID: ${studentUserId}).`);

    // --- Find Existing Attendance Record ---
    const attendanceRef = db.collection(ATTENDANCE_COLLECTION); // Defined here
    let attendanceQuery;
    try {
        console.log(`[Manual Check-In ${trimmedLectureId}] Querying existing attendance for student ${studentUserId}...`);
        attendanceQuery = await attendanceRef
          .where('lectureId', '==', trimmedLectureId)
          .where('userId', '==', studentUserId)
          .limit(1)
          .get();
        console.log(`[Manual Check-In ${trimmedLectureId}] Existing attendance query completed. Found: ${!attendanceQuery.empty}`);
    } catch (queryError) {
        console.error(`[Manual Check-In ${trimmedLectureId}] Error querying existing attendance:`, queryError);
        if (queryError.code === 'failed-precondition' || (queryError.message && queryError.message.includes('index'))) {
            console.error(`[Manual Check-In ${trimmedLectureId}] Firestore index missing for attendance query (lectureId, userId).`);
            return res.status(500).json({ message: 'Internal Server Error: Database configuration issue (index missing). Please contact support.', details: 'Index missing for attendance query.' });
        }
        throw queryError; // Re-throw other errors
    }


    // --- Check if Joined ---
    if (attendanceQuery.empty) {
      console.warn(`[Manual Check-In ${trimmedLectureId}] REJECTED: Student ${studentUserId} (${trimmedRegNum}) has not joined lecture.`);
      return res.status(400).json({ message: 'Student has not joined this lecture yet.' });
    }

    // --- Process Check-in (Update or Conflict) ---
    const attendanceDocRef = attendanceQuery.docs[0].ref;
    const currentAttendanceData = attendanceQuery.docs[0].data();
    const serverTimestamp = admin.firestore.FieldValue.serverTimestamp();
    let statusCode = 200;
    let responseMessage = '';

    if (currentAttendanceData.checkedIn === true) {
        responseMessage = 'Student already checked in.';
        statusCode = 409; // Conflict
        console.log(`[Manual Check-In ${trimmedLectureId}] Skipped: Student ${trimmedRegNum} already checked in.`);
    } else {
        // Proceed with check-in (time is valid, joined, not checked in)
        console.log(`[Manual Check-In ${trimmedLectureId}] Updating attendance record for student ${trimmedRegNum}...`);
        await attendanceDocRef.update({
          checkedIn: true,
          checkInTime: serverTimestamp,
          checkedInBy: lecturerUserId,
        });
        responseMessage = `Student ${studentName} (${trimmedRegNum}) checked in successfully.`;
        statusCode = 200; // OK
        console.log(`[Manual Check-In ${trimmedLectureId}] Attendance record updated.`);
    }

    // --- Return Response ---
    const finalDoc = await attendanceDocRef.get();
    const finalData = finalDoc.data();
    console.log(`[Manual Check-In ${trimmedLectureId}] Responding with status ${statusCode}.`);
    res.status(statusCode).json({
        message: responseMessage,
        id: finalDoc.id,
        ...finalData,
        checkInTime: formatTimestamp(finalData.checkInTime),
        joinedAt: formatTimestamp(finalData.joinedAt),
        checkedIn: finalData.checkedIn === true,
    });

  } catch (error) {
    console.error(`[Manual Check-In ${req.body?.lectureId}] UNHANDLED Error during lecturer check-in (Reg#: ${req.body?.registrationNumber}) by lecturer ${lecturerUserId}:`, error);
    res.status(500).json({
        message: 'Internal Server Error: Failed to check in student',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});


// --- Student views their attendance history & summary ---
router.get('/student/:userId', checkAuth, async (req, res) => {
  const studentUserId = req.params.userId;
  const authUserId = req.userData.userId;
  const { year, semester } = req.query; // Get optional year/semester filters

  console.log(`Fetching attendance summary for student ${studentUserId}. Filters - Year: ${year}, Semester: ${semester}. Requested by: ${authUserId}`);

  // Basic Authorization: Ensure the request is for the logged-in user
  if (studentUserId !== authUserId) {
    console.warn(`Forbidden: User ${authUserId} attempting to access summary for ${studentUserId}.`);
    return res.status(403).json({ message: 'Forbidden: You can only view your own attendance summary.' });
  }

  // Validate filters if provided
  if ((year && !semester) || (!year && semester)) {
      console.log(`Bad Request: Both year and semester must be provided together for filtering, or neither.`);
      return res.status(400).json({ message: 'Bad Request: Year and Semester must be provided together for filtering.' });
  }

  try {
    // 1. Fetch the student's profile to get their course details
    console.log(`[Summary ${studentUserId}] Fetching student profile...`);
    const userDoc = await db.collection(USERS_COLLECTION).doc(studentUserId).get();
    if (!userDoc.exists) {
        console.log(`[Summary ${studentUserId}] Student profile not found.`);
        return res.status(404).json({ message: 'Student profile not found.' });
    }
    const userData = userDoc.data();
    const { school, department, course } = userData;
    console.log(`[Summary ${studentUserId}] Student profile found.`);

    // Check if profile details are complete
    if (!school || !department || !course) {
        console.warn(`[Summary ${studentUserId}] Cannot calculate percentage: Missing profile details (School/Dept/Course).`);
        // Return records without percentage if profile is incomplete
        const attendanceSnapshot = await db.collection(ATTENDANCE_COLLECTION)
            .where('userId', '==', studentUserId)
            .orderBy('joinedAt', 'desc') // Example sort
            .get();
        const attendanceRecords = attendanceSnapshot.docs.map(doc => ({
            id: doc.id, ...doc.data(),
            joinedAt: formatTimestamp(doc.data().joinedAt),
            checkInTime: formatTimestamp(doc.data().checkInTime),
            percentage: "N/A" // Indicate percentage couldn't be calculated
        }));
        return res.json({
            attendanceRecords,
            percentage: "N/A",
            totalLectures: 0, // Cannot determine total without profile filters
            attendedLectures: attendanceRecords.filter(r => r.checkedIn).length // Can still count attended from fetched records
        });
    }

    // Determine the year and semester to use for filtering lectures
    const filterYear = year || userData.yearOfStudy;
    const filterSemester = semester || userData.semester;

    if (!filterYear || !filterSemester) {
        console.warn(`[Summary ${studentUserId}] Cannot calculate percentage: Missing year/semester in profile or query.`);
         // Similar fallback as above if year/semester are missing
        const attendanceSnapshot = await db.collection(ATTENDANCE_COLLECTION).where('userId', '==', studentUserId).orderBy('joinedAt', 'desc').get();
        const attendanceRecords = attendanceSnapshot.docs.map(doc => ({ id: doc.id, ...doc.data(), joinedAt: formatTimestamp(doc.data().joinedAt), checkInTime: formatTimestamp(doc.data().checkInTime), percentage: "N/A" }));
        return res.json({ attendanceRecords, percentage: "N/A", totalLectures: 0, attendedLectures: attendanceRecords.filter(r => r.checkedIn).length });
    }
    console.log(`[Summary ${studentUserId}] Using filters - School: ${school}, Dept: ${department}, Course: ${course}, Year: ${filterYear}, Sem: ${filterSemester}`);


    // 2. Query relevant lectures for the student's course FOR THE SPECIFIED PERIOD
    let lecturesSnapshot;
    let relevantLectureIdsForPeriod = [];
    let totalRelevantLectures = 0;
    try {
        console.log(`[Summary ${studentUserId}] Querying relevant lectures...`);
        const lecturesQuery = db.collection(LECTURES_COLLECTION)
            .where('school', '==', school)
            .where('department', '==', department)
            .where('course', '==', course)
            .where('yearOfStudy', '==', filterYear)
            .where('semester', '==', filterSemester);
        lecturesSnapshot = await lecturesQuery.get();
        relevantLectureIdsForPeriod = lecturesSnapshot.docs.map(doc => doc.id);
        totalRelevantLectures = relevantLectureIdsForPeriod.length;
        console.log(`[Summary ${studentUserId}] Found ${totalRelevantLectures} relevant lectures for the period.`);
    } catch (queryError) {
        console.error(`[Summary ${studentUserId}] Error querying relevant lectures:`, queryError);
         if (queryError.code === 'failed-precondition' || (queryError.message && queryError.message.includes('index'))) {
            console.error(`[Summary ${studentUserId}] Firestore index missing for lectures query (school, department, course, yearOfStudy, semester).`);
            return res.status(500).json({ message: 'Internal Server Error: Database configuration issue (index missing). Please contact support.', details: 'Index missing for lectures query.' });
        }
        throw queryError; // Re-throw other errors
    }


    // 3. Query ALL attendance records for this student (regardless of period initially)
    let attendedSnapshot;
    let attendedRecordsMap = new Map(); // Use a map for faster lookup
    try {
        console.log(`[Summary ${studentUserId}] Querying all attended records for student...`);
        const attendedQuery = db.collection(ATTENDANCE_COLLECTION)
            .where('userId', '==', studentUserId);
            // .where('checkedIn', '==', true); // Fetch all, filter later if needed for specific views
        attendedSnapshot = await attendedQuery.get();
        attendedSnapshot.docs.forEach(doc => {
            attendedRecordsMap.set(doc.data().lectureId, { id: doc.id, ...doc.data() }); // Map by lectureId
        });
        console.log(`[Summary ${studentUserId}] Found ${attendedSnapshot.size} total attendance records for student.`);
    } catch (queryError) {
         console.error(`[Summary ${studentUserId}] Error querying student attendance records:`, queryError);
         if (queryError.code === 'failed-precondition' || (queryError.message && queryError.message.includes('index'))) {
            console.error(`[Summary ${studentUserId}] Firestore index missing for attendance query (userId).`);
            // Allow proceeding without percentage if this fails, but log error
            totalRelevantLectures = 0; // Cannot calculate percentage accurately
         } else {
            throw queryError; // Re-throw other errors
         }
    }


    // 4. Calculate Percentage and Filter Attended Records for the SPECIFIC PERIOD
    let attendedLecturesCount = 0;
    let finalAttendanceRecords = [];

    if (totalRelevantLectures > 0 && attendedRecordsMap.size > 0) {
        relevantLectureIdsForPeriod.forEach(lectureId => {
            const record = attendedRecordsMap.get(lectureId);
            if (record && record.checkedIn === true) {
                attendedLecturesCount++;
            }
            // Include the record in the response list if it exists for a relevant lecture
            if (record) {
                 finalAttendanceRecords.push({
                    ...record,
                    joinedAt: formatTimestamp(record.joinedAt),
                    checkInTime: formatTimestamp(record.checkInTime),
                    // Percentage here is the overall for the period, add to each record if needed later
                 });
            }
        });
    } else if (attendedRecordsMap.size > 0) {
        // If no relevant lectures found for period, but student has records, return all records
         finalAttendanceRecords = Array.from(attendedRecordsMap.values()).map(record => ({
            ...record,
            joinedAt: formatTimestamp(record.joinedAt),
            checkInTime: formatTimestamp(record.checkInTime),
         }));
    }


    // Sort the final list (e.g., by joined date descending)
    finalAttendanceRecords.sort((a, b) => {
        const dateA = a.joinedAt ? new Date(a.joinedAt) : new Date(0);
        const dateB = b.joinedAt ? new Date(b.joinedAt) : new Date(0);
        return dateB - dateA; // Descending
    });


    const percentage = (totalRelevantLectures > 0)
        ? ((attendedLecturesCount / totalRelevantLectures) * 100).toFixed(2)
        : "0.00"; // Handle division by zero if no relevant lectures

    console.log(`[Summary ${studentUserId}] Calculation complete. Total Relevant: ${totalRelevantLectures}, Attended in Period: ${attendedLecturesCount}, Percentage: ${percentage}%.`);

    // 5. Return the summary
    res.json({
        attendanceRecords: finalAttendanceRecords, // Return records relevant to the period (or all if period empty)
        percentage: percentage,
        totalLectures: totalRelevantLectures,
        attendedLectures: attendedLecturesCount,
    });

  } catch (error) {
    console.error(`[Summary ${studentUserId}] UNHANDLED Error getting student attendance summary:`, error);
    res.status(500).json({
        message: 'Internal Server Error: Failed to get attendance summary',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});


//--- Lecturer view student attendance for a particular lecture --- (Robust Percentage Calc)
router.get('/lecture/:lectureId', checkAuth, async (req, res) => {
  const lectureId = req.params.lectureId;
  const lecturerUserId = req.userData.userId;
  console.log(`Lecturer ${lecturerUserId} viewing attendance for lecture ${lectureId}`);

  try {
    // --- Authorization ---
    console.log(`[Lecture View ${lectureId}] Verifying lecturer role ${lecturerUserId}...`);
    const lecturerUserRef = db.collection(USERS_COLLECTION).doc(lecturerUserId);
    const lecturerUserDoc = await lecturerUserRef.get();
    if (!lecturerUserDoc.exists || lecturerUserDoc.data().role !== 'lecturer') {
        console.log(`[Lecture View ${lectureId}] Forbidden: User ${lecturerUserId} is not a lecturer.`);
        return res.status(403).json({ message: 'Forbidden: Only lecturers can view lecture attendance.' });
    }
     console.log(`[Lecture View ${lectureId}] Lecturer role verified.`);

    // --- Verify Lecture & Get Year/Semester ---
    console.log(`[Lecture View ${lectureId}] Fetching lecture details...`);
    const lectureRef = db.collection(LECTURES_COLLECTION).doc(lectureId);
    const lectureDoc = await lectureRef.get();
    if (!lectureDoc.exists) {
        console.log(`[Lecture View ${lectureId}] Lecture not found.`);
        return res.status(404).json({ message: 'Lecture not found.' });
    }
    const lectureData = lectureDoc.data();
    const lectureYear = lectureData.yearOfStudy;
    const lectureSemester = lectureData.semester;
    console.log(`[Lecture View ${lectureId}] Lecture found.`);

    if (!lectureYear || !lectureSemester) {
        console.error(`[Lecture View ${lectureId}] Attendance view failed: Lecture is missing yearOfStudy or semester data.`);
        return res.status(500).json({ message: 'Internal Server Error: Lecture data is incomplete.' });
    }
    console.log(`[Lecture View ${lectureId}] Using lecture's period - Year: ${lectureYear}, Sem: ${lectureSemester}`);

    // --- Fetch Attendance Records for THIS lecture ---
    const attendanceRef = db.collection(ATTENDANCE_COLLECTION); // *** DEFINED attendanceRef HERE ***
    let snapshot;
    try {
        console.log(`[Lecture View ${lectureId}] Querying attendance records for this lecture...`);
        const attendanceQuery = attendanceRef // Now using the defined ref
            .where('lectureId', '==', lectureId)
            .orderBy('studentName', 'asc'); // Sort by name for display
        snapshot = await attendanceQuery.get();
        console.log(`[Lecture View ${lectureId}] Found ${snapshot.size} attendance records for this lecture.`);
    } catch (queryError) {
        console.error(`[Lecture View ${lectureId}] Error querying attendance for this lecture:`, queryError);
         if (queryError.code === 'failed-precondition' || (queryError.message && queryError.message.includes('index'))) {
            console.error(`[Lecture View ${lectureId}] Firestore index missing for attendance query (lectureId, studentName).`);
            return res.status(500).json({ message: 'Internal Server Error: Database configuration issue (index missing). Please contact support.', details: 'Index missing for attendance query.' });
        }
        throw queryError; // Re-throw other errors
    }


    const attendanceRecordsRaw = snapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
    }));

    // --- Calculate SCOPED Percentage for Each Student (More Robustly) ---
    console.log(`[Lecture View ${lectureId}] Starting percentage calculation for ${attendanceRecordsRaw.length} students...`);
    const percentageCalculationPromises = attendanceRecordsRaw.map(async (record) => {
        let percentage = "N/A"; // Default value
        const studentUserId = record.userId;

        try {
            if (!studentUserId) {
                console.warn(`[Lecture View ${lectureId}] Skipping percentage for record ${record.id}: Missing userId.`);
            } else {
                // 1. Fetch student profile
                const userDoc = await db.collection(USERS_COLLECTION).doc(studentUserId).get();
                if (userDoc.exists) {
                    const userData = userDoc.data();
                    const { school, department, course } = userData;

                    // 2. Check if profile details are complete
                    if (school && department && course) {
                        // 3. Query relevant lectures using LECTURE'S year/semester
                        let lecturesSnapshot;
                        let relevantLectureIdsForPeriod = [];
                        let totalRelevantLectures = 0;
                        try {
                            const lecturesQuery = db.collection(LECTURES_COLLECTION)
                                .where('school', '==', school)
                                .where('department', '==', department)
                                .where('course', '==', course)
                                .where('yearOfStudy', '==', lectureYear) // LECTURE'S YEAR
                                .where('semester', '==', lectureSemester); // LECTURE'S SEMESTER
                            lecturesSnapshot = await lecturesQuery.get();
                            relevantLectureIdsForPeriod = lecturesSnapshot.docs.map(doc => doc.id);
                            totalRelevantLectures = relevantLectureIdsForPeriod.length;
                        } catch (lectQueryError) {
                             console.error(`[Lecture View ${lectureId}] Error querying relevant lectures for student ${studentUserId} percentage calc:`, lectQueryError);
                             // If this fails, we can't calculate percentage
                             totalRelevantLectures = 0;
                             if (lectQueryError.code === 'failed-precondition') {
                                 console.error(`[Lecture View ${lectureId}] Index missing for lectures query in percentage calc.`);
                             }
                        }


                        if (totalRelevantLectures > 0) {
                            // 4. Query ALL attended records for this student
                            let attendedSnapshot;
                            let attendedLecturesCount = 0;
                            try {
                                const attendedQuery = db.collection(ATTENDANCE_COLLECTION)
                                    .where('userId', '==', studentUserId)
                                    .where('checkedIn', '==', true);
                                attendedSnapshot = await attendedQuery.get();

                                // 5. Filter attended records for the specific period
                                attendedLecturesCount = attendedSnapshot.docs.filter(doc =>
                                    relevantLectureIdsForPeriod.includes(doc.data().lectureId)
                                ).length;

                                // 6. Calculate percentage
                                percentage = ((attendedLecturesCount / totalRelevantLectures) * 100).toFixed(2);

                            } catch (attQueryError) {
                                console.error(`[Lecture View ${lectureId}] Error querying attended records for student ${studentUserId} percentage calc:`, attQueryError);
                                percentage = "N/A"; // Mark as unavailable if query fails
                                if (attQueryError.code === 'failed-precondition') {
                                    console.error(`[Lecture View ${lectureId}] Index missing for attendance query (userId, checkedIn) in percentage calc.`);
                                }
                            }

                        } else {
                            percentage = "0.00"; // No relevant lectures in this period
                        }
                    } else {
                         console.warn(`[Lecture View ${lectureId}] Cannot calculate scoped percentage for user ${studentUserId}: Missing profile details (School/Dept/Course).`);
                    }
                } else {
                     console.warn(`[Lecture View ${lectureId}] Cannot calculate scoped percentage for user ${studentUserId}: User document not found.`);
                }
            }
        } catch (percError) {
            console.error(`[Lecture View ${lectureId}] Error calculating scoped percentage for student ${studentUserId}:`, percError);
            percentage = "N/A";
        }

        return { ...record, percentage };
    });

    // Wait for all percentage calculations to complete
    const attendanceRecordsWithPercentage = await Promise.all(percentageCalculationPromises);
    console.log(`[Lecture View ${lectureId}] Percentage calculation finished.`);
    // --- *** END SCOPED PERCENTAGE CALCULATION *** ---


    // --- Format final response ---
    const finalResponseData = attendanceRecordsWithPercentage.map(data => ({
        id: data.id,
        registrationNumber: data.registrationNumber || 'N/A',
        studentName: data.studentName || 'N/A',
        lectureId: data.lectureId,
        userId: data.userId,
        checkedIn: data.checkedIn === true,
        checkInTime: formatTimestamp(data.checkInTime),
        joinedAt: formatTimestamp(data.joinedAt),
        checkedInBy: data.checkedInBy || null,
        percentage: data.percentage, // Include the calculated SCOPED percentage
    }));

    console.log(`[Lecture View ${lectureId}] Responding with ${finalResponseData.length} attendance records.`);
    res.json(finalResponseData);

  } catch (error) {
    console.error(`[Lecture View ${req.params.lectureId}] UNHANDLED Error getting lecture attendance:`, error);
    res.status(500).json({
        message: 'Internal Server Error: Failed to get lecture attendance',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});

module.exports = router;
