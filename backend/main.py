"""DermaScreen API (FastAPI).

Run from this folder:   uvicorn main:app --reload --port 8000
Swagger UI (try every endpoint in the browser):   http://localhost:8000/docs
"""
from dotenv import load_dotenv

load_dotenv()  # reads backend/.env (never committed to Git)

import os
from datetime import datetime, timezone

import jwt
import psycopg
from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

import auth_store as store
import security
from auth_queries import get_user_for_login
from db import db_for
from scans import make_router as make_scans_router
from results import make_router as make_results_router
from schemas import AccessOut, LoginIn, RefreshIn, RegisterIn, TokenOut, UserOut

app = FastAPI(title="DermaScreen API", version="0.1.0")

# --- CORS: lets the Flutter web app (a different port) call this API -----------
_origins = [o.strip() for o in os.environ.get("CORS_ORIGINS", "").split(",") if o.strip()]
_localhost_regex = (
    r"^http://(localhost|127\.0\.0\.1)(:\d+)?$"
    if os.environ.get("CORS_ALLOW_LOCALHOST", "true").lower() == "true" else None
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=_origins,
    allow_origin_regex=_localhost_regex,
    allow_credentials=False,
    allow_methods=["GET", "POST", "PATCH", "DELETE"],
    allow_headers=["Authorization", "Content-Type"],
)


@app.exception_handler(psycopg.OperationalError)
async def database_unavailable(request: Request, exc: psycopg.OperationalError):
    # Never send the real database error (host names, user names) to the client.
    return JSONResponse(status_code=503, content={"detail": "Database unavailable. Please try again."})


def _ip(request: Request) -> str | None:
    # Behind a reverse proxy (Render/Railway) configure uvicorn --proxy-headers instead.
    return request.client.host if request.client else None


# --- Health check ----------------------------------------------------------------
@app.get("/health", tags=["system"])
def health():
    with db_for(None, "auth") as conn:
        conn.execute("SELECT 1")
    return {"status": "ok", "database": "connected"}


# --- Register ----------------------------------------------------------------------
@app.post("/auth/register", status_code=201, tags=["auth"])
def register(body: RegisterIn, request: Request):
    ip = _ip(request)
    data = body.model_dump(exclude={"password", "consent"})
    data["password_hash"] = security.hash_password(body.password)
    try:
        with db_for(None, "auth") as conn:          # registration can only ever create a 'patient'
            user_id = store.create_user(conn, data)
            store.audit(conn, user_id, "user.registered", ip)
    except psycopg.errors.UniqueViolation:
        raise HTTPException(status_code=409, detail="That username is already taken.")
    return {"user_id": user_id, "message": "Account created. You can now sign in."}


# --- Login (5 failed attempts -> locked for 3 minutes; remember me = 7 days) -------------
def _locked(until: datetime):
    secs = max(1, int((until - datetime.now(timezone.utc)).total_seconds()) + 1)
    return HTTPException(status_code=423, detail={
        "message": "Too many failed attempts. Sign-in is locked.", "locked_seconds": secs})


