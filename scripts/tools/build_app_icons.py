#!/usr/bin/env python3
"""Cut one tile out of the app-icon contact sheet and bake the Android launcher icons.

    python3 scripts/tools/build_app_icons.py --list
    python3 scripts/tools/build_app_icons.py --row 1 --col 2
    python3 scripts/tools/build_app_icons.py --row 1 --col 2 --check

Source is art_source/aura.png, a 3x3 contact sheet of nine candidate icons rendered as
one image -- NOT a single icon. Picking one is a human decision; this file only does the
cutting, so re-cutting a different tile is one flag rather than an afternoon in GIMP.
Sources live in art_source/, which carries a .gdignore: the repo root and assets/ both
ship, art_source/ does not. Same rule as build_pano_strip.py and build_ice_texture.py.

Shipped 2026-08-25 with --row 1 --col 2, the aurora over dark peaks -- the game's
namesake, and the highest-contrast tile of the nine.

WHAT IT WRITES, and why each one exists

    assets/icons/icon_192.png                       legacy square launcher icon
    assets/icons/icon_adaptive_background_432.png   adaptive icon, back layer
    assets/icons/icon_adaptive_foreground_432.png   adaptive icon, front layer

    Android 8+ composites the two adaptive layers and masks the result to whatever
    shape the launcher wants -- circle, squircle, rounded square. Only the middle
    ~66% survives that mask; the outer third is bleed. So the art goes in the BACK
    layer full-bleed, where the crop is safe, and the front layer is deliberately
    fully transparent.

    THE TRANSPARENT FRONT LAYER IS LOAD-BEARING, NOT A PLACEHOLDER. Leaving
    launcher_icons/adaptive_foreground_432x432 empty in export_presets.cfg does not
    mean "no front layer" -- Godot substitutes the project icon (res://icon.svg,
    still the stock Godot robot), and it lands on top of the aurora. An empty string
    there ships a Godot logo over the art. Verified by exporting and unzipping the
    APK, which is also how to re-check it: see --check.

WHY THE TILE IS CROPPED TWICE, at two different insets

    Each tile on the sheet has ROUNDED CORNERS baked into the pixels, sitting on the
    sheet's black gutter. That black is part of the art, not padding.

    - The adaptive background takes the FULL tile, corners and all, because the
      launcher's mask cuts well inside them. Insetting here would zoom the art in
      for no reason.
    - The legacy 192px icon takes an INSET crop (CORNER_INSET below), because old
      launchers draw the square as-is and the baked corners read as a black frame.

    Get these backwards and the icon is either black-cornered or over-zoomed. Both
    look like a bad export rather than a bad crop, which is why this is written down.

THE GRID IS MEASURED, NOT ASSUMED. The tile bounds come from finding the sheet's dark
gutter bands at runtime, so a re-rendered sheet at a different size still cuts cleanly.
It asserts it found exactly 3 tiles per axis rather than cutting garbage quietly.
"""

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow required:  python3 -m pip install Pillow")

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / "art_source" / "aura.png"
OUT_DIR = REPO / "assets" / "icons"

# A gutter pixel is near-black across the sheet's whole span. The sheet's art is
# pale-to-mid blue everywhere, so 30/255 separates gutter from art with room to spare.
GUTTER_MAX_LUMA = 30

# Fraction of the tile trimmed from each edge for the legacy icon, to clear the
# rounded corners baked into the tile. Measured off the 2026-08-25 sheet: the corner
# radius is ~11% of the tile, and 8% per edge clears the visible black without
# eating into the composition.
CORNER_INSET = 0.08

LEGACY_SIZE = 192
ADAPTIVE_SIZE = 432


def gutter_runs(is_dark):
    """[(start, end)] index runs where is_dark is True."""
    runs, start = [], None
    for i, dark in enumerate(is_dark):
        if dark and start is None:
            start = i
        elif not dark and start is not None:
            runs.append((start, i - 1))
            start = None
    if start is not None:
        runs.append((start, len(is_dark) - 1))
    return runs


