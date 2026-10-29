#!/usr/bin/env python3
"""Synthesise the menu sounds: click, back, start and purchase .wav under assets/audio/sfx/.

    python3 scripts/tools/build_ui_sfx.py

Same contract as build_crack_sfx.py: placeholders, 44.1 kHz mono 16-bit, deterministic (fixed
seed), so a re-run reproduces the shipped files and a recorded set can replace them later.

Every sound is built from one voice, a struck-glass TINK: a few sine partials at inharmonic
ratios (what makes glass or ice ring rather than beep), the higher ones dying faster, over a
millisecond of noise for the strike. The four differ only in pitch, direction and how many tinks:
  * click    -- one high tink. Forward: every select, open and resume.
  * back     -- one lower tink sliding slightly down. Close, Back, Home.
  * start    -- two tinks rising, over a short breath of air. A run begins.
  * purchase -- a three-tink rising arpeggio with a long ring. Something was bought.
"""
import math
import random
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUTPUT_DIR = ROOT / "assets" / "audio" / "sfx"
RATE = 44100
SEED = 11
# (ratio, gain, decay as a fraction of the tink's own decay): a glass-like, inharmonic set.
PARTIALS = ((1.0, 1.0, 1.0), (2.32, 0.45, 0.6), (4.25, 0.22, 0.35), (6.63, 0.1, 0.2))
STRIKE_SECONDS = 0.0015
FADE_SECONDS = 0.005

# name -> (duration, peak, [(start s, hz, glide to hz, decay s)], air seconds)
SOUNDS = {
    "click": (0.14, 0.45, [(0.0, 1568.0, 1568.0, 0.035)], 0.0),
    "back": (0.18, 0.4, [(0.0, 1047.0, 960.0, 0.05)], 0.0),
    "start": (0.45, 0.55, [(0.0, 988.0, 988.0, 0.08), (0.07, 1319.0, 1319.0, 0.16)], 0.3),
    "purchase": (0.8, 0.6, [(0.0, 1319.0, 1319.0, 0.22), (0.06, 1661.0, 1661.0, 0.22), (0.12, 1976.0, 1976.0, 0.3)], 0.0),
}


def add_tink(samples, rng, start, hz, glide_hz, decay):
    offset = int(start * RATE)
    for i in range(int(STRIKE_SECONDS * RATE)):
        samples[offset + i] += rng.uniform(-1.0, 1.0) * 0.3 * (1.0 - i / (STRIKE_SECONDS * RATE))
    for ratio, gain, decay_scale in PARTIALS:
        phase = 0.0
        for i in range(len(samples) - offset):
            t = i / RATE
            # The glide eases out over the tink's first decay.
            frequency = (glide_hz + (hz - glide_hz) * math.exp(-t / decay)) * ratio
            if frequency >= RATE / 2:
                break
            phase += 2.0 * math.pi * frequency / RATE
            samples[offset + i] += math.sin(phase) * gain * math.exp(-t / (decay * decay_scale))


# Soft air under the start: low-passed noise swelling in and out.
def add_air(samples, rng, seconds):
    smoothed = 0.0
    count = int(seconds * RATE)
    for i in range(count):
        smoothed += 0.06 * (rng.uniform(-1.0, 1.0) - smoothed)
        samples[i] += smoothed * 0.5 * math.sin(math.pi * i / count)


def build(name, duration, peak, tinks, air_seconds, rng):
    samples = [0.0] * int(duration * RATE)
    for start, hz, glide_hz, decay in tinks:
        add_tink(samples, rng, start, hz, glide_hz, decay)
    if air_seconds > 0.0:
        add_air(samples, rng, air_seconds)
    fade = int(FADE_SECONDS * RATE)
    for i in range(fade):
        samples[-1 - i] *= i / fade
    scale = peak / max(abs(s) for s in samples)
    path = OUTPUT_DIR / f"{name}.wav"
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(s * scale * 32767)) for s in samples))
    print(f"wrote {path.relative_to(ROOT)} ({duration}s)")


def main() -> None:
    rng = random.Random(SEED)
    for name, (duration, peak, tinks, air_seconds) in SOUNDS.items():
        build(name, duration, peak, tinks, air_seconds, rng)


if __name__ == "__main__":
    main()
