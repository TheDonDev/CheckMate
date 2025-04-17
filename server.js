const express = require('express');
const cors = require('cors'); // Import the cors package
const dotenv = require('dotenv');
const { db, messaging, admin } = require('./firebase'); // Assuming firebase.js exports these correctly
dotenv.config();

const app = express();

// --- Explicit CORS Configuration ---
// Define allowed origins.
// IMPORTANT: Replace 'http://localhost:XXXXX' and 'http://127.0.0.1:XXXXX'
// with the actual origin(s) your Flutter web app runs on during development.
// Check the browser's address bar or the 'flutter run -d chrome' output for the correct port.
const allowedOrigins = [
  // Add the specific origin(s) of your Flutter web development server
  'http://localhost:63632', // Example port from your initial logs - ADJUST IF NEEDED!
  'http://127.0.0.1:63632', // Include both localhost and 127.0.0.1 versions - ADJUST IF NEEDED!

  // Add the URL of your deployed Flutter web app here for production later
  // e.g., 'https://your-app-domain.com'
];

const corsOptions = {
  origin: function (origin, callback) {
    // Allow requests with no origin (like mobile apps, curl, Postman)
    // or requests from origins in the allowedOrigins list
    if (!origin || allowedOrigins.indexOf(origin) !== -1) {
      callback(null, true); // Allow the request
    } else {
      console.error(`CORS Error: Origin ${origin} not allowed.`); // Log denied origins
      callback(new Error('Not allowed by CORS')); // Deny the request
    }
  },
  methods: 'GET,HEAD,PUT,PATCH,POST,DELETE', // Specify allowed HTTP methods
  allowedHeaders: ['Content-Type', 'Authorization'], // Explicitly allow Content-Type and Authorization headers
  credentials: true // Allow credentials (like Authorization header with token) to be sent
};

// Apply the CORS middleware with the specified options
app.use(cors(corsOptions));
// --- End CORS Configuration ---


// --- Standard Middleware ---
// Middleware to parse incoming JSON request bodies
app.use(express.json());
// Middleware to parse URL-encoded request bodies (optional, if you use form submissions)
// app.use(express.urlencoded({ extended: true }));
// --- End Standard Middleware ---


// --- API Route Definitions ---
// Import route handlers from separate files
const firebaseLectureRoutes = require('./routes/firebaseLectures');
const firebaseAttendanceRoutes = require('./routes/firebaseAttendance');
const firebaseUserRoutes = require('./routes/firebaseUsers');
const firebaseSchoolRoutes = require('./routes/firebaseSchools');
const firebaseDepartmentRoutes = require('./routes/firebaseDepartments');
const firebaseCourseRoutes = require('./routes/firebaseCourses');

// Mount the imported routes onto specific base paths
app.use('/api/firebase/lectures', firebaseLectureRoutes);
app.use('/api/firebase/attendance', firebaseAttendanceRoutes);
app.use('/api/firebase/users', firebaseUserRoutes);
app.use('/api/firebase/schools', firebaseSchoolRoutes);
app.use('/api/firebase/departments', firebaseDepartmentRoutes);
app.use('/api/firebase/courses', firebaseCourseRoutes);
// --- End API Route Definitions ---


// --- Health Check Endpoint (Optional but Recommended) ---
app.get('/health', (req, res) => {
  res.status(200).send('Server is healthy');
});
// --- End Health Check Endpoint ---


// --- Global Error Handler (Optional but Recommended) ---
// Catches errors from async route handlers if they are not caught locally
app.use((err, req, res, next) => {
  console.error("Global Error Handler Caught:", err.stack); // Log the error stack trace
  // Avoid sending stack trace to client in production
  const statusCode = err.statusCode || 500;
  const message = process.env.NODE_ENV === 'production' ? 'An internal server error occurred' : err.message;
  res.status(statusCode).json({ error: message });
});
// --- End Global Error Handler ---


// --- Start the Server ---
// Define the port the server will listen on, using environment variable or default
const PORT = process.env.PORT || 5000;

// Start the Express server
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
  console.log(`Allowed CORS origins: ${allowedOrigins.join(', ')}`); // Log allowed origins on startup
});
// --- End Start the Server ---
