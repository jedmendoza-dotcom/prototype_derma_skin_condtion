"""Password hashing and tokens.

* Passwords: argon2id (never stored or logged in plain text).
* Access token: short-lived JWT (default 15 minutes).
* Refresh token: random string; only its SHA-256 hash is stored in the database
  (auth_sessions.token_hash), so a database leak does not leak usable tokens.
"""
import hashlib
import os
import secrets
from datetime import datetime, timedelta, timezone

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError

_ph = PasswordHasher()  # argon2id with safe defaults
# Used to spend the same time when a username does not exist, so response
# time does not reveal which usernames are registered.
_DUMMY_HASH = _ph.hash("dummy-password-for-timing-only")


def hash_password(password: str) -> str:
    return _ph.hash(password)


def verify_password(stored_hash: str, password: str) -> bool:
    try:
        return _ph.verify(stored_hash, password)
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False


def burn_time(password: str) -> None:
    verify_password(_DUMMY_HASH, password)


def _secret() -> str:
    s = os.environ.get("JWT_SECRET", "")
    if len(s) < 32:
        raise RuntimeError("JWT_SECRET must be set in the environment and be at least 32 characters long")
    return s


def access_minutes() -> int:
    return int(os.environ.get("ACCESS_TOKEN_MINUTES", "15"))


def make_access_token(user_id: int, role: str, session_id: int) -> str:
    now = datetime.now(timezone.utc)
    return jwt.encode(
        {
            "sub": str(user_id),
            "role": role,
            "sid": session_id,
            "type": "access",
            "iat": now,
            "exp": now + timedelta(minutes=access_minutes()),
        },
        _secret(),
        algorithm="HS256",
    )


def decode_access_token(token: str) -> dict:
    """Raises jwt.PyJWTError if the token is invalid, expired or the wrong kind."""
    payload = jwt.decode(token, _secret(), algorithms=["HS256"], options={"require": ["exp", "sub", "sid"]})
    if payload.get("type") != "access":
        raise jwt.InvalidTokenError("wrong token type")
    return payload


def new_refresh_token() -> str:
    return secrets.token_urlsafe(48)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()
