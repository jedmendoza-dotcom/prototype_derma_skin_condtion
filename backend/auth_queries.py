"""SQL used by the login feature of DermaScreen."""
from db import db_for


def get_user_for_login(username: str):
    """Look up an account by the username typed on the Login page.

    `username` is untrusted user input. It is passed as a bound parameter
    (%s + a values tuple), so PostgreSQL treats it only as data and never as
    part of the SQL command.
    """
    with db_for(None, "auth") as conn:                   # login path: no user id yet
        return conn.execute(
            "SELECT user_id, password_hash, role, is_active, "
            "       failed_attempts, locked_until "
            "FROM skin_classification_schema.users "
            "WHERE lower(username) = lower(%s)",
            (username,),
        ).fetchone()
