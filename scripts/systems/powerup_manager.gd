extends Node

class_name PowerupManager

@export var player_path: NodePath = NodePath("../Player")
@export var powerup_spawner_path: NodePath = NodePath("../TerrainGenerator/PowerupSpawner")
@export var powerup_label_path: NodePath = NodePath("../CanvasLayer/PowerupLabel")
@export var terrain_generator_path: NodePath = NodePath("../TerrainGenerator")
@export var coin_spawner_path: NodePath = NodePath("../TerrainGenerator/CoinSpawner")

# One pair of signals for every effect, rather than a _started/_ended pair per kind.
# The per-kind form was already two effects' worth of signal; at six kinds it is twelve
# declarations and twelve connect() calls for listeners that (like GameManager's powerup
# SFX) do not care which kind fired.
signal effect_started(effect: StringName)
signal effect_ended(effect: StringName)

const EFFECT_SPEED_BOOST: StringName = &"speed_boost"
const EFFECT_JUMP_BOOST: StringName = &"jump_boost"
const EFFECT_COIN_MAGNET: StringName = &"coin_magnet"
const EFFECT_COIN_DOUBLER: StringName = &"coin_doubler"
const EFFECT_SHIELD: StringName = &"shield"
const EFFECT_GLIDE: StringName = &"glide"

const SPEED_BOOST_DURATION: float = 3.0
const SPEED_BOOST_SPEED: float = 1000.0
const COIN_MULTIPLIER: float = 2.0

const JUMP_BOOST_DURATION: float = 3.0
# sqrt(2): jump height is proportional to velocity SQUARED
# (h = v^2 / (2*GRAVITY)), so doubling the HEIGHT the player asked for means
# multiplying JUMP_VELOCITY by sqrt(2), not by 2.
# Read by terrain_invariant_check.gd's CHASM_NOT_CLEARABLE assertion -- the name and
# location of this constant are part of that gate's contract.
const JUMP_BOOST_VELOCITY_MULTIPLIER: float = 1.4142135

const COIN_MAGNET_DURATION: float = 4.0
const COIN_DOUBLER_DURATION: float = 6.0
const COIN_DOUBLER_MULTIPLIER: float = 2.0
const GLIDE_DURATION: float = 7.0

# How long each timed effect lasts. An effect absent from this table is untimed and is
# never expired by _process() -- it is owned by whatever consumes it (a shield is spent
# on a hit, not on a clock).
const EFFECT_DURATIONS: Dictionary = {
	EFFECT_SPEED_BOOST: SPEED_BOOST_DURATION,
	EFFECT_JUMP_BOOST: JUMP_BOOST_DURATION,
	EFFECT_COIN_MAGNET: COIN_MAGNET_DURATION,
	EFFECT_COIN_DOUBLER: COIN_DOUBLER_DURATION,
	EFFECT_GLIDE: GLIDE_DURATION,
}

# Label line per effect; the "%.1f" is fed the remaining seconds. An effect with no entry
# here runs silently.
const EFFECT_LABEL_FORMATS: Dictionary = {
	EFFECT_SPEED_BOOST: "BOOST! %.1fs",
	EFFECT_JUMP_BOOST: "JUMP x2! %.1fs",
	EFFECT_COIN_MAGNET: "MAGNET! %.1fs",
	EFFECT_COIN_DOUBLER: "COINS x2! %.1fs",
	EFFECT_GLIDE: "GLIDE! %.1fs",
}

# Coin multiplier contributed by each effect while active. The wallet applies the MAX of
# these, never the product -- see refresh_coin_multiplier(). A doubler taken mid-speed-boost
# stays at x2, not x4, and doesn't drop early if the boost ends first.
const EFFECT_COIN_MULTIPLIERS: Dictionary = {
	EFFECT_SPEED_BOOST: COIN_MULTIPLIER,
	EFFECT_COIN_DOUBLER: COIN_DOUBLER_MULTIPLIER,
}

# Effects that must not be allowed to expire while the player is over a void.
# See can_end_effect() for why this list exists and what happens without it.
const VOID_GUARDED_EFFECTS: Array[StringName] = [EFFECT_SPEED_BOOST, EFFECT_GLIDE]

var player: Player
var powerup_spawner: PowerupSpawner
var powerup_label: Label
var terrain_generator: TerrainGenerator
var coin_spawner: CoinSpawner
# effect StringName -> seconds remaining. Membership IS "active"; an untimed effect sits
# in here with INF remaining, so one dictionary answers both questions.
var active_effects: Dictionary = {}
# Read on every coin pickup by GameManager._on_coin_collected(). Recomputed from
# active_effects on every start/end rather than assigned by each effect, so two
# multiplier effects overlapping cannot leave a stale value behind when the first ends.
var coin_multiplier: float = 1.0


func _ready() -> void:
	player = get_node_or_null(player_path) as Player
	powerup_spawner = get_node_or_null(powerup_spawner_path) as PowerupSpawner
	powerup_label = get_node_or_null(powerup_label_path) as Label
	# The generator the PowerupSpawner already hangs off, resolved separately because
	# can_end_effect() needs it. Not added to the required set below: a null one only
	# costs the void guard, and can_end_effect() degrades to unguarded expiry.
	terrain_generator = get_node_or_null(terrain_generator_path) as TerrainGenerator
	# Same tier as terrain_generator: a null one only costs the magnet effect, which
	# degrades to "does nothing" rather than crashing.
	coin_spawner = get_node_or_null(coin_spawner_path) as CoinSpawner
	if player == null or powerup_spawner == null or powerup_label == null:
		push_error("PowerupManager requires a Player, a PowerupSpawner at %s, and a powerup label at %s." % [powerup_spawner_path, powerup_label_path])
		set_process(false)
		return

	powerup_spawner.powerup_collected.connect(start_effect)
	# Shield is consumed by absorb_hit(), not by _process()'s timer -- Player is the
	# only thing that knows when that happens, so it tells us via this signal.
	player.shield_consumed.connect(_on_shield_consumed)
	powerup_label.visible = false


