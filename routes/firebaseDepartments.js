// c:\Users\Test\FlutterProjects\checkmate\routes\firebaseDepartments.js
const express = require('express');
const { db } = require('../firebase'); // Assuming firebase.js exports db
const router = express.Router();
const checkAuth = require('../middleware/checkAuth'); // Assuming you have authentication middleware

// --- Constants ---
const DEPARTMENTS_COLLECTION = 'departments'; // Standardize on lowercase
const SCHOOLS_COLLECTION = 'schools';         // Standardize on lowercase
const USERS_COLLECTION = 'users';             // For admin checks

// --- Create a new department ---
// SECURITY: Creating departments should likely be restricted to administrators.
// Apply checkAuth and add role-based authorization.
router.post('/', checkAuth, async (req, res) => { // Added checkAuth
  try {
    // --- Authorization Check (Example: Check if user is admin) ---
    const requestingUserId = req.userData.userId;
    try {
        const userDoc = await db.collection(USERS_COLLECTION).doc(requestingUserId).get();
        if (!userDoc.exists || userDoc.data().role !== 'admin') {
          console.warn(`Unauthorized attempt to create department by user: ${requestingUserId}`);
          return res.status(403).json({ error: 'Forbidden: Only administrators can create departments.' });
        }
    } catch (authError) {
        console.error(`Error checking admin role for user ${requestingUserId}:`, authError);
        return res.status(500).json({ error: 'Internal Server Error during authorization check.' });
    }
    // --- End Authorization Check ---

    const { name, schoolId } = req.body;

    // --- Validation ---
    if (!name || typeof name !== 'string' || name.trim() === '') {
        console.log('Department creation failed: Invalid or missing name.');
        return res.status(400).json({ error: 'Department name is required and must be a non-empty string.' });
    }
    if (!schoolId || typeof schoolId !== 'string' || schoolId.trim() === '') {
        console.log('Department creation failed: Invalid or missing schoolId.');
        return res.status(400).json({ error: 'School ID is required and must be a non-empty string.' });
    }

    // --- Validate that the referenced School exists ---
    const schoolRef = db.collection(SCHOOLS_COLLECTION).doc(schoolId.trim());
    const schoolDoc = await schoolRef.get();
    if (!schoolDoc.exists) {
        console.log(`Department creation failed: Referenced school with ID "${schoolId.trim()}" does not exist.`);
        return res.status(400).json({ error: `Invalid School ID: The specified school does not exist.` });
    }

    // --- Optional: Check for duplicate department name within the same school ---
    const existingDeptQuery = await db.collection(DEPARTMENTS_COLLECTION)
        .where('name', '==', name.trim())
        .where('schoolId', '==', schoolId.trim()) // Check within the specific school
        .limit(1)
        .get();

    if (!existingDeptQuery.empty) {
        console.log(`Department creation failed: Department "${name.trim()}" already exists in school ${schoolId.trim()}.`);
        return res.status(409).json({ error: `Department with name "${name.trim()}" already exists in this school.` }); // 409 Conflict
    }

    // --- Prepare Data ---
    const newDepartment = {
      name: name.trim(), // Trim whitespace
      schoolId: schoolId.trim(), // Store the ID of the parent school
      // Add other fields if needed (e.g., HOD name/ID)
      createdAt: new Date(), // Add a timestamp for tracking
    };

    // --- Add to Firestore ---
    const docRef = await db.collection(DEPARTMENTS_COLLECTION).add(newDepartment);
    console.log(`Department "${newDepartment.name}" created successfully with ID: ${docRef.id} under school ${schoolId.trim()}`);

    // Return the created object including its ID
    res.status(201).json({ id: docRef.id, ...newDepartment });

  } catch (error) {
    console.error('Error creating department:', error);
    console.error('Error Stack:', error.stack);
    res.status(500).json({
        error: 'Internal Server Error: Failed to create department',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});

// --- Get all departments ---
// Apply checkAuth if only logged-in users should see the list. Remove if public.
router.get('/', checkAuth, async (req, res) => {
  try {
    console.log('Fetching all departments');
    // Order by name for consistent listing
    const snapshot = await db.collection(DEPARTMENTS_COLLECTION).orderBy('name', 'asc').get();
    const departments = [];
    snapshot.forEach((doc) => {
      departments.push({
          id: doc.id,
          name: doc.data().name, // Explicitly get fields
          schoolId: doc.data().schoolId,
          // Include other fields if added later
       });
    });
    console.log(`Found ${departments.length} departments.`);
    res.json(departments); // Return the array of department objects
  } catch (error) {
    console.error('Error getting departments:', error);
    console.error('Error Stack:', error.stack);
    res.status(500).json({
        error: 'Internal Server Error: Failed to get departments',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});

// --- Get department by ID ---
// Apply checkAuth if only logged-in users should access this. Remove if public.
router.get('/:departmentId', checkAuth, async (req, res) => {
  try {
    const departmentId = req.params.departmentId;
    console.log(`Fetching department by ID: ${departmentId}`);

    const doc = await db.collection(DEPARTMENTS_COLLECTION).doc(departmentId).get();

    if (!doc.exists) {
      console.log(`Department not found for ID: ${departmentId}`);
      return res.status(404).json({ error: 'Department not found' });
    } else {
      console.log(`Found department for ID: ${departmentId}`);
      res.json({
          id: doc.id,
          name: doc.data().name, // Explicitly get fields
          schoolId: doc.data().schoolId,
          // Include other fields if added later
       });
    }
  } catch (error) {
    console.error(`Error getting department by ID ${req.params.departmentId}:`, error);
    console.error('Error Stack:', error.stack);
    res.status(500).json({
        error: 'Internal Server Error: Failed to get department',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});

// --- Get departments by school ID ---
// Apply checkAuth if only logged-in users should access this. Remove if public.
// NOTE: This uses the School's *Document ID*. If the frontend only has the school *name*,
// it would need to first query for the school ID based on the name, or this endpoint
// needs to be changed to accept schoolName.
router.get('/school/:schoolId', checkAuth, async (req, res) => {
  try {
    const schoolId = req.params.schoolId;
    console.log(`Fetching departments for school ID: ${schoolId}`);

    // Validate the school ID exists (optional but good practice)
    const schoolRef = db.collection(SCHOOLS_COLLECTION).doc(schoolId);
    const schoolDoc = await schoolRef.get();
    if (!schoolDoc.exists) {
        console.log(`Attempted to fetch departments for non-existent school ID: ${schoolId}`);
        return res.status(404).json({ error: `School with ID ${schoolId} not found.` });
    }

    // Query departments collection
    const departmentsRef = db.collection(DEPARTMENTS_COLLECTION);
    // This query requires a Firestore index on 'schoolId'. Check console/logs if it fails.
    const snapshot = await departmentsRef
        .where('schoolId', '==', schoolId)
        .orderBy('name', 'asc') // Order departments alphabetically
        .get();

    const departments = [];
    snapshot.forEach((doc) => {
      departments.push({
          id: doc.id,
          name: doc.data().name, // Explicitly get fields
          schoolId: doc.data().schoolId,
          // Include other fields if added later
       });
    });

    console.log(`Found ${departments.length} departments for school ID ${schoolId}.`);
    res.json(departments);

  } catch (error) {
    console.error(`Error getting departments by school ID ${req.params.schoolId}:`, error);
    console.error('Error Stack:', error.stack);
    // Check specifically for Firestore index errors
    if (error.code === 'failed-precondition' || (error.message && error.message.includes('index'))) {
        console.error("Firestore Index Missing: The query on 'schoolId' requires an index. Check the error details for a link to create it in the Firebase console.");
        return res.status(500).json({
            error: 'Internal Server Error: Failed to get departments due to missing database index.',
            details: 'A required Firestore index on the schoolId field is missing.'
        });
    }
    res.status(500).json({
        error: 'Internal Server Error: Failed to get departments by school ID',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});

// --- Add PUT (Update) and DELETE endpoints if needed, with appropriate authorization ---
// Example:
// router.put('/:departmentId', checkAuth, async (req, res) => { /* ... admin check, update logic ... */ });
// router.delete('/:departmentId', checkAuth, async (req, res) => { /* ... admin check, delete logic ... */ });

module.exports = router;
