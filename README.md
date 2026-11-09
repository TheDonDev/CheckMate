# CheckMate

CheckMate is a mobile application for streamlined student class attendance management in universities. Built with **Flutter (Dart)** for the frontend and **Node.js + PostgreSQL** for the backend, CheckMate enables lecturers and students to manage attendance digitally.

## Architecture

| Layer | Technology |
|-------|------------|
| Frontend | Flutter (Dart) — Android APK |
| Backend | Node.js + Express |
| Database | PostgreSQL |
| Auth | JWT (local, no Firebase) |
| API base URL | `http://10.0.2.2:5000` (Android emulator) / `http://localhost:5000` (web/desktop) |

## Features

- **Local authentication** — register, login, JWT session persistence (7-day expiry)
- **Role-based access** — student, lecturer, admin
- **Admin catalog management** — schools, departments, courses, venues, years of study, semesters, users
- **Lecture management** — lecturers create, view, edit, delete lectures
- **Attendance** — students join lectures, check in via QR code or manual lecturer check-in
- **Attendance export** — CSV export of lecture attendance
- **Admin dashboards** — promote/demote users, manage all catalog records

## Prerequisites

- PostgreSQL 18+ installed and running
- Node.js 18+ and npm
- Flutter SDK 3.0+ (for building the APK)
- Android SDK with build tools (for APK builds)

## Backend Setup

### 1. Create the PostgreSQL role and database

```sh
# Using the system postgres cluster
sudo -u postgres psql -c "CREATE USER checkmate WITH PASSWORD 'change-this-local-password';"
sudo -u postgres psql -c "CREATE DATABASE checkmate OWNER checkmate;"

# Load the schema
psql -U checkmate -d checkmate -f database/schema.sql
```

If you cannot access the `postgres` superuser, initialize a local cluster as your own user:

```sh
export PATH=$PATH:/usr/lib/postgresql/18/bin
initdb -D /tmp/kilo/pgdata -U checkmate --auth=trust
pg_ctl -D /tmp/kilo/pgdata -l /tmp/kilo/pgdata.log -o "-p 5433 -c unix_socket_directories='/tmp/kilo'" start
psql -h /tmp/kilo -p 5433 -U checkmate -d postgres -c "CREATE USER checkmate WITH PASSWORD 'change-this-local-password';"
psql -h /tmp/kilo -p 5433 -U checkmate -d postgres -c "CREATE DATABASE checkmate OWNER checkmate;"
psql -h /tmp/kilo -p 5433 -U checkmate -d checkmate -f database/schema.sql
```

### 2. Configure environment

Copy `.env.example` to `.env` and set a private `PGPASSWORD` and a long random `JWT_SECRET`:

```sh
cp .env.example .env
```

Example `.env`:

```ini
PGHOST=127.0.0.1
PGPORT=5433
PGDATABASE=checkmate
PGUSER=checkmate
PGPASSWORD=change-this-local-password
JWT_SECRET=replace-with-a-long-random-secret
PORT=5000
```

> **Note:** `JWT_SECRET` must be a long, randomly generated string. `PGPASSWORD` must match the PostgreSQL role password. Never commit `.env` to version control.

### 3. Install and start the backend

```sh
npm ci
npm start
```

The API initializes tables from `database/schema.sql` at startup. Verify with:

```sh
curl http://localhost:5000/health
# Expected: {"status":"ok","database":"postgresql"}
```

The backend listens on `PORT` (default `5000`). The Android emulator reaches the host at `http://10.0.2.2:5000`.

## API Endpoints

### Auth (`/api/auth`)
| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| POST | `/register` | Register a new account | No |
| POST | `/login` | Log in and receive JWT | No |
| GET | `/me` | Get current user profile | Yes (JWT) |

### Catalog (`/api/catalog/:collection`)
Collections: `schools`, `departments`, `courses`, `venues`, `years_of_study`, `semesters`

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | `/:collection` | List items (optionally filtered by parent) | No |
| GET | `/:collection/:id` | Get a single item | No |
| POST | `/:collection` | Create item | Yes (admin) |
| PUT | `/:collection/:id` | Update item | Yes (admin) |
| DELETE | `/:collection/:id` | Delete item | Yes (admin) |

### Users (`/api/firebase/users`)
| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | `/` | List all users | Yes (admin) |
| PATCH | `/:userId/role` | Update user role | Yes (admin) |
| DELETE | `/:userId` | Delete user | Yes (admin) |

### Lectures (`/api/firebase/lectures`)
| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| POST | `/` | Create a lecture | Yes (verified lecturer) |
| GET | `/lecturer/:lecturerId` | Get lecturer's lectures | Yes (owner) |
| GET | `/student` | Get student's lectures (filtered) | Yes (student) |
| GET | `/student/dashboard/:studentId` | Get student dashboard lectures | Yes (owner) |
| GET | `/` | List all lectures | Yes (admin) |
| GET | `/:lectureId` | Get a lecture | Yes |
| PUT | `/:lectureId` | Update a lecture | Yes (owner or admin) |
| DELETE | `/:lectureId` | Delete a lecture | Yes (owner or admin) |

### Attendance (`/api/firebase/attendance`)
| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| POST | `/join/:lectureId` | Join a lecture | Yes (student) |
| POST | `/checkin/student/:lectureId` | Self check-in via QR | Yes (student) |
| POST | `/checkin` | Lecturer checks in a student | Yes (lecturer) |
| GET | `/lecture/:lectureId` | Get attendance roster | Yes (lecturer owner) |
| GET | `/student/:userId` | Get student's attendance summary | Yes (owner) |

