extends Node

class_name AuroraDirector

# Owns timing and the single cosmetic ramp; SkyBackdrop owns the curtains.
# One event per run, due 30 minutes after the last completed event, with enough night
# remaining for the entire event. Reserves a future flat, then waits for safe entry.
# Spawners and PowerupManager own exclusion; actual Aurora flight is still unbuilt.
const AURORA_INTERVAL_SECONDS: float = 1800.0
const AURORA_DURATION_SECONDS: float = 45.0
const AURORA_FADE_SECONDS: float = 8.0
const NIGHT_THRESHOLD: float = 0.8
# Space to let an existing glide/boost finish and land before the presentation starts.
# A failed/late entry skips the appearance without undoing the immutable flat.
const ENTRY_WAIT_DISTANCE: float = 10000.0
const MIN_RECOVERY_DISTANCE: float = 2048.0
const BODY_CLEARANCE: float = 128.0
# One gentle lift at the broad crest. Long ramps keep takeoff/landing inside the protected flat.
const FLIGHT_RISE_START_SECONDS: float = 27.0
const FLIGHT_RISE_END_SECONDS: float = 32.0
const FLIGHT_RELEASE_START_SECONDS: float = 40.0
const FLIGHT_RELEASE_END_SECONDS: float = 45.0

# Plain vars, never exported. shipping_values_check protects the defaults.
# Preview completions never grant progress or change an existing deadline.
var debug_aurora_interval_override: float = 10.0
var debug_aurora_ignore_night: bool = true

@export var player_path: NodePath = NodePath("../Player")
@export var biome_director_path: NodePath = NodePath("../BiomeDirector")
@export var sky_backdrop_path: NodePath = NodePath("../SkyBackdrop")

enum Phase { IDLE, PENDING_ENTRY, ACTIVE, RECOVERY, DONE }
signal aurora_started
signal aurora_finished(total_auroras: int)

var phase: Phase = Phase.IDLE
var player: Player
var biome_director: BiomeDirector
var sky_backdrop: Node
var aurora_wash: Node
var blade_glow: Node
var snow: Node
var wisps: Node
var wings: Node
var main_node: Main
var services: GameServices
var is_headless: bool = false
var active_elapsed: float = 0.0
var terrain: TerrainGenerator
var obstacle_spawner: ObstacleSpawner
var powerup_spawner: PowerupSpawner
var powerups: PowerupManager
var lake: FrozenLakeDirector
var flat_start_x: float = 0.0
var flat_end_x: float = 0.0
var recovery_distance: float = MIN_RECOVERY_DISTANCE
var dependencies_ready: bool = false
# Latched at entry so turning off a preview knob cannot make the event earn credit.
var is_preview: bool = false


func _ready() -> void:
	# Local check: autoload readiness cannot be assumed in script harnesses.
	# Headless gates must not read or write the player's progression.
	is_headless = DisplayServer.get_name() == "headless"
	if is_headless:
		set_physics_process(false)
		return
	if not resolve_dependencies():
		push_warning("AuroraDirector disabled: missing required dependency.")
		set_physics_process(false)
		return
	player.died.connect(_on_player_died)
	schedule_if_unscheduled()


# Also used by the isolated integration probe, which supplies an in-memory save
# before driving the lifecycle explicitly. Headless startup itself stays disabled.
func resolve_dependencies() -> bool:
	player = get_node_or_null(player_path) as Player
	biome_director = get_node_or_null(biome_director_path) as BiomeDirector
	sky_backdrop = get_node_or_null(sky_backdrop_path)
	aurora_wash = get_node_or_null("../AuroraWash")
	blade_glow = get_node_or_null("../AuroraBladeGlow")
	snow = get_node_or_null("../SnowDrift/SnowParticles")
	wisps = get_node_or_null("../AuroraWisps")
	wings = get_node_or_null("../AuroraWings")
	main_node = get_parent() as Main
	services = GameServices.resolve(self)
	terrain = get_node_or_null("../TerrainGenerator") as TerrainGenerator
	obstacle_spawner = get_node_or_null("../TerrainGenerator/ObstacleSpawner") as ObstacleSpawner
	powerup_spawner = get_node_or_null("../TerrainGenerator/PowerupSpawner") as PowerupSpawner
	powerups = get_node_or_null("../PowerupManager") as PowerupManager
	lake = get_node_or_null("../FrozenLakeDirector") as FrozenLakeDirector
	dependencies_ready = player != null and biome_director != null and main_node != null and services != null \
		and terrain != null and obstacle_spawner != null and powerup_spawner != null \
		and powerups != null and lake != null
	return dependencies_ready


