extends Node

class_name AuroraAudio

# Dedicated long-form event voice. It never occupies the one-shot SFX pool and routes through the
# existing Music bus, so the saved music-volume setting remains the sole user gain control.
const AURORA_BED: AudioStream = preload("res://assets/audio/ambient/aurora_bed.wav")
const MUSIC_BUS: StringName = &"Music"
const MAX_LINEAR_GAIN: float = 0.55
const SILENT_DB: float = -80.0

@export var game_manager_path: NodePath = NodePath("../GameManager")

var audio_player: AudioStreamPlayer
var game_manager: GameManager
var disabled: bool = false
var applied_linear_gain: float = 0.0


func _ready() -> void:
	# As with SfxPlayer, never touch the audio server in script harnesses.
	if DisplayServer.get_name() == "headless":
		disabled = true
		return
	game_manager = get_node_or_null(game_manager_path) as GameManager
	if game_manager == null:
		disabled = true
		push_warning("AuroraAudio disabled: missing GameManager.")
		return
	audio_player = AudioStreamPlayer.new()
	audio_player.name = "AmbientPlayer"
	var event_stream: AudioStreamWAV = AURORA_BED.duplicate() as AudioStreamWAV
	if event_stream != null:
		event_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		audio_player.stream = event_stream
	else:
		audio_player.stream = AURORA_BED
	audio_player.bus = MUSIC_BUS
	audio_player.volume_db = SILENT_DB
	add_child(audio_player)
	game_manager.state_changed.connect(_on_game_state_changed)


func apply_aurora(blend: float, elapsed: float) -> void:
	if disabled:
		return
	applied_linear_gain = clampf(blend, 0.0, 1.0) * MAX_LINEAR_GAIN
	if applied_linear_gain <= 0.0:
		audio_player.stop()
		audio_player.volume_db = SILENT_DB
		return
	if not audio_player.playing:
		var loop_length: float = AURORA_BED.get_length()
		audio_player.play(fposmod(elapsed, loop_length) if loop_length > 0.0 else 0.0)
	audio_player.volume_db = linear_to_db(applied_linear_gain)


func _on_game_state_changed(new_state: GameManager.State) -> void:
	if disabled:
		return
	if new_state == GameManager.State.PAUSED:
		audio_player.stream_paused = true
	elif new_state == GameManager.State.PLAYING:
		audio_player.stream_paused = false
	else:
		applied_linear_gain = 0.0
		audio_player.stop()
		audio_player.volume_db = SILENT_DB
