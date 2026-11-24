# DermaScreen database security

Based on ADMS Lesson 7, *PostgreSQL Security for Integrated Web Systems*.
Security question for every decision: **who can connect, what can they do, and which rows can they see?**

Files: `dermascreen_schema.sql` (tables), `dermascreen_security.sql` (roles, GRANT/REVOKE, RLS),
`dermascreen_security_test.sql` (proves allowed and blocked actions), `.env.example`.

## 1. Setup order

```bash
createdb dermascreen
psql -d dermascreen -f dermascreen_schema.sql
psql -d dermascreen \
     -v app_pw='...' -v report_pw='...' -v admin_pw='...' \
     -f dermascreen_security.sql
psql -d dermascreen -f dermascreen_security_test.sql     # use a fresh test DB; expect all PASS
```

Needs PostgreSQL 15+ and a superuser to run the security script. Use three different strong
passwords, and different ones for development, testing and production (slide 16).

First administrator account (created as `db_admin`, because registration can only create patients):

```bash
psql -U db_admin -d dermascreen -c "INSERT INTO users
 (first_name,last_name,contact_number,age,username,password_hash,role)
 VALUES ('First','Admin','09XXXXXXXXX',30,'admin_01','<bcrypt hash from your API>','administrator');"
```

## 2. Role list (slides 5, 6, 10, 11)

| Database role | Type | Used by | Main privileges |
|---|---|---|---|
| `app_service` | login, member of `app_rw_group` | FastAPI backend (the only app connection) | SELECT / INSERT / limited UPDATE on project tables. No DELETE (one exception), no DDL |
| `report_reader` | login, member of `report_ro_group` | reports page | SELECT only, on de-identified stats and condition info |
| `db_admin` | login, owns schema and tables | developer / migrations | setup, maintenance |
| `app_rw_group`, `report_ro_group` | group (NOLOGIN) | | hold the privileges; members inherit them |

None is a superuser, can create roles or databases, or bypasses RLS. The backend owns no tables,
so it can never DROP or ALTER them, and RLS always applies to it.

**Database roles vs application roles (slide 7).** The app has three roles: Patient, Administrator,
Medical Reviewer (plus an internal `auth` path for login/register). They control screens and
features. PostgreSQL controls data. The flow is:

```
Browser user -> Flutter app -> FastAPI checks the app role -> app_service connects
             -> PostgreSQL checks table privileges, then RLS policies
```

## 3. Access-control matrix (slide 21)

`own` = only rows belonging to the signed-in user. `-` = no access. All of it is enforced by GRANT + RLS.

| Table | Patient | Medical Reviewer | Administrator | Login/register code (`auth`) | report_reader |
|---|---|---|---|---|---|
| `users` | read/update **own** (not role or lock fields) | own row only | read all, create staff, change role | look up by username, create **patient** only, update login counters | - |
| `auth_sessions` | own | - | all | all (refresh/remember-me) | - |
| `login_attempts` | - | - | read | read/insert | - |
| `skin_conditions`, `guidance_recommendations` | read | read | read/insert/update | - | read |
| `model_versions` | read | read | read/insert/update | - | - |
| `scan_records` | create + read + update **own** | read all, update status | read all | - | - |
| `reported_symptoms` | create/read **own scans'** | read | all | - | - |
| `classification_results` | read **own**, insert for own scans | read | read | - | - |
| `medical_reviews` | read reviews of **own** scans | create/update **own** reviews | read all | - | - |
| `audit_logs` | append only | append only | append + read | append | - |
| `v_scan_summary` (view) | own rows | all, patient name hidden | all | - | - |
| `v_condition_stats` (view) | - | - | - | - | read (counts only) |

Nobody, including the administrator through the app, can DELETE users, scans or logs; deactivate with `is_active`.
The one exception is `auth_sessions`, where only expired or revoked sessions can be deleted.

## 4. How this supports least privilege

- **Separate accounts for separate duties** (slides 6, 11): backend, reports and admin each have their own login.
  If `report_reader` leaks, the damage is limited to anonymous totals. If `app_service` leaks, the attacker still
  cannot drop tables, delete data, edit the audit log or change a prediction result.
