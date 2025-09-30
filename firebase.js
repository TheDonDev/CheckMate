
const admin = require('firebase-admin');

const serviceAccount = require('./serviceAccountKey.json'); // Service account key path

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  databaseURL: 'https://checkmate-1eba2.firebaseio.com' // If you need Realtime Database
});

const db = admin.firestore();
const messaging = admin.messaging();

module.exports = { db, messaging, admin };
