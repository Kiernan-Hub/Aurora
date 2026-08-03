extends Node2D

class_name PowerupSpawner

# Same reasoning as CoinSpawner/ObstacleSpawner: a child of TerrainGenerator so
# world rebasing (which shifts TerrainGenerator.position.y directly in main.gd)
# carries every spawned powerup along for free.
@export var terrain_generator_path: NodePath = NodePath("..")
@export var player_path: NodePath = NodePath("../../Player")

signal powerup_collected(effect: StringName)

const SPEED_POWERUP_SCENE: PackedScene = preload("res://scenes/pickups/speed_powerup.tscn")
const JUMP_POWERUP_SCENE: PackedScene = preload("res://scenes/pickups/jump_powerup.tscn")
# Above the sampled surface, low enough to be grabbed while grounded (player
# capsule half-height is 24px) -- same reasoning as CoinSpawner's clearance.
const POWERUP_SURFACE_CLEARANCE: float = 40.0
# TESTING cadence: placed to be reached a few seconds into a run at starting
# speed (300px/s) -- roughly the t=3s and t=10s marks, offset from each other
# so the two never land on top of one another once both repeat on the same
# spacing. Flip POWERUP_SPACING_WORLD_X to the real "once a minute" cadence
# (already is: 500px/s cap speed * 60s = 30000px) once the effect is verified.
const SPEED_POWERUP_FIRST_WORLD_X: float = 900.0
const JUMP_POWERUP_FIRST_WORLD_X: float = 3200.0
const POWERUP_SPACING_WORLD_X: float = 30000.0
# Mirrors the chunk spawners' forward lookahead so pickups are never seen
# popping into existence.
const SPAWN_LOOKAHEAD_WORLD_X: float = 1500.0
# Well behind the player is safe to free -- an uncollected pickup this far back
# (e.g. jumped over) is unreachable again.
const DESPAWN_BEHIND_WORLD_X: float = 1500.0

var terrain_generator: TerrainGenerator
var player: CharacterBody2D
var next_speed_powerup_world_x: float = SPEED_POWERUP_FIRST_WORLD_X
var next_jump_powerup_world_x: float = JUMP_POWERUP_FIRST_WORLD_X
var active_powerups: Array[Node2D] = []


func _ready() -> void:
	terrain_generator = get_node_or_null(terrain_generator_path) as TerrainGenerator
	player = get_node_or_null(player_path) as CharacterBody2D
	if terrain_generator == null or player == null:
		push_error("PowerupSpawner requires a valid terrain_generator_path and player_path.")
		set_physics_process(false)


func _physics_process(_delta: float) -> void:
	var lookahead_world_x: float = player.global_position.x + SPAWN_LOOKAHEAD_WORLD_X

	while next_speed_powerup_world_x <= lookahead_world_x:
		spawn_powerup(SPEED_POWERUP_SCENE, next_speed_powerup_world_x, &"speed_boost")
		next_speed_powerup_world_x += POWERUP_SPACING_WORLD_X

	while next_jump_powerup_world_x <= lookahead_world_x:
		spawn_powerup(JUMP_POWERUP_SCENE, next_jump_powerup_world_x, &"jump_boost")
		next_jump_powerup_world_x += POWERUP_SPACING_WORLD_X

	var despawn_world_x: float = player.global_position.x - DESPAWN_BEHIND_WORLD_X
	for index: int in range(active_powerups.size() - 1, -1, -1):
		var powerup: Node2D = active_powerups[index]
		if not is_instance_valid(powerup):
			active_powerups.remove_at(index)
		elif powerup.position.x < despawn_world_x:
			powerup.free()
			active_powerups.remove_at(index)


func spawn_powerup(scene: PackedScene, world_x: float, effect: StringName) -> void:
	var world_y: float = terrain_generator.ground_y + terrain_generator.get_terrain_height(world_x) - POWERUP_SURFACE_CLEARANCE
	var powerup: Powerup = scene.instantiate() as Powerup
	powerup.position = Vector2(world_x, world_y)
	powerup.collected.connect(_on_powerup_collected.bind(effect))
	add_child(powerup)
	active_powerups.append(powerup)


func _on_powerup_collected(effect: StringName) -> void:
	powerup_collected.emit(effect)
