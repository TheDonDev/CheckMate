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
  // If it's already null, undefined, or some other type, return null
  return null;
};


// --- Student JOINS a lecture (Manual Button) ---
// Endpoint: POST /api/firebase/attendance/join/:lectureId
// This endpoint ONLY marks the student as having joined. It DOES NOT check them in.
// Requires authentication (checkAuth middleware)
router.post('/join/:lectureId', checkAuth, async (req, res) => {
  try {
    const lectureId = req.params.lectureId;
    const studentUserId = req.userData.userId; // Get user ID from authenticated token

    // --- Validate Lecture Exists ---
    const lectureRef = db.collection(LECTURES_COLLECTION).doc(lectureId);
    const lectureDoc = await lectureRef.get();
    if (!lectureDoc.exists) {
        console.log(`Join attempt failed: Lecture not found with ID: ${lectureId}`);
        return res.status(404).json({ message: 'Lecture not found or is no longer available.' }); // Use message for consistency
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

    // --- Optional: Validate if student's profile matches lecture criteria ---
    if (studentData.school !== lectureData.school ||
        studentData.department !== lectureData.department ||
        studentData.course !== lectureData.course ||
        studentData.yearOfStudy !== lectureData.yearOfStudy ||
        studentData.semester !== lectureData.semester) {
        console.error(`Join attempt BLOCKED: Student ${studentUserId} profile details do not match lecture ${lectureId} criteria.`);
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
        // Record EXISTS - Return existing data, DO NOT MODIFY checkedIn status
        console.log(`Student ${studentUserId} already has a record for lecture ${lectureId}. Returning existing record.`);
        const existingDoc = existingJoinQuery.docs[0];
        recordId = existingDoc.id;
        attendanceRecordData = existingDoc.data();
        // If already checked in, update message
        if (attendanceRecordData.checkedIn === true) {
            message = 'Already checked in for this lecture.';
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
        message: 'Internal Server Error: Failed to process join request', // Use message
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});


// --- Student CHECKS IN for a lecture via Lecture QR Scan ---
// Endpoint: POST /api/firebase/attendance/checkin/student/:lectureId
// This endpoint is triggered ONLY when a student scans the LECTURER's QR code.
// Requires the student to have ALREADY JOINED (checkedIn: false).
// Requires authentication (checkAuth middleware)
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
            return res.status(400).json({ message: 'Check-in failed: You must join the lecture first.' }); // 400 Bad Request or 404 Not Found
        }

        // Record EXISTS - Check its status
        const attendanceDoc = attendanceQuery.docs[0];
        const attendanceData = attendanceDoc.data();

        if (attendanceData.checkedIn === true) {
            // Already checked in
            console.log(`Student QR Check-in skipped: Student ${studentUserId} already checked in for lecture ${lectureId}.`);
            return res.status(200).json({ // 200 OK or 409 Conflict
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
// Requires authentication (checkAuth middleware)
router.post('/checkin', checkAuth, async (req, res) => {
  try {
    const lecturerUserId = req.userData.userId; // Get lecturer ID from token

    // --- Get registrationNumber AND lectureId from request body ---
    const { registrationNumber, lectureId } = req.body;

    // --- Validate Input ---
    if (!registrationNumber || typeof registrationNumber !== 'string' || registrationNumber.trim() === '') {
      console.log(`Lecturer Check-in failed: Missing or invalid registrationNumber in request body.`);
      return res.status(400).json({ message: 'Student Registration Number is required.' }); // Use message
    }
    if (!lectureId || typeof lectureId !== 'string' || lectureId.trim() === '') {
      console.log(`Lecturer Check-in failed: Missing or invalid lectureId in request body.`);
      return res.status(400).json({ message: 'Lecture ID is required.' }); // Use message
    }
    const trimmedRegNum = registrationNumber.trim().toUpperCase(); // Ensure uppercase for query consistency
    const trimmedLectureId = lectureId.trim();

    // --- Verify Lecturer Role ---
    const lecturerUserRef = db.collection(USERS_COLLECTION).doc(lecturerUserId);
    const lecturerUserDoc = await lecturerUserRef.get();
    if (!lecturerUserDoc.exists || lecturerUserDoc.data().role !== 'lecturer') {
        console.log(`Lecturer Check-in failed: User ${lecturerUserId} is not authorized (not found or not a lecturer).`);
        return res.status(403).json({ message: 'Forbidden: Only lecturers can check students in.' }); // Use message
    }

    // --- Verify the Lecture Exists ---
    const lectureRef = db.collection(LECTURES_COLLECTION).doc(trimmedLectureId);
    const lectureDoc = await lectureRef.get();
    if (!lectureDoc.exists) {
        console.log(`Lecturer Check-in failed: Lecture ${trimmedLectureId} not found.`);
        return res.status(404).json({ message: 'Lecture not found.' }); // Use message
    }

    // --- Optional: Verify this lecturer is associated with the lecture ---
    if (lectureDoc.data().lecturerId !== lecturerUserId) {
         console.warn(`Check-in allowed: Lecturer ${lecturerUserId} checking in for lecture ${trimmedLectureId} taught by ${lectureDoc.data().lecturerId}.`);
    }

    // --- Find the student's user document by registration number ---
    // This query requires an index on 'registrationNumber' in the 'users' collection.
    const studentQuery = await db.collection(USERS_COLLECTION)
        .where('registrationNumber', '==', trimmedRegNum) // Use uppercase reg num
        .where('role', '==', 'student') // Ensure we find a student
        .limit(1)
        .get();

    if (studentQuery.empty) {
        console.log(`Lecturer Check-in failed: Student with registration number ${trimmedRegNum} not found.`);
        return res.status(404).json({ message: `Student with registration number ${trimmedRegNum} not found.` }); // Use message
    }
    const studentDoc = studentQuery.docs[0];
    const studentUserId = studentDoc.id;
    const studentData = studentDoc.data();
    const studentName = studentData.name || 'N/A';

    // --- Find or Create/Update the attendance record ---
    const attendanceRef = db.collection(ATTENDANCE_COLLECTION);
    const attendanceQuery = await attendanceRef
      .where('lectureId', '==', trimmedLectureId)
      .where('userId', '==', studentUserId) // Use the found studentUserId
      .limit(1)
      .get();

    let attendanceDocRef;
    let currentAttendanceData = {};
    const serverTimestamp = admin.firestore.FieldValue.serverTimestamp();
    let statusCode = 200; // Default OK
    let responseMessage = '';

    if (attendanceQuery.empty) {
      // Student hasn't joined via app, create a new record directly as checked-in
      console.log(`Lecturer Check-in: No existing record for student ${studentUserId} in lecture ${trimmedLectureId}. Creating new checked-in record.`);
      const newAttendanceData = {
        lectureId: trimmedLectureId,
        userId: studentUserId,
        registrationNumber: trimmedRegNum,
        studentName: studentName,
        joinedAt: serverTimestamp, // Set joined time to now (when lecturer checked them in)
        checkedIn: true,
        checkInTime: serverTimestamp, // Set check-in time to now
        checkedInBy: lecturerUserId, // Record who checked them in
      };
      attendanceDocRef = await attendanceRef.add(newAttendanceData);
      currentAttendanceData = newAttendanceData; // Use the data we just prepared
      statusCode = 201; // Created
      responseMessage = `Student ${studentName} (${trimmedRegNum}) checked in successfully (new record created).`;

    } else {
      // Record exists, check if already checked in
      attendanceDocRef = attendanceQuery.docs[0].ref;
      currentAttendanceData = attendanceQuery.docs[0].data();

      if (currentAttendanceData.checkedIn === true) {
          console.log(`Lecturer Check-in skipped: Student ${trimmedRegNum} already checked into lecture ${trimmedLectureId}.`);
          responseMessage = 'Student already checked in.';
          statusCode = 200; // OK, already done
      } else {
          // Record exists but not checked in, update it
          console.log(`Lecturer Check-in: Updating existing record for student ${studentUserId} in lecture ${trimmedLectureId}.`);
          await attendanceDocRef.update({
            checkedIn: true,
            checkInTime: serverTimestamp,
            checkedInBy: lecturerUserId,
          });
          responseMessage = `Student ${studentName} (${trimmedRegNum}) checked in successfully (updated existing record).`;
          statusCode = 200; // OK, updated
      }
    }

    console.log(`Lecturer Check-in processed for student ${trimmedRegNum} in lecture ${trimmedLectureId} by lecturer ${lecturerUserId}. Status: ${statusCode}`);

    // Fetch the final data (either newly created or updated) to return consistent timestamps
    const finalDoc = await attendanceDocRef.get();
    const finalData = finalDoc.data();

    // --- Return success message with student details ---
    res.status(statusCode).json({
        message: responseMessage,
        // Return the full record data for consistency
        id: finalDoc.id,
        ...finalData,
        // Format timestamps for client
        checkInTime: formatTimestamp(finalData.checkInTime),
        joinedAt: formatTimestamp(finalData.joinedAt),
        checkedIn: finalData.checkedIn === true, // Ensure boolean
    });

  } catch (error) {
    console.error(`Error during lecturer check-in (Reg#: ${req.body?.registrationNumber}, Lecture: ${req.body?.lectureId}) by lecturer ${req.userData?.userId}:`, error);
    console.error('Error Stack:', error.stack);
    // Check specifically for Firestore index errors if ordering was added
    if (error.code === 'failed-precondition' || (error.message && error.message.includes('index'))) {
        console.error("Firestore Index Missing: The query requires an index (likely on registrationNumber and role in users collection). Check the error details for a link to create it.");
        return res.status(500).json({
            message: 'Internal Server Error: Failed to check in student due to missing database index.', // Use message
            details: 'A required Firestore index is missing.'
        });
    }
    res.status(500).json({
        message: 'Internal Server Error: Failed to check in student', // Use message
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});


// --- Student views their attendance history ---
// Endpoint: GET /api/firebase/attendance/student/:userId
// Requires authentication (checkAuth middleware)
router.get('/student/:userId', checkAuth, async (req, res) => {
  try {
    const requestedUserId = req.params.userId;
    const authUserId = req.userData.userId; // User ID from the token

    // --- Authorization: Ensure users can only view their own attendance ---
    if (requestedUserId !== authUserId) {
        console.log(`Forbidden attempt: User ${authUserId} tried to access attendance for ${requestedUserId}`);
        return res.status(403).json({ message: 'Forbidden: You can only access your own attendance records.' }); // Use message
    }

    // --- Fetch Attendance Records for the student ---
    const attendanceRef = db.collection(ATTENDANCE_COLLECTION);
    // Order by joinedAt descending to show most recent first
    const snapshot = await attendanceRef.where('userId', '==', requestedUserId).orderBy('joinedAt', 'desc').get();

    const attendanceRecords = [];
    snapshot.forEach((doc) => {
      const data = doc.data();
      attendanceRecords.push({
          id: doc.id,
          ...data,
          // Convert Timestamps for client consistency
          checkInTime: formatTimestamp(data.checkInTime),
          joinedAt: formatTimestamp(data.joinedAt),
          checkedIn: data.checkedIn === true, // Ensure boolean value, default false if missing
       });
    });

    // --- Percentage Calculation ---
    let percentage = 0;
    let totalRelevantLectures = 0;
    // Count attended lectures directly from the fetched records where checkedIn is true
    let attendedLecturesCount = attendanceRecords.filter((record) => record.checkedIn === true).length;

    try {
        // Fetch user profile to get criteria for finding relevant lectures
        const userDoc = await db.collection(USERS_COLLECTION).doc(requestedUserId).get();
        if (userDoc.exists) {
            const userData = userDoc.data();
            // **IMPORTANT**: Ensure these field names EXACTLY match your 'users' and 'lectures' collections
            const { school, department, course, yearOfStudy, semester } = userData;

            // Check if all necessary fields are present for the query
            if (school && department && course && yearOfStudy && semester) {
                const lecturesRef = db.collection(LECTURES_COLLECTION);
                // This query requires a composite index in Firestore.
                // Example Index: lectures | school ASC | department ASC | course ASC | yearOfStudy ASC | semester ASC | startTime ASC (or DESC)
                let lecturesQuery = lecturesRef
                    .where('school', '==', school)
                    .where('department', '==', department)
                    .where('course', '==', course)
                    .where('yearOfStudy', '==', yearOfStudy)
                    .where('semester', '==', semester);

                // Optional: Only count lectures that have already started/passed?
                // lecturesQuery = lecturesQuery.where('startTime', '<=', new Date());

                const lecturesSnapshot = await lecturesQuery.get();

                totalRelevantLectures = lecturesSnapshot.size; // Total lectures matching student's profile criteria
                percentage = totalRelevantLectures > 0 ? (attendedLecturesCount / totalRelevantLectures) * 100 : 0;
                console.log(`Attendance calculation for ${requestedUserId}: Attended ${attendedLecturesCount} / Total ${totalRelevantLectures} relevant lectures.`);
            } else {
                 console.warn(`Cannot calculate percentage for user ${requestedUserId}: Missing profile details (school/dept/course/year/semester). Percentage based on joined lectures only.`);
                 // Fallback: Calculate percentage based only on lectures the student actually joined
                 totalRelevantLectures = attendanceRecords.length; // Less accurate, but better than 0 if profile is incomplete
                 percentage = totalRelevantLectures > 0 ? (attendedLecturesCount / totalRelevantLectures) * 100 : 0;
            }
        } else {
             console.warn(`Cannot calculate percentage for user ${requestedUserId}: User document not found. Percentage based on joined lectures only.`);
             // Fallback if user doc is missing
             totalRelevantLectures = attendanceRecords.length;
             percentage = totalRelevantLectures > 0 ? (attendedLecturesCount / totalRelevantLectures) * 100 : 0;
        }
    } catch (calcError) {
        console.error(`Error calculating attendance percentage for user ${requestedUserId}:`, calcError);
        // Check specifically for Firestore index errors during percentage calculation
        if (calcError.code === 'failed-precondition' || (calcError.message && calcError.message.includes('index'))) {
             console.error("Firestore Index Missing for Percentage Calculation: The query requires an index. Check the error details for a link to create it in the Firebase console.");
             // Inform the client or just proceed without percentage?
        }
        // Proceed without percentage if calculation fails, don't crash the request
        console.warn(`Proceeding without accurate percentage calculation due to error.`);
        // Fallback calculation based only on joined records
        totalRelevantLectures = attendanceRecords.length;
        percentage = totalRelevantLectures > 0 ? (attendedLecturesCount / totalRelevantLectures) * 100 : 0;
    }
    // --- End Percentage Calculation ---

    const data = {
      attendanceRecords, // Contains registrationNumber, studentName etc. from when they joined
      percentage: percentage.toFixed(2), // Format to 2 decimal places
      totalLectures: totalRelevantLectures, // Total relevant lectures found (can be 0 or based on fallback)
      attendedLectures: attendedLecturesCount, // Number of checked-in records found
    };
    res.json(data);

  } catch (error) {
    console.error(`Error getting student attendance for user ${req.params.userId}:`, error);
    console.error('Error Stack:', error.stack);
    res.status(500).json({
        message: 'Internal Server Error: Failed to get student attendance', // Use message
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});

//--- Lecturer view student attendance for a particular lecture ---
// Endpoint: GET /api/firebase/attendance/lecture/:lectureId
// Requires authentication (checkAuth middleware)
router.get('/lecture/:lectureId', checkAuth, async (req, res) => {
  try {
    const lectureId = req.params.lectureId;
    const lecturerUserId = req.userData.userId; // User ID from the token

    // --- Authorization: Ensure user is a lecturer ---
    const lecturerUserRef = db.collection(USERS_COLLECTION).doc(lecturerUserId);
    const lecturerUserDoc = await lecturerUserRef.get();
    if (!lecturerUserDoc.exists || lecturerUserDoc.data().role !== 'lecturer') {
        console.log(`Attendance view failed: User ${lecturerUserId} is not authorized (not found or not a lecturer).`);
        return res.status(403).json({ message: 'Forbidden: Only lecturers can view lecture attendance.' }); // Use message
    }

    // --- Verify the lecture exists ---
    const lectureRef = db.collection(LECTURES_COLLECTION).doc(lectureId);
    const lectureDoc = await lectureRef.get();
    if (!lectureDoc.exists) {
        console.log(`Attendance view failed: Lecture ${lectureId} not found.`);
        return res.status(404).json({ message: 'Lecture not found.' }); // Use message
    }
    // --- Optional: Verify this lecturer owns the lecture ---
    // if (lectureDoc.data().lecturerId !== lecturerUserId) {
    //     console.log(`Attendance view failed: Lecturer ${lecturerUserId} is not the assigned lecturer for lecture ${lectureId}.`);
    //     return res.status(403).json({ message: 'Forbidden: You can only view attendance for your own lectures.' }); // Use message
    // }

    // --- Fetch Attendance Records for the specific lecture ---
    const attendanceRef = db.collection(ATTENDANCE_COLLECTION);
    // Order results by student name ascending
    // This query requires a composite index on lectureId (ASC) and studentName (ASC)
    const snapshot = await attendanceRef.where('lectureId', '==', lectureId).orderBy('studentName', 'asc').get();

    const attendanceRecords = [];
    snapshot.forEach((doc) => {
      const data = doc.data();
      attendanceRecords.push({
        id: doc.id,
        registrationNumber: data.registrationNumber || 'N/A',
        studentName: data.studentName || 'N/A',
        lectureId: data.lectureId,
        userId: data.userId,
        checkedIn: data.checkedIn === true, // Ensure boolean, default false
        checkInTime: formatTimestamp(data.checkInTime),
        joinedAt: formatTimestamp(data.joinedAt),
        checkedInBy: data.checkedInBy || null,
      });
    });

    console.log(`Fetched ${attendanceRecords.length} attendance records for lecture ${lectureId} by request from lecturer ${lecturerUserId}.`);
    res.json(attendanceRecords); // Return the array of records

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
