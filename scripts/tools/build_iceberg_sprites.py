#!/usr/bin/env python3
"""Turn a generated iceberg painting into a game-ready background sprite.

    python3 scripts/tools/build_iceberg_sprites.py --check art_source/berg_shelf_01.png
    python3 scripts/tools/build_iceberg_sprites.py art_source/berg_shelf_01.png
    python3 scripts/tools/build_iceberg_sprites.py art_source/berg_shelf_01.png assets/textures/background/iceberg_shelf_01.png

The output path is optional and defaults to assets/textures/background/<stem>.png,
so building a library is a shell loop and this tool needs no batch mode.

Sources live in art_source/, which carries a .gdignore -- the repo root and
assets/ both ship, art_source/ does not. Same rule as build_ice_texture.py.

WHAT THE SOURCE MUST BE
    ONE ice formation, alone, centred, its base at the bottom edge, painted flat
    and cel-shaded on a SOLID MAGENTA (#FF00FF) background. No sky, no ground, no
    horizon, no water, no second formation. 1024x1024 or larger.

    Everything pale: the darkest shape no darker than about #B3B3B3. Nothing dark
    anywhere. The full prompt spec is in docs/development/visuals.md.

WHY THE OUTPUT IS NOT JUST THE INPUT
    1. ALPHA. The generator cannot emit transparency, so the magenta has to be
       keyed out here. Magenta because no ice, snow, sky or shadow is ever
       magenta, so the key can be wide and still never eat the subject.
    2. LEVELS. The sprite hangs under BackgroundGenerator's `ridges_root`, whose
       `modulate` carries the biome's scenery colour, and Godot renders
       texture * modulate. So this file is a MULTIPLIER, not a colour -- exactly
       like the ice depth tile, and for exactly the same reason.

       Measured on art_source/example.png, the target art: the ice formations sit
       at luminance p1 0.67-0.75, median 0.80, p95 0.86-0.92, at a saturation
       (~0.19) barely above the sky's (~0.15). The whole look is a 0.25-wide band
       with NOTHING dark in it.

       Then the test that matters: take a crop of that reference, throw away all
       colour, and multiply the greyscale by ONE flat colour. It reconstructs the
       original at 3-5/255 mean absolute error. There is no painterly colour in
       this reference to lose -- it is greyscale structure times a flat blue tint,
       which is precisely the operation `modulate` already performs. So the sprite
       is stored near-greyscale in a fixed bright band, and all eight biome
       palettes come free.

WHAT THIS DELIBERATELY DOES *NOT* INHERIT FROM build_ice_texture.py
    The temptation to copy that file is strong and four of its steps are actively
    wrong here. Each of these is a bug, not a style preference:

      * ITS remap_levels() NORMALISES ON values.min()/max(). Here a single stray
        bright antialiasing pixel, or one un-keyed remnant, would set the whole
        range and collapse the band. EVERY statistic in this file runs over MASKED
        pixels only and uses PERCENTILES, never extremes.
      * OUTPUT_FLOOR = 0.38 is wrong here by a factor of two. That floor exists
        because the tile's whole meaning is a depth ramp that must go dark. This
        band's meaning is facet contrast on an object that in the reference never
        drops below 0.67. Rendering a formation at 38% of its layer colour is
        "it just looks like rocks" expressed as a number.
      * match_depth_ramp() has nothing to match. There is no shared ramp between
        two formations and no cross-dissolve putting two on screen at once.
      * flatten_horizontal_banding() divides out low-frequency structure. Here the
        low-frequency structure IS the facets -- it is the entire content.
      * make_horizontally_seamless() has no tile to make seamless. A formation is
        an island placed on a grid; it has no wrap and no seam. That is the whole
        reason this route works where four rounds of tiled raster art did not.

HOW THE KEY WORKS, AND WHY NOT RGB DISTANCE
    Keying on distance from pure magenta breaks the moment the generator puts a
    soft contact shadow or a vignette into its "flat" backdrop, which it does no
    matter how the prompt is worded: shaded magenta (0.6, 0, 0.6) is 0.57 away
    from (1, 0, 1) and reads as subject.

    So the key is MAGENTA EXCESS -- min(R, B) - G -- which is a ratio-like measure
    of how green-deficient a pixel is, and is therefore invariant to how brightly
    the backdrop is lit:

        pure magenta  (1.00, 0.00, 1.00) ->  1.00
        shaded magenta(0.60, 0.00, 0.60) ->  0.60
        white ice     (1.00, 1.00, 1.00) ->  0.00
        pale blue ice (0.80, 0.85, 0.95) -> -0.05

    Every magenta shade is strongly positive; everything ice-like is at or below
    zero. The threshold pair below has margin on both sides.
"""

