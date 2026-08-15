extends Node

class_name FrozenLakeDirector

# Schedules and runs the frozen lake set piece: roughly every 20 minutes of CUMULATIVE
# playtime, the player reaches a 7500px sheet of dead-flat ice, crosses it in ~10 seconds
# with every input ignored, and nothing spawns on it. The first one earns an achievement.
#
# Division of labour. This file owns WHEN and the state machine; TerrainGenerator owns the
# geometry (arm_lake / is_lake_world_x), the six spawners own their own suppression, Player
# owns is_jump_suppressed, and SaveStore owns the counters. Nothing here reaches into a
# system to do that system's job.
#
# WHY A SIBLING NODE RATHER THAN PART OF GameManager. GameManager is already 700 lines and
# owns state, screens, score and the shop; this is orthogonal run-scoped direction with its
# own clock. BiomeDirector is the exact precedent -- a sibling Node that reads terrain plus
# persisted session state, drives presentation, and hard-skips headless.
#
# IT IS NOT A GameManager.State. The game is still PLAYING throughout: the player keeps
# running, the timer keeps counting, coins already on screen are still collectable.
# GameManager.set_state() remains the only thing in the project allowed to touch
# get_tree().paused or a screen's visibility, and nothing here goes near either.
#
# Default process_mode (INHERIT), so this freezes on every menu for free -- the lake cannot
# advance while the game is paused, and the playtime clock it reads is Main.elapsed_time,
# which stops for the same reason.

# Cumulative playtime between lakes. The count of completed lakes doubles as the index of
# the next threshold, so this is a plain multiple rather than a running deadline that could
# drift or be lost.
const LAKE_INTERVAL_SECONDS: float = 1200.0

# A lake may only begin once the current RUN has passed this mark, and it buys two things
# with one constant.
#
# 1. A DETERMINISTIC 10 SECONDS. The lake is a fixed 7500px, so its duration is set by how
#    fast the player is moving. SpeedManager caps at MAX_SPEED (750) at t=120s, so past that
#    the crossing is exactly 10.0s. Fire it during the ramp instead -- five seconds into a
#    fresh run, at ~150 px/s -- and the same 7500px becomes nearly a minute of nothing.
# 2. QUICK RESTART. reload_current_scene() resets the run clock but not the saved playtime,
#    so without this a restart taken just before a due lake would drop one ~4 seconds into
#    the new run, mid-ramp.
#
# THE COST, and it is real: the lake only appears in runs lasting over ~2 minutes, so in
# practice the cadence is "the first good run after 20 minutes of play" rather than strictly
# every 20 minutes. That was the project owner's choice between the two.
const LAKE_MIN_RUN_TIME: float = 130.0

# Playtest override for LAKE_INTERVAL_SECONDS. Any value > 0 replaces it, so a lake can be
# reached in seconds instead of twenty minutes.
#
# Plain var, not @export, like every other knob in this project: an exported float
# serialises into main.tscn and ships silently, which is the world_rebase_enabled regression
# exactly (CLAUDE.md, "Things that break silently"). shipping_values_check fails on it.
#
# Note this does NOT bypass LAKE_MIN_RUN_TIME -- a playtest still has to survive past the
# speed ramp, deliberately, because that is the state the real lake happens in.
var debug_lake_interval_override: float = 0.0

@export var player_path: NodePath = NodePath("../Player")
@export var terrain_generator_path: NodePath = NodePath("../TerrainGenerator")

enum Phase { IDLE, ARMED, ACTIVE, DONE }

signal lake_started
signal lake_finished(total_lakes: int)

var phase: Phase = Phase.IDLE
var player: Player
var terrain_generator: TerrainGenerator
var main_node: Main
var services: GameServices
var is_headless: bool = false

var lake_start_x: float = 0.0
var lake_end_x: float = 0.0


