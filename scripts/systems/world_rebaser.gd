extends RefCounted

class_name WorldRebaser

# Keeps the active play area near the world origin on the Y axis.
#
# Why this exists: terrain baselines drift downward without bound (measured ~16%
# average grade, no rebound), so after a few minutes the collision surface sits
# tens of thousands of pixels below y=0. Godot's 2D physics works in 32-bit
# floats, so the representable step at the contact point grows with |y|:
#
#     y =    192  ->  ulp = 0.000015 px
#     y = 37,404  ->  ulp = 0.0039 px   (1/256)
#     y = 150,192 ->  ulp = 0.0156 px   (1/64)
#
# Contact separation vectors are of order safe_margin (1.0 px), so at depth they
# are only a few hundred ulps long and their *direction* quantises to coarse
# integer ratios. get_floor_normal() then returns an off-vertical normal on
# provably flat ground -- observed values are exact fractions such as 23/64 and
# 11/32. player.gd:76-78 aims velocity along that normal, into the ground,
# move_and_slide() exhausts max_slides, and motion.x collapses to 0: the freeze.
#
# Shifting the whole play area back toward y=0 restores precision at the contact
# point. Measured: 3 reproducing stalls across 60 trials -> 0, and the slide
# count stops reaching the engine's max_slides cap of 4.
#
# ONLY Y IS REBASED. X is deliberately untouched so that
# TerrainGenerator.get_terrain_height(world_x) stays a pure function of
# (session_seed, world_x) and every recorded repro seed stays valid. X precision
# does eventually degrade too, but only around x ~ 1e6 (~33 minutes of play)
# versus y trouble by x ~ 226,000, so it is a separate, later concern.
#
# The shift is always a whole multiple of REBASE_QUANTUM_Y, and that quantum is a
# power of two, so applying it is exact in binary and cannot itself introduce
# rounding into positions that were previously exact.

# Rebase once the focus point drifts this far from the origin.
const REBASE_THRESHOLD_Y: float = 2048.0
# Snap the correction to a multiple of this. Power of two: exact in binary.
const REBASE_QUANTUM_Y: float = 1024.0


# Returns the Y shift to apply to the whole play area, or 0.0 if none is due.
# focus_world_y should be the point precision matters most at -- the player, since
# the player and the terrain it contacts share essentially the same depth.
#
# Static and stateless: callers preload this script rather than relying on the
# class_name global registry, which only refreshes when the editor rescans.
static func get_rebase_shift(focus_world_y: float) -> float:
	if absf(focus_world_y) <= REBASE_THRESHOLD_Y:
		return 0.0
	return -roundf(focus_world_y / REBASE_QUANTUM_Y) * REBASE_QUANTUM_Y
