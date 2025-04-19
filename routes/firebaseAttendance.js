// c:\Users\Test\FlutterProjects\checkmate\routes\firebaseAttendance.js

const express = require('express');
const { db, admin } = require('../firebase'); // Ensure admin is required for FieldValue.serverTimestamp()
const router = express.Router();
const checkAuth = require('../middleware/checkAuth'); // Ensure this path is correct

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


// --- Student joins a lecture ---
// Endpoint: POST /api/attendance/join/:lectureId (Assuming '/api/attendance' is the base path in your server setup)
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
        return res.status(404).json({ error: 'Lecture not found.' });
    }
    const lectureData = lectureDoc.data(); // Get lecture data for potential validation

    // --- Fetch Student Details (including registrationNumber and name) from Firestore ---
    const studentUserRef = db.collection(USERS_COLLECTION).doc(studentUserId);
    const studentUserDoc = await studentUserRef.get();

    if (!studentUserDoc.exists) {
        console.error(`Join attempt failed: User document not found for authenticated user ID: ${studentUserId}`);
        return res.status(404).json({ error: 'Your user profile could not be found.' });
    }
    const studentData = studentUserDoc.data();

    // --- Authorization & Validation ---
    if (studentData.role !== 'student') {
        console.log(`Join attempt failed: User ${studentUserId} is not a student (role: ${studentData.role}).`);
        return res.status(403).json({ error: 'Forbidden: Only students can join lectures.' });
    }

    // CRITICAL: Use registrationNumber from the user's profile, not request body
    const registrationNumber = studentData.registrationNumber;
    if (!registrationNumber) {
        console.log(`Join attempt failed: Student ${studentUserId} does not have a registration number in their profile.`);
        return res.status(400).json({ error: 'Your profile is missing the registration number. Cannot join lecture.' });
    }
    // Use name from profile, provide a default if missing
    const studentName = studentData.name || 'N/A';

    // --- Optional: Validate if student's profile matches lecture criteria ---
    // This adds an extra layer of validation if needed
    if (studentData.school !== lectureData.school ||
        studentData.department !== lectureData.department ||
        studentData.course !== lectureData.course ||
        studentData.yearOfStudy !== lectureData.yearOfStudy ||
        studentData.semester !== lectureData.semester) {
        console.warn(`Join attempt warning: Student ${studentUserId} profile details do not fully match lecture ${lectureId} criteria. Allowing join anyway.`);
        // Decide whether to block (403) or just warn based on requirements
        // return res.status(403).json({ error: 'Your profile details do not match this lecture.' });
    }

    // --- Check if already joined this specific lecture ---
    const attendanceRef = db.collection(ATTENDANCE_COLLECTION);
    const existingJoinQuery = await attendanceRef
        .where('lectureId', '==', lectureId)
        .where('userId', '==', studentUserId) // Check based on authenticated user ID
        .limit(1)
        .get();

    if (!existingJoinQuery.empty) {
        console.log(`Join attempt blocked: Student ${studentUserId} already joined lecture ${lectureId}.`);
        const existingDoc = existingJoinQuery.docs[0];
        const existingData = existingDoc.data();
        // Return the existing record data, ensuring timestamps are formatted
        return res.status(200).json({
            message: 'Already joined this lecture.',
            id: existingDoc.id,
            ...existingData,
            checkedIn: existingData.checkedIn || false, // Ensure boolean exists
            checkInTime: formatTimestamp(existingData.checkInTime),
            joinedAt: formatTimestamp(existingData.joinedAt),
        });
    }

    // --- Prepare data for Firestore ---
    const attendanceData = {
      lectureId,
      userId: studentUserId,    // Use authenticated user ID
      registrationNumber,       // From user profile
      studentName,              // From user profile
      checkInTime: null,        // Initially null
      checkedIn: false,         // Standardized field name (camelCase)
      joinedAt: admin.firestore.FieldValue.serverTimestamp(), // Track when they joined
      checkedInBy: null,        // Who performed the check-in (lecturer's userId)
    };

    // --- Add attendance record ---
    const docRef = await attendanceRef.add(attendanceData);
    console.log(`Student ${studentUserId} (${registrationNumber}) successfully joined lecture ${lectureId}. Record ID: ${docRef.id}`);

    // Fetch the created doc to return accurate data including server timestamp
    const createdDoc = await docRef.get();
    const createdData = createdDoc.data();

    res.status(201).json({
        id: createdDoc.id,
        ...createdData,
        // Format timestamps for client consistency
        joinedAt: formatTimestamp(createdData.joinedAt),
        checkInTime: formatTimestamp(createdData.checkInTime), // Will be null here
     });

  } catch (error) {
    console.error(`Error joining lecture ${req.params.lectureId} for user ${req.userData?.userId}:`, error);
    console.error('Error Stack:', error.stack);
    res.status(500).json({
        error: 'Internal Server Error: Failed to join lecture',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});

// --- Lecturer checks in a student ---
// Endpoint: POST /api/attendance/checkin
// Requires authentication (checkAuth middleware)
router.post('/checkin', checkAuth, async (req, res) => {
  try {
    const lecturerUserId = req.userData.userId; // Get lecturer ID from token

    // --- Get registrationNumber AND lectureId from request body ---
    const { registrationNumber, lectureId } = req.body;

    // --- Validate Input ---
    if (!registrationNumber || typeof registrationNumber !== 'string' || registrationNumber.trim() === '') {
      console.log(`Check-in failed: Missing or invalid registrationNumber in request body.`);
      return res.status(400).json({ error: 'Student Registration Number is required.' });
    }
    if (!lectureId || typeof lectureId !== 'string' || lectureId.trim() === '') {
      console.log(`Check-in failed: Missing or invalid lectureId in request body.`);
      return res.status(400).json({ error: 'Lecture ID is required.' });
    }

    // --- Verify Lecturer Role ---
    const lecturerUserRef = db.collection(USERS_COLLECTION).doc(lecturerUserId);
    const lecturerUserDoc = await lecturerUserRef.get();
    if (!lecturerUserDoc.exists || lecturerUserDoc.data().role !== 'lecturer') {
        console.log(`Check-in failed: User ${lecturerUserId} is not authorized (not found or not a lecturer).`);
        return res.status(403).json({ error: 'Forbidden: Only lecturers can check students in.' });
    }

    // --- Verify the Lecture Exists ---
    const lectureRef = db.collection(LECTURES_COLLECTION).doc(lectureId.trim());
    const lectureDoc = await lectureRef.get();
    if (!lectureDoc.exists) {
        console.log(`Check-in failed: Lecture ${lectureId.trim()} not found.`);
        return res.status(404).json({ error: 'Lecture not found.' });
    }

    // --- Optional: Verify this lecturer is associated with the lecture ---
    // Decide on strictness: Allow any lecturer or only the assigned one?
    // if (lectureDoc.data().lecturerId !== lecturerUserId) {
    //     console.log(`Check-in failed: Lecturer ${lecturerUserId} is not the assigned lecturer for lecture ${lectureId.trim()}.`);
    //     return res.status(403).json({ error: 'Forbidden: You are not the lecturer for this session.' });
    // }
    // For now, allow any lecturer but log if it's not the assigned one
    if (lectureDoc.data().lecturerId !== lecturerUserId) {
         console.warn(`Check-in allowed: Lecturer ${lecturerUserId} checking in for lecture ${lectureId.trim()} taught by ${lectureDoc.data().lecturerId}.`);
    }

    // --- Find the specific attendance record using BOTH registrationNumber and lectureId ---
    const attendanceRef = db.collection(ATTENDANCE_COLLECTION);
    const querySnapshot = await attendanceRef
      .where('registrationNumber', '==', registrationNumber.trim()) // Use trimmed value
      .where('lectureId', '==', lectureId.trim()) // Use trimmed value
      .limit(1) // Should only be one record per student per lecture
      .get();

    if (querySnapshot.empty) {
      console.log(`Check-in failed: No attendance record found for registration number ${registrationNumber.trim()} in lecture ${lectureId.trim()}. Student might not have joined.`);
      return res.status(404).json({ error: 'Student with this registration number has not joined this specific lecture session.' });
    }

    // Get the document reference and data
    const attendanceDocRef = querySnapshot.docs[0].ref;
    const attendanceData = querySnapshot.docs[0].data();

    // --- Check if already checked in ---
    if (attendanceData.checkedIn === true) {
        console.log(`Check-in skipped: Student ${registrationNumber.trim()} already checked into lecture ${lectureId.trim()}.`);
        return res.status(200).json({
            message: 'Student already checked in.',
            id: querySnapshot.docs[0].id,
            ...attendanceData,
            checkInTime: formatTimestamp(attendanceData.checkInTime),
            joinedAt: formatTimestamp(attendanceData.joinedAt),
        });
    }

    // --- Update the attendance record ---
    const checkInTimestamp = admin.firestore.FieldValue.serverTimestamp();
    await attendanceDocRef.update({
      checkInTime: checkInTimestamp,
      checkedIn: true,
      checkedInBy: lecturerUserId, // Record who checked them in
    });

    console.log(`Check-in successful: Student ${registrationNumber.trim()} checked into lecture ${lectureId.trim()} by lecturer ${lecturerUserId}.`);

    // Fetch the updated data to return
    const updatedDoc = await attendanceDocRef.get();
    const updatedData = updatedDoc.data();

    // --- Return success message with student details ---
    res.json({
        message: `Student ${updatedData.studentName || 'N/A'} (${updatedData.registrationNumber}) checked in successfully.`,
        checkedInData: {
            id: updatedDoc.id,
            ...updatedData,
            // Format timestamps for client
            checkInTime: formatTimestamp(updatedData.checkInTime),
            joinedAt: formatTimestamp(updatedData.joinedAt),
        }
    });

  } catch (error) {
    console.error(`Error checking in student (Reg#: ${req.body?.registrationNumber}, Lecture: ${req.body?.lectureId}) by lecturer ${req.userData?.userId}:`, error);
    console.error('Error Stack:', error.stack);
    res.status(500).json({
        error: 'Internal Server Error: Failed to check in student',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});

// --- Student views their attendance history ---
// Endpoint: GET /api/attendance/student/:userId
// Requires authentication (checkAuth middleware)
router.get('/student/:userId', checkAuth, async (req, res) => {
  try {
    const requestedUserId = req.params.userId;
    const authUserId = req.userData.userId; // User ID from the token

    // --- Authorization: Ensure users can only view their own attendance ---
    if (requestedUserId !== authUserId) {
        console.log(`Forbidden attempt: User ${authUserId} tried to access attendance for ${requestedUserId}`);
        return res.status(403).json({ error: 'Forbidden: You can only access your own attendance records.' });
    }

    // --- Fetch Attendance Records for the student ---
    const attendanceRef = db.collection(ATTENDANCE_COLLECTION);
    // Consider ordering if needed, e.g., by joinedAt descending
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
          checkedIn: data.checkedIn || false, // Ensure boolean value
       });
    });

    // --- Percentage Calculation ---
    let percentage = 0;
    let totalRelevantLectures = 0;
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

                // Optional: Only count lectures that have already passed?
                // lecturesQuery = lecturesQuery.where('startTime', '<=', new Date());

                const lecturesSnapshot = await lecturesQuery.get();

                totalRelevantLectures = lecturesSnapshot.size;
                percentage = totalRelevantLectures > 0 ? (attendedLecturesCount / totalRelevantLectures) * 100 : 0;
                console.log(`Attendance calculation for ${requestedUserId}: Attended ${attendedLecturesCount} / Total ${totalRelevantLectures} relevant lectures.`);
            } else {
                 console.warn(`Cannot calculate percentage for user ${requestedUserId}: Missing profile details (school/dept/course/year/semester).`);
                 // Decide how to handle this - percentage remains 0, or calculate based on joined lectures?
                 // totalRelevantLectures = attendanceRecords.length; // Less accurate alternative
                 // percentage = totalRelevantLectures > 0 ? (attendedLecturesCount / totalRelevantLectures) * 100 : 0;
            }
        } else {
             console.warn(`Cannot calculate percentage for user ${requestedUserId}: User document not found.`);
        }
    } catch (calcError) {
        console.error(`Error calculating attendance percentage for user ${requestedUserId}:`, calcError);
        // Check specifically for Firestore index errors during percentage calculation
        if (calcError.code === 'failed-precondition' || (calcError.message && calcError.message.includes('index'))) {
             console.error("Firestore Index Missing for Percentage Calculation: The query requires an index. Check the error details for a link to create it in the Firebase console.");
             // Inform the client or just proceed without percentage?
        }
        // Proceed without percentage if calculation fails, don't crash the request
    }
    // --- End Percentage Calculation ---

    const data = {
      attendanceRecords, // Contains registrationNumber, studentName etc. from when they joined
      percentage: percentage.toFixed(2), // Format to 2 decimal places
      totalLectures: totalRelevantLectures, // Total relevant lectures found (can be 0)
      attendedLectures: attendedLecturesCount, // Number of checked-in records found
    };
    res.json(data);

  } catch (error) {
    console.error(`Error getting student attendance for user ${req.params.userId}:`, error);
    console.error('Error Stack:', error.stack);
    res.status(500).json({
        error: 'Internal Server Error: Failed to get student attendance',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});

//--- Lecturer view student attendance for a particular lecture ---
// Endpoint: GET /api/attendance/lecture/:lectureId
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
        return res.status(403).json({ error: 'Forbidden: Only lecturers can view lecture attendance.' });
    }

    // --- Verify the lecture exists ---
    const lectureRef = db.collection(LECTURES_COLLECTION).doc(lectureId);
    const lectureDoc = await lectureRef.get();
    if (!lectureDoc.exists) {
        console.log(`Attendance view failed: Lecture ${lectureId} not found.`);
        return res.status(404).json({ error: 'Lecture not found.' });
    }
    // --- Optional: Verify this lecturer owns the lecture ---
    // if (lectureDoc.data().lecturerId !== lecturerUserId) {
    //     console.log(`Attendance view failed: Lecturer ${lecturerUserId} is not the assigned lecturer for lecture ${lectureId}.`);
    //     return res.status(403).json({ error: 'Forbidden: You can only view attendance for your own lectures.' });
    // }

    // --- Fetch Attendance Records for the specific lecture ---
    const attendanceRef = db.collection(ATTENDANCE_COLLECTION);
    // Consider ordering results, e.g., by student name or registration number
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
        checkedIn: data.checkedIn || false,
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
            error: 'Internal Server Error: Failed to get lecture attendance due to missing database index.',
            details: 'A required Firestore index is missing.'
        });
    }
    res.status(500).json({
        error: 'Internal Server Error: Failed to get lecture attendance',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});

module.exports = router;
