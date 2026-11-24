# CARAGA STATE UNIVERSITY - CABADBARAN CAMPUS
## College of Engineering and Information Technology
### IT 110 – Web Systems and Technologies | Laboratory Activity No. 10

---

# LABORATORY ACTIVITY REPORT: FASTAPI BACKEND TESTING AND RESOLVING API ERRORS

**Course Title:** IT 110 – Web Systems and Technologies  
**Activity:** Laboratory Activity No. 10  
**Topic:** FastAPI Backend Health Check and REST API Testing  
**System Title:** **DermaScreen: AI-Powered Skin Condition Assessment & Classification System**  
**Group / Authors:** Jed Mendoza (Lead / Administrator: `Bajed17`) and Group Members  
**Backend Framework:** FastAPI 0.162.0 (ASGI) / Uvicorn 0.54.0 / Python 3.11  
**Database System:** PostgreSQL 18.6 (Schema: `skin_classification_schema`)  
**Frontend Client:** Flutter 3.47.7 (Web / Mobile)  

---

## 1. System Architecture & Startup Command

DermaScreen employs a secure **Three-Tier Architecture** that enforces clean separation of concerns and prevents client browsers from accessing database credentials:
1. **Presentation Layer (Flutter Web & Mobile):** Client interface handling user input forms, responsive UI components, and state management.
2. **Application / REST API Layer (FastAPI):** Business logic, Pydantic input validation, Argon2id password hashing, JWT bearer session management, and role-based authorization.
3. **Data Layer (PostgreSQL):** IT 108 relational database schema (`skin_classification_schema`) with Row-Level Security (RLS), foreign key constraints, and audit logging.

### Backend Launch Command
To start the FastAPI server with hot-reload enabled:
```powershell
# Navigate to backend directory
cd d:\Prototype_dermaskin_condition\prototype_derma_condition\backend

# Run FastAPI via Uvicorn
.\.venv\Scripts\uvicorn.exe main:app --reload --host 127.0.0.1 --port 8000
```
*Expected Terminal Output:*
```text
INFO:     Will watch for changes in: ['D:\\Prototype_dermaskin_condition\\prototype_derma_condition\\backend']
INFO:     Uvicorn running on http://127.0.0.1:8000 (Press CTRL+C to quit)
INFO:     Started reloader process using WatchFiles
INFO:     Started server process
INFO:     Waiting for application startup.
INFO:     Application startup complete.
```

---

## 2. Mandatory Setup & Baseline Evidence

### Screenshot Label: S01 — Health Check Endpoint Evidence
* **URL:** `http://127.0.0.1:8000/health`
* **HTTP Method:** `GET`
* **HTTP Status Code:** `200 OK`
* **Response Headers:** `Content-Type: application/json`
* **Response Body:**
  ```json
  {
    "status": "ok"
  }
  ```
* **Verification Detail:** The `/health` endpoint executes an active test transaction (`SELECT 1`) against the PostgreSQL database under the least-privilege `app_service` role. Returning `{"status": "ok"}` confirms that the FastAPI web server is alive and actively communicating with PostgreSQL on port 5432.

---

### Screenshot Label: S02 — Swagger UI Interactive Documentation
* **URL:** `http://127.0.0.1:8000/docs`
* **Interface:** OpenAPI 3.1 Swagger UI
* **Visible Operations:**
  * **system:**
    * `GET /health` — Baseline connectivity check
  * **conditions (IT 108 Data Catalog):**
    * `GET /conditions` — Retrieve all active skin conditions
    * `GET /conditions/{condition_id}` — Retrieve specific skin condition details
  * **auth (Authentication & Session Management):**
    * `POST /auth/register` — Register a new patient account
    * `POST /auth/login` — Sign in and obtain JWT access & refresh tokens
    * `POST /auth/refresh` — Issue a new short-lived access token
    * `GET /auth/me` — Read authenticated user profile (Bearer token required)
    * `POST /auth/logout` — Revoke active session

---

## 3. Part A — Feature-to-Endpoint Inventory

| Feature / User Action | Method & Path | Role / Test Data Needed | Expected Status | Proof ID |
| :--- | :--- | :--- | :---: | :---: |
| **System Health Check** | `GET /health` | Public / None | `200 OK` | **S01** |
| **Browse Skin Conditions** | `GET /conditions` | Public / Patient | `200 OK` | **F01** |
| **View Condition Details** | `GET /conditions/{condition_id}` | Public / ID: `1` (Acne) | `200 OK` | **F02** |
| **Patient Registration** | `POST /auth/register` | Public / Patient JSON payload | `201 Created` | **F03** |
| **User Sign-In** | `POST /auth/login` | Valid credentials (`username`, `password`) | `200 OK` | **F04** |
| **View Authenticated Profile** | `GET /auth/me` | Bearer JWT Token (`Authorization: Bearer <token>`) | `200 OK` | **F05** |
| **Refresh Access Token** | `POST /auth/refresh` | Valid `refresh_token` string | `200 OK` | **F06** |
| **Sign Out / Revoke Session** | `POST /auth/logout` | Bearer JWT Token (`Authorization: Bearer <token>`) | `200 OK` | **F07** |

