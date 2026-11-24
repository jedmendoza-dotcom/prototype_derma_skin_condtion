"""All SQL for register / login / sessions.

Every statement uses bound parameters (%s + a values tuple). User input is never
joined into the SQL text. The Login lookup itself lives in auth_queries.py.
Each function runs inside db_for(...), so the Row-Level Security policies see
who is calling.
"""
S = "skin_classification_schema"

MAX_ATTEMPTS = 5
LOCK_MINUTES = 3
IP_LIMIT = 20  # failed logins per IP in 3 minutes before answering 429


def create_user(conn, d: dict) -> int:
    row = conn.execute(
        f"INSERT INTO {S}.users "
        "(first_name, last_name, middle_name, contact_number, age, username, password_hash) "
        "VALUES (%s, %s, %s, %s, %s, %s, %s) RETURNING user_id",
        (d["first_name"], d["last_name"], d["middle_name"], d["contact_number"],
         d["age"], d["username"], d["password_hash"]),
    ).fetchone()
    return row[0]


def count_recent_failures_from_ip(conn, ip: str | None) -> int:
    if not ip:
        return 0
    return conn.execute(
        f"SELECT count(*) FROM {S}.login_attempts "
        "WHERE ip_address = %s::inet AND NOT was_successful "
        "AND attempted_at > now() - interval '3 minutes'",
        (ip,),
    ).fetchone()[0]


def record_attempt(conn, user_id: int | None, username: str, ip: str | None, ok: bool) -> None:
    conn.execute(
        f"INSERT INTO {S}.login_attempts (user_id, username_tried, ip_address, was_successful) "
        "VALUES (%s, %s, %s::inet, %s)",
        (user_id, username[:40], ip, ok),
    )


def register_failure(conn, user_id: int):
    """Atomically count a failed login; lock the account when the limit is reached.
    Returns (failed_attempts, locked_until)."""
    return conn.execute(
        f"UPDATE {S}.users SET "
        f"  failed_attempts = LEAST(failed_attempts + 1, {MAX_ATTEMPTS}), "
        f"  locked_until = CASE WHEN failed_attempts + 1 >= {MAX_ATTEMPTS} "
        f"                      THEN now() + interval '{LOCK_MINUTES} minutes' ELSE locked_until END "
        "WHERE user_id = %s RETURNING failed_attempts, locked_until",
        (user_id,),
    ).fetchone()


def reset_counters(conn, user_id: int) -> None:
    conn.execute(
        f"UPDATE {S}.users SET failed_attempts = 0, locked_until = NULL WHERE user_id = %s",
        (user_id,),
    )


def mark_login_success(conn, user_id: int) -> None:
    conn.execute(
        f"UPDATE {S}.users SET failed_attempts = 0, locked_until = NULL, last_login_at = now() "
        "WHERE user_id = %s",
        (user_id,),
    )


def get_profile(conn, user_id: int):
    return conn.execute(
        f"SELECT user_id, username, first_name, last_name, role FROM {S}.users "
        "WHERE user_id = %s AND is_active",
        (user_id,),
    ).fetchone()


def create_session(conn, user_id: int, token_hash: str, remember: bool,
                   user_agent: str | None, ip: str | None):
    days = 7 if remember else 1
    return conn.execute(
        f"INSERT INTO {S}.auth_sessions (user_id, token_hash, remember_me, user_agent, ip_address, expires_at) "
        "VALUES (%s, %s, %s, %s, %s::inet, now() + make_interval(days => %s)) "
        "RETURNING session_id, expires_at",
        (user_id, token_hash, remember, (user_agent or "")[:300] or None, ip, days),
    ).fetchone()


def find_session_by_refresh(conn, token_hash: str):
    return conn.execute(
        f"SELECT s.session_id, s.user_id, u.role::text "
        f"FROM {S}.auth_sessions s JOIN {S}.users u ON u.user_id = s.user_id "
        "WHERE s.token_hash = %s AND s.revoked_at IS NULL AND s.expires_at > now() AND u.is_active",
        (token_hash,),
    ).fetchone()


def session_is_active(conn, session_id: int, user_id: int) -> bool:
    row = conn.execute(
        f"SELECT 1 FROM {S}.auth_sessions "
        "WHERE session_id = %s AND user_id = %s AND revoked_at IS NULL AND expires_at > now()",
        (session_id, user_id),
    ).fetchone()
    return row is not None


def revoke_session(conn, session_id: int, user_id: int) -> None:
    conn.execute(
        f"UPDATE {S}.auth_sessions SET revoked_at = now() "
        "WHERE session_id = %s AND user_id = %s AND revoked_at IS NULL",
        (session_id, user_id),
    )


def audit(conn, user_id: int | None, action: str, ip: str | None) -> None:
    conn.execute(
        f"INSERT INTO {S}.audit_logs (user_id, action, entity, entity_id, ip_address) "
        "VALUES (%s, %s, 'user', %s, %s::inet)",
        (user_id, action, user_id, ip),
    )
