"""Results: build the screening result for a saved scan and serve it to the app.

GET /scans/{scan_id}/result   the result page data (the owner patient only, RLS enforced)
Everything here is a SCREENING aid, never a diagnosis.
"""
import os

from fastapi import APIRouter, Depends, HTTPException

import predictor
import symptom_rules as rules
from db import db_for

S = "skin_classification_schema"
MIN_CONF = float(os.environ.get("RESULT_MIN_CONF", "0.40"))
DISCLAIMER = ("This is a screening result, not a medical diagnosis. Only a doctor can tell you "
              "what skin condition you have.")
RED_FLAGS = ["fever or you feel very sick", "the rash spreads quickly", "pus, severe pain or warm, swollen skin",
             "swelling of the face, lips or eyes, or trouble breathing (go to the emergency room)",
             "it is on a baby under 1 year old"]


def compute(form: dict, image) -> tuple[list, str]:
    """-> (top3 [(code, confidence)], method). image may be None (poor photo)."""
    r = rules.rule_probs(form["age_group"], form["duration_range"], form["itch_score"],
                         form["has_swelling"], form["has_allergy"], form["description"])
    model = predictor.predict(image) if image is not None else None
    model = {k: v for k, v in model.items() if k != 'other'} if model else None
    conf = rules.combine(r, model)
    top = sorted(conf.items(), key=lambda kv: kv[1], reverse=True)[:3]
    return top, ("model_and_rules" if model else "rules_only")


def store(conn, scan_id: int, top: list):
    model_id = conn.execute(f"SELECT model_id FROM {S}.model_versions WHERE is_active LIMIT 1").fetchone()
    if not model_id:
        raise RuntimeError("No active row in model_versions")
    for rank, (code, c) in enumerate(top, start=1):
        conn.execute(
            f"INSERT INTO {S}.classification_results (scan_id, condition_id, model_id, confidence, rank) "
            f"SELECT %s, condition_id, %s, %s, %s FROM {S}.skin_conditions WHERE code = %s",
            (scan_id, model_id[0], round(c, 4), rank, code))


def _sign_matches(sign: str, description_lower: str) -> bool:
    """A typical sign counts as 'matched' when one of its main words appears in what the user wrote."""
    words = [w.strip(".,()'").lower() for w in sign.split()]
    return any(len(w) >= 5 and w in description_lower for w in words)


def make_router(current_user) -> APIRouter:
    router = APIRouter(prefix="/scans", tags=["results"])

    @router.get("")
    def my_records(user: dict = Depends(current_user)):
        """The signed-in person's own screenings, newest first."""
        with db_for(user["user_id"], user["role"]) as conn:
            rows = conn.execute(
                f"SELECT s.scan_id, s.scanned_at, s.age_group, s.duration_range, s.itch_score, "
                f"       s.description, s.result_basis, c.name, r.confidence "
                f"FROM {S}.scan_records s "
                f"LEFT JOIN {S}.classification_results r ON r.scan_id = s.scan_id AND r.rank = 1 "
                f"LEFT JOIN {S}.skin_conditions c ON c.condition_id = r.condition_id "
                f"WHERE s.user_id = %s ORDER BY s.scanned_at DESC LIMIT 100", (user["user_id"],)).fetchall()
        return [{"scan_id": a, "scanned_at": b.isoformat(), "age_group": c_, "duration_range": d,
                 "itch_score": e, "description": f[:140], "result_basis": g,
                 "top_condition": h, "top_confidence": float(i) if i is not None else None}
                for (a, b, c_, d, e, f, g, h, i) in rows]

    @router.get("/{scan_id}/result")
    def get_result(scan_id: int, user: dict = Depends(current_user)):
        with db_for(user["user_id"], user["role"]) as conn:
            scan = conn.execute(
                f"SELECT result_basis, result_method, itch_score, has_swelling, age_group, duration_range, "
                f"       has_allergy, allergy_details, description, scanned_at "
                f"FROM {S}.scan_records WHERE scan_id = %s", (scan_id,)).fetchone()
            if not scan:                                    # not yours or does not exist: same answer
                raise HTTPException(status_code=404, detail="Result not found.")
            basis, method, itch, swelling, age, dur, allergy, allergy_d, desc, when = scan
            dlow = (desc or "").lower()
            rows = conn.execute(
                f"SELECT r.rank, r.confidence, c.condition_id, c.code, c.name, c.category, c.description, "
                f"       c.common_signs, c.reference_url, c.reference_source "
                f"FROM {S}.classification_results r JOIN {S}.skin_conditions c USING (condition_id) "
                f"WHERE r.scan_id = %s ORDER BY r.rank", (scan_id,)).fetchall()
            if not rows:
                raise HTTPException(status_code=404, detail="No result yet for this screening.")

            want = "moderate" if (swelling or itch >= 8) else "mild"
            out = []
            for (rank, conf, cid, code, name, cat, desc, signs, url, src) in rows:
                g = conn.execute(
                    f"SELECT severity::text, urgency::text, title, advice, see_doctor_when "
                    f"FROM {S}.guidance_recommendations WHERE condition_id = %s "
                    f"ORDER BY (severity::text = %s) DESC, severity LIMIT 1", (cid, want)).fetchone()
                out.append({
                    "rank": rank, "code": code, "name": name, "category": cat,
                    "confidence": float(conf), "description": desc, "common_signs": signs or [],
                    "matched_signs": [s for s in (signs or []) if _sign_matches(s, dlow)],
                    "more_details_url": url, "more_details_source": src,
                    "guidance": None if not g else {
                        "severity": g[0], "urgency": g[1], "title": g[2], "advice": g[3], "see_doctor_when": g[4]},
                })

        top = out[0]["confidence"]
        return {
            "scan_id": scan_id,
            "inconclusive": top < MIN_CONF,
            "method": method,                       # rules_only = no photo model used
            "basis": basis,                         # description_only = photo was too poor
            "min_confidence": MIN_CONF,
            "your_answers": {
                "age_group": age, "duration_range": dur, "itch_score": itch, "has_swelling": swelling,
                "has_allergy": allergy, "allergy_details": allergy_d, "description": desc,
                "submitted_at": when.isoformat()},
            "conditions": out,
            "red_flags": RED_FLAGS,
            "disclaimer": DISCLAIMER,
            "notes": [n for n in [
                "Your photo was not clear, so this result uses your answers only." if basis == "description_only" else None,
                "This version compares your answers with common skin conditions. The photo model is still being trained."
                if method == "rules_only" else None] if n],
        }

    return router