extends Node

class_name GameManager


@export var player_path: NodePath = NodePath("../Player")
@export var start_screen_path: NodePath = NodePath("../CanvasLayer/StartScreen")
@export var start_button_path: NodePath = NodePath("../CanvasLayer/StartScreen/StartButton")
@export var death_screen_path: NodePath = NodePath("../CanvasLayer/DeathScreen")
@export var death_stats_label_path: NodePath = NodePath("../CanvasLayer/DeathScreen/CenterContainer/VBoxContainer/StatsLabel")
@export var restart_button_path: NodePath = NodePath("../CanvasLayer/DeathScreen/CenterContainer/VBoxContainer/RestartButton")
@export var coin_spawner_path: NodePath = NodePath("../TerrainGenerator/CoinSpawner")
@export var coin_label_path: NodePath = NodePath("../CanvasLayer/CoinLabel")
@export var powerup_manager_path: NodePath = NodePath("../PowerupManager")

# Deliberately not @export, same reasoning as Main.world_rebase_enabled: this is
# the "is this a real playthrough" switch, and main.tscn silently serializing it to
# false would silently disable the start screen for weeks the same way that bug did
# for world rebasing. Any headless debug harness that steps many physics frames
# expecting the player to actually move (freeze_replay_runner.gd, freeze_search.gd,
# floor_flicker_probe.gd, camera_shake_probe.gd, freeze_ab_runner.gd,
# stall_recovery_probe.gd) must set this to false in code before add_child, the
# same way they set Main.world_rebase_enabled -- otherwise
# the whole run sits paused on the start screen and the gate trivially "passes" by
# doing nothing. Not needed by terrain_invariant_check.gd: it awaits exactly one
# physics_frame (SceneTree's frame signals fire regardless of pause) then samples
# the height field directly, without depending on player movement or GameManager
# at all. Any NEW harness that steps many frames needs the same opt-out line.
var require_start_screen: bool = true

var player: Player
var main: Main
var start_screen: Control
var start_button: Button
var death_screen: Control
var death_stats_label: Label
var restart_button: Button
var coin_spawner: CoinSpawner
var coin_label: Label
var coin_count: int = 0
var powerup_manager: PowerupManager
var best_score: int = 0

const SAVE_PATH: String = "user://save.dat"


func _ready() -> void:
	main = get_parent() as Main
	player = get_node_or_null(player_path) as Player
	if main == null or player == null:
		push_error("GameManager requires a Main parent and a Player node at %s." % player_path)
		return

	start_screen = get_node_or_null(start_screen_path) as Control
	start_button = get_node_or_null(start_button_path) as Button
	if start_screen == null or start_button == null:
		push_error("GameManager requires a start screen at %s." % start_screen_path)
		return

	start_button.pressed.connect(_on_start_pressed)
	if require_start_screen:
		start_screen.visible = true
		get_tree().paused = true
	else:
		start_screen.visible = false

	death_screen = get_node_or_null(death_screen_path) as Control
	death_stats_label = get_node_or_null(death_stats_label_path) as Label
	restart_button = get_node_or_null(restart_button_path) as Button
	if death_screen == null or death_stats_label == null or restart_button == null:
		push_error("GameManager requires a death screen at %s." % death_screen_path)
		return

	death_screen.visible = false
	restart_button.pressed.connect(_on_restart_pressed)
	player.died.connect(_on_player_died)

	coin_spawner = get_node_or_null(coin_spawner_path) as CoinSpawner
	coin_label = get_node_or_null(coin_label_path) as Label
	if coin_spawner == null or coin_label == null:
		push_error("GameManager requires a CoinSpawner at %s and a coin label at %s." % [coin_spawner_path, coin_label_path])
		return

	coin_spawner.coin_collected.connect(_on_coin_collected)
	update_coin_label()

	powerup_manager = get_node_or_null(powerup_manager_path) as PowerupManager
	if powerup_manager == null:
		push_error("GameManager requires a PowerupManager at %s." % powerup_manager_path)
		return

	best_score = load_best_score()


func _on_start_pressed() -> void:
	get_tree().paused = false
	start_screen.visible = false
	# InputSetup binds a mouse-button event to "ui_accept" so taps also register as
	# that action (see input_setup.gd) -- meaning the SAME tap that just dismissed
	# this screen would otherwise still read as "just pressed" on the very first
	# physics frame of gameplay, since the global Input singleton's action state
	# isn't reset by a Control consuming the click for its own gui_input/pressed
	# signal. Left unhandled, that becomes a free involuntary jump at spawn.
	# Forcing a release here (before Player's next _physics_process reads it) is
	# the standard fix, and it's scoped entirely to this transition -- nothing
	# about jumping DURING a run is affected.
	Input.action_release(&"ui_accept")


func _on_player_died() -> void:
	get_tree().paused = true
	var is_new_best: bool = coin_count > best_score
	if is_new_best:
		best_score = coin_count
		save_best_score(best_score)
	var best_suffix: String = " (New Best!)" if is_new_best else ""
	death_stats_label.text = "Coins: %d\nTime: %s\nBest: %d%s" % [coin_count, main.format_elapsed_time(main.elapsed_time), best_score, best_suffix]
	death_screen.visible = true


func load_best_score() -> int:
	if not FileAccess.file_exists(SAVE_PATH):
		return 0
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return 0
	var data: Variant = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY or not data.has("best_score"):
		return 0
	return int(data["best_score"])


func save_best_score(value: int) -> void:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("GameManager failed to open %s for writing." % SAVE_PATH)
		return
	file.store_string(JSON.stringify({"best_score": value}))


func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_coin_collected(value: int) -> void:
	var multiplier: float = powerup_manager.coin_multiplier if powerup_manager != null else 1.0
	coin_count += int(value * multiplier)
	update_coin_label()


func update_coin_label() -> void:
	coin_label.text = "Coins: %d" % coin_count
