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
# does eventually degrade too, around x ~ 1e6, versus y trouble by x ~ 226,000 --
# so it is a separate, later concern.
#
# "x ~ 1e6" IS THE WRONG SHAPE OF NUMBER, and the "~33 minutes" this comment used to
# carry was wrong outright. Nothing happens AT 1e6: float32 resolution is a step
# function that halves at each power of two, so the only thresholds that exist are the
# powers of two. Integrating the shipped SpeedManager ramp (100->500 over 10s, 500->750
# over the next 110s, then flat), ignoring slope -- which makes these upper bounds on x
# and therefore LOWER bounds on when each arrives:
#
#     x = 2^19 =   524,288   ulp 0.0625 px   t = 12.1 min   (frame  43,408)
#     x = 2^20 = 1,048,576   ulp 0.1250 px   t = 23.7 min   (frame  85,351)
#     x = 2^21 = 2,097,152   ulp 0.2500 px   t = 47.0 min   (frame 169,238)
#
# So the first real step down is 23.7 min, not 33. 33 minutes is x ~ 1.5e6, which sits
# in the middle of the 2^20 band and is not a boundary at all -- the old line paired a
# time from one band with a distance from another.
#
# WHY THIS IS NOT (YET) THE Y BUG AGAIN. The freeze above was a bad contact SEPARATION
# direction, and separations are of order safe_margin (1.0 px) and below, so the error
# is atan(ulp / separation). At 2^20 that is 3.6 deg for a 1.0 px separation but 26.6
# deg for a 0.25 px one -- i.e. the mechanism is live at these magnitudes, and whether
# it bites depends on whether the terrain actually produces sub-pixel separations there.
# It is a probabilistic cliff, not a hard one. (For scale: the recorded freeze normals
# were 9.9 and 21.1 deg off vertical; floor_max_angle is 45.)
#
# MEASURED 2026-08-24, AND IT IS CLEAN THROUGH 2^21. Three seeds x 200,000 frames
# (~55 min of play each, reaching x ~ 2.43e6, 16% past 2^21): all status=no_freeze with
# stall_recoveries=0. 2^21 was the band worth testing -- it is where a 0.25 px separation
# quantises to exactly floor_max_angle. So this is NOT a live risk: 2^22 needs 94 minutes
# of unbroken play in a single run, uninterrupted by any death, chasm or app switch.
#
# DO NOT REBASE X ON THE STRENGTH OF THIS COMMENT. The cost was measured too: ~44 reads of
# player.global_position.x across 17 files would have to become a logical world x, each a
# silent wrong answer if missed. It is not justified. docs/research/x_precision_cliff.md
# has the full costing and the cheaper safe_margin lever to try first if it ever is.
#
# NOTE THAT NO GATE REACHES ANY OF THIS, and none will. freeze_replay_runner at its
# 60,000-frame gate size stops at x ~ 732,000 -- inside the 2^19 band, one band short of
# even 2^20. Never infer long-run safety from a passing gate here; run the soak:
#
#     freeze_replay_runner.gd -- --seed=<s> --frames=200000    # ~55 min play, x ~ 2.43e6
#
# Only the physics solver's float32 world transforms were ever at risk. get_terrain_height()
# is computed in GDScript float, which is 64-bit, so the height field itself has no float32
# problem at any x -- do not "fix" the generator.
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
