extends Node

class_name SfxPlayer

# One-shot gameplay sound effects (jump, coin, powerup, death), routed through the
# "SFX" bus so the pause screen's sound slider controls them independently of music.
# A pool of players rather than one, because a coin pickup and a jump landing can
# overlap in the same frame and each needs its own voice.
#
# Placeholder sounds -- generated tones, same role as the ColorRect/Polygon2D
# placeholder art. Swap the .wav files under assets/audio/sfx/ for real assets later;
# nothing else here needs to change.

const JUMP_SOUND: AudioStream = preload("res://assets/audio/sfx/jump.wav")
const COIN_SOUND: AudioStream = preload("res://assets/audio/sfx/coin.wav")
const POWERUP_SOUND: AudioStream = preload("res://assets/audio/sfx/powerup.wav")
const DEATH_SOUND: AudioStream = preload("res://assets/audio/sfx/death.wav")
const CLICK_SOUND: AudioStream = preload("res://assets/audio/sfx/click.wav")

const SFX_BUS: StringName = &"SFX"
# Comfortably above the number of gameplay sounds that can land on the same frame
# (jump + coin + powerup, at most) with headroom for a fast coin streak.
const POOL_SIZE: int = 6

var players: Array[AudioStreamPlayer] = []
var next_player_index: int = 0
var is_headless: bool = false


func _ready() -> void:
	# PROCESS_MODE_ALWAYS, because the sounds that matter most all fire on a frame the tree
	# is being paused. GameManager.set_state() sets get_tree().paused for DEAD, PAUSED and
	# SHOP, and death, menu clicks and the shop's purchase click are all played from inside
	# those transitions -- under the default INHERIT the pool stops processing on the same
	# frame the sound is requested, so the one-shot is cut or never audible.
	#
	# Safe in the direction that matters: nothing here plays on its own. Every voice is
	# started by an explicit play_*() call, and while paused the only code still running to
	# make one is the menu UI, which is exactly what should be audible. GameManager already
	# uses ALWAYS for the same reason.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Deliberately NOT read from Services.is_headless: in at least one headless
	# harness (freeze_replay_runner.gd), root.add_child(main) runs synchronously
	# inside the script's _init(), which calls this _ready() before the Services
	# autoload's own deferred _ready() has flushed -- so Services.is_headless is
	# still its default `false` at that point. Measured 2026-08-03: SfxPlayer built
	# its voice pool and actually played the coin sound during a "headless" freeze
	# gate, leaking an AudioStreamWAV/AudioStreamPlaybackWAV pair every run. Same
	# root-cause class as the session_seed ordering trap in architecture.md --
	# computing this locally, the same one-line check Services itself uses, removes
	# the cross-autoload ordering dependency entirely.
	is_headless = DisplayServer.get_name() == "headless"
	if is_headless:
		return

	for i: int in range(POOL_SIZE):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "Voice%d" % i
		player.bus = SFX_BUS
		add_child(player)
		players.append(player)


func play_jump() -> void:
	play(JUMP_SOUND)


func play_coin() -> void:
	play(COIN_SOUND)


func play_powerup() -> void:
	play(POWERUP_SOUND)


func play_death() -> void:
	play(DEATH_SOUND)


func play_click() -> void:
	play(CLICK_SOUND)


func play(stream: AudioStream) -> void:
	if is_headless or players.is_empty():
		return

	var player: AudioStreamPlayer = players[next_player_index]
	next_player_index = (next_player_index + 1) % players.size()
	player.stream = stream
	player.play()
