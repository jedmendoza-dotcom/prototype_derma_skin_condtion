"""Print the quality numbers of a photo, to tune the thresholds in image_quality.py.

    python check_photo.py my_sharp_photo.jpg my_blurry_photo.jpg
"""
import sys

import image_quality as iq


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit("Usage: python check_photo.py photo1.jpg [photo2.jpg ...]")
    print(f"limits: sharpness >= {iq.BLUR_MIN}, brightness {iq.DARK_MAX}-{iq.BRIGHT_MIN}, shorter side >= {iq.MIN_SIDE}px\n")
    for path in sys.argv[1:]:
        with open(path, "rb") as f:
            try:
                q = iq.analyze(iq.load(f.read()))
            except iq.BadImage as e:
                print(f"{path}: {e}")
                continue
        verdict = "OK" if q.ok else f"POOR ({q.issue})"
        print(f"{path}: {verdict}  sharpness={q.score:.1f}  brightness={q.brightness:.0f}  size={q.width}x{q.height}")


if __name__ == "__main__":
    main()