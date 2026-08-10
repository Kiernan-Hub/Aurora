#!/usr/bin/env python3
"""Turn a raw generated ice panel into the game-ready depth tile.

    python3 scripts/tools/build_ice_texture.py --check panel.png   (validate a source panel)
python3 scripts/tools/build_ice_texture.py three.png
    python3 scripts/tools/build_ice_texture.py four.png assets/textures/terrain/ice_faceted.png

The output path is optional and defaults to DEFAULT_OUTPUT_PATH (the smooth tile
every biome starts on). Pass it to build one of the pattern VARIANTS -- see
docs/development/biomes.md, "Per-biome ice textures". Every variant must go
through this same script: the levels work below is what stops a raw panel
multiplying its biome tint to black.

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

WHY A VARIANT'S DEPTH RAMP IS MATCHED TO THE DEFAULT TILE'S
    A biome change swaps the tile one 512px CHUNK at a time (biomes.md, "The
    pattern does not crossfade"), so there is a live vertical boundary with the
    old tile on one side and the new one on the other. The tile is a MULTIPLIER,
    so if the two tiles disagree about how bright ice is at a given depth, that
    boundary is a flat brightness STEP -- which reads as a hard cutoff no matter
    how similar the patterns are. Measured before this: default 0.98 at the ride
    line and 0.49 at half depth, faceted 0.86 and 0.66.

    So every variant is rescaled per row to the default tile's own light-to-dark
    ramp. What survives is the variant's high-frequency detail -- its cracks and
    facets -- which is the whole reason it exists; what goes is the disagreement
    about overall depth brightness, which was never a per-biome creative choice.
"""

import sys

import numpy as np
from PIL import Image, ImageFilter

DEFAULT_OUTPUT_PATH = "assets/textures/terrain/ice_depth_gradient.png"
# Every variant is built at this size. terrain_generator.gd reads the tile's own
# get_size() for its UVs, so a differently sized variant would not break -- but it
# would change how fast the pattern repeats relative to the others, which is not a
# knob worth having per texture when ICE_TILE_WORLD_WIDTH already owns that.
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

# How hard a variant is pulled onto the default tile's depth ramp. 1.0 is a full
# match. Lower it if a full match over-flattens a tile whose source has no real
# structure where the reference is bright -- four.png has no snow band, so its top
# rows get lifted into a band with little internal detail. That is the right trade
# for the seam, but if it reads as a flat white bar in game, ease this to ~0.7
# rather than turning the match off.
RAMP_MATCH_STRENGTH = 1.0
# Vertical sigma, in rows, that the per-row correction is smoothed over. The
# correction is one scalar per row, so it cannot erase detail WITHIN a row -- but
# row-to-row noise in it would stamp horizontal banding across the tile. Only the
# low-frequency ramp is meant to move.
RAMP_SMOOTH_SIGMA = 8.0

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


def smooth_vertically(column, sigma):
    """Gaussian-blur a 1-D profile, edge-extended. Hand-rolled so the tool keeps
    its two dependencies (numpy, Pillow) and does not pull in scipy for this."""
    radius = max(1, int(round(sigma * 3.0)))
    offsets = np.arange(-radius, radius + 1, dtype=np.float64)
    kernel = np.exp(-0.5 * np.square(offsets / sigma))
    kernel /= kernel.sum()
    padded = np.pad(column, radius, mode="edge")
    return np.convolve(padded, kernel, mode="valid")


def match_depth_ramp(values, reference_path):
    """Rescale each row so the tile's light-to-dark depth ramp agrees with the
    default tile's. See the module docstring for why -- in short, the chunk
    boundary during a biome change is a live seam between two tiles, and both are
    multipliers, so a ramp disagreement is a visible brightness step.

    Multiplicative, not additive: the tile multiplies a biome tint, so scaling a
    row preserves its internal contrast ratios, which is exactly the detail the
    variant exists to provide.
    """
    reference = np.asarray(Image.open(reference_path).convert("L"), dtype=np.float64) / 255.0
    if reference.shape[0] != values.shape[0]:
        raise SystemExit(
            "reference %s is %d rows, this tile is %d -- both must be OUTPUT_SIZE"
            % (reference_path, reference.shape[0], values.shape[0]))

    reference_rows = smooth_vertically(reference.mean(axis=1), RAMP_SMOOTH_SIGMA)
    source_rows = smooth_vertically(values.mean(axis=1), RAMP_SMOOTH_SIGMA)
    # Guarded because a row of an unlifted source can sit near zero; after
    # remap_levels() nothing should, but a divide-by-zero here would silently
    # produce a white tile rather than fail.
    ratio = reference_rows / np.maximum(source_rows, 1e-6)
    ratio = 1.0 + ((ratio - 1.0) * RAMP_MATCH_STRENGTH)

    matched = values * ratio[:, None]
    return np.clip(matched, OUTPUT_FLOOR, OUTPUT_CEILING)


