#!/usr/bin/env python3
"""Turn a hand-stitched ice panorama into a game-ready looping background strip.

    python3 scripts/tools/build_pano_strip.py --check art_source/background/arch_spike_massif.png
    python3 scripts/tools/build_pano_strip.py art_source/background/arch_spike_massif.png
    python3 scripts/tools/build_pano_strip.py art_source/background/arch_spike_massif.png assets/textures/background/ice_pano.png

The output path is optional and defaults to assets/textures/background/<stem>.png.

Sources live in art_source/, which carries a .gdignore -- the repo root and assets/
both ship, art_source/ does not. Same rule as build_ice_texture.py and
build_iceberg_sprites.py.

WHAT THE SOURCE MUST BE
    ONE wide, already-stitched panorama of ice formations over water, opaque RGB,
    with its own sky baked in. Nothing is keyed out by hand and nothing is painted
    on a flat backdrop -- this file's whole job is to separate that baked sky from
    the ice using nothing but the pixels.

    Everything pale, the way art_source/background/example.png is pale: the ice is
    a narrow bright band, and NOTHING in the frame is dark. --check enforces that.

WHY THIS IS A SEPARATE FILE FROM build_iceberg_sprites.py
    That tool takes ONE formation, alone, on a solid magenta backdrop, and emits a
    small sprite to be scattered on a grid. Three of its assumptions are false here
    and each would be a bug:

      * ITS KEY IS A COLOUR. Magenta excess, min(R,B) - G, works because the
        backdrop is a colour no ice ever is. This source's backdrop is a SKY --
        pale blue, i.e. exactly what ice is -- so no colour key can separate them.
        The key here is spatial instead: see THE SKY MODEL below.
      * IT HAS NO SEAM. "A formation is an island placed on a grid; it has no wrap."
        A panorama is the opposite: it is a loop, and its wrap is the one seam that
        can ruin it. make_loop_seamless() exists here for that reason.
      * ITS ALPHA IS BINARY, feathered only to kill stair-stepping. Here PARTIAL
        ALPHA IS THE CONTENT. In the reference the ice does not end, it dissolves
        into fog, and that dissolve is the single strongest depth cue in the art.

THE SKY MODEL, AND WHY IT IS NOT A PER-ROW MEDIAN
    Alpha comes from how far a pixel sits BELOW its own local sky, so the ice --
    which is uniformly darker than the sky behind it -- keys out and the fog keys
    out proportionally, coming through as the partial alpha the look depends on.

    The obvious version, one sky value per row taken across the whole width, fails
    on a hand-stitched source. The panels were generated separately and their skies
    differ by a few units, so a single per-row value is wrong by that much on two
    of the three panels, and the error prints as FAINT RECTANGLES in the sky, one
    per panel, invisible in the source and clearly visible once a biome multiplies
    the layer. Measured on the first cut of this file: exactly that.

    So the sky is estimated LOCALLY -- a high percentile per row within each column
    block, smoothed across blocks -- which tracks a panel step as easily as it
    tracks a gradient. The remaining low-level error is removed by ALPHA_DEADZONE
    rather than by trusting the model to be exact.

WHY THE OUTPUT KEEPS ITS COLOUR, UNLIKE THE OTHER TWO BAKE TOOLS
    The strip hangs under a `modulate` carrying the biome's scenery colour and Godot
    renders texture * modulate, so what is stored here is a MULTIPLIER. Its LUMINANCE
    is seated on a fixed bright band, which is what makes all eight palettes work.

    Its HUE, though, is the source painting's own, and that is a deliberate departure
    from build_ice_texture.py and build_iceberg_sprites.py, which both store
    greyscale. Those store greyscale to survive being multiplied by a warm palette;
    measured, this palette set has no warm entry -- all nine scenery_far colours are
    blue-dominant -- so there is nothing for greyscale to defend against here, and
    it costs the difference between reading as ice and reading as rock.

    Shipped grey once before this was understood. See CHROMA_STRENGTH for the
    numbers and for the gamut cost that comes with it.

WHAT THE ALPHA BUYS BEYOND THE LOOK -- READ THIS BEFORE MAKING IT OPAQUE
    SkyBackdrop is CanvasLayer -200 and ParallaxBackground is -100, so the sun, the
    moon, the stars and the planned aurora ALL draw behind this strip. The source is
    opaque RGB with a sky in it; shipped as-is it covers every one of them.

    docs/development/visuals.md, "There has to BE a sky", records this bug already:
    the parallax layers once covered the frame edge to edge and all four sun discs
    measured 0/255 on screen. Keying the sky to alpha is what prevents a repeat --
    the ice stays opaque and still occludes the sun, while the fog passes it through
    at partial alpha, which is what fog does.
"""