import os
import sys

import numpy as np
from PIL import Image, ImageFilter

DEFAULT_OUTPUT_DIR = "assets/textures/background"

# The backdrop the generator is asked for. Used to unpremultiply the feathered
# edge, so it must match what the prompt spec asks for.
KEY_COLOR = np.array([1.0, 0.0, 1.0])
# Magenta excess (see the docstring) at or above which a pixel is fully
# background, and at or below which it is fully subject. The gap is the feather.
KEY_EXCESS_BACKGROUND = 0.30
KEY_EXCESS_SUBJECT = 0.10

# THE MEASURED TARGET BAND. See the docstring for where these come from. The
# reference's absolute readings include the flat blue tint and the sky behind it,
# so what carries over is the RATIOS: p1/p95 = 0.67/0.90 = 0.745, median/p95 =
# 0.89. Mapping onto [0.70, 1.00] with the median at 0.80 reproduces those, with
# very slightly more internal contrast than the reference -- which is correct,
# because the layer's own haze band then takes some back out.
#
# NOTHING IS DARK. The last raster attempt put 7.5% of the form below 0.45
# luminance against a reference that bottoms out near 0.67, and that is what read
# as "a shaded 3D render".
OUTPUT_FLOOR = 0.70
OUTPUT_CEILING = 1.0
TARGET_MEDIAN = 0.80
# Percentiles the source's own band is normalised on, before it is seated on the
# range above. Not min/max -- see the docstring.
BAND_PERCENTILES = (2.0, 98.0)
# The gamma that seats the median is clamped to this. A clamp hit means the source
# histogram was so far off that the remap could not seat it, which is worth being
# told before the sprite looks flat in game, so it is printed rather than silent.
GAMMA_LIMITS = (0.4, 2.5)

# Rec.601, matching scripts/debug/biome_schedule_check.gd, so a number printed
# here is the same quantity the gate measures.
LUMA_WEIGHTS = np.array([0.299, 0.587, 0.114])

# Alpha at or above which a pixel counts as "the formation" for every statistic.
SUBJECT_ALPHA = 0.5

# Morphological opening radius, in source px, applied to the alpha before
# feathering. Kills key speckle and single-pixel spurs. Deliberately does NOT fill
# holes: the arch in the reference IS a hole, and filling it is the difference
# between an arch and a lump.
SPECKLE_RADIUS = 2
# Sub-pixel at 2x authoring. Enough to kill the key's stair-stepping, not enough
# to soften a facet edge -- hard edges between facets are the whole look.
EDGE_FEATHER_RADIUS = 1.5
# The base fades to nothing over this fraction of the trimmed height, so a
# formation has no bottom edge to notice. The layer's haze band already dissolves
# the base -- that dissolve is the single strongest depth cue in the reference --
# but haze alpha varies 0.38-0.62 across the palettes and the sprite should not
# depend on it. This also means iceberg_sink can never expose a hard alpha cut.
BASE_FADE_FRACTION = 0.18

# Longest edge of the output. visuals.md wants raster art at ~2x its world size
# and the near layer's tallest formation is ~150 viewport px, so this is 2.5x with
# margin. It is also the VRAM budget: 384x384 RGBA8 is 590KB, so a 20-formation
# library is ~12MB, which the Mobile renderer can carry. At 1024 it would be
# 4.2MB each and ~84MB, which it cannot. Do not raise this without redoing that
# arithmetic -- and note VRAM compression is NOT the escape hatch, because block
# compression on a near-flat 0.70-1.00 band bands visibly.
MAX_OUTPUT_EDGE = 384

