# Dead / disabled code

Reference doc for code that looks reachable but isn't — check here before "fixing" or
resurrecting something. `CLAUDE.md` keeps the still-active guard this code left behind
(the collision-layer/group check in `obstacle.gd`); this file has the full removal
history.

## Obstacle spawning — gone, not just disabled

`spawn_chunk_obstacle`, `is_world_x_in_mega_drop`, `is_chunk_overlapping_mega_drop`,
and their constants (`MIN_SAFE_START_DISTANCE`, `MIN_OBSTACLE_GAP`,
`OBSTACLE_EDGE_PADDING`, `OBSTACLE_SURFACE_Y_OFFSET`) were deleted from
`terrain_generator.gd` rather than left commented out — they were unreachable dead
code and included a latent bug (`maxi(float, float)` on the padding calc).
`scenes/obstacles/obstacle.tscn` / `scripts/obstacles/obstacle.gd` still exist but
are unreferenced by anything; a re-implementation starts from scratch against the
current `TerrainGenerator` API, not from the deleted functions.

Separately: a hand-placed `Obstacle` node that used to sit at `(68,56)` in
`main.tscn` was deleted earlier — jumping at t=0 landed the capsule inside it at
t≈0.10s, killing the run and making every manual playtest and the harness's
`tree_paused` result ambiguous.

## Vertical parallax — tried, reverted

Background parallax is **horizontal only** (`motion_scale = (0.3, 0)`). Vertical
parallax is deliberately off: it made the layer jump ~0.3× the camera's Y move, so
each world rebase (~every 26s) snapped the background, and the layer's
`y ∈ [-1024,1024]` coverage vanished after a few mega drops. With `motion_scale.y = 0`
the layer is screen-locked vertically and both symptoms are gone. Restoring vertical
parallax means tiling `background_generator.gd` stripes on a 2D grid.

## Leave alone unless asked

`project.godot`, `.godot/`, `*.uid` files (must move with their script), `icon.svg`.