func _physics_process(delta: float) -> void:
	match phase:
		Phase.IDLE:
			schedule_if_unscheduled()
			if wants_reservation():
				try_reserve()
		Phase.PENDING_ENTRY:
			is_preview = is_preview or is_preview_mode()
			if player.global_position.x < flat_start_x + recovery_distance:
				return
			# Never chase night inside a finite span or start a shortened encounter.
			if not has_duration_room() or not is_sky_ready() or has_existing_conflict():
				phase = Phase.RECOVERY
				return
			begin_aurora()
		Phase.ACTIVE:
			is_preview = is_preview or is_preview_mode()
			# Fail closed if a future consumer violates the movement/position contract.
			if not terrain.is_aurora_flat_world_x(player.global_position.x) \
					or player.is_boosting or player.is_glide_active:
				push_blend(0.0)
				phase = Phase.RECOVERY
				return
			active_elapsed += delta
			push_blend(get_aurora_blend())
			if active_elapsed >= get_total_seconds():
				finish_aurora()
		Phase.RECOVERY:
			if player.global_position.x >= flat_end_x + BODY_CLEARANCE:
				phase = Phase.DONE
		Phase.DONE:
			pass


func wants_reservation() -> bool:
	return phase == Phase.IDLE and dependencies_ready \
		and is_aurora_due() and is_sky_ready()


# Existing set pieces win; otherwise an eligible Aurora has priority because it
# needs night. Both directors ask this same rule, independent of their tree order.
func blocks_lake_arming() -> bool:
	return phase in [Phase.PENDING_ENTRY, Phase.ACTIVE, Phase.RECOVERY] or wants_reservation()


func get_recovery_distance() -> float:
	var camera: Camera2D = main_node.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return MIN_RECOVERY_DISTANCE
	return maxf(MIN_RECOVERY_DISTANCE, get_viewport().get_visible_rect().size.x / camera.zoom.x + 512.0)


func get_furthest_body_edge(spawner: Node) -> float:
	var furthest: float = player.global_position.x
	for child: Node in spawner.get_children():
		var shape: CollisionShape2D = child.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if shape != null and shape.shape != null:
			var bounds: Rect2 = shape.global_transform * shape.shape.get_rect()
			furthest = maxf(furthest, bounds.end.x)
	return furthest


func try_reserve() -> bool:
	if not wants_reservation() or lake.phase in [FrozenLakeDirector.Phase.ARMED, FrozenLakeDirector.Phase.ACTIVE]:
		return false
	recovery_distance = get_recovery_distance()
	# Move the cache beyond every existing obstacle/pickup and the current viewport.
	# The write-ahead arm will then be farther still. No visible objects are removed.
	var clear_after: float = maxf(get_furthest_body_edge(obstacle_spawner), get_furthest_body_edge(powerup_spawner))
	clear_after = maxf(clear_after, player.global_position.x + recovery_distance)
	terrain.ensure_segment_cache_for_world_x(clear_after + BODY_CLEARANCE)
	# Boost/glide cannot start on this flat; ordinary movement is bounded by MAX_SPEED.
	var length: float = SpeedManager.MAX_SPEED * get_total_seconds() + ENTRY_WAIT_DISTANCE + 2.0 * recovery_distance
	if not terrain.arm_aurora_flat(length):
		return false
	flat_start_x = terrain.get_aurora_flat_start_x()
	flat_end_x = terrain.get_aurora_flat_end_x()
	is_preview = is_preview_mode()
	phase = Phase.PENDING_ENTRY
	return true


func has_duration_room() -> bool:
	return flat_end_x - player.global_position.x >= SpeedManager.MAX_SPEED * get_total_seconds() \
		+ maxf(recovery_distance, get_recovery_distance())


func has_existing_conflict() -> bool:
	for spawner: Node in [obstacle_spawner, powerup_spawner]:
		for child: Node in spawner.get_children():
			if child is Powerup and not PowerupManager.is_aurora_excluded_effect((child as Powerup).effect):
				continue
			var shape: CollisionShape2D = child.get_node_or_null("CollisionShape2D") as CollisionShape2D
			if shape != null and shape.shape != null:
				var bounds: Rect2 = shape.global_transform * shape.shape.get_rect()
				if bounds.end.x >= player.global_position.x - BODY_CLEARANCE and bounds.position.x < flat_end_x:
					return true
	return false


func get_interval_seconds() -> float:
	return AURORA_INTERVAL_SECONDS


func get_total_seconds() -> float:
	return AURORA_DURATION_SECONDS + AURORA_FADE_SECONDS * 2.0


func get_aurora_blend() -> float:
	if phase != Phase.ACTIVE:
		return 0.0
	var fade_in: float = clampf(active_elapsed / AURORA_FADE_SECONDS, 0.0, 1.0)
	var fade_out: float = clampf((get_total_seconds() - active_elapsed) / AURORA_FADE_SECONDS, 0.0, 1.0)
	return fade_in * fade_out


func get_total_playtime_seconds() -> float:
	if main_node.game_manager != null:
		return main_node.game_manager.get_total_playtime_seconds()
	# With no GameManager nothing has banked this run.
	return services.save_store.total_playtime_seconds + main_node.elapsed_time


