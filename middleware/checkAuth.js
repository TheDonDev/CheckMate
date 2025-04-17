// middleware/checkAuth.js
const { admin } = require('../firebase'); // Assuming firebase.js exports initialized admin SDK

const checkAuth = async (req, res, next) => {
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        console.log('Authentication Error: No Bearer token provided.');
        return res.status(401).json({ error: 'Unauthorized: No token provided.' });
    }

    const idToken = authHeader.split('Bearer ')[1];

    try {
        const decodedToken = await admin.auth().verifyIdToken(idToken);
        // Attach user info to the request object for later use
        req.userData = {
            userId: decodedToken.uid,
            email: decodedToken.email,
            // You can add other token claims if needed
        };
        // console.log(`User authenticated: ${req.userData.email} (${req.userData.userId})`); // Debug log
        next(); // Proceed to the next middleware or route handler
    } catch (error) {
        console.error('Authentication Error: Invalid or expired token.', error.code);
        // Provide specific error messages based on error code
        if (error.code === 'auth/id-token-expired') {
             return res.status(401).json({ error: 'Unauthorized: Token expired.' });
        }
        return res.status(401).json({ error: 'Unauthorized: Invalid token.' });
    }
};

module.exports = checkAuth;
