const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');
const { db, messaging, admin } = require('./firebase');
dotenv.config();

const app = express();
app.use(cors());
app.use(express.json());

// New Firebase Routes
const firebaseLectureRoutes = require('./routes/firebaseLectures');
const firebaseAttendanceRoutes = require('./routes/firebaseAttendance');
const firebaseUserRoutes = require('./routes/firebaseUsers');
const firebaseSchoolRoutes = require('./routes/firebaseSchools')
const firebaseDepartmentRoutes = require('./routes/firebaseDepartments')
const firebaseCourseRoutes = require('./routes/firebaseCourses')

app.use('/api/firebase/lectures', firebaseLectureRoutes);
app.use('/api/firebase/attendance', firebaseAttendanceRoutes);
app.use('/api/firebase/users', firebaseUserRoutes);
app.use('/api/firebase/schools', firebaseSchoolRoutes);
app.use('/api/firebase/departments', firebaseDepartmentRoutes);
app.use('/api/firebase/courses', firebaseCourseRoutes)

const PORT = process.env.PORT || 5000;

app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
