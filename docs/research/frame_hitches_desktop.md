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