## First Administrator Setup

1. Register an account in the app (or via the register endpoint).
2. Promote that account to admin in PostgreSQL:

```sh
psql -U checkmate -d checkmate -c "UPDATE users SET role = 'admin' WHERE email = 'your-admin-email@example.com';"
```

3. Sign out and back in. The admin screens can then create the school, department, course, venue, year, and semester records needed by registration and lecture creation.

## Database Schema

Defined in `database/schema.sql`. Core tables:

- **users** — id, name, email, password_hash, phone_number, role, is_verified, school, department, course, registration_number, year_of_study, semester, created_at
- **schools** — id, name
- **departments** — id, name, school_id
- **courses** — id, name, department_id
- **venues** — id, name
- **years_of_study** — id, name
- **semesters** — id, name
- **lectures** — id, lecturer_id, lecturer_name, school, department, course, year_of_study, semester, unit_name, unit_code, lecture_date, start_time, end_time, venue, online_link, reminder_sent, created_at
- **attendance** — id, user_id, student_name, registration_number, lecture_id, joined_at, checked_in, check_in_time, checked_in_by

## Frontend (Flutter)

### Screens
- **WelcomeScreen** — login / register entry
- **LoginScreen** — email/password login, resend verification, forgot password, contact support
- **RegisterScreen** — account creation with cascading school/department/course dropdowns
- **Wrapper** — routes to role-based dashboard based on auth state
- **StudentDashboard** — attendance summary, today's lectures, join lecture, QR scan check-in
- **LecturerDashboard** — create lecture, view own lectures, check-in students, edit/delete lectures
- **LectureAttendanceScreen** — QR code display, attendance roster, CSV export
- **AdminDashboard** — manage schools, departments, courses, venues, users, years, semesters
- **Manage* Screens** — CRUD for each catalog entity and user management

### Services
- **AuthService** — register, login, logout, session restore, token storage
- **AdminService** — catalog CRUD, user management, document name lookup
- **ApiService** — lectures and attendance API calls

### Limitations (local development)
- No email verification or password-reset emails (endpoints throw "not configured for local development")
- Registration assigns only `student` or `lecturer` roles; admin must be promoted manually in PostgreSQL
- No file storage (StorageService is a stub)
- Not intended for production deployment without further security hardening

## Building the APK

### 1. Install Flutter and Android SDK

```sh
# Clone Flutter
git clone https://github.com/flutter/flutter.git -b stable --depth 1 ~/flutter
export PATH="$HOME/flutter/bin:$PATH"

# Install Android SDK command-line tools, then:
flutter doctor --android-licenses
```

### 2. Configure Android SDK

Set `ANDROID_HOME` or use `flutter config --android-sdk <path>`.

### 3. Build the release APK

```sh
export PATH="$HOME/flutter/bin:$PATH"
cd /home/thadon/Projects/CheckMate
flutter build apk --release
```

The output APK is at `build/app/outputs/flutter-apk/app-release.apk`.

> The current `android/app/build.gradle.kts` signs with the debug keystore. For production client delivery, configure a release signing config with your own keystore.

## Running on Android Emulator

1. Start the backend (`npm start`) and confirm `http://localhost:5000/health` returns OK.
2. Ensure the emulator can reach the host at `10.0.2.2:5000`.
3. Run the app:

```sh
flutter run
```

## Development vs Production

| Item | Development | Production |
|------|-------------|------------|
| Database | Local PostgreSQL | Managed PostgreSQL (RDS/DO DB/etc.) |
| Backend host | `localhost:5000` | Domain behind nginx + HTTPS |
| JWT secret | Random string in `.env` | Strong secret, env var or secret manager |
| CORS | Localhost + emulator origins | Production domain only |
| Signing | Debug keystore | Release keystore |
| Email verification | Not configured | Required (SMTP or auth provider) |
| Password reset | Not configured | Required |

## Project Structure

```
CheckMate/
├── android/                # Android project files
├── database/
│   ├── README.md           # PostgreSQL setup instructions
│   └── schema.sql          # Database schema
├── lib/
│   ├── models/             # Dart data models (app_user, lecture, attendance, catalog)
│   ├── screens/            # Flutter UI screens
│   ├── screens/admin/      # Admin management screens
│   ├── services/           # AuthService, AdminService, ApiService, StorageService, RemoteConfigService
│   ├── widgets/            # Reusable Flutter widgets
│   ├── main.dart           # App entry point
│   ├── wrapper.dart        # Auth-based routing
│   └── firebase_options.dart # Firebase placeholder (no longer used)
├── middleware/
│   ├── localCheckAuth.js   # JWT verification middleware
│   └── checkAuth.js
├── routes/
│   ├── localAuth.js        # Auth routes (register/login/me)
│   ├── localCatalog.js     # Catalog CRUD routes
│   ├── localUsers.js       # User management routes
│   ├── localLectures.js    # Lecture routes
│   └── localAttendance.js  # Attendance routes
├── server.js               # Express app entry point
├── db.js                   # PostgreSQL pool + schema initialization
├── .env.example            # Environment variable template
├── .env                    # Local environment (gitignored)
├── package.json            # Node.js dependencies
├── pubspec.yaml            # Flutter dependencies
└── README.md
```

## License

This project is open source. See the repository for licensing details.

## Support

For issues or feature requests, open an issue in the project repository.