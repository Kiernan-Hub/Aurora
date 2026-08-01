extends Node


@export var player_path: NodePath = NodePath("../Player")
@export var death_screen_path: NodePath = NodePath("../CanvasLayer/DeathScreen")
@export var death_stats_label_path: NodePath = NodePath("../CanvasLayer/DeathScreen/CenterContainer/VBoxContainer/StatsLabel")
@export var restart_button_path: NodePath = NodePath("../CanvasLayer/DeathScreen/CenterContainer/VBoxContainer/RestartButton")
@export var coin_spawner_path: NodePath = NodePath("../TerrainGenerator/CoinSpawner")
@export var coin_label_path: NodePath = NodePath("../CanvasLayer/CoinLabel")

var player: Player
var main: Main
var death_screen: Control
var death_stats_label: Label
var restart_button: Button
var coin_spawner: CoinSpawner
var coin_label: Label
var coin_count: int = 0


func _ready() -> void:
	main = get_parent() as Main
	player = get_node_or_null(player_path) as Player
	if main == null or player == null:
		push_error("GameManager requires a Main parent and a Player node at %s." % player_path)
		return

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


func _on_player_died() -> void:
	get_tree().paused = true
	death_stats_label.text = "Coins: %d\nTime: %s" % [coin_count, main.format_elapsed_time(main.elapsed_time)]
	death_screen.visible = true


func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_coin_collected(value: int) -> void:
	coin_count += value
	update_coin_label()


func update_coin_label() -> void:
	coin_label.text = "Coins: %d" % coin_count
