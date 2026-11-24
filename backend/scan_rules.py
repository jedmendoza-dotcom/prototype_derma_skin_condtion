"""What happens to a screening photo. No web code in this file, so it is easy to test.

The rule you asked for:
  1. The photo is checked. If it is good, it is used together with the description.
  2. If it is blurry / too dark / too bright / too small, the user must retake it.
  3. If the retaken photo is still poor, the result is based on the description only.
     (A photo is still required and still stored.)
"""

RETAKES_BEFORE_FALLBACK = 1   # how many retakes we ask for before using the description only

ACCEPT = "accept"
RETAKE = "retake"
DESCRIPTION_ONLY = "description_only"

# Plain-language advice shown to the user, one line per problem.
MESSAGES = {
    "blurry": "The photo looks blurry. Hold the phone steady, tap the skin area to focus, and try again.",
    "too_dark": "The photo is too dark. Move to a brighter place (daylight is best) and try again.",
    "too_bright": "The photo is too bright or washed out. Avoid direct sunlight or flash and try again.",
    "too_small": "The photo is too small. Move a little closer and use your phone's normal camera.",
}


def decide(quality_ok: bool, retake_count: int) -> str:
    """ACCEPT, RETAKE or DESCRIPTION_ONLY for the photo that was just checked."""
    if quality_ok:
        return ACCEPT
    if retake_count < RETAKES_BEFORE_FALLBACK:
        return RETAKE
    return DESCRIPTION_ONLY