# Dead / disabled code

Reference doc for code that looks reachable but isn't — check here before "fixing" or
resurrecting something. `CLAUDE.md` keeps the still-active guard this code left behind
(the collision-layer/group check in `obstacle.gd`); this file has the full removal
history.

## Terrain-driven obstacle placement — gone, not just disabled

> **Scope note (2026-08-03):** this section is about the *old* placement code that
> lived inside `terrain_generator.gd`. Obstacles themselves are **live again** —
> `scripts/systems/obstacle_spawner.gd` is wired into `main.tscn` under
> `TerrainGenerator`, spawns `scenes/obstacles/obstacle.tscn`, and a hit calls
> `Player.die()`. Until 2026-08-03 this file and `CLAUDE.md` both still said
> obstacles were unreferenced, which is why the note is here: don't read the
> paragraph below as "there are no obstacles".

`spawn_chunk_obstacle`, `is_world_x_in_mega_drop`, `is_chunk_overlapping_mega_drop`,
and their constants (`MIN_SAFE_START_DISTANCE`, `MIN_OBSTACLE_GAP`,
`OBSTACLE_EDGE_PADDING`, `OBSTACLE_SURFACE_Y_OFFSET`) were deleted from
`terrain_generator.gd` rather than left commented out — they were unreachable dead
code and included a latent bug (`maxi(float, float)` on the padding calc). The
current `ObstacleSpawner` was written from scratch against the public
`TerrainGenerator` API (`get_terrain_height` / `get_slope_angle_at_x`) and schedules
clusters off `Player.speed_manager.elapsed_time` rather than off chunk spawning; it
shares no code with the deleted functions, and reviving them is still the wrong move.

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