---

## 4. Feature-by-Feature Successful Test Execution

### [F01] Browse Skin Conditions (`GET /conditions`)
* **Endpoint:** `GET http://127.0.0.1:8000/conditions`
* **Headers:** `Accept: application/json`
* **HTTP Status:** `200 OK`
* **Response Body (Sample of 6 records from IT 108 schema):**
  ```json
  [
    {
      "condition_id": 1,
      "code": "acne",
      "name": "Acne Vulgaris",
      "category": "Inflammatory",
      "description": "Clogged pores and inflammation causing pimples, blackheads and cysts on the face, chest and back.",
      "is_active": true
    },
    {
      "condition_id": 2,
      "code": "eczema",
      "name": "Atopic Dermatitis (Eczema)",
      "category": "Inflammatory",
      "description": "A long-term condition that leaves the skin dry, itchy and inflamed, often triggered by heat, sweat and dust.",
      "is_active": true
    },
    {
      "condition_id": 3,
      "code": "tinea",
      "name": "Tinea (Ringworm)",
      "category": "Fungal",
      "description": "Fungal infection common in warm, humid climates causing scaly, itchy, ring-shaped patches.",
      "is_active": true
    }
  ]
  ```
* **Database Verification:** Direct `SELECT COUNT(*) FROM skin_classification_schema.skin_conditions WHERE is_active = true` returns 6 rows.

---

### [F02] View Condition Details (`GET /conditions/{condition_id}`)
* **Endpoint:** `GET http://127.0.0.1:8000/conditions/1`
* **Path Parameter:** `condition_id = 1`
* **HTTP Status:** `200 OK`
* **Response Body:**
  ```json
  {
    "condition_id": 1,
    "code": "acne",
    "name": "Acne Vulgaris",
    "category": "Inflammatory",
    "description": "Clogged pores and inflammation causing pimples, blackheads and cysts on the face, chest and back.",
    "is_active": true
  }
  ```
* **Technical Note:** Parameterized lookup prevents SQL injection (`WHERE condition_id = %s`).

---

### [F03] Patient Registration (`POST /auth/register`)
* **Endpoint:** `POST http://127.0.0.1:8000/auth/register`
* **Request Headers:** `Content-Type: application/json`
* **Request Body:**
  ```json
  {
    "first_name": "Juan",
    "last_name": "Dela Cruz",
    "middle_name": "Santos",
    "contact_number": "09123456789",
    "age": 25,
    "username": "juan_patient",
    "password": "Password@123",
    "consent": true
  }
  ```
* **HTTP Status:** `201 Created`
* **Response Body:**
  ```json
  {
    "user_id": 9,
    "message": "Account created. You can now sign in."
  }
  ```
* **Database Verification:** 
  * A new row is inserted into `skin_classification_schema.users` with `role = 'patient'` and an Argon2id password hash.
  * An entry is logged into `skin_classification_schema.audit_logs` (`action: 'user.registered'`).

---

### [F04] User Sign-In (`POST /auth/login`)
* **Endpoint:** `POST http://127.0.0.1:8000/auth/login`
* **Request Headers:** `Content-Type: application/json`
* **Request Body:**
  ```json
  {
    "username": "juan_patient",
    "password": "Password@123",
    "remember_me": true
  }
  ```
* **HTTP Status:** `200 OK`
* **Response Body:**
  ```json
  {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refresh_token": "PI-MAGWeGT7c4iX9nR6KkQ-0YQ1Z8e0u4v2...",
    "token_type": "bearer",
    "expires_in": 900,
    "refresh_expires_at": "2026-11-03T13:25:03.589882+00:00",
    "user": {
      "user_id": 9,
      "username": "juan_patient",
      "first_name": "Juan",
      "last_name": "Dela Cruz",
      "role": "patient"
    }
  }
  ```
* **Database Verification:**
  * Validated against `skin_classification_schema.users`.
  * Success recorded in `skin_classification_schema.login_attempts` (`was_successful = true`).
  * New active session recorded in `skin_classification_schema.auth_sessions` (`token_hash` securely hashed).

---

### [F05] Authenticated User Profile (`GET /auth/me`)
* **Endpoint:** `GET http://127.0.0.1:8000/auth/me`
* **Request Headers:**
  * `Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...`
  * `Accept: application/json`