import os
import sys

import numpy as np
from PIL import Image

DEFAULT_OUTPUT_DIR = "assets/textures/background"

# --- The sky model ---------------------------------------------------------
# Column block width, in source px, that the per-row sky percentile is taken
# over. Small enough to track a panel step, wide enough that a formation cannot
# dominate the sample.
SKY_BLOCK_WIDTH = 64
# Percentile within a block. High, not the median: in a row crossing the ice the
# ice is a large minority, and the sky is what is left ABOVE it.
SKY_PERCENTILE = 80.0
# Blocks averaged across, centred. 11 x 64 = 704px of context -- comfortably
# wider than the widest formation here, so no single mass can pull the estimate
# down onto itself.
SKY_SMOOTH_BLOCKS = 11

# --- Alpha -----------------------------------------------------------------
# Luminance below local sky at which alpha starts. Everything under this is sky
# or residual sky-model error, and is discarded. Measured on this source: the
# sky's own noise and the post-model panel residue both sit under 0.008.
ALPHA_DEADZONE = 0.010
# Departure, above the deadzone, at which alpha reaches 1. The fog occupies this
# range, so widening it makes the strip more ghostly and narrowing it more solid.
ALPHA_SCALE = 0.05
# Alpha at or above which a pixel counts as "the ice" for every statistic below.
SUBJECT_ALPHA = 0.5

# --- Levels ----------------------------------------------------------------
# NOT the same band as build_iceberg_sprites.py, and the difference is a bug that
# shipped once. That tool builds NEAR-layer sprites on [0.70, 1.00]; this is the
# FAR layer, where the requirement inverts.
#
# WHY A TEXTURED FAR LAYER NEEDS A HIGHER BAND THAN A PROCEDURAL ONE
#
#   background_generator.gd renders its ridges FLAT -- ridge.color is WHITE and
#   ridges_root.modulate carries the palette colour -- so a procedural layer's
#   on-screen lightness IS its palette colour, exactly. A textured layer renders
#   texture * colour, so its average lightness is the band's median TIMES that
#   colour, i.e. always darker than a flat layer at the same palette entry.
#
#   visuals.md's depth read depends on far = lighter, with FarRidge the lightest
#   scenery and PineLine the darkest. This layer sits at depth_t 0.0 and so already
#   gets scenery_far, the lightest colour a palette offers; there is no lighter
#   entry to reach for, and a texture can only multiply DOWN. So if the band is
#   low, the FURTHEST layer renders darker than the near ones and the whole depth
#   ordering inverts.
#
#   Measured in game on the [0.70, 1.00] band, first attempt: sky 0.771, ice 0.623,
#   MidRidge 0.704, PineLine 0.735 -- the far layer was the darkest thing on screen
#   and read as rock, which is the exact failure the reverted procedural session
#   ended on.
#
#   The band below targets a rendered median of ~0.74: comfortably lighter than
#   MidRidge's 0.704, still darker than the sky's 0.771 so the ice stays visible,
#   with its brightest facets going above the sky as lit highlights. The narrow
#   range is also what the reference looks like -- in example.png the ice is barely
#   visible, low contrast and half dissolved into the sky.
OUTPUT_FLOOR = 0.78
OUTPUT_CEILING = 0.95
TARGET_MEDIAN = 0.86

