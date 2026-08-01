extends Node


@export var player_path: NodePath = NodePath("../Player")
@export var death_message_label_path: NodePath = NodePath("../CanvasLayer/YouDiedLabel")
@export var coin_spawner_path: NodePath = NodePath("../TerrainGenerator/CoinSpawner")
@export var coin_label_path: NodePath = NodePath("../CanvasLayer/CoinLabel")

var player: Player
var death_message_label: Label
var coin_spawner: CoinSpawner
var coin_label: Label
var coin_count: int = 0


func _ready() -> void:
	player = get_node_or_null(player_path) as Player
	if player == null:
		push_error("GameManager requires a Player node at %s." % player_path)
		return

	death_message_label = get_node_or_null(death_message_label_path) as Label
	if death_message_label == null:
		push_error("GameManager requires a death label at %s." % death_message_label_path)
		return

	death_message_label.visible = false
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
	death_message_label.visible = true


func _on_coin_collected(value: int) -> void:
	coin_count += value
	update_coin_label()


func update_coin_label() -> void:
	coin_label.text = "Coins: %d" % coin_count
