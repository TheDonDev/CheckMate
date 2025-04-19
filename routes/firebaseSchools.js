// c:\Users\Test\FlutterProjects\checkmate\routes\firebaseSchools.js
const express = require('express');
const { db } = require('../firebase'); // Assuming firebase.js exports db
const router = express.Router();
const checkAuth = require('../middleware/checkAuth'); // Assuming you have authentication middleware

// --- Constants ---
const SCHOOLS_COLLECTION = 'schools'; // Standardize on lowercase

// --- Create a new school ---
// SECURITY: Creating schools should likely be restricted to administrators.
// Apply checkAuth and add role-based authorization.
router.post('/', checkAuth, async (req, res) => { // Added checkAuth
  try {
    // --- Authorization Check (Example: Check if user is admin) ---
    // const requestingUserId = req.userData.userId;
    // const userDoc = await db.collection('users').doc(requestingUserId).get(); // Use 'users' collection
    // if (!userDoc.exists || userDoc.data().role !== 'admin') {
    //   console.warn(`Unauthorized attempt to create school by user: ${requestingUserId}`);
    //   return res.status(403).json({ error: 'Forbidden: Only administrators can create schools.' });
    // }
    // --- End Authorization Check ---

    const { name } = req.body;

    // --- Validation ---
    if (!name || typeof name !== 'string' || name.trim() === '') {
        console.log('School creation failed: Invalid or missing name.');
        return res.status(400).json({ error: 'School name is required and must be a non-empty string.' });
    }

    // Optional: Check if school name already exists to prevent duplicates
    const existingSchoolQuery = await db.collection(SCHOOLS_COLLECTION).where('name', '==', name.trim()).limit(1).get();
    if (!existingSchoolQuery.empty) {
        console.log(`School creation failed: School with name "${name.trim()}" already exists.`);
        return res.status(409).json({ error: `School with name "${name.trim()}" already exists.` }); // 409 Conflict
    }

    // --- Prepare Data ---
    const newSchool = {
      name: name.trim(), // Trim whitespace
      // Add other fields if needed in the future (e.g., abbreviation, dean)
      createdAt: new Date(), // Add a timestamp for tracking
    };

    // --- Add to Firestore ---
    const docRef = await db.collection(SCHOOLS_COLLECTION).add(newSchool);
    console.log(`School "${newSchool.name}" created successfully with ID: ${docRef.id}`);

    // Return the created object including its ID
    res.status(201).json({ id: docRef.id, ...newSchool });

  } catch (error) {
    console.error('Error creating school:', error);
    console.error('Error Stack:', error.stack);
    res.status(500).json({
        error: 'Internal Server Error: Failed to create school',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});

// --- Get all schools ---
// Apply checkAuth if only logged-in users should see the list. Remove if public.
router.get('/', checkAuth, async (req, res) => {
  try {
    console.log('Fetching all schools');
    // Order by name for consistent listing
    const snapshot = await db.collection(SCHOOLS_COLLECTION).orderBy('name', 'asc').get();
    const schools = [];
    snapshot.forEach((doc) => {
      schools.push({
          id: doc.id,
          name: doc.data().name, // Explicitly get name
          // Include other fields if added later
       });
    });
    console.log(`Found ${schools.length} schools.`);
    res.json(schools); // Return the array of school objects
  } catch (error) {
    console.error('Error getting schools:', error);
    console.error('Error Stack:', error.stack);
    res.status(500).json({
        error: 'Internal Server Error: Failed to get schools',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});

// --- Get school by ID ---
// Apply checkAuth if only logged-in users should access this. Remove if public.
router.get('/:schoolId', checkAuth, async (req, res) => {
  try {
    const schoolId = req.params.schoolId;
    console.log(`Fetching school by ID: ${schoolId}`);

    const doc = await db.collection(SCHOOLS_COLLECTION).doc(schoolId).get();

    if (!doc.exists) {
      console.log(`School not found for ID: ${schoolId}`);
      return res.status(404).json({ error: 'School not found' });
    } else {
      console.log(`Found school for ID: ${schoolId}`);
      res.json({
          id: doc.id,
          name: doc.data().name, // Explicitly get name
          // Include other fields if added later
       });
    }
  } catch (error) {
    console.error(`Error getting school by ID ${req.params.schoolId}:`, error);
    console.error('Error Stack:', error.stack);
    res.status(500).json({
        error: 'Internal Server Error: Failed to get school',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined
    });
  }
});

// --- Add PUT (Update) and DELETE endpoints if needed, with appropriate authorization ---
// Example:
// router.put('/:schoolId', checkAuth, async (req, res) => { /* ... admin check, update logic ... */ });
// router.delete('/:schoolId', checkAuth, async (req, res) => { /* ... admin check, delete logic ... */ });

module.exports = router;
