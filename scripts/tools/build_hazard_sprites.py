#!/usr/bin/env python3
"""Bake the three hazard sprites from their art_source/ originals.

    python3 scripts/tools/build_hazard_sprites.py

Sources are art_source/hazards/<kind>_source.png: light-greyscale generations on real alpha,
so obstacle.gd can MULTIPLY each biome's obstacle_color over them (the coin's contract). Same
art_source -> assets rule as build_app_icons.py and build_ice_texture.py.

THE SPRITE IS THE HITBOX. Each source is cropped to its solid silhouette (alpha >= 128) and
stretched to exactly 3x its PIECE_KINDS box, so the scene scales it by 1/3 and the drawn
edge lands on the box edge (and, for spike and shard, on the outline printed below). Change a hitbox and its row here together, or the art
stops telling the player where the danger is. The faint halo the generator leaves outside the
silhouette is dropped below SOFT_ALPHA_FLOOR rather than shipped as a grey smear.

Thin ice is different: a STRIP tiled along ThinIce's Line2D, so only its height is fixed (the
line's OVERLAY_WIDTH) and its length follows the source's aspect. The generator's "seamless"
ends never quite match, so the last SEAM_FRACTION is crossfaded over the first and dropped.
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = ROOT / "art_source" / "hazards"
OUTPUT_DIR = ROOT / "assets" / "sprites" / "hazards"
# Authored at 3x world size (visuals.md, "Authoring raster art").
SCALE = 3
# kind -> hitbox in world px, matching scenes/obstacles/<scene>.tscn.
HAZARDS = {
    "spike": (32, 32),
    "floe": (32, 136),
    "shard": (32, 32),
}
# Must equal ThinIce.OVERLAY_WIDTH.
THIN_ICE_BAND_HEIGHT = 8
SEAM_FRACTION = 0.1
SOLID_ALPHA = 128
SOFT_ALPHA_FLOOR = 16


def load_cropped(kind: str) -> Image.Image:
    image = Image.open(SOURCE_DIR / f"{kind}_source.png").convert("RGBA")
    alpha = image.getchannel("A")
    image.putalpha(alpha.point(lambda a: 0 if a < SOFT_ALPHA_FLOOR else a))
    solid = alpha.point(lambda a: 255 if a >= SOLID_ALPHA else 0).getbbox()
    if solid is None:
        raise SystemExit(f"{kind}: source has no solid pixels")
    return image.crop(solid)


def save(kind: str, image: Image.Image) -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    image.save(OUTPUT_DIR / f"{kind}.png", optimize=True)
    print(f"{kind}: -> {image.size}")


def bake(kind: str, hitbox: tuple[int, int]) -> None:
    size = (hitbox[0] * SCALE, hitbox[1] * SCALE)
    baked = load_cropped(kind).resize(size, Image.LANCZOS)
    save(kind, baked)
    if kind in OUTLINED:
        print_outline(kind, baked)


# The pointed kinds collide on their silhouette, not their box: a spike covers 48% of its
# 32x32 and the shard 37%, so a rectangle killed on empty air at its corners. This prints the
# convex hull of the opaque pixels, in world px about the node origin, for the scene's
# ConvexPolygonShape2D (paste it after a re-bake). The hull lies inside the PIECE_KINDS box,
# so every fairness proof run on the box still holds: a line that clears the box clears this.
OUTLINED = ("spike", "shard")
OUTLINE_MAX_POINTS = 10


def convex_hull(points: list[tuple[float, float]]) -> list[tuple[float, float]]:
    points = sorted(set(points))
    cross = lambda o, a, b: (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower: list[tuple[float, float]] = []
    upper: list[tuple[float, float]] = []
    for p in points:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(points):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def print_outline(kind: str, image: Image.Image) -> None:
    alpha = image.getchannel("A")
    corners = []
    for y in range(image.height):
        for x in range(image.width):
            if alpha.getpixel((x, y)) >= SOLID_ALPHA:
                corners += [(x, y), (x + 1, y), (x, y + 1), (x + 1, y + 1)]
    hull = convex_hull(corners)
    # Drop the vertex whose removal loses the least area until few enough remain. Removing a
    # convex vertex only ever shrinks the polygon, so it stays inside the hull and the box.
    triangle = lambda a, b, c: abs((b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1]))
    while len(hull) > OUTLINE_MAX_POINTS:
        n = len(hull)
        i = min(range(n), key=lambda k: triangle(hull[k - 1], hull[k], hull[(k + 1) % n]))
        hull.pop(i)
    world = [(x / SCALE - image.width / SCALE / 2, y / SCALE - image.height / SCALE / 2) for x, y in hull]
    print(f"  {kind} outline: PackedVector2Array("
          + ", ".join(f"{x:g}, {y:g}" for x, y in world) + ")")


def bake_thin_ice() -> None:
    strip = load_cropped("thin_ice")
    height = THIN_ICE_BAND_HEIGHT * SCALE
    width = round(strip.width * height / strip.height)
    seam = round(width * SEAM_FRACTION)
    strip = strip.resize((width + seam, height), Image.LANCZOS)
    # The tail fades out over the head, so the last column of the result meets the first.
    head = strip.crop((0, 0, seam, height))
    tail = strip.crop((width, 0, width + seam, height))
    ramp = Image.linear_gradient("L").rotate(90, expand=True).resize((seam, height))
    tiled = strip.crop((0, 0, width, height))
    tiled.paste(Image.composite(head, tail, ramp), (0, 0))
    save("thin_ice", tiled)


if __name__ == "__main__":
    for kind, hitbox in HAZARDS.items():
        bake(kind, hitbox)
    bake_thin_ice()
