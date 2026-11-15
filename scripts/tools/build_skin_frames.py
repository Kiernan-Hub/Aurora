#!/usr/bin/env python3
"""Bake each skater skin from its art_source/ generation into the Player's frame layout.

    python3 scripts/tools/build_skin_frames.py [skin_id ...]

A source is art_source/skins/<id>_source.png: ONE ROW of the four skate frames on real alpha,
generated from the original girl's frames (assets/sprites/player/skate_0..3.png) as reference.
Each comes out as assets/sprites/player/<id>/skate_0..3.png plus frames.tres, a SpriteFrames
with the original's "skate" animation, ready for Skins.SKINS.

THE ORIGINAL IS THE MEASURE. The Player's capsule is the hitbox for every skin, so each skin is
scaled to the girl's drawn height (one scale for all four frames, from their median, so the cycle
cannot pump) and each frame is placed where the girl's matching frame sits: same 150x180 canvas,
feet on the same row, front edge on the same column. A taller adult would otherwise look like it
clips a floe it actually passes under.
"""
import statistics
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = ROOT / "art_source" / "skins"
PLAYER_DIR = ROOT / "assets" / "sprites" / "player"
FRAME_COUNT = 4
SOLID_ALPHA = 128
SOFT_ALPHA_FLOOR = 16
# The bottom share of a source ignored when finding the gaps between frames: a generated ice line
# often runs unbroken under all four.
FLOOR_BAND = 0.08
FPS = 10.0
# A generation that came back on SOLID BLACK instead of real alpha (it happens; so does a painted
# checkerboard, which cannot be keyed -- regenerate that one) is keyed: the black connected to the
# image border is background, and so is any pocket at or below POCKET_THRESHOLD (the gap between
# two legs never touches the border); a dark garment above that survives. The EDGE_PX ring around
# the background takes alpha from its brightness and is un-premultiplied off the black.
BLACK_KEY_THRESHOLD = 14
POCKET_THRESHOLD = 6
EDGE_PX = 2
EDGE_FULL_ALPHA = 56


def solid_bbox(image):
    return image.getchannel("A").point(lambda a: 255 if a >= SOLID_ALPHA else 0).getbbox()


# The original's four frames: canvas size, and each frame's solid box.
def reference_boxes():
    frames = [Image.open(PLAYER_DIR / f"skate_{i}.png").convert("RGBA") for i in range(FRAME_COUNT)]
    return frames[0].size, [solid_bbox(frame) for frame in frames]


# The source's four figures, left to right, split at the three widest empty column runs.
def split_frames(source):
    alpha = source.getchannel("A")
    width, height = source.size
    body = alpha.crop((0, 0, width, int(height * (1.0 - FLOOR_BAND)))).point(lambda a: 255 if a >= SOLID_ALPHA else 0)
    filled = [body.crop((x, 0, x + 1, body.height)).getbbox() is not None for x in range(width)]
    runs = []
    x = 0
    while x < width:
        if not filled[x]:
            start = x
            while x < width and not filled[x]:
                x += 1
            if start > 0 and x < width:
                runs.append((x - start, start, x))
        else:
            x += 1
    if len(runs) < FRAME_COUNT - 1:
        raise SystemExit(f"found {len(runs) + 1} figures, expected {FRAME_COUNT}: regenerate with more space between frames")
    cuts = sorted(sorted(runs, reverse=True)[:FRAME_COUNT - 1], key=lambda run: run[1])
    edges = [0] + [(start + end) // 2 for _, start, end in cuts] + [width]
    frames = []
    for left, right in zip(edges, edges[1:]):
        frame = source.crop((left, 0, right, height))
        frames.append(frame.crop(solid_bbox(frame)))
    return frames


def key_black_background(image):
    rgb = image.convert("RGB")
    brightness = np.asarray(rgb).max(axis=2)
    # .copy(): an image made by fromarray shares numpy's read-only buffer, and floodfill on it
    # silently changes nothing.
    dark = Image.fromarray(np.where(brightness < BLACK_KEY_THRESHOLD, 255, 0).astype(np.uint8)).copy()
    ImageDraw.floodfill(dark, (0, 0), 128)
    background = (np.asarray(dark) == 128) | (brightness <= POCKET_THRESHOLD)
    near = np.asarray(Image.fromarray((background * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(EDGE_PX * 2 + 1))) > 0
    ring = near & ~background
    alpha = np.full(brightness.shape, 255.0)
    alpha[background] = 0.0
    alpha[ring] = np.clip(brightness[ring] * 255.0 / EDGE_FULL_ALPHA, 0.0, 255.0)
    colour = np.asarray(rgb).astype(np.float64)
    scale = np.where(ring & (alpha > 0.0), 255.0 / np.maximum(alpha, 1.0), 1.0)
    colour = np.clip(colour * scale[..., None], 0.0, 255.0)
    return Image.fromarray(np.dstack([colour, alpha]).astype(np.uint8), "RGBA")


def bake(skin_id):
    source = Image.open(SOURCE_DIR / f"{skin_id}_source.png").convert("RGBA")
    if source.getchannel("A").getextrema()[0] == 255 and max(source.getpixel((0, 0))[:3]) < BLACK_KEY_THRESHOLD:
        source = key_black_background(source)
    source.putalpha(source.getchannel("A").point(lambda a: 0 if a < SOFT_ALPHA_FLOOR else a))
    frames = split_frames(source)
    canvas_size, boxes = reference_boxes()
    reference_height = statistics.median(box[3] - box[1] for box in boxes)
    scale = reference_height / statistics.median(frame.height for frame in frames)
    out_dir = PLAYER_DIR / skin_id
    out_dir.mkdir(parents=True, exist_ok=True)
    for index, (frame, box) in enumerate(zip(frames, boxes)):
        size = (max(1, round(frame.width * scale)), max(1, round(frame.height * scale)))
        if size[0] > canvas_size[0]:
            size = (canvas_size[0], round(size[1] * canvas_size[0] / size[0]))
        frame = frame.resize(size, Image.LANCZOS)
        canvas = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
        left = min(max(box[2] - frame.width, 0), canvas_size[0] - frame.width)
        canvas.alpha_composite(frame, (left, box[3] - frame.height))
        canvas.save(out_dir / f"skate_{index}.png", optimize=True)
    write_frames_resource(skin_id, out_dir)
    print(f"{skin_id}: 4 frames, scale {scale:.3f} -> {out_dir.relative_to(ROOT)}")


# The same shape as player_skate_frames.tres, path-only (Godot fills in uids on import).
def write_frames_resource(skin_id, out_dir):
    lines = [f'[gd_resource type="SpriteFrames" load_steps={FRAME_COUNT + 1} format=3]', ""]
    for index in range(FRAME_COUNT):
        lines.append(f'[ext_resource type="Texture2D" path="res://assets/sprites/player/{skin_id}/skate_{index}.png" id="{index + 1}"]')
    frames = ", ".join(f'{{\n"duration": 1.0,\n"texture": ExtResource("{index + 1}")\n}}' for index in range(FRAME_COUNT))
    lines += ["", "[resource]", f'animations = [{{\n"frames": [{frames}],\n"loop": true,\n"name": &"skate",\n"speed": {FPS}\n}}]', ""]
    (out_dir / "frames.tres").write_text("\n".join(lines))


if __name__ == "__main__":
    ids = sys.argv[1:] or sorted(path.name.removesuffix("_source.png") for path in SOURCE_DIR.glob("*_source.png"))
    for skin_id in ids:
        bake(skin_id)
