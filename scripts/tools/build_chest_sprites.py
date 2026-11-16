#!/usr/bin/env python3
"""Bake the closed/open chest sheet into tiny aligned transparent game sprites.

    python3 scripts/tools/build_chest_sprites.py

The source remains in art_source/ (excluded from exports). Both poses share one scale,
canvas, centre and baseline so opening the chest never changes its body's size or position.
Only image preparation: no painting, tinting, or collision changes.
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art_source/chests/chest_source_v1.png"
OUTPUT = ROOT / "assets/sprites/chest"
TILE_SIZE = 192
BODY_WIDTH = 160
BASELINE = 174


def bake(source_path=SOURCE, prefix=""):
    source = Image.open(source_path).convert("RGBA")
    if source.getchannel("A").getextrema()[0] != 0:
        raise SystemExit("Chest source must have real transparency")
    poses = []
    for index in range(2):
        cell = source.crop((index * source.width // 2, 0, (index + 1) * source.width // 2, source.height))
        alpha = cell.getchannel("A")
        cell.putalpha(alpha.point(lambda value: 0 if value < 16 else value))
        box = alpha.point(lambda value: 255 if value >= 192 else 0).getbbox()
        if box is None:
            raise SystemExit("Empty chest pose")
        poses.append(cell.crop(box))
    scale = BODY_WIDTH / max(pose.width for pose in poses)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, pose in zip(("closed", "open"), poses):
        size = (round(pose.width * scale), round(pose.height * scale))
        if size[1] > BASELINE:
            raise SystemExit("Open pose does not fit: adjust the source or tile size")
        pose = pose.resize(size, Image.Resampling.LANCZOS)
        tile = Image.new("RGBA", (TILE_SIZE, TILE_SIZE))
        tile.alpha_composite(pose, ((TILE_SIZE - size[0]) // 2, BASELINE - size[1]))
        path = OUTPUT / f"{prefix}{name}.png"
        tile.save(path, optimize=True)
        print(f"{path.relative_to(ROOT)}: {path.stat().st_size:,} bytes")


if __name__ == "__main__":
    bake()
    aurora = ROOT / "art_source/chests/aurora_source_v1.png"
    if aurora.exists():
        bake(aurora, "aurora_")