# --- Thresholds for --check ------------------------------------------------
# Calibrated by measuring art_source/example.png -- the target art -- through
# these same code paths, so every threshold has a number the reference actually
# scores sitting next to it. A check the target art would fail is a broken check;
# one draft of this file had two, and both are documented where they were fixed.

# Share of the frame that keys to background. Below: the formation fills the frame
# edge to edge, so there is no keyable backdrop and probably no silhouette either.
# Above: the formation is a speck and has no resolution to spend on facets.
KEYED_FRACTION_LIMITS = (0.35, 0.85)
# RGB standard deviation over the keyed region. A "flat magenta" that came back as
# a gradient or a vignette will fringe or eat the form.
BACKGROUND_FLATNESS_MAX = 0.04
# Mask area over bounding-box area. Only a FLOOR, deliberately: below this the
# form is a wisp with no silhouette.
#
# The obvious upper bound is wrong and was removed after it rejected a correct
# panel. A tabular shelf -- flat top, sheer sides, the clearest and most useful
# form in the reference -- genuinely fills nearly its whole bounding box, so any
# cap that catches "the backdrop never keyed" also catches the family this library
# most needs. The case a cap would have caught is already covered, and covered
# better, by KEYED_FRACTION_LIMITS: a panel whose backdrop never keyed has a
# keyed_fraction near zero, which is a direct measurement rather than an inference
# from silhouette shape.
MIN_FILL_RATIO = 0.20
# THE SHADOW TEST -- the one statistic that cleanly separates the target art from
# every previous raster round, and the only shape check here that is fatal.
#
# It has to be asked of the SOURCE, not of the built result: the build seats
# everything on [OUTPUT_FLOOR, OUTPUT_CEILING], so "fraction below 0.45" is zero by
# construction on the output and would be a check that can never fail. What the
# remap moves is the LEVEL; what it preserves is the SHAPE, so the shape is what
# gets measured, relative to the form's own median.
#
# Measured on the five formation crops of art_source/example.png:
#
#     crop            p1     med    p1/med   below 0.7*med
#     P4 shelf       0.719  0.801   0.897        0.00%
#     P3 spires      0.712  0.811   0.877        0.00%
#     P1 arch        0.726  0.809   0.897        0.00%
#     P2 range       0.737  0.804   0.917        0.00%
#     P3 spires L    0.646  0.823   0.785        0.00%
#
# Zero, on every one. The recorded failure had 7.5% of the form below 0.45
# absolute against a median near 0.80 -- i.e. 0.56 of median, deep inside a region
# the reference does not populate at all. So the ceiling below is generous and
# still unmissable, and the p1/med floor sits under the reference's own worst.
SHADOW_MEDIAN_FRACTION = 0.7
SHADOW_FRACTION_MAX = 0.02
MIN_P1_OVER_MEDIAN = 0.70

# Facet size, in ON-SCREEN px at the assumed height below. ADVISORY, not fatal.
# Measured on the reference at this gradient threshold, run-collapsed: the arch and
# the faceted range give 21px, the spires 11px, and the tabular shelf only 6px --
# its face is finely fluted, and that fluting is real content, not noise. The
# recorded ~5px failure sits barely under the reference's own tightest crop, so
# this number cannot carry a rejection on its own. It is reported because it is
# still the fastest way to notice a panorama that shrank every facet into noise.
FACET_GRADIENT = 0.03
MIN_FACET_ON_SCREEN = 6.0
# The height the sprite is assumed to be scaled to on screen, for that figure.
# MidRidge's mid target; override with --height=N.
DEFAULT_ON_SCREEN_HEIGHT = 90.0
# Advisory only: the build desaturates regardless, and colour was never the
# failure mode.
SATURATION_MAX = 0.35
# Advisory: visuals.md's 2x rule against the near layer's 150px max target.
MIN_TRIMMED_HEIGHT = 300


