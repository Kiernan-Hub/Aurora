#!/usr/bin/env python3
"""Turn a raw generated ice panel into the game-ready depth tile.

    python3 scripts/tools/build_ice_texture.py three.png

Checked in, unlike the ad-hoc script that produced ice_terrain_one.png (whose
provenance had to be reconstructed from a comment). Re-run it to retune, or to
process a replacement panel.

WHAT THE SOURCE MUST BE
    A greyscale ice panel whose VERTICAL AXIS IS DEPTH BELOW THE ICE SURFACE:
    bright snow band at the very top, deepening smoothly downward, thin sparse
    white cracks, a couple of soft snow patches near the top. Smooth and glossy,
    not rough. Horizontal tiling is fixed up here, so the source does not need to
    be seamless -- but the closer its left and right edges already are, the less
    the feather has to hide.

WHY THE OUTPUT IS NOT JUST THE INPUT
    1. LEVELS. Polygon2D renders `texture_sample * vertex_color`, so this tile is
       a MULTIPLIER, not a colour. three.png bottoms out at 0.087 luminance,
       which multiplies any biome tint down to near-black -- deep ice in the
       reference art is dark and saturated, not black. The darks are lifted to
       OUTPUT_FLOOR so the ramp still reads as depth without killing the hue.
    2. SEAM. The tile repeats horizontally forever. Any mismatch between the left
       and right edge is a hard vertical line every repeat, at eye level, moving
       at 750 px/s.

HOW THE WRAP IS MADE SEAMLESS
    By ROLLING the image half its width, not by mirroring and not by blending the
    edges toward each other.

    Rolling puts original column w/2 at the new left edge and column w/2 - 1 at
    the new right edge. Those two were ADJACENT in the source, so the tile now
    wraps exactly -- seamless by construction, no fade, no ghosting. It moves the
    original discontinuity (column w-1 against column 0) into the middle of the
    tile, where a narrow feather hides it and where it does not repeat.

    The first version of this script instead cross-faded the right edge toward
    the left edge. That is a double exposure of two different pieces of ice: it
    left a smeared vertical band at every repeat, which was clearly visible in
    game. Do not go back to it.

    Mirroring also guarantees a seamless join, but stamps a symmetry axis into the
    image -- the faint diamond artifact in the tile this replaced -- and with long
    diagonal cracks that reads as a chevron every repeat.
"""

import sys

import numpy as np
from PIL import Image, ImageFilter

OUTPUT_PATH = "assets/textures/terrain/ice_depth_gradient.png"
OUTPUT_SIZE = (1024, 1024)

# The value the deepest ice multiplies down to. The tile is a MULTIPLIER, so this
# is what stops every biome tint going black at depth -- but it is also the whole
# depth cue, so it must not be lifted far. 0.52 was tried and washed the ice out
# completely: it compressed the source's 0.09..0.99 range into the bright half and
# the ice read as white noise rather than as deep water.
OUTPUT_FLOOR = 0.38
OUTPUT_CEILING = 1.0
# Applied to the normalised source before the floor. >1 pushes midtones DOWN,
# which restores the contrast that mapping onto a raised floor otherwise flattens
# -- the ice reaches its deep colour quickly, the way the reference art does,
# instead of staying pale most of the way down.
MIDTONE_GAMMA = 1.4

# Half the width, in the rolled image, over which the (now central) original seam
# is feathered. Narrow: the seam is in the middle of the tile and does not repeat,
# so it needs hiding, not disguising.
SEAM_FEATHER = 90
# Generated panels carry fine grain that reads as noise once the tile is stretched
# over 1200 world px. The reference ice is glossy and smooth; cracks are far wider
# than this radius and survive it.
SMOOTHING_RADIUS = 0.8


def remap_levels(values):
    """Normalise the source's own range, apply the midtone curve, then seat it on
    OUTPUT_FLOOR. Uses the measured extremes so the full output range is used
    however the source was generated."""
    low, high = values.min(), values.max()
    if high <= low:
        raise SystemExit("source image is a flat colour")
    normalised = (values - low) / (high - low)
    curved = np.power(normalised, MIDTONE_GAMMA)
    return OUTPUT_FLOOR + (curved * (OUTPUT_CEILING - OUTPUT_FLOOR))


def make_horizontally_seamless(values):
    """Roll by half the width so the tile wraps exactly, then feather the seam
    that lands in the middle. See the module docstring for why this beats fading
    the edges into each other.

    The vertical axis is deliberately untouched: it is depth below the ice
    surface, so it must NOT wrap -- the caller keeps V inside the texture.
    """
    width = values.shape[1]
    half = width // 2
    rolled = np.roll(values, half, axis=1)

    # Linear cross-fade across the seam at x == half, between the two sides
    # extended through it. Weight 0 on the left of the band, 1 on the right.
    left = max(0, half - SEAM_FEATHER)
    right = min(width, half + SEAM_FEATHER)
    band_width = right - left
    if band_width < 2:
        return rolled
    weights = np.linspace(0.0, 1.0, band_width)[None, :]
    before = rolled[:, left - 1: left].repeat(band_width, axis=1) if left > 0 else rolled[:, left: left + 1].repeat(band_width, axis=1)
    after = rolled[:, right - 1: right].repeat(band_width, axis=1)
    # Blend the band toward a straight ramp between its two neighbours, then
    # average that with the original content so texture detail survives.
    ramp = (before * (1.0 - weights)) + (after * weights)
    # Weighted toward the ORIGINAL content, not the ramp: the ramp only has to remove the
    # level step across the seam. Leaning on it harder flattens texture detail into a smooth
    # vertical band, which is itself visible against the detailed ice either side of it --
    # that was the faint line still showing at 0.55.
    blend_strength = np.sin(np.linspace(0.0, np.pi, band_width))[None, :] * 0.42
    rolled[:, left:right] = (rolled[:, left:right] * (1.0 - blend_strength)) + (ramp * blend_strength)
    return rolled


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)

    source = Image.open(sys.argv[1]).convert("L")
    print("source      ", source.size, "range", source.getextrema())

    # Resize BEFORE the seam work so the feather is computed at output resolution
    # and cannot be resampled into a soft band of its own.
    resized = source.resize(OUTPUT_SIZE, Image.LANCZOS)
    if SMOOTHING_RADIUS > 0.0:
        resized = resized.filter(ImageFilter.GaussianBlur(SMOOTHING_RADIUS))

    values = np.asarray(resized, dtype=np.float64) / 255.0
    values = remap_levels(values)
    values = make_horizontally_seamless(values)

    output = Image.fromarray(np.clip(values * 255.0, 0, 255).astype(np.uint8), mode="L")
    output.save(OUTPUT_PATH, optimize=True)

    seam_error = float(np.abs(values[:, 0] - values[:, -1]).mean())
    print("wrote       ", OUTPUT_PATH, output.size)
    print("depth ramp  ", " ".join(
        f"{f:.0%}={values[int(f * (values.shape[0] - 1))].mean():.2f}"
        for f in (0.0, 0.05, 0.15, 0.3, 0.5, 0.75, 1.0)))
    print("seam error  ", round(seam_error, 5), "(0 = exact wrap)")


if __name__ == "__main__":
    main()
