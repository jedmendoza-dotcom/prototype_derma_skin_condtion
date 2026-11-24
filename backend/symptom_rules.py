"""Draft symptom rules: turn the form answers into a score per condition.

!! DRAFT FOR DOCTOR REVIEW !!  The weights below are general starting points written
by the developer. They must be checked and corrected by the doctor before real use.
No packages needed: this file is plain Python so it can be tested anywhere.
"""
CODES = ["acne", "eczema", "tinea", "scabies", "impetigo", "melasma"]

LONG = {"3_4w", "1_3m", "gt_3m"}
MID = {"1_2w", "3_4w", "1_3m", "gt_3m"}

# keywords in English, Filipino and Cebuano (starting list; the doctor / native speakers can extend it)
KEYWORDS = {
    "acne":     ["pimple", "acne", "blackhead", "whitehead", "oily", "tigyawat", "taghiyawat", "pigsa"],
    "eczema":   ["dry", "flaky", "patch", "eczema", "rash", "tuyo", "uga", "namumula", "pula"],
    "tinea":    ["ring", "round", "circle", "scaly", "buni", "bilog", "lingin", "hanap"],
    "scabies":  ["night", "gabi", "gabii", "between finger", "galis", "family", "kuti", "iti"],
    "impetigo": ["crust", "honey", "pus", "nana", "blister", "paltos", "sore", "sugat", "samad", "oozing"],
    "melasma":  ["brown", "dark", "patches", "kayumanggi", "itom", "sun", "araw", "pregnan", "buntis"],
}


def raw_scores(age_group: str, duration: str, itch: int, swelling: bool,
               allergy: bool, description: str) -> dict:
    d = (description or "").lower()
    s = {c: 1.0 for c in CODES}

    # acne
    if age_group in ("13-17", "18-30"): s["acne"] += 1.5
    elif age_group in ("31-45",): s["acne"] += 0.5
    if itch <= 3: s["acne"] += 0.7
    if duration in MID: s["acne"] += 0.5
    # eczema
    if itch >= 6: s["eczema"] += 1.5
    if allergy: s["eczema"] += 1.0
    if duration in LONG: s["eczema"] += 0.7
    if age_group in ("0-1", "2-5", "6-12"): s["eczema"] += 0.5
    # tinea
    if 3 <= itch <= 7: s["tinea"] += 1.0
    if duration in MID: s["tinea"] += 0.7
    # scabies
    if itch >= 7: s["scabies"] += 2.0
    if duration in ("1_2w", "3_4w", "1_3m"): s["scabies"] += 0.8
    # impetigo
    if age_group in ("2-5", "6-12"): s["impetigo"] += 2.0
    elif age_group == "0-1": s["impetigo"] += 1.0
    if duration in ("lt_1d", "1_3d", "4_7d", "1_2w"): s["impetigo"] += 0.7
    if swelling: s["impetigo"] += 0.5
    # melasma
    if age_group in ("18-30", "31-45", "46-60"): s["melasma"] += 1.0
    if itch == 0: s["melasma"] += 1.5
    if not swelling: s["melasma"] += 0.3
    if duration in LONG: s["melasma"] += 1.0
    if itch >= 5: s["melasma"] -= 0.8

    for c, words in KEYWORDS.items():
        hits = sum(1 for w in words if w in d)
        s[c] += 1.2 * min(hits, 3)
    return {c: max(v, 0.1) for c, v in s.items()}


def rule_probs(*args, **kw) -> dict:
    raw = raw_scores(*args, **kw)
    total = sum(raw.values())
    return {c: v / total for c, v in raw.items()}


# Without a photo model the rules alone are weak evidence, so the shown confidence is capped.
RULES_ONLY_CAP = 0.55


def combine(rules: dict, model: dict | None, other_prob: float = 0.0) -> dict:
    """Return {code: confidence}. With a model: 70% photo, 30% symptoms."""
    if model is None:
        return {c: min(p, RULES_ONLY_CAP) for c, p in rules.items()}
    # The trained model may know more conditions than the rules do (e.g. psoriasis): those get a
    # neutral rule score. Probability the model gives to 'other' simply lowers every confidence.
    neutral = 1.0 / max(len(rules), 1)
    keys = set(rules) | set(model)
    return {c: 0.7 * model.get(c, 0.0) + 0.3 * rules.get(c, neutral) for c in keys}