def key_background(rgb):
    """Split the image into a foreground alpha and a despilled RGB.

    Returns (rgb_despilled, alpha), both float in [0, 1].
    """
    magenta_excess = np.minimum(rgb[..., 0], rgb[..., 2]) - rgb[..., 1]
    # 1 where the pixel is subject, 0 where it is backdrop, feathered between.
    alpha = (KEY_EXCESS_BACKGROUND - magenta_excess) / (
        KEY_EXCESS_BACKGROUND - KEY_EXCESS_SUBJECT)
    alpha = np.clip(alpha, 0.0, 1.0)

    # Unpremultiply the feathered edge against the known backdrop, so a partly
    # keyed pixel carries the formation's own colour rather than a blend with
    # magenta. Exact if the generator composited linearly, approximate otherwise,
    # and either way the residual is confined to the 1-2px feather and is
    # desaturated away two steps later.
    safe_alpha = np.maximum(alpha, 1e-3)[..., None]
    despilled = (rgb - (1.0 - safe_alpha) * KEY_COLOR) / safe_alpha
    return np.clip(despilled, 0.0, 1.0), alpha


def clean_alpha(alpha):
    """Morphological opening, then a sub-pixel feather.

    Opening is erosion followed by dilation, which removes speckle smaller than
    the radius while leaving everything larger at its original size. Done through
    Pillow's Min/MaxFilter so this file keeps its two dependencies and does not
    pull in scipy, matching build_ice_texture.py's hand-rolled gaussian.

    Holes are deliberately NOT filled -- the reference's arch is a hole.
    """
    size = (SPECKLE_RADIUS * 2) + 1
    image = Image.fromarray((alpha * 255.0).astype(np.uint8))
    image = image.filter(ImageFilter.MinFilter(size)).filter(ImageFilter.MaxFilter(size))
    image = image.filter(ImageFilter.GaussianBlur(EDGE_FEATHER_RADIUS))
    return np.asarray(image, dtype=np.float64) / 255.0


def to_luminance(rgb):
    # Written out rather than `rgb @ LUMA_WEIGHTS`: matmul dispatches to BLAS,
    # which emits spurious divide/overflow warnings on the non-contiguous views
    # this file passes it. Same arithmetic, no dependency on array layout.
    return (rgb[..., 0] * LUMA_WEIGHTS[0]
            + rgb[..., 1] * LUMA_WEIGHTS[1]
            + rgb[..., 2] * LUMA_WEIGHTS[2])


def remap_band(luminance, mask):
    """Seat the formation's luminance on [OUTPUT_FLOOR, OUTPUT_CEILING] with its
    median at TARGET_MEDIAN.

    Percentile-anchored and masked, never min/max -- see the docstring. The gamma
    is solved rather than fixed because a straight linear remap preserves the
    source histogram's shape, and a 3D-render source's histogram is bottom-heavy,
    which is exactly the look being corrected.

    Returns (values, gamma, was_clamped).
    """
    if not mask.any():
        raise SystemExit("nothing survived the key -- is the backdrop magenta?")

    low, high = np.percentile(luminance[mask], BAND_PERCENTILES)
    if high - low < 1e-6:
        raise SystemExit("the formation is a flat colour -- no facets to keep")
    normalised = np.clip((luminance - low) / (high - low), 0.0, 1.0)

    target = (TARGET_MEDIAN - OUTPUT_FLOOR) / (OUTPUT_CEILING - OUTPUT_FLOOR)
    measured = float(np.median(normalised[mask]))
    measured = min(max(measured, 1e-3), 1.0 - 1e-3)
    gamma = float(np.log(target) / np.log(measured))
    clamped = not (GAMMA_LIMITS[0] <= gamma <= GAMMA_LIMITS[1])
    gamma = min(max(gamma, GAMMA_LIMITS[0]), GAMMA_LIMITS[1])

    values = OUTPUT_FLOOR + (np.power(normalised, gamma) * (OUTPUT_CEILING - OUTPUT_FLOOR))
    return values, gamma, clamped