func _ready() -> void:
	# Checked directly rather than through services.is_headless, which is assigned in
	# GameServices._ready() and can still read false here -- the ordering trap CLAUDE.md
	# records twice. This is not an optimisation: the trigger reads cumulative playtime out
	# of the developer's own save.dat, so an ungated director would inject terrain into
	# every gate depending on how much the developer had played. That is the
	# apply_upgrades() failure (48/48 -> 8) with a different field.
	is_headless = DisplayServer.get_name() == "headless"
	if is_headless:
		set_physics_process(false)
		return

	player = get_node_or_null(player_path) as Player
	terrain_generator = get_node_or_null(terrain_generator_path) as TerrainGenerator
	main_node = get_parent() as Main
	services = GameServices.resolve(self)
	if player == null or terrain_generator == null or main_node == null or services == null:
		# Null-guarded rather than fatal: a missing lake is a missing set piece, not a
		# broken game, and this must never be the thing that stops someone playing.
		push_warning("FrozenLakeDirector disabled: missing player, terrain, Main or services.")
		set_physics_process(false)
		return

	player.died.connect(_on_player_died)


func _physics_process(_delta: float) -> void:
	match phase:
		Phase.IDLE:
			if is_lake_due():
				try_arm()
		Phase.ARMED:
			if player.global_position.x >= lake_start_x:
				begin_lake()
		Phase.ACTIVE:
			if player.global_position.x >= lake_end_x:
				finish_lake()
		Phase.DONE:
			pass


func get_interval_seconds() -> float:
	return debug_lake_interval_override if debug_lake_interval_override > 0.0 else LAKE_INTERVAL_SECONDS


# Total playtime including the part of this run that has not been banked yet. Reads
# Main.elapsed_time directly rather than asking GameManager to bank early: banking writes to
# disk, and this is asked every physics frame.
func get_total_playtime_seconds() -> float:
	return services.save_store.total_playtime_seconds + main_node.elapsed_time


func is_lake_due() -> bool:
	if main_node.elapsed_time < LAKE_MIN_RUN_TIME:
		return false
	var next_threshold: float = float(services.save_store.frozen_lake_count + 1) * get_interval_seconds()
	return get_total_playtime_seconds() >= next_threshold


# Commits the geometry, if the player is somewhere it is sane to do that from. A rejected
# frame simply retries on the next one -- the threshold stays crossed, so the lake arms at
# the first clean frame rather than being lost.
#
# These conditions REDUCE but cannot eliminate entering the lake mid-boost or mid-glide, and
# no arm-time check can: arm_lake() commits a segment past the chunk cache watermark, which
# is 3072px (~4.1s at cap) ahead, while a speed boost lasts 3s and powerups spawn at
# player_x + 1500 -- inside that window. So entry is made HARMLESS rather than conditional;
# see begin_lake().
func try_arm() -> void:
	if not player.is_on_floor() or player.is_jump_ascending:
		return
	if not terrain_generator.has_ground_at_world_x(player.global_position.x):
		return
	if not terrain_generator.arm_lake():
		return
	lake_start_x = terrain_generator.get_lake_start_x()
	lake_end_x = terrain_generator.get_lake_end_x()
	phase = Phase.ARMED


# Locks input and nothing else. Deliberately does NOT force-end a speed boost or a glide:
# the lake is flat, void-free and obstacle-free, so a boost across it is safe by
# construction -- it is the same grounded skim that already carries a boost over a chasm,
# on real ground. And because there is no void, PowerupManager.can_end_effect() lets both
# expire normally on their own timers, through the one bookkeeping-safe path. Force-ending
# would add a call site to the active_effects/Player desync class documented in player.gd,
# to save at most 3s of a 10s set piece.
func begin_lake() -> void:
	phase = Phase.ACTIVE
	player.is_jump_suppressed = true
	lake_started.emit()


func finish_lake() -> void:
	phase = Phase.DONE
	player.is_jump_suppressed = false
	# lake_segment_index is deliberately left set on the generator. The segment is behind the
	# player and must stay in the height field -- clearing it would make every cached chunk
	# and collision sample behind the player disagree with a fresh sample of the same x.
	services.save_store.frozen_lake_count += 1
	services.save_store.save_to_disk()
	lake_finished.emit(services.save_store.frozen_lake_count)


# Near-impossible on a lake -- nothing there can kill anyone -- but if the stall watchdog or
# anything else ends the run mid-crossing, the input lock must not survive it. The scene
# reload a restart does would clear it anyway; this covers the death screen, which does not
# reload until the player chooses to.
func _on_player_died() -> void:
	if phase == Phase.ACTIVE:
		player.is_jump_suppressed = false
	phase = Phase.DONE
