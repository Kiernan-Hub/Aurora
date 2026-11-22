# Desktop frame hitches and terrain work

## November 21, 2026

The follow-up to the [mobile readiness audit](../review/2026-11-21-mobile-readiness-audit.md)
measured terrain building, ice repaints, scenery setup, world rebases and obstacle searches
on an M4 Mac with Godot 4.7's Forward Mobile renderer.

An accelerated windowed replay advanced 12 minutes at a fixed simulation rate of 60 fps.
Seed `1811587497` scheduled 161 obstacle patterns with zero movement-stall recoveries.
The 18 longest intervals between draw callbacks had no recorded completion from the measured
tasks. The four longest intervals were 375, 370, 110 and 110 ms. The trace leaves their cause
open. The callback intervals measure desktop execution during the accelerated replay. They
cannot establish displayed frame pacing or Android performance.

The follow-up replay with the terrain changes reached 12 minutes with 166 scheduled patterns
and zero movement-stall recoveries. For 17 of its 18 longest gaps, most of the time fell between
Godot's pre-draw and post-draw callbacks. The other gap fell primarily before the next physics
callback. These callbacks narrow the trace without identifying the CPU, GPU, or operating-system
work inside the interval. The obstacle workloads and wall-clock timings differed across replays,
so the timings below come from the baseline and the controlled comparisons use the separate
benchmark.

| Measured CPU work | Calls | 95th percentile | Maximum |
| --- | ---: | ---: | ---: |
| Terrain chunk creation | 1,008 | 1.37 ms | 2.67 ms |
| Ice repaint | 1,538 | 0.46 ms | 0.97 ms |
| Scenery setup | 1,538 | 0.48 ms | 1.01 ms |
| World rebase | 10 | 0.07 ms | 0.07 ms |
| Obstacle scheduling decision | 1,586 | 0.74 ms | 9.93 ms |

Terrain now compares each regular sample with the last accepted sample. The distance tolerance
and the existing full checks for seams and chasm lips still apply. Ice painting reuses the UV
array per band and fills uniform colors in bulk. A biome update skips the repaint if the ice
tints, snow cap, textures and blend inputs exactly match those already applied. Lake and Aurora
keep their own repaint triggers.

Two alternating before-and-after runs compared 3,200 terrain samples and 1,920 palette updates
per run, covering all eight biome transitions, lake and Aurora blends, and near-duplicate terrain
samples. The recorded sample positions, polygon geometry, colors, UVs, visibility, and material
parameters matched byte for byte. The 95th percentile for sample collection fell from
0.070–0.071 ms to 0.025 ms. For palette calls it fell from 0.257–0.258 ms to 0.210–0.211 ms.
The workload performed 1,423 full repaints instead of 1,951, a 27% reduction.

All 15 checks in `scripts/check.sh --full` passed, including the physics gates and Android pack
content check. The rendered sky, ice and biome checks passed, along with all 14 rendered UI
cases, including the lake exit and Melt portal.

### Real-time desktop replay

A second windowed replay used the same terrain seed and a test-only 60 fps limit on the
Mac's reported 60 Hz display. It reached 12 minutes of gameplay in 720.8 seconds, scheduled
160 patterns and recorded zero movement-stall recoveries. The harness resumed when the window
lost focus so the run could finish. The window was unfocused for almost the entire measurement.

| Draw callbacks | Intervals | Median | 95th percentile | Over 25 ms | Over 100 ms | Maximum |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Outside startup and focus changes | 42,708 | 16.66 ms | 18.21 ms | 70 | 6 | 155.41 ms |
| From 8 minutes onward, same exclusions | 14,255 | 16.67 ms | 18.37 ms | 17 | 0 | 84.25 ms |

The longest gap was 1,005.65 ms. It began about 30 ms after focus loss, with 1,004.27 ms
between the pre-draw and post-draw callbacks. The run continued afterward. Other long gaps
occurred both inside and outside the draw callback interval. The viewport GPU timer returned
zero throughout this capture, so the trace provides no GPU-side attribution. The timing
records callback cadence on this Mac during a background replay, which leaves foreground and
Android frame pacing open.

A two-minute control ran the same window and renderer with only a moving 3×3 rectangle.
It logged 466 draw callbacks. One 24.9-second gap opened around focus loss, while 1,492
physics callbacks continued. Draw callbacks stopped again while the control was unfocused.
Draw callbacks can therefore disappear with no gameplay scene loaded. The control had too
little comparable draw time to estimate a gameplay-specific hitch rate or identify the
one-second pause's exact cause.
