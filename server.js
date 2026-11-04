const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');
dotenv.config();
const { initializeDatabase } = require('./db');

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

app.use('/api/auth', require('./routes/localAuth'));
app.use('/api/catalog', require('./routes/localCatalog'));
app.use('/api/firebase/users', require('./routes/localUsers'));
app.use('/api/firebase/lectures', require('./routes/localLectures'));
app.use('/api/firebase/attendance', require('./routes/localAttendance'));

// --- Health Check Endpoint ---
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok', database: 'postgresql' });
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

initializeDatabase()
  .then(() => app.listen(PORT, () => console.log(`CheckMate API listening on port ${PORT}`)))
  .catch((error) => {
    console.error(`PostgreSQL initialization failed: ${error.message}`);
    process.exitCode = 1;
  });
