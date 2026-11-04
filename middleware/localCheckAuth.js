const jwt = require('jsonwebtoken');

const tokenSecret = process.env.JWT_SECRET || (process.env.NODE_ENV === 'production' ? null : 'checkmate-local-development-secret-change-me');

function localCheckAuth(req, res, next) {
  const authorization = req.headers.authorization;
  if (!authorization?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Unauthorized: No token provided.' });
  }
  if (!tokenSecret) {
    return res.status(500).json({ error: 'JWT_SECRET is not configured.' });
  }
  try {
    const user = jwt.verify(authorization.slice(7), tokenSecret);
    req.userData = { userId: user.sub, email: user.email };
    next();
  } catch (_) {
    res.status(401).json({ error: 'Unauthorized: Invalid token.' });
  }
}

module.exports = localCheckAuth;