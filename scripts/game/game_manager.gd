extends Node


@export var player_path: NodePath = NodePath("../Player")
@export var death_message_label_path: NodePath = NodePath("../CanvasLayer/YouDiedLabel")

var player: Player
var death_message_label: Label


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


func _on_player_died() -> void:
	get_tree().paused = true
	death_message_label.visible = true
