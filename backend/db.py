"""Database access for the DermaScreen FastAPI backend.

Credentials are never written in this file. They are read from environment
variables (a local .env file that is excluded from Git, or the hosting
platform's secret settings on Render/Railway).
"""
import os
from contextlib import contextmanager
from pathlib import Path
from dotenv import load_dotenv

import psycopg

_env_file = Path(__file__).resolve().parent / ".env"
load_dotenv(_env_file)


def _dsn() -> str:
    # os.environ[...] raises KeyError if a variable is missing, so the app
    # fails loudly instead of silently falling back to a default password.
    return (
        f"host={os.environ['DB_HOST']} "
        f"port={os.environ.get('DB_PORT', '5432')} "
        f"dbname={os.environ['DB_NAME']} "
        f"user={os.environ['DB_USER']} "              # app_service, NOT a superuser
        f"password={os.environ['DB_PASSWORD']} "
        f"sslmode={os.environ.get('DB_SSLMODE', 'require')}"
    )


@contextmanager
def db_for(user_id: int | None, app_role: str):
    """Open a transaction that tells PostgreSQL who is calling.

    app_role: 'patient' | 'medical_reviewer' | 'administrator' | 'auth'
    The values last for this transaction only (set_config(..., true)), and the
    Row-Level Security policies read them. user_id must come from the verified
    JWT, never from the request body.
    """
    with psycopg.connect(_dsn()) as conn:
        with conn.transaction():
            conn.execute("SELECT set_config('app.current_user_id', %s, true)",
                         (str(user_id or ""),))
            conn.execute("SELECT set_config('app.current_role', %s, true)",
                         (app_role,))
            yield conn
