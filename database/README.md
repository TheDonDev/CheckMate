# Local PostgreSQL Setup

PostgreSQL must be installed and running. Create a dedicated local database role and database from Ubuntu with:

```sh
sudo -u postgres psql -c "CREATE USER checkmate WITH PASSWORD 'change-this-local-password';"
sudo -u postgres psql -c "CREATE DATABASE checkmate OWNER checkmate;"
```

Copy `.env.example` to `.env`, set a private `PGPASSWORD` and a long random `JWT_SECRET`, then run:

```sh
npm ci
npm start
```

The API initializes the tables from `database/schema.sql` at startup. Check `http://localhost:5000/health` for the backend status. The Android emulator reaches the host API at `http://10.0.2.2:5000`.

For the first local administrator, register an account in the app, then promote that account in PostgreSQL:

```sh
psql -U checkmate -d checkmate -c "UPDATE users SET role = 'admin' WHERE email = 'your-admin-email@example.com';"
```

Sign out and back in after promotion. The admin screens can then create the school, department, course, venue, year, and semester records needed by registration and lecture creation.

The current backend migration includes local auth, lecture, and attendance endpoints. The Flutter app and catalog/admin screens still use Firebase directly, so they are not switched to PostgreSQL yet. Local auth also does not send email verification or password-reset emails, and registration assigns only student or lecturer roles. This is for local development and testing, not production deployment.