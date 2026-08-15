#!/usr/bin/env python3
"""Slice the app icon artwork into every size the two platforms want.

    python3 tool/make_icons.py

The master is tool/app_icon_source.png — the supplied Qamar artwork. Everything
below is derived from it, so re-running this after replacing that one file
regenerates the whole set.

Two things need care:

* iOS icons must have no alpha channel — the App Store rejects them — so they
  are flattened onto the artwork's own background colour.
* Android's adaptive icon wants the subject on a transparent layer over a flat
  background. The artwork is a glow on near-black, which is exactly a
  premultiplied-over-black image, so the alpha can be recovered from its own
  brightness rather than cut out by hand.
"""

import json
import pathlib

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "tool" / "app_icon_source.png"

ANDROID_RES = ROOT / "android" / "app" / "src" / "main" / "res"
IOS_ICONSET = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"

# How much of the icon's width the artwork should span.
#
# The square icon can run close to the edge: launchers mask it to a circle or
# a squircle, and the corners it removes are empty sky. The adaptive
# foreground cannot — Android only guarantees the middle 66dp of the 108dp
# layer survives every launcher's mask, so the artwork is kept inside that
# 0.611 circle. Any larger and the outer rings clip on some devices.
SQUARE_FILL = 0.88
FOREGROUND_FILL = 0.58

# Anything at or below this brightness is sky, not artwork.
SKY_LEVEL = 34

ANDROID_LEGACY = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

# Adaptive-icon layers are 108dp against a 48dp icon.
ANDROID_ADAPTIVE = {
    "mipmap-mdpi": 108,
    "mipmap-hdpi": 162,
    "mipmap-xhdpi": 216,
    "mipmap-xxhdpi": 324,
    "mipmap-xxxhdpi": 432,
}


def content_box(rgb: np.ndarray) -> tuple[int, int, int, int]:
    """The artwork's bounding box, ignoring the sky around it."""
    lum = rgb.max(axis=2)
    ys, xs = np.where(lum > SKY_LEVEL)
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def background_colour(rgb: np.ndarray) -> tuple[int, int, int]:
    """The sky, sampled from the border where nothing is drawn."""
    edge = np.concatenate([rgb[:8].reshape(-1, 3), rgb[-8:].reshape(-1, 3),
                           rgb[:, :8].reshape(-1, 3), rgb[:, -8:].reshape(-1, 3)])
    return tuple(int(round(v)) for v in edge.mean(axis=0))


def framed(source: Image.Image, rgb: np.ndarray, fill: float, size: int, background) -> Image.Image:
    """Recentres the artwork and scales it to span [fill] of a square canvas.

    The supplied art is not quite centred and carries a wide margin; both would
    show up as an icon that sits low and small next to its neighbours on a home
    screen.
    """
    x0, y0, x1, y1 = content_box(rgb)
    span = max(x1 - x0, y1 - y0) + 1
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    crop = span / fill

    # The adaptive foreground wants the artwork smaller than the margin the
    # file provides, so the crop window runs off the edge. Pad rather than
    # clamp: clamping would shift the artwork off-centre to make it fit.
    pad = int(max(0, crop / 2 - min(cx, cy, source.width - cx, source.height - cy))) + 2
    # `background` is None for the transparent foreground layer.
    canvas = Image.new(source.mode, (source.width + 2 * pad, source.height + 2 * pad),
                       background if background else (0, 0, 0, 0))
    canvas.paste(source, (pad, pad))

    cx, cy = cx + pad, cy + pad
    box = (cx - crop / 2, cy - crop / 2, cx + crop / 2, cy + crop / 2)
    return canvas.resize((size, size), Image.LANCZOS, box=box)


def transparent_artwork(rgb: np.ndarray) -> Image.Image:
    """The glow on transparency.

    The artwork is light emitted against black, which is the same thing as a
    colour premultiplied by its own alpha. Dividing it back out recovers both
    the true colour and a soft, correct alpha — no cut-out edge, and the outer
    glow keeps fading the way it was drawn.
    """
    a = rgb.astype(float)
    alpha = a.max(axis=2) / 255.0
    safe = np.maximum(alpha, 1e-6)[..., None]
    colour = np.clip(a / safe, 0, 255)
    out = np.dstack([colour, alpha[..., None] * 255]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def main() -> None:
    source = Image.open(SOURCE).convert("RGB")
    rgb = np.asarray(source)
    sky = background_colour(rgb)
    print(f"sky #{sky[0]:02X}{sky[1]:02X}{sky[2]:02X}")

    for folder, px in ANDROID_LEGACY.items():
        out = ANDROID_RES / folder
        out.mkdir(parents=True, exist_ok=True)
        framed(source, rgb, SQUARE_FILL, px, sky).save(out / "ic_launcher.png")

    glow = transparent_artwork(rgb)
    for folder, px in ANDROID_ADAPTIVE.items():
        out = ANDROID_RES / folder
        out.mkdir(parents=True, exist_ok=True)
        framed(glow, rgb, FOREGROUND_FILL, px, None).save(out / "ic_launcher_foreground.png")

    # Keep the adaptive background in step with the artwork's own sky, so the
    # two layers cannot drift apart.
    (ANDROID_RES / "values").mkdir(parents=True, exist_ok=True)
    (ANDROID_RES / "values" / "colors.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<resources>\n"
        "    <!-- The sky behind the orb on the adaptive launcher icon.\n"
        "         Generated by tool/make_icons.py from the artwork itself. -->\n"
        f'    <color name="ic_launcher_background">#{sky[0]:02X}{sky[1]:02X}{sky[2]:02X}</color>\n'
        "</resources>\n"
    )

    contents = json.loads((IOS_ICONSET / "Contents.json").read_text())
    for entry in contents["images"]:
        filename = entry.get("filename")
        if not filename:
            continue
        scale = int(entry["scale"].rstrip("x"))
        px = round(float(entry["size"].split("x")[0]) * scale)
        framed(source, rgb, SQUARE_FILL, px, sky).save(IOS_ICONSET / filename)

    print("icons written")


if __name__ == "__main__":
    main()