func _process(delta: float) -> void:
	var label_lines: Array[String] = []

	# Keys copied first: end_effect() erases from active_effects, and mutating a
	# Dictionary while iterating it is undefined.
	for effect: StringName in active_effects.keys():
		var time_remaining: float = active_effects[effect]
		if time_remaining == INF:
			continue

		time_remaining -= delta
		active_effects[effect] = time_remaining
		if time_remaining <= 0.0:
			if can_end_effect(effect):
				end_effect(effect)
			continue
		if EFFECT_LABEL_FORMATS.has(effect):
			label_lines.append(EFFECT_LABEL_FORMATS[effect] % time_remaining)

	powerup_label.visible = not label_lines.is_empty()
	if powerup_label.visible:
		powerup_label.text = "\n".join(label_lines)


func is_effect_active(effect: StringName) -> bool:
	return active_effects.has(effect)


func start_effect(effect: StringName) -> void:
	# INF for an untimed effect, so _process() skips it and only its owner can end it.
	active_effects[effect] = EFFECT_DURATIONS.get(effect, INF)
	match effect:
		EFFECT_SPEED_BOOST:
			apply_speed_boost_start()
		EFFECT_JUMP_BOOST:
			player.start_jump_boost(JUMP_BOOST_VELOCITY_MULTIPLIER)
		EFFECT_COIN_MAGNET:
			if coin_spawner != null:
				coin_spawner.set_magnet_active(true)
		EFFECT_SHIELD:
			player.gain_shield()
		EFFECT_GLIDE:
			player.start_glide()
	# EFFECT_COIN_DOUBLER has no case: EFFECT_DURATIONS, EFFECT_LABEL_FORMATS and
	# EFFECT_COIN_MULTIPLIERS above are the entire implementation, nothing else to start.
	refresh_coin_multiplier()
	effect_started.emit(effect)


func end_effect(effect: StringName) -> void:
	if not active_effects.has(effect):
		return

	active_effects.erase(effect)
	match effect:
		EFFECT_SPEED_BOOST:
			player.end_boost()
		EFFECT_JUMP_BOOST:
			player.end_jump_boost()
		EFFECT_COIN_MAGNET:
			if coin_spawner != null:
				coin_spawner.set_magnet_active(false)
		EFFECT_GLIDE:
			player.end_glide()
	refresh_coin_multiplier()
	effect_ended.emit(effect)


# Player has already cleared has_shield and its own visual by the time this fires; all
# that's left here is our bookkeeping, so active_effects and the label stop reporting a
# shield that's already gone.
func _on_shield_consumed() -> void:
	end_effect(EFFECT_SHIELD)


func apply_speed_boost_start() -> void:
	# Captured before start_boost() snaps the player onto the grounded model, so an
	# airborne pickup still reads as airborne even though the boost itself makes
	# is_on_floor() irrelevant for the rest of its duration.
	var was_airborne: bool = not player.is_on_floor()
	player.start_boost(SPEED_BOOST_SPEED)
	if was_airborne:
		player.play_flight_effect(SPEED_BOOST_DURATION)


func refresh_coin_multiplier() -> void:
	# MAX, not product. Two x2 effects overlapping would otherwise pay x4 for the
	# duration of the overlap and drop back to x2 when the first ended, which reads as
	# the coin counter randomly changing rate mid-pickup.
	var highest_multiplier: float = 1.0
	for effect: StringName in active_effects:
		highest_multiplier = maxf(highest_multiplier, EFFECT_COIN_MULTIPLIERS.get(effect, 1.0))
	coin_multiplier = highest_multiplier


# A timed effect in VOID_GUARDED_EFFECTS must not expire while the player is over a chasm.
#
# For the speed boost: it forces Player's grounded, gravity-free velocity model whether or
# not there is a floor (see the LOAD-BEARING FOR CHASMS note at player.gd's
# is_using_grounded_model), which is exactly what carries a boosting player across a void --
# and it has to, because jump input is suppressed for the boost's full 3s. Dropping the boost
# mid-void restores gravity at lip height with no way to jump: unavoidable death, the same
# class as the obstacle/boost issue in CLAUDE.md's Known issues. Extending by the <=0.25s it
# takes to cross the void at 1000 px/s is invisible and removes the failure mode outright.
#
# Any future effect that is the only thing holding the player up over a void belongs on that
# list for the same reason.
func can_end_effect(effect: StringName) -> bool:
	if terrain_generator == null or not VOID_GUARDED_EFFECTS.has(effect):
		return true
	return terrain_generator.has_ground_at_world_x(player.global_position.x)


# Kept as named entry points because external callers depend on them: chasm_probe.gd
# starts a boost directly to measure a boosted void crossing.
func start_speed_boost() -> void:
	start_effect(EFFECT_SPEED_BOOST)


func start_jump_boost() -> void:
	start_effect(EFFECT_JUMP_BOOST)


func start_glide() -> void:
	start_effect(EFFECT_GLIDE)