@app.post("/auth/login", response_model=TokenOut, tags=["auth"])
def login(body: LoginIn, request: Request):
    ip = _ip(request)

    with db_for(None, "auth") as conn:
        if store.count_recent_failures_from_ip(conn, ip) >= store.IP_LIMIT:
            raise HTTPException(status_code=429, detail="Too many attempts. Please wait a few minutes.")

    row = get_user_for_login(body.username)          # parameterized lookup (auth_queries.py)

    if row is None or not row[3]:                    # unknown or deactivated account
        security.burn_time(body.password)            # same response time as a real account
        with db_for(None, "auth") as conn:
            store.record_attempt(conn, None, body.username, ip, False)
        raise HTTPException(status_code=401, detail={"message": "Incorrect username or password."})

    user_id, pw_hash, role, _active, fails, locked_until = row
    now = datetime.now(timezone.utc)

    if locked_until is not None and locked_until > now:
        raise _locked(locked_until)                  # still locked: do not even check the password
    if locked_until is not None or fails >= store.MAX_ATTEMPTS:
        with db_for(None, "auth") as conn:           # lock has expired: fresh start
            store.reset_counters(conn, user_id)

    if not security.verify_password(pw_hash, body.password):
        with db_for(None, "auth") as conn:
            failed, until = store.register_failure(conn, user_id)
            store.record_attempt(conn, user_id, body.username, ip, False)
        if until is not None and failed >= store.MAX_ATTEMPTS:
            raise _locked(until)
        raise HTTPException(status_code=401, detail={
            "message": "Incorrect username or password.",
            "attempts_left": store.MAX_ATTEMPTS - failed})

    refresh_token = security.new_refresh_token()
    with db_for(None, "auth") as conn:
        store.mark_login_success(conn, user_id)
        store.record_attempt(conn, user_id, body.username, ip, True)
        session_id, expires_at = store.create_session(
            conn, user_id, security.hash_token(refresh_token), body.remember_me,
            request.headers.get("user-agent"), ip)
        store.audit(conn, user_id, "user.login", ip)
        p = store.get_profile(conn, user_id)

    return TokenOut(
        access_token=security.make_access_token(user_id, role, session_id),
        refresh_token=refresh_token,
        expires_in=security.access_minutes() * 60,
        refresh_expires_at=expires_at.isoformat(),
        user=UserOut(user_id=p[0], username=p[1], first_name=p[2], last_name=p[3], role=p[4]),
    )


# --- Token refresh -------------------------------------------------------------------------
@app.post("/auth/refresh", response_model=AccessOut, tags=["auth"])
def refresh(body: RefreshIn):
    with db_for(None, "auth") as conn:
        row = store.find_session_by_refresh(conn, security.hash_token(body.refresh_token))
    if row is None:
        raise HTTPException(status_code=401, detail="Session expired. Please sign in again.")
    session_id, user_id, role = row
    return AccessOut(
        access_token=security.make_access_token(user_id, role, session_id),
        expires_in=security.access_minutes() * 60,
    )


# --- Who is calling? (used by every protected endpoint) --------------------------------------
_bearer = HTTPBearer(auto_error=False)


def current_user(creds: HTTPAuthorizationCredentials | None = Depends(_bearer)) -> dict:
    unauthorized = HTTPException(status_code=401, detail="Not signed in or session expired.",
                                 headers={"WWW-Authenticate": "Bearer"})
    if creds is None:
        raise unauthorized
    try:
        payload = security.decode_access_token(creds.credentials)
        user_id, role, session_id = int(payload["sub"]), str(payload["role"]), int(payload["sid"])
    except (jwt.PyJWTError, KeyError, ValueError):
        raise unauthorized
    with db_for(user_id, role) as conn:              # also proves the session was not logged out
        if not store.session_is_active(conn, session_id, user_id):
            raise unauthorized
    return {"user_id": user_id, "role": role, "session_id": session_id}


@app.get("/auth/me", response_model=UserOut, tags=["auth"])
def me(user: dict = Depends(current_user)):
    with db_for(user["user_id"], user["role"]) as conn:
        p = store.get_profile(conn, user["user_id"])
    if p is None:
        raise HTTPException(status_code=401, detail="Account is not active.")
    return UserOut(user_id=p[0], username=p[1], first_name=p[2], last_name=p[3], role=p[4])


@app.post("/auth/logout", tags=["auth"])
def logout(user: dict = Depends(current_user)):
    with db_for(user["user_id"], user["role"]) as conn:
        store.revoke_session(conn, user["session_id"], user["user_id"])
    return {"message": "Signed out."}


# --- Screening: symptom form + photo (scans.py) ---------------------------------------------
app.include_router(make_scans_router(current_user))
app.include_router(make_results_router(current_user))