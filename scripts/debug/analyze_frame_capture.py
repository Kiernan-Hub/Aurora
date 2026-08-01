#!/usr/bin/env python3
"""Measure what actually moves between rendered frames from frame_capture_probe.gd.

Every earlier probe on the mega_drop shake measured an internal engine quantity
and then had to argue it corresponded to what the eye sees; each one decoupled
from perception. This measures the rendered pixels.

METHOD NOTES (both learned the hard way on this capture):

  * The debug HUD is static high-contrast text over the top-left of every frame.
    Left in, it anchors any correlation to zero shift and produces phantom
    "the image barely moved" readings. It must be cropped out.
  * Projection (row/column mean) correlation is ILL-POSED for this scene: the
    terrain is large flat colour bounded by a near-straight diagonal edge, and
    for a straight diagonal a horizontal shift and a vertical shift produce
    identical projections. 2D phase correlation separates them properly.

Reports, per region, how far the image actually translated each frame, and the
frame-to-frame jerk of that translation (the quantity that reads as judder),
against the camera motion recorded in manifest.csv.

Usage:
    python3 analyze_frame_capture.py <capture_dir> [--hud-rows N]
"""
import csv
import sys
from pathlib import Path

import numpy as np
from PIL import Image

# Rows to drop from the top: the debug state Label block plus the timer.
DEFAULT_HUD_ROWS = 215


def load_luma(path):
    return np.asarray(Image.open(path).convert("L"), dtype=np.float64)


def phase_correlate(frame_a, frame_b):
    """Return (dy, dx) translation taking frame_a to frame_b, sub-pixel.

    Standard phase correlation with a Hann window to suppress the wrap-around
    edge discontinuity, plus parabolic peak interpolation.
    """
    height, width = frame_a.shape
    window = np.outer(np.hanning(height), np.hanning(width))
    a = (frame_a - frame_a.mean()) * window
    b = (frame_b - frame_b.mean()) * window

    fa = np.fft.rfft2(a)
    fb = np.fft.rfft2(b)
    cross = fa * np.conj(fb)
    magnitude = np.abs(cross)
    magnitude[magnitude < 1e-12] = 1e-12
    correlation = np.fft.irfft2(cross / magnitude, s=frame_a.shape)

    peak = np.unravel_index(np.argmax(correlation), correlation.shape)
    peak_y, peak_x = int(peak[0]), int(peak[1])

    def refine(axis_index, index):
        size = correlation.shape[axis_index]
        before = correlation[(index - 1) % size, peak_x] if axis_index == 0 else correlation[peak_y, (index - 1) % size]
        centre = correlation[index, peak_x] if axis_index == 0 else correlation[peak_y, index]
        after = correlation[(index + 1) % size, peak_x] if axis_index == 0 else correlation[peak_y, (index + 1) % size]
        denominator = before - 2.0 * centre + after
        if abs(denominator) < 1e-12:
            return 0.0
        offset = 0.5 * (before - after) / denominator
        return offset if -1.0 < offset < 1.0 else 0.0

    dy = peak_y + refine(0, peak_y)
    dx = peak_x + refine(1, peak_x)
    # Unwrap to signed shifts.
    if dy > height / 2:
        dy -= height
    if dx > width / 2:
        dx -= width
    return dy, dx