- **Start from nothing, then grant** (slide 8): the script revokes everything first, then grants table by table,
  with column-level UPDATE (for example `username` and `created_at` can never change).
- **Schema locked down** (slide 9): `USAGE` only, no `CREATE` for anyone but the owner, nothing for `PUBLIC`.
- **Row-Level Security** (slides 12-14): the same `SELECT * FROM scan_records` returns different rows per user.
  A trigger blocks patients from changing their own `role`, `is_active` or login counters, which RLS alone cannot do.
- **Fails closed**: if the backend forgets to say who is calling, every query returns zero rows.
- **Tested** (slide 24, mistake 6): 57 checks of allowed and blocked actions in `dermascreen_security_test.sql`.

## 5. Backend rules (slides 15, 18-20)

Tell PostgreSQL who is calling, once per transaction, then run **parameterized** queries:

```python
# db.py  (psycopg 3). Never hard-code credentials: read them from the environment.
import os, psycopg
from contextlib import contextmanager

DSN = (f"host={os.environ['DB_HOST']} port={os.environ.get('DB_PORT', '5432')} "
       f"dbname={os.environ['DB_NAME']} user={os.environ['DB_USER']} "
       f"password={os.environ['DB_PASSWORD']} sslmode={os.environ.get('DB_SSLMODE', 'require')}")

@contextmanager
def db_for(user_id: int | None, app_role: str):
    """app_role: patient | medical_reviewer | administrator | auth"""
    with psycopg.connect(DSN) as conn:               # use a pool in production
        with conn.transaction():
            conn.execute("SELECT set_config('app.current_user_id', %s, true)", (str(user_id or ""),))
            conn.execute("SELECT set_config('app.current_role', %s, true)", (app_role,))
            yield conn

# SAFE: the value is sent separately from the SQL text
with db_for(None, "auth") as conn:
    row = conn.execute("SELECT user_id, password_hash, failed_attempts, locked_until "
                       "FROM users WHERE lower(username) = lower(%s)", (username,)).fetchone()

# UNSAFE, never do this:
# conn.execute("SELECT * FROM users WHERE username = '" + username + "'")
```

The `true` in `set_config(..., true)` makes the setting last for one transaction only, so a pooled
connection can never carry one user's identity into the next request. Take the user id from the
verified JWT, never from the request body.

## 6. Do and don't (slides 3, 16-20, 23-24)

| Do | Don't |
|---|---|
| Connect the backend as `app_service`, a separate login for each duty | Use `postgres` / a superuser for the app, or one all-powerful account |
| Grant only what is needed; start with no access | Grant INSERT/UPDATE/DELETE to everyone "to make it work" |
| Use RLS so patients only see their own rows | Give table access without thinking about who owns each row |
| Keep passwords and connection strings in environment variables or a secrets manager | Hard-code `DB_PASSWORD = "12345"`, commit `.env`, or post it in GitHub, screenshots, reports or class submissions |
| Use different credentials for development, testing and production | Reuse one password everywhere, or keep default/weak ones |
| Use parameterized queries (`%s` + a values tuple) | Build SQL by joining user input into the string |
| Keep tables owned by `db_admin`, so the backend cannot DROP or ALTER | Let general users create or alter objects in the schema |
| Allow only the backend host in `pg_hba.conf`; use SSL/TLS (`sslmode=require`) | Expose port 5432 to the public internet |
| Store only bcrypt/argon2 hashes in `password_hash` | Store plain-text passwords |
| Test the blocked actions too, and document who can access what and why | Assume it is secure because it works |

Test question from slide 23: *if one account is compromised, can it only do a small amount of damage,
or can it access everything?* Here, no single database account can do everything.

## 7. Limits you should know about

- RLS protects against bugs and mistakes in the backend (a forgotten `WHERE`, a wrong endpoint). A fully
  compromised backend could still set `app.current_role = 'administrator'` itself, so the backend and its
  JWT verification must stay trustworthy, and the database must not be reachable from outside.
- The 5-failed-attempts / 3-minute lockout and the captcha still have to be enforced in the FastAPI code;
  the database only stores the counters and refuses to let patients reset them.
- Per slide 25, this is a teaching-grade setup: add backups, SSL certificates and log monitoring for production.
