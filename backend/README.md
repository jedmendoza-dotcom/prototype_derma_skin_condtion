# DermaScreen backend (FastAPI)

Needs Python 3.10 or newer and the database set up (schema + security scripts).

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate            # Windows   (Mac/Linux: source .venv/bin/activate)
pip install -r requirements.txt
copy ..\.env.example .env         # then open .env and fill in the passwords and JWT_SECRET
python create_admin.py            # once: creates the first administrator
uvicorn main:app --reload --port 8000
```

Open http://localhost:8000/docs to test every endpoint (Swagger UI), and
http://localhost:8000/health to check the database connection.

| Endpoint | Purpose |
|---|---|
| `POST /auth/register` | create a patient account (validated, password hashed with argon2) |
| `POST /auth/login` | 5 failed attempts = 3-minute lock; `remember_me` = 7-day session |
| `POST /auth/refresh` | new access token from the refresh token |
| `GET /auth/me` | current user (needs `Authorization: Bearer <access_token>`) |
| `POST /auth/logout` | revokes the session |
| `GET /health` | API + database check |

Files: `main.py` (routes), `auth_queries.py` (login lookup), `auth_store.py` (other SQL),
`security.py` (argon2 + tokens), `schemas.py` (input validation), `db.py` (connection and
Row-Level-Security context), `create_admin.py`.
