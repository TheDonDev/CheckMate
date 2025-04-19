// middleware/checkAuth.js
const { admin } = require('../firebase'); // points to Firebase Admin initialization

const checkAuth = async (req, res, next) => {
    // --- Log entry point and request path ---
    console.log(`checkAuth: Running for path ${req.method} ${req.path}`); // Log method and path

    const authHeader = req.headers.authorization;

    // Check if the Authorization header exists and starts with "Bearer "
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        // --- Log missing token ---
        console.log('checkAuth: Authentication Error - No Bearer token provided.');
        // Return 401 Unauthorized if the token is missing or format is incorrect
        return res.status(401).json({ error: 'Unauthorized: No token provided.' });
    }

    // Extract the token part after "Bearer "
    const idToken = authHeader.split('Bearer ')[1];

    try {
        // Verify the ID token using the Firebase Admin SDK
        const decodedToken = await admin.auth().verifyIdToken(idToken);

        // --- Log successful verification ---
        console.log(`checkAuth: Token verified successfully for UID ${decodedToken.uid}, Email: ${decodedToken.email}`);

        // Attach user info (UID and email) from the decoded token to the request object
        // This makes it available in route handlers (e.g., req.userData.userId)
        req.userData = {
            userId: decodedToken.uid,
            email: decodedToken.email,
            // Can add other standard claims from decodedToken if needed:
            // name: decodedToken.name,
            // picture: decodedToken.picture,
            // Note: Custom claims would also be available here if set.
        };

        // --- Log attached user data ---
        // Use JSON.stringify for a cleaner log output of the object
        console.log('checkAuth: Attaching userData to request:', JSON.stringify(req.userData));

        // Proceed to the next middleware or the actual route handler
        next();

    } catch (error) {
        // --- Log the full error object and stack trace for debugging ---
        console.error('checkAuth: Authentication Error - Error verifying token:');
        console.error('Error Code:', error.code); // Log specific Firebase Auth error code (e.g., 'auth/id-token-expired')
        console.error('Error Message:', error.message); // Log the error message
        // console.error('Full Error Object:', error); // Uncomment for very detailed debugging 
        // console.error('Error Stack:', error.stack); // Uncomment for stack trace 

        // Provide specific error messages based on common Firebase Auth error codes
        if (error.code === 'auth/id-token-expired') {
             return res.status(401).json({ error: 'Unauthorized: Token expired.' });
        }
        if (error.code === 'auth/argument-error') {
             // This often happens if the token format is wrong before verification
             return res.status(401).json({ error: 'Unauthorized: Invalid token format.' });
        }
        // Handle other potential errors (revoked token, etc.)
        // if (error.code === 'auth/id-token-revoked') {
        //     return res.status(401).json({ error: 'Unauthorized: Token revoked.' });
        // }

        // Return a generic 401 Unauthorized for other verification errors
        return res.status(401).json({ error: 'Unauthorized: Invalid token.' });
    }
};

module.exports = checkAuth;
