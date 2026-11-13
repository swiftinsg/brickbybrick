#!/usr/bin/env python3
"""Turn the pixel-art grids into PNG image sets in the asset catalog.

    python3 tools/sprites.py

Reads Art/houses.json (house sprites designed with DeepSeek) and the tab icons
below, and writes brickbybrick/Assets.xcassets. Pixels are kept at their real
size (32x32 houses); the app scales them up with interpolation off, so they stay
crisp. Standard library only.
"""
import json, os, struct, zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "brickbybrick", "Assets.xcassets")

# 8x8 tab icons, drawn in one colour and tinted by the tab bar (template images).
ICONS = {
    "tab.home": ["...KK...", "..KKKK..", ".KKKKKK.", "KKKKKKKK", ".K....K.", ".K.KK.K.", ".K.KK.K.", ".KKKKKK."],
    "tab.schedule": ["..KKKK..", ".K....K.", "K...K..K", "K...K..K", "K...KKKK", "K......K", ".K....K.", "..KKKK.."],
    "tab.tasks": ["KKKKKKKK", "K......K", "K.....KK", "K....K.K", "KK..K..K", "K.KK...K", "K......K", "KKKKKKKK"],
    "tab.calendar": ["KKKKKKKK", "K.K..K.K", "KKKKKKKK", "K......K", "K.KK.K.K", "K......K", "K.K.KK.K", "KKKKKKKK"],
    "icon.brick": ["KKKKKKKKK", "KRRRKRRRK", "KKKKKKKKK", "KRKRRRKRK", "KKKKKKKKK"],
}
ICON_PALETTE = {"K": "#2B2340", "R": "#B34A34"}


def png(rows, palette, scale=1):
    """PNG bytes for a grid of palette characters ('.' = transparent)."""
    def rgba(ch):
        if ch == ".":
            return b"\0\0\0\0"
        h = palette[ch].lstrip("#")
        return bytes(int(h[i:i + 2], 16) for i in (0, 2, 4)) + b"\xff"

    raw = b"".join((b"\0" + b"".join(rgba(c) * scale for c in row)) * scale for row in rows)
    w, h = len(rows[0]) * scale, len(rows) * scale

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def imageset(name, rows, palette, template=False, scales=(1,)):
    """Write <name>.imageset. Icons get 1x/2x/3x so the tab bar shows them at 3x their grid size."""
    folder = os.path.join(ASSETS, name + ".imageset")
    os.makedirs(folder, exist_ok=True)
    images = []
    for s in scales:
        file = f"{name}@{s}x.png"
        with open(os.path.join(folder, file), "wb") as f:
            f.write(png(rows, palette, s * (3 if template else 1)))
        images.append({"filename": file, "idiom": "universal", "scale": f"{s}x"})
    props = {"template-rendering-intent": "template"} if template else {}
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}, "properties": props}, f, indent=2)


def main():
    os.makedirs(ASSETS, exist_ok=True)
    with open(os.path.join(ASSETS, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)

    houses = json.load(open(os.path.join(ROOT, "Art", "houses.json")))
    for sprite in houses["sprites"]:
        grid = sprite["grid"]
        assert len(grid) == 32 and all(len(r) == 32 for r in grid), sprite["name"]
        imageset("house." + sprite["name"].lower(), grid, houses["palette"])

    for name, grid in ICONS.items():
        template = name.startswith("tab.")
        imageset(name, grid, ICON_PALETTE, template=template, scales=(1, 2, 3) if template else (1,))
    print("wrote", ASSETS)


if __name__ == "__main__":
    main()
