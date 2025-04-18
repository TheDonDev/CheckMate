// c:\Users\Test\FlutterProjects\checkmate\routes\firebaseAttendance.js

const express = require('express');
const { db, admin } = require('../firebase'); // Assuming firebase.js exports db and admin
const router = express.Router();
const checkAuth = require('../middleware/checkAuth'); // <--- Make sure this path is correct

// --- Constants for Collection Names (Good Practice) ---
const ATTENDANCE_COLLECTION = 'Attendance'; // Use your actual collection name
const USERS_COLLECTION = 'users';           // Use your actual users collection name
const LECTURES_COLLECTION = 'lectures';     // Use your actual lectures collection name

// --- Helper Function for Timestamp Conversion ---
const formatTimestamp = (timestamp) => {
  // Check if it's a Firestore Timestamp object and has the toDate method
  if (timestamp && typeof timestamp.toDate === 'function') {
    return timestamp.toDate().toISOString();
  }
  // If it's already null, undefined, or some other type, return null
  return null;
};


// --- Student joins a lecture ---
// Apply checkAuth middleware to ensure user is logged in
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

    // --- Fetch Student Details (including registrationNumber and name) from Firestore ---
    const studentUserRef = db.collection(USERS_COLLECTION).doc(studentUserId);
    const studentUserDoc = await studentUserRef.get();

    if (!studentUserDoc.exists) {
        console.error(`Join attempt failed: User document not found for authenticated user ID: ${studentUserId}`);
        return res.status(404).json({ error: 'Authenticated user profile not found.' });
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
        // Match the frontend error handling requirement
        return res.status(400).json({ error: 'User profile is missing the registration number. Cannot join lecture.' });
    }
    // Use name from profile, provide a default if missing
    const studentName = studentData.name || 'N/A';

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

    // Return the created record with approximated timestamp for immediate use
    res.status(201).json({
        id: docRef.id,
        ...attendanceData,
        joinedAt: new Date().toISOString(), // Return current time as approximation
        checkInTime: null, // Explicitly null
     });

  } catch (error) {
    console.error(`Error joining lecture ${req.params.lectureId} for user ${req.userData?.userId}:`, error);
    console.error('Error Stack:', error.stack);
    res.status(500).json({
        error: 'Internal Server Error: Failed to join lecture',
        // Provide more detail only in non-production environments
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});

// --- Lecturer checks in a student ---
// Apply checkAuth middleware
router.post('/checkin', checkAuth, async (req, res) => {
  try {
    const lecturerUserId = req.userData.userId; // Get lecturer ID from token

    // --- Get registrationNumber AND lectureId from request body ---
    // LectureId is crucial to identify the correct attendance record
    const { registrationNumber, lectureId } = req.body;

    // --- Validate Input ---
    if (!registrationNumber || !lectureId) {
      console.log(`Check-in failed: Missing registrationNumber or lectureId in request body.`);
      return res.status(400).json({ error: 'Both registrationNumber and lectureId are required in the request body.' });
    }

    // --- Verify Lecturer Role ---
    const lecturerUserRef = db.collection(USERS_COLLECTION).doc(lecturerUserId);
    const lecturerUserDoc = await lecturerUserRef.get();
    if (!lecturerUserDoc.exists || lecturerUserDoc.data().role !== 'lecturer') {
        console.log(`Check-in failed: User ${lecturerUserId} is not authorized (not found or not a lecturer).`);
        return res.status(403).json({ error: 'Forbidden: Only lecturers can check students in.' });
    }

    // --- Optional but Recommended: Verify this lecturer is associated with the lecture ---
    const lectureRef = db.collection(LECTURES_COLLECTION).doc(lectureId);
    const lectureDoc = await lectureRef.get();
    if (!lectureDoc.exists) {
        console.log(`Check-in failed: Lecture ${lectureId} not found.`);
        return res.status(404).json({ error: 'Lecture not found.' });
    }
    // Decide on strictness: Allow any lecturer or only the assigned one?
    // if (lectureDoc.data().lecturerId !== lecturerUserId) {
    //     console.log(`Check-in failed: Lecturer ${lecturerUserId} is not the assigned lecturer for lecture ${lectureId}.`);
    //     return res.status(403).json({ error: 'Forbidden: You are not the lecturer for this session.' });
    // }
    // For now, allow any lecturer but log if it's not the assigned one
    if (lectureDoc.data().lecturerId !== lecturerUserId) {
         console.warn(`Check-in allowed: Lecturer ${lecturerUserId} checking in for lecture ${lectureId} taught by ${lectureDoc.data().lecturerId}.`);
    }

    // --- Find the specific attendance record using BOTH registrationNumber and lectureId ---
    const attendanceRef = db.collection(ATTENDANCE_COLLECTION);
    const querySnapshot = await attendanceRef
      .where('registrationNumber', '==', registrationNumber)
      .where('lectureId', '==', lectureId) // Ensure we target the correct lecture
      .limit(1) // Should only be one record per student per lecture
      .get();

    if (querySnapshot.empty) {
      console.log(`Check-in failed: No attendance record found for registration number ${registrationNumber} in lecture ${lectureId}. Student might not have joined.`);
      // Provide a more specific error message
      return res.status(404).json({ error: 'Student with this registration number has not joined this specific lecture session.' });
    }

    // There should be only one document due to the limit(1) and query constraints
    const attendanceDoc = querySnapshot.docs[0];
    const attendanceData = attendanceDoc.data();

    // --- Check if already checked in ---
    if (attendanceData.checkedIn === true) {
        console.log(`Check-in skipped: Student ${registrationNumber} already checked into lecture ${lectureId}.`);
        // Return current data with a specific message
        return res.status(200).json({
            message: 'Student already checked in.',
            id: attendanceDoc.id,
            ...attendanceData,
            // Ensure timestamps are formatted for client
            checkInTime: formatTimestamp(attendanceData.checkInTime),
            joinedAt: formatTimestamp(attendanceData.joinedAt),
        });
    }

    // --- Update the attendance record ---
    const checkInTimestamp = admin.firestore.FieldValue.serverTimestamp();
    await attendanceDoc.ref.update({
      checkInTime: checkInTimestamp,
      checkedIn: true, // Use standardized field name
      checkedInBy: lecturerUserId, // Record who checked them in
    });

    console.log(`Check-in successful: Student ${registrationNumber} checked into lecture ${lectureId} by lecturer ${lecturerUserId}.`);

    // --- Return success message with student details (as requested by frontend) ---
    res.json({
        // Use studentName from the record we found
        message: `Student ${attendanceData.studentName || 'N/A'} (${registrationNumber}) checked in successfully.`,
        // Optionally return the updated record data, formatted correctly
        checkedInData: {
            id: attendanceDoc.id,
            lectureId: attendanceData.lectureId,
            userId: attendanceData.userId,
            registrationNumber: attendanceData.registrationNumber,
            studentName: attendanceData.studentName,
            checkedIn: true,
            checkInTime: new Date().toISOString(), // Return current time as approximation
            checkedInBy: lecturerUserId,
            joinedAt: formatTimestamp(attendanceData.joinedAt),
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
// Apply checkAuth middleware
router.get('/student/:userId', checkAuth, async (req, res) => {
  try {
    const requestedUserId = req.params.userId;
    const authUserId = req.userData.userId; // User ID from the token

    // --- Authorization: Ensure users can only view their own attendance ---
    if (requestedUserId !== authUserId) {
        console.log(`Forbidden attempt: User ${authUserId} tried to access attendance for ${requestedUserId}`);
        return res.status(403).json({ error: 'Forbidden: You can only access your own attendance records.' });
    }

    // --- Fetch Attendance Records ---
    const attendanceRef = db.collection(ATTENDANCE_COLLECTION);
    const snapshot = await attendanceRef.where('userId', '==', requestedUserId).get();

    const attendanceRecords = [];
    snapshot.forEach((doc) => {
      const data = doc.data();
      attendanceRecords.push({
          id: doc.id,
          ...data,
          // Convert Timestamps for client consistency
          checkInTime: formatTimestamp(data.checkInTime),
          joinedAt: formatTimestamp(data.joinedAt),
          // Ensure consistent field name and boolean value
          checkedIn: data.checkedIn || false,
       });
    });

    // --- Percentage Calculation ---
    let percentage = 0;
    let totalLectures = 0;
    let attendedLecturesCount = attendanceRecords.filter((record) => record.checkedIn === true).length;

    try {
        // Fetch user profile to get criteria for finding relevant lectures
        const userDoc = await db.collection(USERS_COLLECTION).doc(requestedUserId).get();
        if (userDoc.exists) {
            const userData = userDoc.data();
            // **IMPORTANT**: Adjust these field names to EXACTLY match your 'users' and 'lectures' collections
            const { school, department, course, yearOfStudy, semester } = userData; // Example field names

            // Check if all necessary fields are present for the query
            if (school && department && course && yearOfStudy && semester) {
                const lecturesRef = db.collection(LECTURES_COLLECTION);
                // This query likely requires a composite index in Firestore.
                // Check Firestore console -> Indexes if this query fails or is slow.
                const lecturesSnapshot = await lecturesRef
                    .where('school', '==', school) // Adjust field name if needed
                    .where('department', '==', department) // Adjust field name if needed
                    .where('course', '==', course) // Adjust field name if needed
                    .where('yearOfStudy', '==', yearOfStudy) // Adjust field name if needed (e.g., 'year')
                    .where('semester', '==', semester) // Adjust field name if needed
                    .get();

                totalLectures = lecturesSnapshot.size;
                percentage = totalLectures > 0 ? (attendedLecturesCount / totalLectures) * 100 : 0;
                console.log(`Attendance calculation for ${requestedUserId}: Attended ${attendedLecturesCount} / Total ${totalLectures} relevant lectures.`);
            } else {
                 console.warn(`Cannot calculate percentage for user ${requestedUserId}: Missing profile details (school/dept/course/year/semester). Using attended count only.`);
                 // Fallback: maybe calculate based only on lectures they *joined*? Less accurate.
                 // totalLectures = attendanceRecords.length; // Alternative, less accurate total
                 // percentage = totalLectures > 0 ? (attendedLecturesCount / totalLectures) * 100 : 0;
            }
        } else {
             console.warn(`Cannot calculate percentage for user ${requestedUserId}: User document not found.`);
        }
    } catch (calcError) {
        console.error(`Error calculating attendance percentage for user ${requestedUserId}:`, calcError);
        // Proceed without percentage if calculation fails, don't crash the request
    }
    // --- End Percentage Calculation ---

    const data = {
      attendanceRecords, // Contains registrationNumber, studentName etc. from when they joined
      percentage: percentage.toFixed(2), // Format to 2 decimal places
      totalLectures: totalLectures, // Total relevant lectures found (can be 0)
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
// Apply checkAuth middleware
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

    // --- Optional but Recommended: Verify the lecture exists and maybe if this lecturer owns it ---
    const lectureRef = db.collection(LECTURES_COLLECTION).doc(lectureId);
    const lectureDoc = await lectureRef.get();
    if (!lectureDoc.exists) {
        console.log(`Attendance view failed: Lecture ${lectureId} not found.`);
        return res.status(404).json({ error: 'Lecture not found.' });
    }
    // Allow any lecturer to view for now, but could restrict here:
    // if (lectureDoc.data().lecturerId !== lecturerUserId) {
    //     console.log(`Attendance view failed: Lecturer ${lecturerUserId} is not the assigned lecturer for lecture ${lectureId}.`);
    //     return res.status(403).json({ error: 'Forbidden: You can only view attendance for your own lectures.' });
    // }

    // --- Fetch Attendance Records for the specific lecture ---
    const attendanceRef = db.collection(ATTENDANCE_COLLECTION);
    const snapshot = await attendanceRef.where('lectureId', '==', lectureId).get();

    const attendanceRecords = [];
    snapshot.forEach((doc) => {
      const data = doc.data();
      // Ensure all necessary fields are included, matching frontend needs
      attendanceRecords.push({
        id: doc.id,
        registrationNumber: data.registrationNumber || 'N/A', // Default if missing
        studentName: data.studentName || 'N/A',             // Default if missing
        lectureId: data.lectureId,
        userId: data.userId,
        checkedIn: data.checkedIn || false, // Standardized name, default false
        // Convert Timestamps for client consistency
        checkInTime: formatTimestamp(data.checkInTime),
        joinedAt: formatTimestamp(data.joinedAt),
        checkedInBy: data.checkedInBy || null, // Include who checked them in
      });
    });

    console.log(`Fetched ${attendanceRecords.length} attendance records for lecture ${lectureId} by request from lecturer ${lecturerUserId}.`);
    // Return the array of records (frontend will handle sorting)
    res.json(attendanceRecords);

  } catch (error) {
    console.error(`Error getting lecture attendance for lecture ${req.params.lectureId}:`, error);
    console.error('Error Stack:', error.stack);
    res.status(500).json({
        error: 'Internal Server Error: Failed to get lecture attendance',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});

module.exports = router;
