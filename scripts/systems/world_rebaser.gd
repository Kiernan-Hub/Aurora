extends RefCounted

class_name WorldRebaser

# Keeps the active play area near the world origin on the Y axis.
#
# WHY: terrain baselines drift downward without bound, and Godot's 2D physics is float32. Far
# from y=0 a contact separation (~1 px, safe_margin) quantises to an off-vertical floor normal
# on flat ground, the player is aimed into the ground along it, and motion.x collapses: the
# freeze. Shifting everything back toward y=0 removed it (3 stalls in 60 trials -> 0).
# Measurements: docs/research/freeze_bug.md.
#
# ONLY Y IS REBASED. X stays untouched so get_terrain_height(world_x) stays pure in
# (session_seed, world_x) and every recorded repro seed stays valid. X precision is measured
# clean through 2^21 (~47 min of unbroken play), and rebasing X would touch ~44 reads across
# 17 files, each a silent wrong answer if missed. DO NOT REBASE X without reading
# docs/research/x_precision_cliff.md: the cost, the cheaper lever to try first, the soak
# command, and why no gate reaches this (the 60,000-frame gate stops near x = 732,000).
#
# The height field is 64-bit GDScript float and has no precision problem: do not "fix" the
# generator. The shift is a whole multiple of REBASE_QUANTUM_Y, a power of two, so applying
# it is exact in binary and adds no rounding.

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
