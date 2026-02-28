const express = require('express');
const cors = require('cors'); // Import the cors package
const dotenv = require('dotenv');
const { db, messaging, admin } = require('./firebase'); // Assuming firebase.js exports these correctly
dotenv.config();

const app = express();

// --- Explicit CORS Configuration ---
// Define specific allowed origins (e.g., for production deployment).
const specificAllowedOrigins = [
  'http://localhost:65178', // Flutter app origin
  'http://127.0.0.1:65178', // Flutter app origin
  'http://10.0.2.2:5000',   // Android emulator accessing localhost
  'http://localhost:50169',  // Allow Flutter app origin
  'http://localhost:51897'   // Allow Flutter app origin
];

const corsOptions = {
  origin: function (origin, callback) {
    // 1. Allow requests with no origin (like mobile apps, curl requests, server-to-server)
    if (!origin) {
      return callback(null, true);
    }

    // 2. Allow origins matching localhost or 127.0.0.1 with any port (for local development)
    const developmentOriginRegex = /^http:\/\/(localhost|127.0.0.1):\d+$/;
    if (developmentOriginRegex.test(origin)) {
      return callback(null, true);
    }

    // 3. Allow specific origins from the predefined list (for production, staging, etc.)
    if (specificAllowedOrigins.includes(origin)) {
      return callback(null, true);
    }

    // 4. If none of the above match, deny the request
    console.error(`CORS Error: Origin ${origin} not allowed.`); // Log denied origins
    callback(new Error('Not allowed by CORS')); // Deny the request
  },
  methods: 'GET,HEAD,PUT,PATCH,POST,DELETE', // Specify allowed HTTP methods
  allowedHeaders: ['Content-Type', 'Authorization'], // Explicitly allow Content-Type and Authorization headers
  credentials: true // Allow credentials (like Authorization header with token) to be sent
};

// Apply the CORS middleware with the specified options
app.use(cors(corsOptions));
// --- End CORS Configuration ---

// --- Standard Middleware ---
app.use(express.json());

// --- API Route Definitions ---
const firebaseLectureRoutes = require('./routes/firebaseLectures');
const firebaseAttendanceRoutes = require('./routes/firebaseAttendance');
const firebaseUserRoutes = require('./routes/firebaseUsers');
const firebaseSchoolRoutes = require('./routes/firebaseSchools');
const firebaseDepartmentRoutes = require('./routes/firebaseDepartments');
const firebaseCourseRoutes = require('./routes/firebaseCourses');

app.use('/api/firebase/lectures', firebaseLectureRoutes);
app.use('/api/firebase/attendance', firebaseAttendanceRoutes);
app.use('/api/firebase/users', firebaseUserRoutes);
app.use('/api/firebase/schools', firebaseSchoolRoutes);
app.use('/api/firebase/departments', firebaseDepartmentRoutes);
app.use('/api/firebase/courses', firebaseCourseRoutes);

// --- Health Check Endpoint ---
app.get('/health', (req, res) => {
  res.status(200).send('Server is healthy');
});

// --- Global Error Handler ---
app.use((err, req, res, next) => {
  if (err.message === 'Not allowed by CORS') {
      console.error("CORS Error caught by Global Handler:", err.message);
      return res.status(403).json({ error: 'Not allowed by CORS' }); // 403 Forbidden is appropriate
  }

  console.error("Global Error Handler Caught:", err.stack || err);
  const statusCode = err.statusCode || 500;
  const message = (process.env.NODE_ENV === 'production' && statusCode === 500)
                  ? 'An internal server error occurred'
                  : err.message || 'An unexpected error occurred';
  res.status(statusCode).json({ error: message });
});

// --- Start the Server ---
const PORT = process.env.PORT || 5000;

app.listen(PORT, async () => {
  console.log(`Server running on port ${PORT}`);
  console.log(`CORS configured to allow:`);
  console.log(`  - Requests with no origin`);
  console.log(`  - Any origin matching http://localhost:<port> or http://127.0.0.1:<port> (for development)`);
  if (specificAllowedOrigins.length > 0) {
    console.log(`  - Specific origins: ${specificAllowedOrigins.join(', ')}`);
  } else {
    console.log(`  - No specific origins currently listed in specificAllowedOrigins.`);
  }

  // --- Connection Verification ---
  try {
    console.log("Verifying Firestore connection...");
    await db.listCollections();
    console.log("✅ Firestore connection verified.");
  } catch (error) {
    console.error("❌ Firestore connection FAILED.");
    console.error("Error details:", error.message);
    if (error.message.includes("UNAUTHENTICATED") || error.message.includes("ACCESS_TOKEN_EXPIRED")) {
        console.error("👉 SUGGESTION: Your local Google Cloud credentials may have expired.\n   Run: 'gcloud auth application-default login'");
    }
  }
});