func is_preview_mode() -> bool:
	return debug_aurora_interval_override > 0.0 or debug_aurora_ignore_night \
			or (biome_director != null and (biome_director.debug_biome_seconds > 0.0 \
			or biome_director.debug_pin_intro_biome))


func schedule_if_unscheduled() -> void:
	if is_preview_mode() or services.save_store.next_aurora_due_seconds >= 0.0:
		return
	# At scene load or after a start-screen reset, banked time is the clock origin.
	# Persist once so subsequent launches cannot keep postponing the first event.
	services.save_store.next_aurora_due_seconds = services.save_store.total_playtime_seconds + get_interval_seconds()
	services.save_store.save_to_disk()


func is_aurora_due() -> bool:
	if debug_aurora_interval_override > 0.0:
		return main_node.elapsed_time >= debug_aurora_interval_override
	var deadline: float = services.save_store.next_aurora_due_seconds
	return deadline >= 0.0 and get_total_playtime_seconds() >= deadline


func is_sky_ready() -> bool:
	if debug_aurora_ignore_night:
		return true
	return biome_director.get_night_amount() >= NIGHT_THRESHOLD \
			and biome_director.get_minimum_night_ahead(get_total_seconds(), PowerupManager.SPEED_BOOST_SPEED) >= NIGHT_THRESHOLD


func begin_aurora() -> void:
	if phase != Phase.PENDING_ENTRY or not player.is_on_floor() or player.is_jump_ascending \
			or player.is_boosting or player.is_glide_active \
			or player.global_position.x < flat_start_x + recovery_distance \
			or not has_duration_room() or not is_sky_ready() or has_existing_conflict():
		return
	phase = Phase.ACTIVE
	active_elapsed = 0.0
	is_preview = is_preview or is_preview_mode()
	aurora_started.emit()


func finish_aurora() -> void:
	if phase != Phase.ACTIVE or active_elapsed < get_total_seconds():
		return
	phase = Phase.RECOVERY
	push_blend(0.0)
	if is_preview or is_preview_mode():
		return
	# Keep the saved clock and its new deadline in the same snapshot. Banking through
	# GameManager advances its watermark too, so a later pause cannot count time twice.
	if main_node.game_manager == null:
		push_warning("Aurora completion cannot be saved without GameManager.")
		return
	main_node.game_manager.bank_playtime()
	services.save_store.aurora_count += 1
	services.save_store.next_aurora_due_seconds = get_total_playtime_seconds() + get_interval_seconds()
	services.save_store.save_to_disk()
	aurora_finished.emit(services.save_store.aurora_count)


func push_blend(blend: float) -> void:
	if player != null:
		player.set_aurora_flight_strength(get_aurora_flight_strength(blend))
	if sky_backdrop != null and sky_backdrop.has_method("apply_aurora"):
		sky_backdrop.call("apply_aurora", blend, active_elapsed)
	if aurora_wash != null and aurora_wash.has_method("apply_aurora"):
		aurora_wash.call("apply_aurora", blend, active_elapsed)
	if blade_glow != null and blade_glow.has_method("apply_aurora"):
		blade_glow.call("apply_aurora", blend, active_elapsed)
	if snow != null and snow.has_method("apply_aurora"):
		snow.call("apply_aurora", get_aurora_snow_blend(blend), active_elapsed)
	if wisps != null and wisps.has_method("apply_aurora"):
		wisps.call("apply_aurora", blend, active_elapsed)
	if wings != null and wings.has_method("apply_aurora"):
		wings.call("apply_aurora", blend, active_elapsed)
	if terrain != null:
		terrain.set_aurora_ice_blend(blend)


func get_aurora_flight_strength(base_blend: float) -> float:
	if base_blend <= 0.0:
		return 0.0
	var rise: float = smoothstep(FLIGHT_RISE_START_SECONDS, FLIGHT_RISE_END_SECONDS, active_elapsed)
	var release: float = 1.0 - smoothstep(
		FLIGHT_RELEASE_START_SECONDS, FLIGHT_RELEASE_END_SECONDS, active_elapsed)
	return clampf(base_blend * rise * release, 0.0, 1.0)


# Snow gathers gently after the sky arrives, reaches one broad crest halfway through,
# then relaxes before the final fade. It derives from the one event clock and base
# visibility envelope; there is no second timer or tween to pause/clean up.
func get_aurora_snow_blend(base_blend: float) -> float:
	if base_blend <= 0.0:
		return 0.0
	var progress: float = clampf(active_elapsed / get_total_seconds(), 0.0, 1.0)
	var broad_crest: float = 0.65 + 0.35 * sin(PI * progress)
	return clampf(base_blend * broad_crest, 0.0, 1.0)


func _on_player_died() -> void:
	push_blend(0.0)
	phase = Phase.DONE
