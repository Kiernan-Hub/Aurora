extends RefCounted

class_name UpgradeStore

# The meta-progression catalog and the purchase transactions against it. Owned by the
# Services autoload alongside SaveStore, because upgrades must outlive a run and restart
# is get_tree().reload_current_scene().
#
# The file is deliberately two halves:
#
#   STATIC HALF -- the catalog (multipliers, costs, level math). Callable with no
#   instance, no autoload and no save file, which is what lets terrain_invariant_check
#   assert against the curve from a --headless --script run.
#
#   INSTANCE HALF -- get_level/purchase/get_wallet, operating on an injected SaveStore.
#   `save_store` is assigned by GameServices._ready(), never resolved from here.
#
# NEVER write the bare identifier `Services` in this file. It is reachable from probe
# scripts, and a `Services.x` there is a COMPILE error that takes the whole class down
# to Nil and hangs the gate with no output. See the header of scripts/autoload/services.gd.
#
# Note that the autoload NODE does exist in `--headless --script` runs even though the
# global identifier does not, so GameServices.resolve() succeeds inside a probe and this
# store is fully live there. That is exactly why GameManager.apply_upgrades() refuses to
# run under a headless DisplayServer: a gate must never measure physics derived from
# whatever is in the developer's own save.dat.
#
# SaveStore must not reference this class in return. The dependency stays one-directional
# so there is no class_name cycle, and so an upgrade id written by a later build loads
# harmlessly in an earlier one (SaveStore keeps whatever ids it read; clamping to a legal
# level happens here, in get_level).

const JUMP_UPGRADE_ID: String = "jump"
const UPGRADE_IDS: Array[String] = [JUMP_UPGRADE_ID]

# Jump velocity multiplier per level, applied on top of Player.JUMP_VELOCITY.
#
# THE CURVE ENDS AT EXACTLY 1.0, AND THAT IS A HARD CEILING, NOT TASTE. Every jump-reach
# constant in the project -- CHASM_MAX_REACH_FRACTION, CHASM_LEAD_IN_LENGTH, the obstacle
# cluster gaps -- was tuned against multiplier 1.0. Ending there means the fully-upgraded
# player is exactly today's player and none of that tuning has to move. The player starts
# nerfed and buys their way back to baseline.
#
# The specific ceiling: CHASM_LEAD_IN_TOO_SHORT requires
#   MAX_SPEED(750) * 0.8 * M * JUMP_BOOST_VELOCITY_MULTIPLIER(sqrt 2) + LEAD_IN_MARGIN(32)
#     <= CHASM_LEAD_IN_LENGTH(900)
#   -> 848.53 * M <= 868  ->  M <= 1.0224
# Above that a jump-boosted max-upgrade player who jumps at the first pixel of a chasm
# run-up overshoots the lead-in and lands inside the void. terrain_invariant_check
# asserts this, so raising the ceiling fails the build rather than shipping the bug.
#
# The floor of 0.60 is bounded from below by the obstacle, not the chasm. An obstacle is
# 32x32 sitting on the surface and kills on any contact; jump apex is 128 * m^2, so
# m = 0.50 gives an apex of exactly 32.0 and the first cluster becomes a wall. 0.55
# clears it by 6.7px and leaves ~3.7 frames of window, which reads as a broken game
# rather than a hard one. 0.60 gives 46.1px of apex and ~8.6 frames -- hard but fair.
# check_obstacle_clearance() in terrain_invariant_check.gd asserts all of this.
const JUMP_MULTIPLIERS: Array[float] = [0.60, 0.70, 0.80, 0.90, 1.00]

# Cost of the purchase that moves level i -> i+1, so this is always one shorter than
# JUMP_MULTIPLIERS. Sized against a coin density of roughly 0.00234 coins/px (3 slots per
# 512px chunk at a 0.4 include chance): about 26 coins for a 25s run, 56 for 45s, 122 for
# 90s. Total 1130 across the curve is ~15 runs to max.
const JUMP_UPGRADE_COSTS: Array[int] = [60, 150, 320, 600]

const NO_COST: int = -1

# Injected by GameServices._ready(). Null in any context that has no autoload, which is
# every headless probe -- callers must null-guard, matching the services contract.
var save_store: SaveStore


# --- Static catalog -----------------------------------------------------------------
# Everything below this line is answerable from constants alone.

static func get_max_level(upgrade_id: String) -> int:
	if upgrade_id == JUMP_UPGRADE_ID:
		return JUMP_MULTIPLIERS.size() - 1
	return 0


# Clamps rather than asserting: a save file written by a later build can legitimately
# carry a level this build has no entry for, and a player who downgrades should get the
# best jump this build knows about, not a crash.
static func get_jump_multiplier(level: int) -> float:
	return JUMP_MULTIPLIERS[clampi(level, 0, JUMP_MULTIPLIERS.size() - 1)]


# Cost to go from `level` to `level + 1`, or NO_COST when already maxed.
# Takes an upgrade_id it does not strictly need yet: a second upgrade track is meant to
# be a table row plus a branch here, not a new function.
static func get_upgrade_cost(upgrade_id: String, level: int) -> int:
	if upgrade_id != JUMP_UPGRADE_ID:
		return NO_COST
	if level < 0 or level >= JUMP_UPGRADE_COSTS.size():
		return NO_COST
	return JUMP_UPGRADE_COSTS[level]


# The weakest jump the game can be played at. terrain_invariant_check uses this as the
# worst case for "is this chasm physically clearable at all".
static func get_min_jump_multiplier() -> float:
	return JUMP_MULTIPLIERS[0]


# The strongest jump the game can be played at. Worst case for the chasm lead-in, since
# the jump powerup stacks multiplicatively on top of it.
static func get_max_jump_multiplier() -> float:
	return JUMP_MULTIPLIERS[JUMP_MULTIPLIERS.size() - 1]


# --- Instance: transactions against the save file ------------------------------------

func get_level(upgrade_id: String) -> int:
	if save_store == null:
		return 0
	var stored_level: int = save_store.upgrade_levels.get(upgrade_id, 0)
	return clampi(stored_level, 0, get_max_level(upgrade_id))


func get_next_cost(upgrade_id: String) -> int:
	return get_upgrade_cost(upgrade_id, get_level(upgrade_id))


func get_wallet() -> int:
	if save_store == null:
		return 0
	return save_store.coin_wallet


func is_maxed(upgrade_id: String) -> bool:
	return get_level(upgrade_id) >= get_max_level(upgrade_id)


func can_purchase(upgrade_id: String) -> bool:
	if save_store == null:
		return false
	var cost: int = get_next_cost(upgrade_id)
	return cost != NO_COST and get_wallet() >= cost


# The only place the wallet is ever decremented. Writes through immediately: a purchase
# is rare and explicitly user-initiated, so a synchronous save here is nothing like the
# volume sliders, which fire on every step of a drag and are batched on drag end instead.
func purchase(upgrade_id: String) -> bool:
	if not can_purchase(upgrade_id):
		return false

	var cost: int = get_next_cost(upgrade_id)
	save_store.coin_wallet -= cost
	save_store.upgrade_levels[upgrade_id] = get_level(upgrade_id) + 1
	save_store.save_to_disk()
	return true
