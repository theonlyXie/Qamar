#!/usr/bin/env python3
"""Slice the rendered moon into every launcher-icon size both platforms want.

    flutter test tool/render_app_icon.dart   # draws the 1024px masters
    python3 tool/make_icons.py               # slices them

Nothing here is hand-drawn: the masters come from the app's own QamarMoon
painter, so the icon cannot drift away from the moon on screen.

iOS icons must have no alpha channel — the App Store rejects them — so they are
flattened onto the same navy the master is drawn on.
"""

import json
import pathlib

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
MASTER = ROOT / "tool" / "app_icon_1024.png"
FOREGROUND = ROOT / "tool" / "app_icon_foreground_1024.png"

ANDROID_RES = ROOT / "android" / "app" / "src" / "main" / "res"
IOS_ICONSET = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"

# Android legacy launcher icon, per density bucket.
ANDROID_LEGACY = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

# Adaptive-icon layers are 108dp; the launcher crops them to the middle 72dp.
ANDROID_ADAPTIVE = {
    "mipmap-mdpi": 108,
    "mipmap-hdpi": 162,
    "mipmap-xhdpi": 216,
    "mipmap-xxhdpi": 324,
    "mipmap-xxxhdpi": 432,
}

BACKGROUND = (10, 14, 26)


def resize(img: Image.Image, px: int) -> Image.Image:
    return img.resize((px, px), Image.LANCZOS)


def main() -> None:
    master = Image.open(MASTER).convert("RGBA")
    foreground = Image.open(FOREGROUND).convert("RGBA")

    for folder, px in ANDROID_LEGACY.items():
        out = ANDROID_RES / folder
        out.mkdir(parents=True, exist_ok=True)
        resize(master, px).save(out / "ic_launcher.png")

    for folder, px in ANDROID_ADAPTIVE.items():
        out = ANDROID_RES / folder
        out.mkdir(parents=True, exist_ok=True)
        resize(foreground, px).save(out / "ic_launcher_foreground.png")

    # iOS: every size listed in the asset catalogue, flattened.
    contents = json.loads((IOS_ICONSET / "Contents.json").read_text())
    flat = Image.new("RGB", master.size, BACKGROUND)
    flat.paste(master, mask=master.split()[3])
    for entry in contents["images"]:
        filename = entry.get("filename")
        if not filename:
            continue
        scale = int(entry["scale"].rstrip("x"))
        px = round(float(entry["size"].split("x")[0]) * scale)
        flat.resize((px, px), Image.LANCZOS).save(IOS_ICONSET / filename)

    print("icons written")


if __name__ == "__main__":
    main()