# --- Chroma ----------------------------------------------------------------
# How much of the SOURCE's own hue is kept, 0 = pure greyscale, 1 = the painting's
# full cast. This is the difference between ice and rock on screen and it was set
# to 0 for the first two cuts, which is why the shipped strip read grey.
#
# WHY GREYSCALE WAS WRONG HERE, HAVING BEEN RIGHT EVERYWHERE ELSE
#
#   build_ice_texture.py and build_iceberg_sprites.py both store greyscale, on the
#   rule that baked art must survive being multiplied by eight biome palettes and
#   so cannot carry colour of its own. That rule defends against ONE failure: cool
#   art times a warm tint, which goes muddy.
#
#   Measured, this palette set contains no warm entry. All nine scenery_far colours
#   are blue-dominant -- the reddest, mauve_haze at (0.72, 0.68, 0.78), still has
#   blue on top. There is no cool-times-warm case to defend against, so the rule
#   costs the look and buys nothing.
#
#   What greyscale actually cost: the source ice measures saturation 0.206, and
#   scenery_far averages 0.15, so greyscale x tint rendered at 0.12 -- grey. Keeping
#   the source cast puts the ice near 0.30 and it reads as ice again.
#
# THE CEILING ABOVE IS WHY THIS COSTS SOMETHING. Preserving hue at a fixed
# luminance means the brightest channel runs above that luminance: this source's
# blue sits at 1.143x its own luma, peaking at 1.215x. At the previous band median
# of 0.88 the blue channel would have crossed 1.0 on half the ice and clipped back
# toward grey -- the exact thing being fixed. So the band drops to a median of 0.86
# under a 0.95 ceiling, which keeps the typical blue at 0.98, inside gamut.
#
# The top of the band still clips, deliberately and only there: 0.95 x 1.143 is
# 1.09, so the brightest facet edges lose blue and go white. That is what an ice
# highlight should do, so it is left alone rather than compressed.
CHROMA_STRENGTH = 1.0
# Percentiles the source's own band is normalised on. Not min/max -- one stray
# bright pixel would set the range and collapse the band.
BAND_PERCENTILES = (2.0, 98.0)
# A clamp hit means the source histogram was too far off to seat, which is worth
# being told rather than discovering in game, so it is printed.
GAMMA_LIMITS = (0.4, 2.5)

# Rec.601, matching scripts/debug/biome_schedule_check.gd, so a number printed
# here is the same quantity the gate measures.
LUMA_WEIGHTS = (0.299, 0.587, 0.114)

# --- The loop seam ---------------------------------------------------------
# Width, in source px, over which the right edge is ramped onto the left edge's
# values so the strip wraps invisibly.
#
# A CROSS-FADE IS THE WRONG TOOL HERE and was rejected: it would blend the massif
# at the right edge onto the arch at the left, ghosting two distinct formations
# into each other over the whole margin. This source's wrap mismatch was measured
# at mean 3.5/255 (max 37, in one band at the horizon) -- small enough that simply
# ADDING a linearly-tapering correction closes it with no ghosting at all, at the
# cost of a sub-1% brightness gradient nobody can see. If a future panorama comes
# in with a genuinely large mismatch, fix it in GIMP; do not widen this.
SEAM_RAMP_WIDTH = 256

# --- Thresholds for --check ------------------------------------------------
# Fraction of the frame that keys to sky. Below: the ice fills the frame and there
# is no sky to key, so the sun would be covered anyway. Above: the panorama is
# mostly empty and there is barely any art in it.
SKY_FRACTION_LIMITS = (0.45, 0.95)
# A panorama is wide by definition. A squarer image is a single panel that was
# never stitched, or the wrong file.
MIN_ASPECT_RATIO = 2.0
# Saturation over the ice. NOT a near-greyscale requirement -- the build keeps the
# source's hue on purpose (see CHROMA_STRENGTH), and example.png, the target art,
# measures ~0.19 here itself. This is only a guard against a garish source: past
# this the cast starts fighting the biome tint it gets multiplied by rather than
# riding it, and no palette in this game is saturated enough to absorb that.
SUBJECT_SATURATION_MAX = 0.45
# THE SHADOW TEST, asked of the SOURCE for the same reason build_iceberg_sprites.py
# gives: the build seats everything on [OUTPUT_FLOOR, OUTPUT_CEILING], so an
# absolute darkness test on the RESULT is zero by construction and could never
# fire. What the remap moves is the LEVEL; what it preserves is the SHAPE.
SHADOW_MEDIAN_FRACTION = 0.7
SHADOW_FRACTION_MAX = 0.02
# Residual alpha left in the top rows after keying. This is the sun test: whatever
# is here is a veil drawn over the sky, and the sky is where the sun, the moon and
# the planned aurora live.
SKY_BAND_FRACTION = 0.2
SKY_BAND_ALPHA_MAX = 0.02


