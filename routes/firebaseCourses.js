// c:\Users\Test\FlutterProjects\checkmate\routes\firebaseCourses.js
const express = require('express');
const { db } = require('../firebase'); // Assuming firebase.js exports db
const router = express.Router();
const checkAuth = require('../middleware/checkAuth'); // Assuming you have authentication middleware

// --- Constants ---
const COURSES_COLLECTION = 'courses';         // Standardize on lowercase
const DEPARTMENTS_COLLECTION = 'departments'; // Standardize on lowercase
const USERS_COLLECTION = 'users';             // For admin checks

// --- Create a new course ---
// SECURITY: Creating courses should likely be restricted to administrators.
// Apply checkAuth and add role-based authorization.
router.post('/', checkAuth, async (req, res) => { // Added checkAuth
  try {
    // --- Authorization Check (Example: Check if user is admin) ---
    const requestingUserId = req.userData.userId;
    try {
        const userDoc = await db.collection(USERS_COLLECTION).doc(requestingUserId).get();
        if (!userDoc.exists || userDoc.data().role !== 'admin') {
          console.warn(`Unauthorized attempt to create course by user: ${requestingUserId}`);
          return res.status(403).json({ error: 'Forbidden: Only administrators can create courses.' });
        }
    } catch (authError) {
        console.error(`Error checking admin role for user ${requestingUserId}:`, authError);
        return res.status(500).json({ error: 'Internal Server Error during authorization check.' });
    }
    // --- End Authorization Check ---

    // --- Extract Data from Request Body ---
    // Consider if schoolId is also needed for context or validation, depending on data model
    const { name, departmentId } = req.body;

    // --- Validation ---
    if (!name || typeof name !== 'string' || name.trim() === '') {
        console.log('Course creation failed: Invalid or missing name.');
        return res.status(400).json({ error: 'Course name is required and must be a non-empty string.' });
    }
    if (!departmentId || typeof departmentId !== 'string' || departmentId.trim() === '') {
        console.log('Course creation failed: Invalid or missing departmentId.');
        return res.status(400).json({ error: 'Department ID is required and must be a non-empty string.' });
    }

    // --- Validate that the referenced Department exists ---
    const departmentRef = db.collection(DEPARTMENTS_COLLECTION).doc(departmentId.trim());
    const departmentDoc = await departmentRef.get();
    if (!departmentDoc.exists) {
        console.log(`Course creation failed: Referenced department with ID "${departmentId.trim()}" does not exist.`);
        return res.status(400).json({ error: `Invalid Department ID: The specified department does not exist.` });
    }

    // --- Optional: Check for duplicate course name within the same department ---
    const existingCourseQuery = await db.collection(COURSES_COLLECTION)
        .where('name', '==', name.trim())
        .where('departmentId', '==', departmentId.trim()) // Check within the specific department
        .limit(1)
        .get();

    if (!existingCourseQuery.empty) {
        console.log(`Course creation failed: Course "${name.trim()}" already exists in department ${departmentId.trim()}.`);
        return res.status(409).json({ error: `Course with name "${name.trim()}" already exists in this department.` }); // 409 Conflict
    }

    // --- Prepare Data ---
    const newCourse = {
      name: name.trim(), // Trim whitespace
      departmentId: departmentId.trim(), // Store the ID of the parent department
      // Add other fields if needed (e.g., course code, credits, schoolId if denormalizing)
      createdAt: new Date(), // Add a timestamp for tracking
    };

    // --- Add to Firestore ---
    const docRef = await db.collection(COURSES_COLLECTION).add(newCourse);
    console.log(`Course "${newCourse.name}" created successfully with ID: ${docRef.id} under department ${departmentId.trim()}`);

    // Return the created object including its ID
    res.status(201).json({ id: docRef.id, ...newCourse });

  } catch (error) {
    console.error('Error creating course:', error);
    console.error('Error Stack:', error.stack);
    res.status(500).json({
        error: 'Internal Server Error: Failed to create course',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});

// --- Get all courses ---
// Apply checkAuth if only logged-in users should see the list. Remove if public.
router.get('/', checkAuth, async (req, res) => {
  try {
    console.log('Fetching all courses');
    // Order by name for consistent listing
    const snapshot = await db.collection(COURSES_COLLECTION).orderBy('name', 'asc').get();
    const courses = [];
    snapshot.forEach((doc) => {
      courses.push({
          id: doc.id,
          name: doc.data().name, // Explicitly get fields
          departmentId: doc.data().departmentId,
          // Include other fields if added later
       });
    });
    console.log(`Found ${courses.length} courses.`);
    res.json(courses); // Return the array of course objects
  } catch (error) {
    console.error('Error getting courses:', error);
    console.error('Error Stack:', error.stack);
    res.status(500).json({
        error: 'Internal Server Error: Failed to get courses',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});

// --- Get course by ID ---
// Apply checkAuth if only logged-in users should access this. Remove if public.
router.get('/:courseId', checkAuth, async (req, res) => {
  try {
    const courseId = req.params.courseId;
    console.log(`Fetching course by ID: ${courseId}`);

    const doc = await db.collection(COURSES_COLLECTION).doc(courseId).get();

    if (!doc.exists) {
      console.log(`Course not found for ID: ${courseId}`);
      return res.status(404).json({ error: 'Course not found' });
    } else {
      console.log(`Found course for ID: ${courseId}`);
      res.json({
          id: doc.id,
          name: doc.data().name, // Explicitly get fields
          departmentId: doc.data().departmentId,
          // Include other fields if added later
       });
    }
  } catch (error) {
    console.error(`Error getting course by ID ${req.params.courseId}:`, error);
    console.error('Error Stack:', error.stack);
    res.status(500).json({
        error: 'Internal Server Error: Failed to get course',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});

// --- Get courses by department ID ---
// Apply checkAuth if only logged-in users should access this. Remove if public.
// NOTE: This uses the Department's *Document ID*.
router.get('/department/:departmentId', checkAuth, async (req, res) => {
  try {
    const departmentId = req.params.departmentId;
    console.log(`Fetching courses for department ID: ${departmentId}`);

    // Validate the department ID exists (optional but good practice)
    const departmentRef = db.collection(DEPARTMENTS_COLLECTION).doc(departmentId);
    const departmentDoc = await departmentRef.get();
    if (!departmentDoc.exists) {
        console.log(`Attempted to fetch courses for non-existent department ID: ${departmentId}`);
        return res.status(404).json({ error: `Department with ID ${departmentId} not found.` });
    }

    // Query courses collection
    const coursesRef = db.collection(COURSES_COLLECTION);
    // This query requires a Firestore index on 'departmentId'. Check console/logs if it fails.
    const snapshot = await coursesRef
        .where('departmentId', '==', departmentId)
        .orderBy('name', 'asc') // Order courses alphabetically
        .get();

    const courses = [];
    snapshot.forEach((doc) => {
      courses.push({
          id: doc.id,
          name: doc.data().name, // Explicitly get fields
          departmentId: doc.data().departmentId,
          // Include other fields if added later
       });
    });

    console.log(`Found ${courses.length} courses for department ID ${departmentId}.`);
    res.json(courses);

  } catch (error) {
    console.error(`Error getting courses by department ID ${req.params.departmentId}:`, error);
    console.error('Error Stack:', error.stack);
    // Check specifically for Firestore index errors
    if (error.code === 'failed-precondition' || (error.message && error.message.includes('index'))) {
        console.error("Firestore Index Missing: The query on 'departmentId' requires an index. Check the error details for a link to create it in the Firebase console.");
        return res.status(500).json({
            error: 'Internal Server Error: Failed to get courses due to missing database index.',
            details: 'A required Firestore index on the departmentId field is missing.'
        });
    }
    res.status(500).json({
        error: 'Internal Server Error: Failed to get courses by department ID',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});

// --- Add PUT (Update) and DELETE endpoints if needed, with appropriate authorization ---
// Example:
// router.put('/:courseId', checkAuth, async (req, res) => { /* ... admin check, update logic ... */ });
// router.delete('/:courseId', checkAuth, async (req, res) => { /* ... admin check, delete logic ... */ });

module.exports = router;