def trim_to_content(values, alpha):
    """Crop to the alpha bounding box, leaving a fully transparent 2px margin so
    the feather is never clipped and Godot's fix_alpha_border has somewhere to
    bleed into."""
    rows = np.where(alpha.max(axis=1) > 0.02)[0]
    columns = np.where(alpha.max(axis=0) > 0.02)[0]
    if rows.size == 0 or columns.size == 0:
        raise SystemExit("nothing survived the key -- is the backdrop magenta?")

    top, bottom = rows[0], rows[-1] + 1
    left, right = columns[0], columns[-1] + 1
    values = values[top:bottom, left:right]
    alpha = alpha[top:bottom, left:right]
    return np.pad(values, 2, constant_values=OUTPUT_CEILING), np.pad(alpha, 2)


def fade_base(alpha):
    """Ramp alpha to zero over the bottom BASE_FADE_FRACTION of the form."""
    height = alpha.shape[0]
    fade_rows = max(1, int(round(height * BASE_FADE_FRACTION)))
    ramp = np.ones(height)
    ramp[height - fade_rows:] = np.linspace(1.0, 0.0, fade_rows)
    return alpha * ramp[:, None]


def resize_plane(plane, size):
    """Resample one float plane. Mode "F" so nothing is quantised to 8 bits until
    the final write -- the band is only 0.30 wide, i.e. ~77 of 255 levels, and
    there is no reason to spend any of them here."""
    image = Image.fromarray(plane.astype(np.float32))
    return np.asarray(image.resize(size, Image.LANCZOS), dtype=np.float64)


def fit_output_size(values, alpha):
    """Downscale so the longest edge is MAX_OUTPUT_EDGE. Never upscales.

    THE TWO PLANES ARE RESAMPLED SEPARATELY, and that is load-bearing rather than
    incidental. Pillow's resize() on an RGBA image is alpha-weighted: it treats
    the colour as premultiplied, so every fully transparent pixel comes back BLACK
    no matter what colour it held going in. Reproduced minimally -- a white RGBA
    image with a transparent half resamples to RGB 0 there under BILINEAR and to a
    ringing 0..255 under LANCZOS.

    That would silently undo the white fill in to_image() below, and reintroduce
    exactly the dark halo around the feathered edge that the fill exists to
    prevent. Resampling the planes independently keeps the two decisions separate,
    and to_image() then gets the last word on what transparent pixels carry.
    """
    height, width = values.shape
    longest = max(width, height)
    if longest <= MAX_OUTPUT_EDGE:
        return values, alpha, 1.0
    scale = MAX_OUTPUT_EDGE / float(longest)
    size = (max(1, int(round(width * scale))), max(1, int(round(height * scale))))
    return resize_plane(values, size), np.clip(resize_plane(alpha, size), 0.0, 1.0), scale


def to_image(values, alpha):
    """Assemble the RGBA output. Transparent pixels carry WHITE, not black, so
    there is no dark halo even if Godot's fix_alpha_border is ever turned off.

    Runs AFTER fit_output_size() -- see its docstring for why that ordering is not
    negotiable.
    """
    grey = np.clip(values, 0.0, 1.0)
    grey = np.where(alpha > 0.0, grey, OUTPUT_CEILING)
    channels = np.stack([grey, grey, grey, np.clip(alpha, 0.0, 1.0)], axis=-1)
    return Image.fromarray((channels * 255.0).round().astype(np.uint8))