def tile_bounds(sheet):
    """(col_spans, row_spans) of the nine tiles, measured off the gutters."""
    grey = sheet.convert("L")
    w, h = grey.size
    px = grey.load()

    col_dark = [max(px[x, y] for y in range(h)) < GUTTER_MAX_LUMA for x in range(w)]
    row_dark = [max(px[x, y] for x in range(w)) < GUTTER_MAX_LUMA for y in range(h)]

    def spans(dark, extent):
        # A tile is a run of NOT-gutter. Filtering by width drops any hairline run
        # left by a soft gutter edge, so a slightly blurry sheet still cuts cleanly.
        out = [(a, b) for a, b in gutter_runs([not d for d in dark])
               if b - a + 1 > extent // 10]
        if len(out) != 3:
            sys.exit(
                "Expected a 3x3 sheet, measured %d tiles on one axis (gutters: %s).\n"
                "The source is not the contact sheet this tool cuts."
                % (len(out), gutter_runs(dark))
            )
        return out

    return spans(col_dark, w), spans(row_dark, h)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--row", type=int, default=1, help="1-3, top to bottom")
    ap.add_argument("--col", type=int, default=2, help="1-3, left to right")
    ap.add_argument("--list", action="store_true",
                    help="print the measured tile grid and exit, writing nothing")
    ap.add_argument("--check", action="store_true",
                    help="print how to verify the result in a built APK, and exit")
    args = ap.parse_args()

    if args.check:
        print(__doc__.split("WHY THE TILE IS CROPPED TWICE")[0].strip())
        print("\nTo verify what actually shipped:\n"
              "  Godot --headless --path . --export-release Android /tmp/aura.apk\n"
              "  unzip -l /tmp/aura.apk | grep -i 'mipmap\\|ic_launcher'\n"
              "Expect icon.png, icon_background.png and icon_foreground.png under res/,\n"
              "and NO Godot robot in the foreground layer.")
        return

    if not SOURCE.exists():
        sys.exit("Source not found: %s" % SOURCE)
    if not (1 <= args.row <= 3 and 1 <= args.col <= 3):
        sys.exit("--row and --col are 1-3")

    sheet = Image.open(SOURCE).convert("RGB")
    cols, rows = tile_bounds(sheet)

    if args.list:
        print("%s  %dx%d" % (SOURCE.relative_to(REPO), *sheet.size))
        for r, (y0, y1) in enumerate(rows, 1):
            for c, (x0, x1) in enumerate(cols, 1):
                print("  row %d col %d   x %4d-%-4d  y %4d-%-4d  (%dx%d)"
                      % (r, c, x0, x1, y0, y1, x1 - x0 + 1, y1 - y0 + 1))
        return

    x0, x1 = cols[args.col - 1]
    y0, y1 = rows[args.row - 1]
    tile = sheet.crop((x0, y0, x1 + 1, y1 + 1))
    size = min(tile.size)

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    # Adaptive background: full bleed. The launcher's mask cuts inside the baked corners.
    background = tile.resize((ADAPTIVE_SIZE, ADAPTIVE_SIZE), Image.LANCZOS)
    background.save(OUT_DIR / "icon_adaptive_background_432.png")

    # Adaptive foreground: deliberately empty. See the module docstring -- an empty
    # path in export_presets.cfg would ship the stock Godot icon here instead.
    foreground = Image.new("RGBA", (ADAPTIVE_SIZE, ADAPTIVE_SIZE), (0, 0, 0, 0))
    foreground.save(OUT_DIR / "icon_adaptive_foreground_432.png")

    # Legacy square icon: inset past the baked rounded corners.
    inset = int(round(size * CORNER_INSET))
    legacy = tile.crop((inset, inset, tile.width - inset, tile.height - inset))
    legacy = legacy.resize((LEGACY_SIZE, LEGACY_SIZE), Image.LANCZOS)
    legacy.save(OUT_DIR / "icon_192.png")

    print("cut row %d col %d  (%dx%d from %s)"
          % (args.row, args.col, tile.width, tile.height, SOURCE.name))
    for name in ("icon_192.png", "icon_adaptive_background_432.png",
                 "icon_adaptive_foreground_432.png"):
        path = OUT_DIR / name
        print("  %-38s %6d bytes" % (path.relative_to(REPO), path.stat().st_size))


if __name__ == "__main__":
    main()