* **HTTP Status:** `200 OK`
* **Response Body:**
  ```json
  {
    "user_id": 9,
    "username": "juan_patient",
    "first_name": "Juan",
    "last_name": "Dela Cruz",
    "role": "patient"
  }
  ```
* **Verification Detail:** The backend extracts `sub` and `sid` from the JWT claims, confirms the session is active in PostgreSQL, and enforces Row-Level Security under the caller's role.

---

### [F06] Token Session Refresh (`POST /auth/refresh`)
* **Endpoint:** `POST http://127.0.0.1:8000/auth/refresh`
* **Request Body:**
  ```json
  {
    "refresh_token": "PI-MAGWeGT7c4iX9nR6KkQ-0YQ1Z8e0u4v2..."
  }
  ```
* **HTTP Status:** `200 OK`
* **Response Body:**
  ```json
  {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.NEW_TOKEN...",
    "token_type": "bearer",
    "expires_in": 900
  }
  ```

---

### [F07] Sign Out / Session Revocation (`POST /auth/logout`)
* **Endpoint:** `POST http://127.0.0.1:8000/auth/logout`
* **Headers:** `Authorization: Bearer <access_token>`
* **HTTP Status:** `200 OK`
* **Response Body:**
  ```json
  {
    "message": "Signed out."
  }
  ```
* **Database Verification:** The session row in `skin_classification_schema.auth_sessions` is revoked (`revoked_at = now()`). Subsequent attempts to use the same token produce `401 Unauthorized`.

---

## 5. Negative Test Matrix (Error Handling Verification)

| Scenario / Goal | Tested Endpoint | Input Data | Expected & Actual Status | Server Response | Verification Note |
| :--- | :--- | :--- | :---: | :--- | :--- |
| **Missing Resource** | `GET /conditions/999` | Non-existent `condition_id = 999` | `404 Not Found` | `{"detail": "Skin condition not found."}` | Graceful 404 without crashing or leaking SQL. |
| **Path Type Mismatch** | `GET /conditions/abc` | Path parameter `condition_id = "abc"` | `422 Unprocessable Entity` | `{"detail": [{"loc": ["path", "condition_id"], "msg": "Input should be a valid integer..."}]}` | FastAPI automatically halts processing before DB query. |
| **Validation Failure** | `POST /auth/register` | `first_name: "J"`, `age: 200`, `contact: "123"` | `422 Unprocessable Entity` | Pydantic validation error array specifying exact field constraints. | Database transaction is never initiated. |
| **Uniqueness Conflict** | `POST /auth/register` | Existing `username: "juan_patient"` | `409 Conflict` | `{"detail": "That username is already taken."}` | Caught via PostgreSQL Unique Violation on `users_username_uq`. |
| **Wrong Password** | `POST /auth/login` | `username: "juan_patient"`, `password: "WrongPass!1"` | `401 Unauthorized` | `{"detail": {"message": "Incorrect username or password.", "attempts_left": 4}}` | Logs failed attempt to PostgreSQL; decrements lockout counter. |
| **Missing Auth Bearer** | `GET /auth/me` | No `Authorization` header | `401 Unauthorized` | `{"detail": "Not signed in or session expired."}` | HTTPBearer dependency rejects unauthenticated request. |

---

## 6. Part B — Error Resolution Log

| Endpoint / Feature | Before: Code + Issue | Cause and Correction | After: Status | Evidence / Commit |
| :--- | :--- | :--- | :---: | :---: |
| **Server CLI Command Syntax** | `uvicorn main:app --port8000` threw: `Error: No such option '--port8000'. Did you mean '--port'?` | **Cause:** Typographical omission of whitespace between flag `--port` and port argument `8000`.<br>**Correction:** Corrected command to `--port 8000`. | `200 OK` (Uvicorn started on port 8000) | **E01-before / after** |
| **Root Route Discovery** | Visiting `http://127.0.0.1:8000/` returned `404 Not Found` (`{"detail": "Not Found"}`) | **Cause:** FastAPI had routes for `/health`, `/docs`, and `/conditions`, but lacked a root `/` GET route handler.<br>**Correction:** Implemented `@app.get("/")` returning API status and interactive links to `/docs` and `/health`. | `200 OK` (`{"message": "DermaScreen API is running"}`) | **E02-before / after** |
| **Frontend Registration Schema Mismatch** | Client registration failed with `422 Unprocessable Entity` | **Cause:** Pydantic schema `RegisterIn` requires `consent: bool` (RA 10173 consent), but `RegisterData.toJson()` in Flutter omitted the field.<br>**Correction:** Added `final bool consent;` to `RegisterData` and passed `'consent': consent` in `toJson()`. | `201 Created` (Registration succeeds) | **E03-before / after** |
| **Windows Desktop Host Connectivity** | Native Windows client threw: `SocketException: Connection refused` | **Cause:** `AuthService.baseUrl` used ternary `kIsWeb ? ... : 'http://10.0.2.2:8000'` which directed Windows desktop traffic to the Android emulator loopback IP.<br>**Correction:** Refactored `baseUrl` using `defaultTargetPlatform` to route Windows, macOS, and Linux desktop to `http://localhost:8000`. | `200 OK` (Connected to backend on Windows) | **E04-before / after** |
| **Standalone Scripts / Database Access** | Importing `auth_queries.py` or `db.py` directly caused `KeyError: 'DB_HOST'` | **Cause:** Only `main.py` had `load_dotenv()`. Standalone test scripts failed.<br>**Correction:** Added automated `load_dotenv()` within `db.py` to ensure environment variables are always loaded on import. | `200 OK` (Standalone tests execute cleanly) | **E05-before / after** |

