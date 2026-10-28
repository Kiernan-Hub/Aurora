#!/usr/bin/env python3
"""Bake the three hazard sprites from their art_source/ originals.

    python3 scripts/tools/build_hazard_sprites.py

Sources are art_source/hazards/<kind>_source.png: light-greyscale generations on real alpha,
so obstacle.gd can MULTIPLY each biome's obstacle_color over them (the coin's contract). Same
art_source -> assets rule as build_app_icons.py and build_ice_texture.py.

THE SPRITE IS THE HITBOX. Each source is cropped to its solid silhouette (alpha >= 128) and
stretched to exactly 3x its scene's RectangleShape2D, so the scene scales it by 1/3 and the
drawn edge lands on the collision edge. Change a hitbox and its row here together, or the art
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
    save(kind, load_cropped(kind).resize(size, Image.LANCZOS))


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
