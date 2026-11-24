"""Photo checks for the screening upload: is it a real image, is it sharp, is it
well lit, is it big enough? Also re-saves the photo as a clean JPEG, which removes
hidden metadata such as the GPS location a phone writes into a picture.

Needs: Pillow, numpy.

The thresholds are starting values. Skin photos are smooth, so tune them with a few
of your own sharp and blurry phone photos:  python check_photo.py photo.jpg
"""
import hashlib
import io
import os
from dataclasses import dataclass

import numpy as np
from PIL import Image, ImageOps, UnidentifiedImageError

Image.MAX_IMAGE_PIXELS = 40_000_000          # refuse "decompression bomb" images

MAX_BYTES = 8 * 1024 * 1024                  # 8 MB upload limit
MIN_SIDE = 300                               # pixels, shorter side
MAX_SIDE = 2048                              # stored photos are shrunk to this
ALLOWED_FORMATS = {"JPEG", "PNG", "WEBP"}

BLUR_MIN = float(os.environ.get("BLUR_MIN", "30"))       # sharpness below this = blurry
DARK_MAX = float(os.environ.get("DARK_MAX", "45"))       # average brightness (0-255) below = too dark
BRIGHT_MIN = float(os.environ.get("BRIGHT_MIN", "225"))  # above = too bright


class BadImage(ValueError):
    """The upload is not a usable image."""


@dataclass
class Quality:
    ok: bool
    issue: str | None       # blurry | too_dark | too_bright | too_small | None
    score: float            # sharpness (variance of the Laplacian)
    brightness: float       # 0-255
    width: int
    height: int


def load(data: bytes) -> Image.Image:
    """Open the bytes as an image, or raise BadImage. The file type is decided by
    Pillow from the content, never from the file name or the Content-Type header."""
    if not data:
        raise BadImage("No photo received.")
    if len(data) > MAX_BYTES:
        raise BadImage("Photo is too large (maximum 8 MB).")
    try:
        probe = Image.open(io.BytesIO(data))
        if probe.format not in ALLOWED_FORMATS:
            raise BadImage("Please use a JPEG, PNG or WebP photo.")
        probe.verify()                                   # detects truncated/corrupt files
        img = Image.open(io.BytesIO(data))               # verify() invalidates the first handle
        img = ImageOps.exif_transpose(img)               # respect phone rotation
        img.load()
        return img.convert("RGB")
    except BadImage:
        raise
    except (UnidentifiedImageError, Image.DecompressionBombError, OSError, SyntaxError, ValueError):
        raise BadImage("That file is not a valid photo.")


def analyze(img: Image.Image) -> Quality:
    w, h = img.size
    gray_img = img.convert("L")
    gray_img.thumbnail((800, 800), Image.LANCZOS)        # same scale for every phone
    g = np.asarray(gray_img, dtype=np.float64)

    brightness = float(g.mean())
    if g.shape[0] < 3 or g.shape[1] < 3:
        score = 0.0
    else:
        lap = (-4.0 * g[1:-1, 1:-1] + g[:-2, 1:-1] + g[2:, 1:-1] + g[1:-1, :-2] + g[1:-1, 2:])
        score = float(lap.var())

    issue = None
    if min(w, h) < MIN_SIDE:
        issue = "too_small"
    elif brightness < DARK_MAX:
        issue = "too_dark"
    elif brightness > BRIGHT_MIN:
        issue = "too_bright"
    elif score < BLUR_MIN:
        issue = "blurry"
    return Quality(ok=issue is None, issue=issue, score=score, brightness=brightness, width=w, height=h)


def to_clean_jpeg(img: Image.Image) -> tuple[bytes, str]:
    """Return (jpeg bytes without metadata, sha256 hex)."""
    out = img.copy()
    out.thumbnail((MAX_SIDE, MAX_SIDE), Image.LANCZOS)
    buf = io.BytesIO()
    out.save(buf, format="JPEG", quality=90, optimize=True)   # no exif= argument: metadata is dropped
    data = buf.getvalue()
    return data, hashlib.sha256(data).hexdigest()