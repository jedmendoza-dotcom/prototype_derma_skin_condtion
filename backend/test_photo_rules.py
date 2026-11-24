"""Tests for the photo rules. Run from this folder:  python -m unittest -v test_photo_rules

They build their own pictures, so no real photo is needed. Needs Pillow and numpy.
"""
import io
import unittest

import numpy as np
from PIL import Image, ImageFilter

import image_quality as iq
import scan_rules


def _jpeg(img: Image.Image) -> bytes:
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=92)
    return buf.getvalue()


def _textured(size=(900, 900), base=140, noise=28, seed=1) -> Image.Image:
    """A skin-toned picture with fine detail (what a sharp photo looks like)."""
    rng = np.random.default_rng(seed)
    arr = np.empty((size[1], size[0], 3), dtype=np.float64)
    arr[..., 0], arr[..., 1], arr[..., 2] = base + 40, base + 10, base
    arr += rng.normal(0, noise, arr.shape)
    return Image.fromarray(np.clip(arr, 0, 255).astype("uint8"), "RGB")


def _quality(img: Image.Image) -> iq.Quality:
    return iq.analyze(iq.load(_jpeg(img)))


class PhotoQuality(unittest.TestCase):
    def test_sharp_photo_is_ok(self):
        q = _quality(_textured())
        self.assertTrue(q.ok, q)

    def test_blurry_photo_is_poor(self):
        q = _quality(_textured().filter(ImageFilter.GaussianBlur(9)))
        self.assertEqual(q.issue, "blurry")

    def test_dark_photo_is_poor(self):
        q = _quality(_textured(base=5, noise=6))
        self.assertEqual(q.issue, "too_dark")

    def test_bright_photo_is_poor(self):
        q = _quality(_textured(base=250, noise=3))
        self.assertEqual(q.issue, "too_bright")

    def test_small_photo_is_poor(self):
        q = _quality(_textured(size=(200, 200)))
        self.assertEqual(q.issue, "too_small")

    def test_not_an_image_is_rejected(self):
        with self.assertRaises(iq.BadImage):
            iq.load(b"this is not a picture")
        with self.assertRaises(iq.BadImage):
            iq.load(b"")

    def test_oversized_upload_is_rejected(self):
        with self.assertRaises(iq.BadImage):
            iq.load(b"0" * (iq.MAX_BYTES + 1))

    def test_clean_jpeg_has_no_metadata(self):
        img = _textured()
        exif = Image.Exif()
        exif[0x010F] = "SomePhoneMaker"          # a metadata tag a phone would write
        buf = io.BytesIO()
        img.save(buf, format="JPEG", exif=exif)
        data, sha = iq.to_clean_jpeg(iq.load(buf.getvalue()))
        self.assertEqual(len(sha), 64)
        self.assertEqual(len(Image.open(io.BytesIO(data)).getexif()), 0)


class RetakeRule(unittest.TestCase):
    def test_good_photo_is_accepted(self):
        self.assertEqual(scan_rules.decide(True, 0), scan_rules.ACCEPT)

    def test_first_poor_photo_must_be_retaken(self):
        self.assertEqual(scan_rules.decide(False, 0), scan_rules.RETAKE)

    def test_second_poor_photo_uses_description_only(self):
        self.assertEqual(scan_rules.decide(False, scan_rules.RETAKES_BEFORE_FALLBACK),
                         scan_rules.DESCRIPTION_ONLY)

    def test_a_good_retake_is_accepted(self):
        self.assertEqual(scan_rules.decide(True, 1), scan_rules.ACCEPT)

    def test_every_problem_has_a_message(self):
        for issue in ("blurry", "too_dark", "too_bright", "too_small"):
            self.assertIn(issue, scan_rules.MESSAGES)


if __name__ == "__main__":
    unittest.main()