def build(path):
    """The whole pipeline, in memory. Shared by the builder and --check, which is
    the point: ice_panels.md's hardest-won lesson is that "--check passing does
    not predict how much contrast survives the build", and it cost a whole panel
    round-trip on the ice tiles. Here the check measures the built result.
    """
    source = Image.open(path).convert("RGB")
    rgb = np.asarray(source, dtype=np.float64) / 255.0

    despilled, raw_alpha = key_background(rgb)
    alpha = clean_alpha(raw_alpha)
    mask = alpha >= SUBJECT_ALPHA

    luminance = to_luminance(despilled)
    values, gamma, gamma_clamped = remap_band(luminance, mask)

    values, alpha = trim_to_content(values, alpha)
    alpha = fade_base(alpha)
    values, alpha, scale = fit_output_size(values, alpha)
    image = to_image(values, alpha)

    return {
        "source": source,
        "source_rgb": rgb,
        "despilled": despilled,
        "raw_alpha": raw_alpha,
        "alpha": alpha,
        "values": values,
        "gamma": gamma,
        "gamma_clamped": gamma_clamped,
        "image": image,
        "scale": scale,
    }


def measure_facet_px(values, mask):
    """Median distance between facet edges along a row, inside the mask.

    This is "how wide is a flat face", the number the ~5px failure was measured
    on. Rows are scanned independently and their gaps pooled, so a tall formation
    with few vertical fractures is not dragged down by the handful of rows that
    cross a spire tip.

    RUNS OF ADJACENT STRONG GRADIENTS COLLAPSE TO ONE EDGE. Without that, a soft
    edge spanning four pixels registers as four separate edges one pixel apart and
    the median gap comes out at 1-2px no matter how broad the facets actually are
    -- which is what the first cut of this did, reporting 1px on reference art
    whose facets are 20px wide.
    """
    dx = np.abs(np.diff(values, axis=1))
    strong = (dx > FACET_GRADIENT) & mask[:, 1:]
    gaps = []
    for row_index in range(strong.shape[0]):
        edges = np.where(strong[row_index])[0]
        if edges.size < 2:
            continue
        edges = edges[np.insert(np.diff(edges) > 1, 0, True)]
        if edges.size >= 2:
            gaps.append(np.diff(edges))
    if not gaps:
        return float("inf")
    return float(np.median(np.concatenate(gaps)))


def measure(built, on_screen_height):
    """Every statistic --check reports, over the source and the built result."""
    raw_alpha = built["raw_alpha"]
    source_mask = raw_alpha >= SUBJECT_ALPHA
    keyed = raw_alpha < 0.1

    stats = {}
    stats["keyed_fraction"] = float(keyed.mean())
    stats["background_flatness"] = (
        float(built["source_rgb"][keyed].std(axis=0).max()) if keyed.any() else 0.0)

    columns = source_mask.any(axis=0)
    minimum_run = max(1, int(round(columns.size * 0.02)))
    runs, run = 0, 0
    for occupied in np.append(columns, False):
        if occupied:
            run += 1
        else:
            if run >= minimum_run:
                runs += 1
            run = 0
    stats["column_runs"] = runs

    rows = np.where(source_mask.any(axis=1))[0]
    cols = np.where(columns)[0]
    if rows.size and cols.size:
        box = (rows[-1] - rows[0] + 1) * (cols[-1] - cols[0] + 1)
        stats["fill_ratio"] = float(source_mask.sum()) / float(box)
        stats["trimmed_height"] = int(rows[-1] - rows[0] + 1)
    else:
        stats["fill_ratio"] = 0.0
        stats["trimmed_height"] = 0

    rgb = built["despilled"]
    if source_mask.any():
        subject = rgb[source_mask]
        top, bottom = subject.max(axis=1), subject.min(axis=1)
        saturation = np.where(top > 0, (top - bottom) / np.maximum(top, 1e-6), 0.0)
        stats["saturation_median"] = float(np.median(saturation))

        # THE SHADOW TEST, on the source -- see the constants for why it cannot be
        # asked of the built result.
        source_luminance = to_luminance(rgb)[source_mask]
        p1, median = np.percentile(source_luminance, (1.0, 50.0))
        stats["source_p1"] = float(p1)
        stats["source_median"] = float(median)
        stats["p1_over_median"] = float(p1 / max(median, 1e-6))
        stats["shadow_fraction"] = float(
            (source_luminance < SHADOW_MEDIAN_FRACTION * median).mean())
    else:
        stats["saturation_median"] = 0.0
        stats["source_p1"] = 0.0
        stats["source_median"] = 0.0
        stats["p1_over_median"] = 0.0
        stats["shadow_fraction"] = 1.0

    # Everything below is measured on the BUILT result, to confirm the remap seated
    # and that facets survived it.
    values, alpha = built["values"], built["alpha"]
    built_mask = alpha >= SUBJECT_ALPHA
    if built_mask.any():
        stats["built_percentiles"] = tuple(
            float(v) for v in np.percentile(values[built_mask], (1.0, 50.0, 95.0)))
        facet_px = measure_facet_px(values, built_mask)
        stats["facet_px"] = facet_px
        height = max(values.shape[0], 1)
        stats["facet_on_screen"] = facet_px * (on_screen_height / float(height))
    else:
        stats["built_percentiles"] = (0.0, 0.0, 0.0)
        stats["facet_px"] = float("inf")
        stats["facet_on_screen"] = float("inf")

    return stats