def format_ramp(values):
    return " ".join(
        f"{f:.0%}={values[int(f * (values.shape[0] - 1))].mean():.2f}"
        for f in (0.0, 0.05, 0.15, 0.3, 0.5, 0.75, 1.0))


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


def inspect_panel(path):
    """Report whether a SOURCE panel is usable, before building anything.

    Every rejection here is something the build would otherwise paper over silently: the
    builder lifts darks, matches the depth ramp and feathers the seam, so a panel that is
    upside down or has no vertical structure still produces a tile -- just a wrong one, and
    the only symptom is ice that looks flat in game. Cheaper to say so up front.
    """
    image = Image.open(path).convert("L")
    values = np.asarray(image.resize(OUTPUT_SIZE, Image.LANCZOS), dtype=np.float64) / 255.0
    rows = values.mean(axis=1)
    top = rows[: OUTPUT_SIZE[1] // 8].mean()
    bottom = rows[-OUTPUT_SIZE[1] // 8 :].mean()
    within_row = values.std(axis=1).mean()

    print("panel       ", path, image.size, "mode", image.mode)
    print("top eighth  ", round(top, 3), " bottom eighth", round(bottom, 3))
    print("within-row  ", round(within_row, 4), "(contrast that survives the ramp match)")

    problems = []
    if top <= bottom:
        problems.append(
            "TOP IS NOT BRIGHTER THAN THE BOTTOM. The vertical axis is DEPTH BELOW THE RIDE "
            "SURFACE, not a side view of ice: snow band at the top, darkening downward. "
            "A panel that is upside down builds fine and renders as ice lit from below."
        )
    elif top - bottom < 0.12:
        problems.append(
            "Barely any vertical structure (top-bottom %.3f). The tile IS the depth ramp; "
            "without one there is nothing for V to mean." % (top - bottom)
        )
    if within_row < 0.02:
        problems.append(
            "Almost no WITHIN-ROW contrast (%.4f). match_depth_ramp() rescales each row onto "
            "the default tile's brightness, so between-row contrast is normalised away by "
            "design -- facets and cracks have to live ACROSS a row to survive." % within_row
        )
    # A WARNING, not a rejection: four.png is 1022x755 and produced a shipped tile. Upscaling
    # costs sharpness, which is a quality call, not a correctness one.
    warnings = []
    if image.size[0] < OUTPUT_SIZE[0] or image.size[1] < OUTPUT_SIZE[1]:
        warnings.append(
            "Smaller than the %dx%d output, so it will be upscaled and slightly soft."
            % OUTPUT_SIZE
        )

    if warnings:
        print()
        for warning in warnings:
            print("  note:", warning)

    if problems:
        print()
        print("NOT READY:")
        for problem in problems:
            print("  *", problem)
        return 1
    print()
    print("OK -- build it with:  python3 scripts/tools/build_ice_texture.py", path, "<output.png>")
    return 0


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--check":
        raise SystemExit(inspect_panel(sys.argv[2]))
    if len(sys.argv) not in (2, 3):
        raise SystemExit(__doc__)
    output_path = sys.argv[2] if len(sys.argv) == 3 else DEFAULT_OUTPUT_PATH

    source = Image.open(sys.argv[1]).convert("L")
    print("source      ", source.size, "range", source.getextrema())

    # Resize BEFORE the seam work so the feather is computed at output resolution
    # and cannot be resampled into a soft band of its own.
    resized = source.resize(OUTPUT_SIZE, Image.LANCZOS)
    if SMOOTHING_RADIUS > 0.0:
        resized = resized.filter(ImageFilter.GaussianBlur(SMOOTHING_RADIUS))

    values = np.asarray(resized, dtype=np.float64) / 255.0
    values = remap_levels(values)
    # Keyed off "an output path was given", which is exactly the definition of a
    # variant -- so there is no flag to forget on a rebuild, and the default tile
    # (its own reference) cannot match against itself.
    is_variant = output_path != DEFAULT_OUTPUT_PATH
    if is_variant:
        print("own ramp    ", format_ramp(values))
        values = match_depth_ramp(values, DEFAULT_OUTPUT_PATH)
    # Last, so the feather has the final word on the wrap. The row scaling above is
    # seam-neutral (one scalar per row hits both edges equally), but ordering it
    # this way means only one step can ever be responsible for a visible repeat.
    values = make_horizontally_seamless(values)

    output = Image.fromarray(np.clip(values * 255.0, 0, 255).astype(np.uint8), mode="L")
    output.save(output_path, optimize=True)

    seam_error = float(np.abs(values[:, 0] - values[:, -1]).mean())
    print("wrote       ", output_path, output.size)
    print("depth ramp  ", format_ramp(values))
    if is_variant:
        reference = np.asarray(Image.open(DEFAULT_OUTPUT_PATH).convert("L"), dtype=np.float64) / 255.0
        print("reference   ", format_ramp(reference), "  <- must track the line above")
    print("seam error  ", round(seam_error, 5), "(0 = exact wrap)")


if __name__ == "__main__":
    main()
