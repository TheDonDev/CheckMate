// middleware/checkAuth.js
const { admin } = require('../firebase');

const checkAuth = async (req, res, next) => {
    // --- Log entry point and request path ---
    console.log(`checkAuth: Running for path ${req.method} ${req.path}`); // Log method and path

    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        // --- Log missing token ---
        console.log('checkAuth: Authentication Error - No Bearer token provided.');
        return res.status(401).json({ error: 'Unauthorized: No token provided.' });
    }

    const idToken = authHeader.split('Bearer ')[1];

    try {
        const decodedToken = await admin.auth().verifyIdToken(idToken);

        // --- Log successful verification ---
        console.log(`checkAuth: Token verified successfully for UID ${decodedToken.uid}, Email: ${decodedToken.email}`);

        // Attach user info to the request object for later use
        req.userData = {
            userId: decodedToken.uid,
            email: decodedToken.email,
            // Add other token claims if needed (e.g., name, picture from token)
        };

        // --- Log attached user data ---
        console.log('checkAuth: Attaching userData to request:', JSON.stringify(req.userData)); // Stringify for cleaner log

        next(); // Proceed to the next middleware or route handler

    } catch (error) {
        // --- Log the full error object and stack trace ---
        console.error('checkAuth: Authentication Error - Error verifying token:');
        console.error('Error Code:', error.code); // Log specific Firebase Auth error code
        console.error('Error Message:', error.message); // Log error message
        console.error('Full Error Object:', error); // Log the full error object for details
        console.error('Error Stack:', error.stack); // Log the stack trace

        // Provide specific error messages based on error code
        if (error.code === 'auth/id-token-expired') {
             return res.status(401).json({ error: 'Unauthorized: Token expired.' });
        }
        // Add more specific checks if needed (e.g., auth/argument-error, auth/id-token-revoked)
        return res.status(401).json({ error: 'Unauthorized: Invalid token.' });
    }
};

module.exports = checkAuth;
