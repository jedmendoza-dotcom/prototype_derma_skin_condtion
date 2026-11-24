"""Screening submission: the symptom form + a photo that is quality-checked.

POST /scans/check-photo   check one photo (used after every capture, nothing is saved)
POST /scans               save the form + photo (multipart/form-data)

Every field of the form is required. A missing or invalid field returns status 422 in
FastAPI's normal error format, so the app can mark exactly which fields to fix.
"""
import os
import re
import uuid
from pathlib import Path
from typing import Literal

import psycopg
from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile

import image_quality as iq
import results
import scan_rules
from db import db_for

S = "skin_classification_schema"

AgeGroup = Literal["0-1", "2-5", "6-12", "13-17", "18-30", "31-45", "46-60", "61+"]
Duration = Literal["lt_1d", "1_3d", "4_7d", "1_2w", "3_4w", "1_3m", "gt_3m"]

_PHONE = re.compile(r"^(09\d{9}|\+639\d{9})$")
_MAX_SCORE = 999999.99            # column is NUMERIC(8,2)


def _upload_dir() -> Path:
    return Path(os.environ.get("UPLOAD_DIR", "uploads")).resolve()


def _field_error(field: str, message: str) -> HTTPException:
    """Same shape FastAPI uses for its own validation errors."""
    return HTTPException(status_code=422, detail=[{"loc": ["body", field], "msg": message, "type": "value_error"}])


def _read_and_check(photo: UploadFile):
    data = photo.file.read(iq.MAX_BYTES + 1)           # never read more than the limit
    try:
        img = iq.load(data)
    except iq.BadImage as e:
        raise HTTPException(status_code=400, detail=str(e))
    return img, iq.analyze(img)


def make_router(current_user) -> APIRouter:
    router = APIRouter(prefix="/scans", tags=["scans"])

    @router.post("/check-photo")
    def check_photo(photo: UploadFile = File(...), user: dict = Depends(current_user)):
        _img, q = _read_and_check(photo)
        return {
            "ok": q.ok,
            "issue": q.issue,
            "message": None if q.ok else scan_rules.MESSAGES[q.issue],
            "retakes_before_fallback": scan_rules.RETAKES_BEFORE_FALLBACK,
        }

    @router.post("", status_code=201)
    def create_scan(
        request: Request,
        photo: UploadFile = File(...),
        age_group: AgeGroup = Form(...),
        duration_range: Duration = Form(...),
        itch_score: int = Form(..., ge=0, le=10),
        has_swelling: bool = Form(...),
        has_allergy: bool = Form(...),
        allergy_details: str | None = Form(None),
        description: str = Form(...),
        contact_number: str = Form(...),
        retake_count: int = Form(0, ge=0, le=5),
        user: dict = Depends(current_user),
    ):
        # ---- the form: everything is required ------------------------------------------
        description = description.strip()
        if not 10 <= len(description) <= 1000:
            raise _field_error("description", "Please describe what you feel (10 to 1000 characters).")

        contact = re.sub(r"[\s-]", "", contact_number)
        if not _PHONE.match(contact):
            raise _field_error("contact_number", "Use 09XXXXXXXXX or +639XXXXXXXXX")

        details = (allergy_details or "").strip()
        if has_allergy and not details:
            raise _field_error("allergy_details", "Please say what you are allergic to.")
        if len(details) > 200:
            raise _field_error("allergy_details", "Maximum 200 characters.")
        details = details if has_allergy else None

        # ---- the photo: required, quality-checked on the server (never trust the app) ------
        img, q = _read_and_check(photo)
        decision = scan_rules.decide(q.ok, retake_count)
        if decision == scan_rules.RETAKE:
            raise HTTPException(status_code=422, detail={
                "code": "retake_required",
                "issue": q.issue,
                "message": scan_rules.MESSAGES[q.issue],
            })
        good = decision == scan_rules.ACCEPT

        # ---- store: re-encoded JPEG without metadata, random file name -------------------------
        jpeg, sha = iq.to_clean_jpeg(img)
        rel_path = f"{user['user_id']}/{uuid.uuid4().hex}.jpg"
        target = _upload_dir() / rel_path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(jpeg)

        top, method = results.compute(
            {"age_group": age_group, "duration_range": duration_range, "itch_score": itch_score,
             "has_swelling": has_swelling, "has_allergy": has_allergy, "description": description},
            img if good else None)

        try:
            with db_for(user["user_id"], user["role"]) as conn:
                scan_id = conn.execute(
                    f"INSERT INTO {S}.scan_records "
                    "(user_id, image_path, image_sha256, age_group, duration_range, itch_score, "
                    " has_swelling, has_allergy, allergy_details, description, contact_number, "
                    " image_quality, quality_issue, quality_score, retake_count, result_basis, result_method) "
                    "VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s) "
                    "RETURNING scan_id",
                    (user["user_id"], rel_path, sha, age_group, duration_range, itch_score,
                     has_swelling, has_allergy, details, description, contact,
                     "good" if good else "poor", None if good else q.issue,
                     round(min(q.score, _MAX_SCORE), 2), retake_count,
                     "image_and_description" if good else "description_only", method),
                ).fetchone()[0]
                results.store(conn, scan_id, top)
                conn.execute(
                    f"INSERT INTO {S}.audit_logs (user_id, action, entity, entity_id, ip_address) "
                    "VALUES (%s, 'scan.submitted', 'scan', %s, %s::inet)",
                    (user["user_id"], scan_id, request.client.host if request.client else None),
                )
        except psycopg.errors.InsufficientPrivilege:
            target.unlink(missing_ok=True)
            raise HTTPException(status_code=403, detail="Only patient accounts can submit a screening.")
        except Exception:
            target.unlink(missing_ok=True)       # do not keep a photo that has no database row
            raise

        return {
            "scan_id": scan_id,
            "image_quality": "good" if good else "poor",
            "quality_issue": None if good else q.issue,
            "result_basis": "image_and_description" if good else "description_only",
            "message": ("Photo and description received." if good else
                        "The photo was not clear enough, so your description will be used on its own. "
                        "The result will be less certain."),
        }

    return router