---

## 7. Section 11 — Post-Laboratory Reflection

### 1. What was the first issue preventing your FastAPI application from passing /health, if any?
> The initial obstacle was twofold: first, transferring the backend folder into the root Flutter workspace invalidated the absolute directory paths hardcoded into the Python virtual environment's executable launchers (`.venv/Scripts/uvicorn.exe`), causing server startup to silently abort. Second, the `.env` configuration file initially contained placeholder text with invalid syntax from copy-pasting instructions. Once `pyvenv.cfg` was updated, `uvicorn` reinstalled, and the database credentials cleanly set, FastAPI launched and `/health` connected to PostgreSQL on port 5432, returning `{"status": "ok"}`.

### 2. Which endpoint was hardest to test, and which request, authentication, or database detail caused the difficulty?
> The `POST /auth/login` and subsequent `GET /auth/me` endpoints were the most complex. Testing them required a multi-step sequence:
> 1. Generating an Argon2id hashed password during registration.
> 2. Authenticating against the database while validating password timing-attack protections and account lockout rules (5 attempts within 3 minutes).
> 3. Generating a cryptographically signed JWT access token and companion refresh token.
> 4. Storing the hashed token in `auth_sessions`.
> 5. Passing the token as an `Authorization: Bearer <token>` header in Swagger UI to test `GET /auth/me` under Row-Level Security.

### 3. What did a failed response reveal about the distinction between invalid client input and a backend defect?
> A failed response caused by invalid client input produces a clean, predictable HTTP status code (such as `422 Unprocessable Entity` for invalid phone numbers or ages, `409 Conflict` for duplicate usernames, or `401 Unauthorized` for bad passwords) accompanied by a structured JSON error explaining the issue without crashing the server. In contrast, a backend defect results in an unhandled exception or an `HTTP 500 Internal Server Error`, indicating broken database connectivity, missing tables, or unhandled syntax in backend code. This distinction confirms that validation logic protects the system before any database transaction is initiated.

### 4. How did you prove that a corrected endpoint now returns the intended result, not just a status code?
> We validated the response payload at both the API level and the database level:
> 1. For `POST /auth/register`, we verified that the response returned `user_id: 9` and queried PostgreSQL (`SELECT * FROM skin_classification_schema.users WHERE user_id = 9;`) to verify that the first name, last name, contact number, and hashed password were properly stored.
> 2. For `GET /conditions`, we verified that the returned JSON matched the exact 6 active conditions seeded in IT 108 (`Acne Vulgaris`, `Eczema`, `Tinea`, etc.).
> 3. We verified that audit records were concurrently created in `skin_classification_schema.audit_logs`.

### 5. Which backend feature is ready for Flutter Web integration, and which issue (if any) still needs work?
> The **Authentication and Condition Catalog features** (`/auth/register`, `/auth/login`, `/auth/me`, `/auth/logout`, and `/conditions`) are completely tested and ready for Flutter Web integration. The CORS middleware in `main.py` is configured to allow `http://localhost:*` origins. The next phase for full semester-project integration is implementing the **Image Upload and ML Prediction endpoint** (`POST /scans/upload`), which will receive the patient's uploaded skin lesion photo, compute its SHA-256 hash, record the scan in `skin_classification_schema.scan_records`, and trigger model inference.

---

## 8. Git Repository Checkpoint & Evidence Summary

To record this verified state in your group's Git repository:
```powershell
cd d:\Prototype_dermaskin_condition\prototype_derma_condition
git add backend/ lib/ evidence/ .gitignore
git commit -m "feat(api): Lab 10 verified FastAPI endpoints, health check, and PostgreSQL integration"
git push origin main
```
* **Git Status:** All secrets (`.env`) and virtual environments (`.venv/`) remain safely ignored by `.gitignore`.
* **Instructor Verification Ready:** All endpoints can be demonstrated live in Swagger UI at `http://127.0.0.1:8000/docs`.