def report_build(path, built, stats, on_screen_height):
    """Print the measurements, then say whether the panel is usable.

    Same register as build_ice_texture.py's inspect_panel(): full explanatory
    sentences, warnings that never fail, exit 1 on any problem.
    """
    image = built["image"]
    print("panel       ", path, built["source"].size)
    print("keyed       ", "%.0f%% of frame is backdrop, flatness %.3f"
          % (stats["keyed_fraction"] * 100.0, stats["background_flatness"]))
    print("silhouette  ", "%d formation(s), fill ratio %.2f, %dpx tall in source"
          % (stats["column_runs"], stats["fill_ratio"], stats["trimmed_height"]))
    print("saturation  ", round(stats["saturation_median"], 3), "(desaturated by the build)")
    print("shadows     ", "source p1/med = %.3f (reference 0.79-0.92), %.2f%% below 0.7*med "
                          "(reference 0.00%%)"
          % (stats["p1_over_median"], stats["shadow_fraction"] * 100.0))
    print("gamma       ", round(built["gamma"], 3),
          "CLAMPED -- source histogram too far off to seat" if built["gamma_clamped"] else "")
    print("built band  ", "p1/med/p95 = %.2f/%.2f/%.2f  (target %.2f/%.2f/%.2f)"
          % (stats["built_percentiles"] + (OUTPUT_FLOOR, TARGET_MEDIAN, OUTPUT_CEILING)))
    print("facets      ", "%.0f source px -> %.1f px on screen at height %.0f"
          % (stats["facet_px"], stats["facet_on_screen"], on_screen_height))
    print("output      ", "%dx%d" % image.size, "(scaled %.2fx)" % built["scale"])

    problems = []
    if not (KEYED_FRACTION_LIMITS[0] <= stats["keyed_fraction"] <= KEYED_FRACTION_LIMITS[1]):
        problems.append(
            "%.0f%% of the frame keyed as backdrop, outside %.0f-%.0f%%. Too little means the "
            "formation fills the frame edge to edge and has no silhouette; too much means it is "
            "a speck with no resolution to spend on facets."
            % (stats["keyed_fraction"] * 100.0,
               KEYED_FRACTION_LIMITS[0] * 100.0, KEYED_FRACTION_LIMITS[1] * 100.0))
    if stats["background_flatness"] > BACKGROUND_FLATNESS_MAX:
        problems.append(
            "The backdrop is not flat (RGB std %.3f > %.3f). It came back as a gradient, a "
            "vignette or a cast shadow, and the key will either fringe or eat part of the form. "
            "Re-generate asking explicitly for a completely flat solid magenta #FF00FF."
            % (stats["background_flatness"], BACKGROUND_FLATNESS_MAX))
    if stats["column_runs"] != 1:
        problems.append(
            "Found %d separate formations in the frame, not 1. One formation per image is what "
            "keeps facets large: a crowded panorama makes the generator shrink every facet into "
            "noise, which is the recorded ~5px failure." % stats["column_runs"])
    if stats["fill_ratio"] < MIN_FILL_RATIO:
        problems.append(
            "Fill ratio %.2f is under the %.2f floor -- the form is a wisp, with too little "
            "silhouette to read at background scale."
            % (stats["fill_ratio"], MIN_FILL_RATIO))
    if stats["shadow_fraction"] > SHADOW_FRACTION_MAX:
        problems.append(
            "%.1f%% of the form sits below 0.7x its own median luminance, against a %.0f%% "
            "ceiling. Every crop of the reference art measures 0.00%% here. This is the recorded "
            "failure -- the last raster round put 7.5%% of the form in exactly this region and "
            "read as a shaded 3D render. The remap lifts the LEVEL; it cannot remove shadow "
            "STRUCTURE. Re-generate with no shadow side, no cast shadow and no ambient occlusion, "
            "and nothing darker than #B3B3B3."
            % (stats["shadow_fraction"] * 100.0, SHADOW_FRACTION_MAX * 100.0))
    elif stats["p1_over_median"] < MIN_P1_OVER_MEDIAN:
        problems.append(
            "The form's darkest percentile is %.2f of its median, under the %.2f floor (the "
            "reference holds 0.79-0.92). Its tonal range runs too deep to sit in a fogged "
            "background band, even though no single region is dark enough to trip the shadow "
            "test." % (stats["p1_over_median"], MIN_P1_OVER_MEDIAN))

    warnings = []
    if stats["facet_on_screen"] < MIN_FACET_ON_SCREEN:
        warnings.append(
            "Facets land at %.1f px on screen at height %.0f, under the %.0f px advisory floor. "
            "The reference measures 6px on its finely fluted tabular shelf and 11-21px on its "
            "spires, arch and range, so this cannot reject a panel on its own -- but the recorded "
            "failure was ~5px, so check the panel is one formation and not a crowded panorama."
            % (stats["facet_on_screen"], on_screen_height, MIN_FACET_ON_SCREEN))
    if stats["saturation_median"] > SATURATION_MAX:
        warnings.append(
            "Saturation %.2f is high, though the build desaturates it anyway and colour was "
            "never the failure mode." % stats["saturation_median"])
    if stats["trimmed_height"] < MIN_TRIMMED_HEIGHT:
        warnings.append(
            "Only %dpx tall in the source. visuals.md wants raster art at ~2x its world size, "
            "and the near layer's tallest formation is ~150 viewport px."
            % stats["trimmed_height"])
    if built["gamma_clamped"]:
        warnings.append(
            "The gamma that would seat the median hit its clamp, so the built band is off "
            "target. The source histogram is far from the reference's shape.")

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
    print("OK -- build it with:  python3 scripts/tools/build_iceberg_sprites.py", path)
    return 0


