#!/usr/bin/env python3
"""Synthesise the thin-ice crack: assets/audio/sfx/crack.wav.

    python3 scripts/tools/build_crack_sfx.py

A placeholder in the same spirit as the other SFX (synthesised, 44.1 kHz mono 16-bit): swap
the file for a recorded crack later and nothing else changes. Deterministic (fixed seed), so a
re-run reproduces the shipped file.

The shape of an ice crack, which is what keeps it from reading as a generic hit:
  1. a sharp broadband SNAP, a few ms of noise with an instant attack;
  2. a short run of CRACKLE, tiny clicks thinning out as the fracture runs along the sheet;
  3. a low, hollow THUNK under both, the sheet flexing, a decaying sine with a slight drop.
"""
import math
import random
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "assets" / "audio" / "sfx" / "crack.wav"
RATE = 44100
DURATION = 0.45
SEED = 7
PEAK = 0.8

SNAP_DECAY = 0.006
CRACKLE_CLICKS = 34
CRACKLE_SPAN = 0.28
CRACKLE_CLICK_DECAY = 0.0012
THUNK_HZ = (170.0, 120.0)
THUNK_DECAY = 0.09
THUNK_GAIN = 0.55


def main() -> None:
    rng = random.Random(SEED)
    count = int(RATE * DURATION)
    samples = [0.0] * count

    for i in range(int(RATE * SNAP_DECAY * 6)):
        t = i / RATE
        samples[i] += rng.uniform(-1.0, 1.0) * math.exp(-t / SNAP_DECAY)

    for _ in range(CRACKLE_CLICKS):
        # Squared so the clicks bunch up early and thin out, like a fracture running away.
        start = int(RATE * CRACKLE_SPAN * rng.random() ** 2)
        gain = rng.uniform(0.25, 0.7) * (1.0 - start / (RATE * CRACKLE_SPAN))
        for i in range(int(RATE * CRACKLE_CLICK_DECAY * 6)):
            if start + i < count:
                samples[start + i] += rng.uniform(-1.0, 1.0) * gain * math.exp(-i / RATE / CRACKLE_CLICK_DECAY)

    phase = 0.0
    for i in range(count):
        t = i / RATE
        hz = THUNK_HZ[0] + (THUNK_HZ[1] - THUNK_HZ[0]) * min(1.0, t / DURATION)
        phase += 2.0 * math.pi * hz / RATE
        samples[i] += math.sin(phase) * THUNK_GAIN * math.exp(-t / THUNK_DECAY)

    # A 5 ms fade so the tail never ends on a click.
    fade = int(RATE * 0.005)
    for i in range(fade):
        samples[count - 1 - i] *= i / fade
    scale = PEAK / max(abs(s) for s in samples)
    with wave.open(str(OUTPUT), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(s * scale * 32767)) for s in samples))
    print(f"wrote {OUTPUT.relative_to(ROOT)} ({DURATION}s)")


if __name__ == "__main__":
    main()
