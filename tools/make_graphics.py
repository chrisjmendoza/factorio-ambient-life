"""Generates AmbientLife's sprite sheets.

Every sprite is drawn white-on-transparent so the mod can tint it at runtime,
and is supersampled 4x before downscaling so the tiny on-screen shapes keep
clean anti-aliased edges. Run from the mod root: python tools/make_graphics.py
"""

import math
import os
from PIL import Image, ImageDraw

SS = 4  # supersample factor
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "graphics")


def new_frame(size):
    return Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))


def finish(frames, size, path):
    """Downscale each frame and pack them into a horizontal strip."""
    sheet = Image.new("RGBA", (size * len(frames), size), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        sheet.paste(frame.resize((size, size), Image.LANCZOS), (i * size, 0))
    sheet.save(os.path.join(OUT, path))
    print(f"  {path}  {sheet.width}x{sheet.height}  ({len(frames)} frames)")


def bird(size=16, frames=4):
    """A distant bird reads as a shallow chevron; flapping just moves the tips."""
    tip_dy = [-11, -3, 8, -3]  # wing tip height per frame, in supersampled px
    out = []
    for f in range(frames):
        img = new_frame(size)
        d = ImageDraw.Draw(img)
        cx = cy = size * SS / 2
        span = size * SS * 0.42
        dy = tip_dy[f % len(tip_dy)] * (SS / 4)
        w = max(2, int(size * SS * 0.105))
        for direction in (-1, 1):
            # Elbow partway out gives the wing its curve.
            elbow = (cx + direction * span * 0.48, cy + dy * 0.30 - SS * 0.5)
            tip = (cx + direction * span, cy + dy)
            d.line([(cx, cy), elbow], fill=(255, 255, 255, 255), width=w, joint="curve")
            d.line([elbow, tip], fill=(255, 255, 255, 235), width=max(1, w - 1), joint="curve")
        out.append(img)
    finish(out, size, "bird.png")


def butterfly(size=12, frames=4):
    """Wings flap by squashing horizontally, which sells the motion side-on."""
    squash = [1.0, 0.66, 0.3, 0.66]
    out = []
    for f in range(frames):
        img = new_frame(size)
        d = ImageDraw.Draw(img)
        cx = cy = size * SS / 2
        s = squash[f % len(squash)]
        upper = size * SS * 0.30
        lower = size * SS * 0.22
        for direction in (-1, 1):
            for radius, oy, alpha in ((upper, -upper * 0.35, 255), (lower, lower * 0.55, 215)):
                w = radius * s
                box = [cx + direction * 1 - (w if direction < 0 else 0),
                       cy + oy - radius,
                       cx + direction * 1 + (w if direction > 0 else 0),
                       cy + oy + radius]
                d.ellipse([min(box[0], box[2]), box[1], max(box[0], box[2]), box[3]],
                          fill=(255, 255, 255, alpha))
        # Body keeps the two wing pairs visually joined.
        d.ellipse([cx - size * SS * 0.045, cy - size * SS * 0.30,
                   cx + size * SS * 0.045, cy + size * SS * 0.30],
                  fill=(255, 255, 255, 255))
        out.append(img)
    finish(out, size, "butterfly.png")


def thumbnail(size=144):
    """Mod portal thumbnail: fireflies over a dark treeline."""
    img = Image.new("RGBA", (size * 2, size * 2), (16, 26, 20, 255))
    d = ImageDraw.Draw(img)
    n = size * 2
    for y in range(n):  # dusk gradient
        t = y / n
        d.line([(0, y), (n, y)], fill=(int(18 + 14 * (1 - t)), int(30 + 22 * (1 - t)), int(28 + 20 * (1 - t))))
    rnd = __import__("random")
    rnd.seed(7)
    for i in range(26):  # treeline silhouette
        tx = i * (n / 25.0) + rnd.uniform(-8, 8)
        h = rnd.uniform(0.30, 0.52) * n
        w = rnd.uniform(0.055, 0.10) * n
        d.polygon([(tx - w, n), (tx, n - h), (tx + w, n)], fill=(10, 20, 14))
    for _ in range(30):  # fireflies
        fx, fy = rnd.uniform(0, n), rnd.uniform(n * 0.25, n * 0.95)
        r = rnd.uniform(1.5, 4.0)
        for k in range(6, 0, -1):  # cheap bloom
            d.ellipse([fx - r * k * 0.7, fy - r * k * 0.7, fx + r * k * 0.7, fy + r * k * 0.7],
                      fill=(int(150 + 12 * k), int(160 + 12 * k), 70, 255) if k == 1 else None,
                      outline=(120, 130, 55, 255) if k < 3 else None)
        d.ellipse([fx - r, fy - r, fx + r, fy + r], fill=(232, 240, 150, 255))
    root = os.path.dirname(OUT)
    img.resize((size, size), Image.LANCZOS).save(os.path.join(root, "thumbnail.png"))
    # Larger copy for the mod portal page; not shipped in the zip.
    img.resize((720, 720), Image.LANCZOS).save(os.path.join(root, "thumbnail_720.png"))
    print(f"  thumbnail.png  {size}x{size}")
    print("  thumbnail_720.png  720x720")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    print("Generating AmbientLife graphics:")
    bird()
    butterfly()
    thumbnail()
