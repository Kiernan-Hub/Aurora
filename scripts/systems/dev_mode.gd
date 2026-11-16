extends RefCounted

class_name DevMode

# DEV MODE: one switch on the start screen that turns the game's existing debug knobs on at
# runtime, so a feature that takes minutes or hours to reach can be seen in one short run. It
# writes no source, so nothing can be left flipped in a commit (shipping_values_check still sees
# every knob at its shipping default), and it does not exist in a release build or under
# --headless: both buttons and every effect are behind is_available().
#
# The switch is a file in user://, so it survives closing the game and a reinstall of the same
# debug build. Main._enter_tree() calls apply() before any child's _ready(), so each system
# starts its run already holding the dev value.
#
# WHAT IT CHANGES (the values below are the whole feature; tune them here):
#   speed             starts at SpeedManager.MAX_SPEED, with the run clock still at zero
#   wallet            topped up to WALLET, IN THE REAL SAVE. Reset Progress in the shop undoes it.
#   biomes            a whole biome every BIOME_SECONDS instead of every ~100s of travel
#   powerups          INTERVAL_SCALE of the usual wait
#   chest tiers       cycle Normal / Rare / Aurora for a quick preview
#   chests, rare coin PICKUP_INTERVAL_SCALE of the usual wait. Measured: a chest about every 40s,
#                     because each still waits for a legal spot (flat take-off, clear of hazards)
#   frozen lake       every LAKE_INTERVAL seconds of play, from LAKE_MIN_RUN_TIME into a run
#   aurora            AURORA_TIME seconds into each run, day or night
#   The Melt          portal from MELT_TIME seconds, still only in a legal pickup slot
# and, with the second switch (CAN'T DIE): hazards pass through the player and a fall into a void
# puts them back on the far side, so the late tiers and every chasm can be reached in one run.
const FLAG_PATH: String = "user://dev_mode"
const WALLET: int = 99999
const BIOME_SECONDS: float = 20.0
const POWERUP_INTERVAL_SCALE: float = 0.3
const PICKUP_INTERVAL_SCALE: float = 0.15
const LAKE_INTERVAL: float = 180.0
const LAKE_MIN_RUN_TIME: float = 45.0
const AURORA_TIME: float = 100.0
const MELT_TIME: float = 12.0

static var is_loaded: bool = false
static var is_enabled: bool = false
static var is_invincible: bool = false


static func is_available() -> bool:
	return OS.is_debug_build() and DisplayServer.get_name() != "headless"


static func is_on() -> bool:
	load_flags()
	return is_enabled


static func is_cant_die() -> bool:
	load_flags()
	return is_enabled and is_invincible


static func load_flags() -> void:
	if is_loaded:
		return
	is_loaded = true
	if not is_available() or not FileAccess.file_exists(FLAG_PATH):
		return
	is_enabled = true
	is_invincible = FileAccess.get_file_as_string(FLAG_PATH).strip_edges() == "invincible"


static func set_flags(enabled: bool, invincible: bool) -> void:
	if not is_available():
		return
	is_loaded = true
	is_enabled = enabled
	is_invincible = enabled and invincible
	if not enabled:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(FLAG_PATH))
		return
	var file: FileAccess = FileAccess.open(FLAG_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string("invincible" if is_invincible else "on")


# Called by Main._enter_tree(), before any child is ready. Every node is looked up null-guarded:
# a scene missing one simply does not get that knob.
static func apply(main: Node) -> void:
	if not is_on():
		return
	var game_manager: GameManager = main.get_node_or_null("GameManager") as GameManager
	if game_manager != null:
		game_manager.debug_start_wallet = WALLET
	var biome_director: BiomeDirector = main.get_node_or_null("BiomeDirector") as BiomeDirector
	if biome_director != null:
		biome_director.debug_biome_seconds = BIOME_SECONDS
	var powerup_spawner: PowerupSpawner = main.get_node_or_null("TerrainGenerator/PowerupSpawner") as PowerupSpawner
	if powerup_spawner != null:
		powerup_spawner.debug_interval_scale = POWERUP_INTERVAL_SCALE
	var rare_coin_spawner: RareCoinSpawner = main.get_node_or_null("TerrainGenerator/RareCoinSpawner") as RareCoinSpawner
	if rare_coin_spawner != null:
		rare_coin_spawner.debug_interval_scale = PICKUP_INTERVAL_SCALE
		rare_coin_spawner.debug_cycle_chest_tiers = true
	var lake_director: FrozenLakeDirector = main.get_node_or_null("FrozenLakeDirector") as FrozenLakeDirector
	if lake_director != null:
		lake_director.debug_lake_interval_override = LAKE_INTERVAL
		lake_director.debug_lake_min_run_time_override = LAKE_MIN_RUN_TIME
	var aurora_director: AuroraDirector = main.get_node_or_null("AuroraDirector") as AuroraDirector
	if aurora_director != null:
		aurora_director.debug_aurora_interval_override = AURORA_TIME
		aurora_director.debug_aurora_ignore_night = true
	var player: Player = main.get_node_or_null("Player") as Player
	var melt: Node = main.get_node_or_null("MeltDirector")
	if melt != null:
		melt.set("debug_first_seconds", MELT_TIME)
	if player != null:
		player.debug_invincible = is_cant_die()