def default_output_path(source_path):
    stem = os.path.splitext(os.path.basename(source_path))[0]
    return os.path.join(DEFAULT_OUTPUT_DIR, stem + ".png")


def parse_height(argv):
    """Pull an optional --height=N out of argv, returning (height, rest)."""
    height, rest = DEFAULT_ON_SCREEN_HEIGHT, []
    for argument in argv:
        if argument.startswith("--height="):
            height = float(argument.split("=", 1)[1])
        else:
            rest.append(argument)
    return height, rest


def main():
    on_screen_height, argv = parse_height(sys.argv[1:])

    if argv and argv[0] == "--check":
        if len(argv) != 2:
            raise SystemExit(__doc__)
        built = build(argv[1])
        raise SystemExit(report_build(argv[1], built, measure(built, on_screen_height),
                                      on_screen_height))

    if len(argv) not in (1, 2):
        raise SystemExit(__doc__)
    source_path = argv[0]
    output_path = argv[1] if len(argv) == 2 else default_output_path(source_path)

    built = build(source_path)
    stats = measure(built, on_screen_height)
    status = report_build(source_path, built, stats, on_screen_height)
    if status != 0:
        print()
        print("Refusing to write. Fix the source and re-run --check.")
        raise SystemExit(status)

    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
    built["image"].save(output_path, optimize=True)
    print("wrote       ", output_path, "%dx%d" % built["image"].size)


if __name__ == "__main__":
    main()