def to_luminance(rgb):
    """Rec.601 luminance. Written out rather than via matmul, which dispatches to
    BLAS and warns on the non-contiguous views this file passes it."""
    return (
        rgb[..., 0] * LUMA_WEIGHTS[0]
        + rgb[..., 1] * LUMA_WEIGHTS[1]
        + rgb[..., 2] * LUMA_WEIGHTS[2]
    )


def to_saturation(rgb):
    largest = rgb.max(axis=-1)
    smallest = rgb.min(axis=-1)
    return np.where(largest > 0.0, (largest - smallest) / np.maximum(largest, 1e-6), 0.0)


def estimate_sky(luminance):
    """Per-pixel local sky luminance. See THE SKY MODEL in the docstring."""
    height, width = luminance.shape
    block_count = max(1, width // SKY_BLOCK_WIDTH)
    usable = block_count * SKY_BLOCK_WIDTH
    blocks = luminance[:, :usable].reshape(height, block_count, SKY_BLOCK_WIDTH)
    per_block = np.percentile(blocks, SKY_PERCENTILE, axis=2)

    # Smooth across blocks with a centred box, edge-padded so the first and last
    # blocks are not dragged toward the middle of the image.
    half = SKY_SMOOTH_BLOCKS // 2
    padded = np.pad(per_block, ((0, 0), (half, half)), mode="edge")
    smoothed = np.empty_like(per_block)
    for block_index in range(block_count):
        smoothed[:, block_index] = padded[
            :, block_index : block_index + SKY_SMOOTH_BLOCKS
        ].mean(axis=1)

    # Nearest-block lookup per column. The field is already smooth at block scale,
    # so interpolating between blocks would change nothing visible.
    column_blocks = np.clip(np.arange(width) // SKY_BLOCK_WIDTH, 0, block_count - 1)
    return smoothed[:, column_blocks]


def build_alpha(luminance, sky_luminance):
    departure = sky_luminance - luminance
    return np.clip((departure - ALPHA_DEADZONE) / ALPHA_SCALE, 0.0, 1.0)


def recover_subject_color(rgb, alpha, sky_rgb):
    """Undo the fog blend.

    Every pixel in the source is already composited: pixel = ice*a + sky*(1-a).
    Godot will composite the result the same way against whatever is behind the
    layer, so what gets STORED has to be the ice, not the composite -- otherwise
    the fog is applied twice and the strip reads milky.

    Where alpha is small the division is unstable (and meaningless, since almost
    none of that pixel is ice), so it is only applied where there is enough alpha
    to invert, and blended in over the transition rather than switched on.
    """
    safe_alpha = np.maximum(alpha, 1e-3)[..., None]
    recovered = (rgb - sky_rgb * (1.0 - alpha[..., None])) / safe_alpha
    # Trust the inversion fully at alpha 1, not at all near 0.
    trust = np.clip(alpha, 0.0, 1.0)[..., None]
    blended = recovered * trust + rgb * (1.0 - trust)
    return np.clip(blended, 0.0, 1.0)


def remap_levels(luminance, subject_mask):
    """Seat the ice's own band on [OUTPUT_FLOOR, OUTPUT_CEILING] with its median at
    TARGET_MEDIAN. Every statistic runs over MASKED pixels only, and on
    percentiles rather than extremes."""
    subject = luminance[subject_mask]
    low, high = np.percentile(subject, BAND_PERCENTILES)
    if high - low < 1e-4:
        print("  WARNING: the ice has almost no internal contrast; levels skipped.")
        return np.clip(luminance, OUTPUT_FLOOR, OUTPUT_CEILING)

    normalized = np.clip((luminance - low) / (high - low), 0.0, 1.0)

    # Gamma that puts the masked median where TARGET_MEDIAN wants it.
    median = float(np.median(normalized[subject_mask]))
    target = (TARGET_MEDIAN - OUTPUT_FLOOR) / (OUTPUT_CEILING - OUTPUT_FLOOR)
    if median <= 0.0 or median >= 1.0:
        gamma = 1.0
    else:
        gamma = float(np.log(target) / np.log(median))
    clamped = float(np.clip(gamma, *GAMMA_LIMITS))
    if abs(clamped - gamma) > 1e-6:
        print(
            "  WARNING: gamma %.3f clamped to %.3f -- the source histogram is far "
            "enough off that the band could not be seated." % (gamma, clamped)
        )
    return OUTPUT_FLOOR + np.power(normalized, clamped) * (OUTPUT_CEILING - OUTPUT_FLOOR)


def apply_source_chroma(value, ice_rgb, subject_mask):
    """Put the source painting's hue back onto the seated luminance.

    The ratio is normalised BY THE SOURCE'S OWN LUMINANCE, which is what makes this
    safe to do after remap_levels: multiplying a luminance by a ratio whose luminance
    is 1 leaves the luminance alone. So the far-lighter depth ordering that the band
    was tuned for survives having colour added, and the two decisions stay separable.

    Reported rather than silent: how much of the ice ends up out of gamut, because
    that is the number that says whether the band and CHROMA_STRENGTH still agree.
    Some clipping is intended and only at the very top -- see the CHROMA_STRENGTH
    comment -- but a large figure means the band crept back up and the cast is being
    quietly flattened toward grey again.
    """
    if CHROMA_STRENGTH <= 0.0:
        return np.repeat(value[..., None], 3, axis=2)

    source_luminance = np.maximum(to_luminance(ice_rgb), 1e-4)
    ratio = ice_rgb / source_luminance[..., None]
    ratio = 1.0 + (ratio - 1.0) * CHROMA_STRENGTH

    tinted = value[..., None] * ratio
    if subject_mask.any():
        out_of_gamut = float((tinted[subject_mask] > 1.0).mean())
        saturation = float(to_saturation(np.clip(tinted, 0.0, 1.0))[subject_mask].mean())
        print(
            "  chroma: strength %.2f, ice saturation %.3f, %.1f%% of ice channels clipped"
            % (CHROMA_STRENGTH, saturation, out_of_gamut * 100.0)
        )
    return np.clip(tinted, 0.0, 1.0)


def make_loop_seamless(value, alpha):
    """Ramp the right edge onto the left edge's values. See THE LOOP SEAM."""
    width = value.shape[1]
    ramp_width = min(SEAM_RAMP_WIDTH, width // 4)
    if ramp_width < 2:
        return value, alpha, 0.0

    before = float(np.abs(value[:, -1] - value[:, 0]).mean())

    # 0 at the start of the margin, 1 at the last column, so only the wrap moves.
    # value carries a colour plane (h, w, 3) while alpha is (h, w), so the taper
    # needs a trailing axis to broadcast against the former.
    taper = (np.arange(ramp_width) / float(ramp_width - 1))[None, :]
    colour_taper = taper[..., None]

    value_delta = (value[:, 0] - value[:, -1])[:, None]
    value = value.copy()
    value[:, -ramp_width:] = np.clip(
        value[:, -ramp_width:] + value_delta * colour_taper, 0.0, 1.0
    )

    alpha_delta = (alpha[:, 0] - alpha[:, -1])[:, None]
    alpha = alpha.copy()
    alpha[:, -ramp_width:] = np.clip(alpha[:, -ramp_width:] + alpha_delta * taper, 0.0, 1.0)

    after = float(np.abs(value[:, -1] - value[:, 0]).mean())
    print(
        "  loop seam: mean |right - left| %.1f/255 -> %.1f/255 over a %dpx ramp"
        % (before * 255.0, after * 255.0, ramp_width)
    )
    return value, alpha, before


def print_placement(alpha):
    """The two source rows BackgroundStrip needs to place this texture.

    The strip is positioned in the scene by naming where its SKYLINE and its
    WATERLINE should land as fractions of viewport height; the script then derives
    both scale and offset from those two, which means it needs to know which rows
    of this particular texture they are. They are a property of the art, not of the
    game, so they are measured here and typed into main.tscn rather than hardcoded
    in the script -- a re-baked or replaced panorama just reprints them.
    """
    height = alpha.shape[0]
    solid_rows = np.where((alpha >= SUBJECT_ALPHA).any(axis=1))[0]
    if solid_rows.size == 0:
        return
    skyline = int(solid_rows.min())
    horizon = int(np.argmax((alpha >= SUBJECT_ALPHA).mean(axis=1)))
    print(
        "  placement for main.tscn: source_skyline_y = %d, source_horizon_y = %d"
        % (skyline, horizon)
    )
    print(
        "    (skyline is the tallest ice at %.3f of texture height, waterline at %.3f;"
        % (skyline / float(height), horizon / float(height))
    )
    print(
        "     everything above row %d is empty sky and costs VRAM -- see BackgroundStrip)"
        % skyline
    )


def load_source(path):
    image = Image.open(path)
    rgb = np.asarray(image.convert("RGB")).astype(np.float32) / 255.0
    return image, rgb


def check(path):
    """Refuse a panorama that cannot work, and say which measurement refused it."""
    image, rgb = load_source(path)
    height, width, _ = rgb.shape
    print("%s  %dx%d  %s" % (os.path.basename(path), width, height, image.mode))

    failures = []

    aspect = width / float(height)
    print("  aspect ratio            %.2f   (need >= %.2f)" % (aspect, MIN_ASPECT_RATIO))
    if aspect < MIN_ASPECT_RATIO:
        failures.append("not a panorama -- too square to be a stitched strip")

    luminance = to_luminance(rgb)
    sky_luminance = estimate_sky(luminance)
    alpha = build_alpha(luminance, sky_luminance)
    subject_mask = alpha >= SUBJECT_ALPHA

    sky_fraction = float((alpha <= 0.0).mean())
    print(
        "  keyed to sky            %.3f   (want %.2f-%.2f)"
        % (sky_fraction, *SKY_FRACTION_LIMITS)
    )
    if not SKY_FRACTION_LIMITS[0] <= sky_fraction <= SKY_FRACTION_LIMITS[1]:
        failures.append("sky fraction outside the workable range")

    subject_pixels = int(subject_mask.sum())
    if subject_pixels == 0:
        print("  FAIL: nothing keyed as ice at all.")
        return False

    saturation = float(to_saturation(rgb)[subject_mask].mean())
    print(
        "  ice saturation          %.3f   (need <= %.2f)"
        % (saturation, SUBJECT_SATURATION_MAX)
    )
    if saturation > SUBJECT_SATURATION_MAX:
        failures.append("ice too saturated to survive the biome multiply")

    subject_luminance = luminance[subject_mask]
    median = float(np.median(subject_luminance))
    shadow_fraction = float(
        (subject_luminance < median * SHADOW_MEDIAN_FRACTION).mean()
    )
    print(
        "  ice luminance p1/median %.3f / %.3f" % (np.percentile(subject_luminance, 1), median)
    )
    print(
        "  below %.1fx its median   %.4f   (need <= %.3f)"
        % (SHADOW_MEDIAN_FRACTION, shadow_fraction, SHADOW_FRACTION_MAX)
    )
    if shadow_fraction > SHADOW_FRACTION_MAX:
        failures.append("there is shading dark enough to read as a 3D render")

    # The sun test. Anything left in the top band veils the sky.
    band_rows = max(1, int(height * SKY_BAND_FRACTION))
    band_alpha = float(alpha[:band_rows].mean())
    print(
        "  alpha in the top %.0f%%    %.4f   (need <= %.3f)"
        % (SKY_BAND_FRACTION * 100.0, band_alpha, SKY_BAND_ALPHA_MAX)
    )
    if band_alpha > SKY_BAND_ALPHA_MAX:
        failures.append("residual haze over the sky -- the sun would be veiled")

    seam = float(np.abs(rgb[:, -1] - rgb[:, 0]).mean())
    print("  wrap mismatch           %.1f/255  (ramped out at build time)" % (seam * 255.0))

    if failures:
        for failure in failures:
            print("  FAIL: %s" % failure)
        return False
    print("  OK")
    return True


def build(source_path, output_path):
    image, rgb = load_source(source_path)
    height, width, _ = rgb.shape
    print("%s  %dx%d  %s" % (os.path.basename(source_path), width, height, image.mode))

    luminance = to_luminance(rgb)
    sky_luminance = estimate_sky(luminance)
    alpha = build_alpha(luminance, sky_luminance)
    subject_mask = alpha >= SUBJECT_ALPHA
    if not subject_mask.any():
        print("  FAIL: nothing keyed as ice. Run --check on this source.")
        return False
    print("  keyed: %.1f%% sky, %.1f%% ice, %.1f%% fog"
          % ((alpha <= 0.0).mean() * 100.0,
             subject_mask.mean() * 100.0,
             ((alpha > 0.0) & ~subject_mask).mean() * 100.0))

    # The sky the fog was blended against, per pixel, as a colour rather than a
    # luminance -- recover_subject_color has to subtract the actual sky RGB.
    sky_scale = np.where(luminance > 1e-4, sky_luminance / np.maximum(luminance, 1e-4), 1.0)
    sky_rgb = np.clip(rgb * sky_scale[..., None], 0.0, 1.0)

    ice_rgb = recover_subject_color(rgb, alpha, sky_rgb)

    # Seat the LUMINANCE on the bright band, then put the source's own hue back on
    # top of it. Luminance is what the far-lighter depth ordering is judged on and
    # what remap_levels controls; hue rides along without changing it, because the
    # ratio below is normalised by that same luminance.
    #
    # Both steps run AFTER the fog is undone, so the fog's tint enters neither the
    # levels statistics nor the hue.
    value = to_luminance(ice_rgb)
    value = remap_levels(value, subject_mask)
    value_rgb = apply_source_chroma(value, ice_rgb, subject_mask)

    value_rgb, alpha, _ = make_loop_seamless(value_rgb, alpha)

    seated = value[subject_mask]
    print("  built ice band: p2 %.3f  median %.3f  p98 %.3f"
          % (*np.percentile(seated, [2.0, 50.0]), np.percentile(seated, 98.0)))
    print_placement(alpha)

    rgba = np.zeros((height, value.shape[1], 4), dtype=np.float32)
    # White where alpha is zero, not black: Pillow's resize() is alpha-weighted on
    # RGBA, so a transparent pixel that holds black comes back black and reappears
    # as a dark halo the moment anything resamples this texture. Godot's mipmapper
    # has the same property.
    rgba[..., :3] = value_rgb
    rgba[..., 3] = alpha

    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
    Image.fromarray((np.clip(rgba, 0.0, 1.0) * 255.0).astype(np.uint8)).save(output_path)
    vram_mb = rgba.shape[0] * rgba.shape[1] * 4 / (1024.0 * 1024.0)
    print("  wrote %s  (%dx%d, %.1fMB VRAM uncompressed)"
          % (output_path, rgba.shape[1], rgba.shape[0], vram_mb))
    return True


def main(argv):
    args = [argument for argument in argv[1:] if argument != "--check"]
    checking = "--check" in argv[1:]

    if not args:
        print(__doc__.strip().splitlines()[0])
        print("usage: build_pano_strip.py [--check] <source.png> [output.png]")
        return 2

    source_path = args[0]
    if not os.path.exists(source_path):
        print("no such file: %s" % source_path)
        return 2

    if checking:
        return 0 if check(source_path) else 1

    if len(args) > 1:
        output_path = args[1]
    else:
        stem = os.path.splitext(os.path.basename(source_path))[0]
        output_path = os.path.join(DEFAULT_OUTPUT_DIR, "%s.png" % stem)

    return 0 if build(source_path, output_path) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