def describe(name, deltas):
    deltas = np.asarray(deltas)
    jerk = np.abs(np.diff(deltas))
    reversals = int(np.sum(np.diff(np.sign(np.diff(deltas))) != 0))
    print(f"  {name}")
    print(f"      delta : mean {np.mean(deltas):8.4f}  min {np.min(deltas):8.4f}  max {np.max(deltas):8.4f}  sd {np.std(deltas):7.4f}")
    print(f"      jerk  : mean {np.mean(jerk):8.4f}  max {np.max(jerk):8.4f}   reversals {reversals}/{max(len(jerk),1)} ({reversals/max(len(jerk),1)*100:.1f}%)")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    capture_dir = Path(sys.argv[1])
    hud_rows = DEFAULT_HUD_ROWS
    if "--hud-rows" in sys.argv:
        hud_rows = int(sys.argv[sys.argv.index("--hud-rows") + 1])

    frames = sorted(capture_dir.glob("frame_*.png"))
    if len(frames) < 3:
        print(f"need at least 3 frames, found {len(frames)}")
        return 1

    manifest = {}
    manifest_path = capture_dir / "manifest.csv"
    if manifest_path.exists():
        with manifest_path.open() as handle:
            for row in csv.DictReader(handle):
                manifest[int(row["index"])] = row

    first = load_luma(frames[0])
    height, width = first.shape
    print(f"analysing {len(frames)} frames, {width}x{height}, dropping top {hud_rows} rows (static HUD)")
    print()

    # Whole content area, and a band well below the terrain edge that is
    # dominated by terrain fill + chunk colour boundaries.
    regions = {
        "content (HUD cropped)": (hud_rows, height, 0, width),
        "lower terrain band": (int(height * 0.75), height, 0, width),
    }

    results = {}
    for name, (y0, y1, x0, x1) in regions.items():
        previous = load_luma(frames[0])[y0:y1, x0:x1]
        dxs, dys = [], []
        for index in range(1, len(frames)):
            current = load_luma(frames[index])[y0:y1, x0:x1]
            dy, dx = phase_correlate(previous, current)
            dxs.append(dx)
            dys.append(dy)
            previous = current
        results[name] = (np.array(dxs), np.array(dys))

    camera_dx = camera_dy = None
    if manifest:
        keys = sorted(manifest)
        camera_dx = np.diff(np.array([float(manifest[i]["camera_x"]) for i in keys]))
        camera_dy = np.diff(np.array([float(manifest[i]["camera_y"]) for i in keys]))

    print("=== MEASURED FROM RENDERED PIXELS (2D phase correlation) ===")
    print("Image shift is NEGATIVE of camera motion: camera right => content left.")
    print()
    for name, (dxs, dys) in results.items():
        print(f"{name}:")
        describe("horizontal (dx)", dxs)
        describe("vertical   (dy)", dys)
        print()

    if camera_dx is not None:
        print("=== ENGINE CAMERA MOTION (same frames) ===")
        describe("camera dx", camera_dx)
        describe("camera dy", camera_dy)
        print()
        print("=== DOES THE IMAGE FOLLOW THE CAMERA? ===")
        for name, (dxs, dys) in results.items():
            n = min(len(dxs), len(camera_dx))
            gap_x = dxs[:n] + camera_dx[:n]   # expect ~0 if image tracks camera
            gap_y = dys[:n] + camera_dy[:n]
            print(f"  {name}")
            print(f"      |img_dx + cam_dx| : mean {np.mean(np.abs(gap_x)):7.4f}  max {np.max(np.abs(gap_x)):7.4f}")
            print(f"      |img_dy + cam_dy| : mean {np.mean(np.abs(gap_y)):7.4f}  max {np.max(np.abs(gap_y)):7.4f}")
        print()

    print("=== PER-FRAME DETAIL (content region) ===")
    dxs, dys = results["content (HUD cropped)"]
    print(f"{'frame':>6} {'world_x':>11} {'img_dx':>9} {'img_dy':>9} {'cam_dx':>9} {'cam_dy':>9} {'sprite_rot':>11}")
    for index in range(min(len(dxs), 40)):
        frame_index = index + 1
        row = manifest.get(frame_index, {})
        cam_x = camera_dx[index] if camera_dx is not None and index < len(camera_dx) else float("nan")
        cam_y = camera_dy[index] if camera_dy is not None and index < len(camera_dy) else float("nan")
        print(f"{frame_index:>6} {row.get('world_x','?'):>11} {dxs[index]:9.4f} {dys[index]:9.4f} "
              f"{cam_x:9.4f} {cam_y:9.4f} {row.get('sprite_rotation','?'):>11}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
