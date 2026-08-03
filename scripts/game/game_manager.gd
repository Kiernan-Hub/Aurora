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
@export var pause_screen_path: NodePath = NodePath("../CanvasLayer/PauseScreen")
@export var pause_button_path: NodePath = NodePath("../CanvasLayer/PauseButton")
@export var resume_button_path: NodePath = NodePath("../CanvasLayer/PauseScreen/CenterContainer/VBoxContainer/ResumeButton")
@export var pause_restart_button_path: NodePath = NodePath("../CanvasLayer/PauseScreen/CenterContainer/VBoxContainer/PauseRestartButton")
@export var music_slider_path: NodePath = NodePath("../CanvasLayer/PauseScreen/CenterContainer/VBoxContainer/MusicSlider")
@export var sfx_slider_path: NodePath = NodePath("../CanvasLayer/PauseScreen/CenterContainer/VBoxContainer/SfxSlider")

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
var pause_screen: Control
var pause_button: Button
var resume_button: Button
var pause_restart_button: Button
var music_slider: HSlider
var sfx_slider: HSlider
var coin_spawner: CoinSpawner
var coin_label: Label
var coin_count: int = 0
var powerup_manager: PowerupManager

# Was previously implicit in get_tree().paused plus which Control happened to be
# visible. That works for two screens and stops working at four -- a pause screen makes
# "paused" ambiguous (menu pause or death pause?) and the audio layer needs to know
# which transition it is reacting to. set_state() is now the ONE place that touches
# get_tree().paused or screen visibility.
enum State { START, PLAYING, PAUSED, DEAD }

signal state_changed(new_state: State)

var state: State = State.START
# Null in headless harness runs -- see GameServices. Every use is null-guarded, and a
# null store simply means this run's best score is not persisted, which is exactly
# what a probe wants anyway.
var services: GameServices


func _ready() -> void:
	# _notification below must still arrive while the tree is paused -- a focus-out that
	# happens on the pause screen, or a back press on the death screen, is exactly when
	# paused-ness is already true. This node has no _process/_physics_process, so ALWAYS
	# costs nothing.
	process_mode = Node.PROCESS_MODE_ALWAYS
	services = GameServices.resolve(self)
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

	death_screen = get_node_or_null(death_screen_path) as Control
	death_stats_label = get_node_or_null(death_stats_label_path) as Label
	restart_button = get_node_or_null(restart_button_path) as Button
	if death_screen == null or death_stats_label == null or restart_button == null:
		push_error("GameManager requires a death screen at %s." % death_screen_path)
		return

	restart_button.pressed.connect(_on_restart_pressed)
	player.died.connect(_on_player_died)

	pause_screen = get_node_or_null(pause_screen_path) as Control
	pause_button = get_node_or_null(pause_button_path) as Button
	resume_button = get_node_or_null(resume_button_path) as Button
	pause_restart_button = get_node_or_null(pause_restart_button_path) as Button
	music_slider = get_node_or_null(music_slider_path) as HSlider
	sfx_slider = get_node_or_null(sfx_slider_path) as HSlider
	if pause_screen == null or pause_button == null or resume_button == null or pause_restart_button == null or music_slider == null or sfx_slider == null:
		push_error("GameManager requires a pause screen at %s with a pause button, resume/restart buttons and two volume sliders." % pause_screen_path)
		return

	pause_button.pressed.connect(_on_pause_pressed)
	resume_button.pressed.connect(_on_resume_pressed)
	pause_restart_button.pressed.connect(_on_restart_pressed)

	if services != null:
		music_slider.value = services.save_store.music_volume
		sfx_slider.value = services.save_store.sfx_volume
	music_slider.value_changed.connect(_on_music_volume_changed)
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)

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

	# require_start_screen=false is the harness opt-out, and it has to skip straight to
	# PLAYING rather than sitting on START -- see the comment on that var.
	set_state(State.START if require_start_screen else State.PLAYING)


# The single owner of get_tree().paused and of every screen's visibility. Nothing else
# in the project may set either; if a new transition is needed, add it to the enum.
func set_state(new_state: State) -> void:
	state = new_state

	start_screen.visible = new_state == State.START
	pause_screen.visible = new_state == State.PAUSED
	death_screen.visible = new_state == State.DEAD
	# Hidden on the menus so it can't be tapped while a screen is up, and hidden on
	# death because the death screen owns the input at that point.
	pause_button.visible = new_state == State.PLAYING

	get_tree().paused = new_state != State.PLAYING
	state_changed.emit(new_state)


# Android lifecycle. There was no _notification anywhere in the project before
# 2026-08-03, which meant three device-only failures that desktop testing cannot show:
# the back button quit the app mid-run, a notification/call/app-switch left the game in
# PLAYING while the player couldn't see it, and neither was recoverable.
#
# Everything here routes through set_state(), which stays the single owner of
# get_tree().paused and screen visibility -- these are new *triggers*, not a second
# pause mechanism.
func _notification(what: int) -> void:
	match what:
		# Back button. project.godot sets quit_on_go_back=false so this arrives instead
		# of Godot quitting for us. Mid-run it pauses (losing a run to a stray back press
		# is the thing being fixed); on the pause screen it resumes, which is what the
		# gesture means there. On START/DEAD there is nothing in progress to protect, and
		# refusing to exit at all would be its own annoyance, so back does quit.
		NOTIFICATION_WM_GO_BACK_REQUEST:
			match state:
				State.PLAYING:
					set_state(State.PAUSED)
				State.PAUSED:
					_on_resume_pressed()
				_:
					get_tree().quit()
		# Focus loss: notification shade, incoming call, recents switcher. Only PLAYING
		# needs handling -- the other three states are already paused. Deliberately does
		# NOT auto-resume on focus-in: coming back to a running game you can't react to
		# yet is how you lose a run to the OS.
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			if state == State.PLAYING:
				set_state(State.PAUSED)


func _on_start_pressed() -> void:
	set_state(State.PLAYING)
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
	# record_run persists only when the run beat the stored best, so the label below
	# always reads the post-update value and "(New Best!)" is never stale.
	var is_new_best: bool = false
	var best_score: int = 0
	if services != null:
		is_new_best = services.save_store.record_run(coin_count, main.elapsed_time)
		best_score = services.save_store.best_score
	var best_suffix: String = " (New Best!)" if is_new_best else ""
	death_stats_label.text = "Coins: %d\nTime: %s\nBest: %d%s" % [coin_count, main.format_elapsed_time(main.elapsed_time), best_score, best_suffix]
	set_state(State.DEAD)


func _on_pause_pressed() -> void:
	if state != State.PLAYING:
		return
	set_state(State.PAUSED)


func _on_resume_pressed() -> void:
	set_state(State.PLAYING)
	# Same reasoning as _on_start_pressed: this tap dismissed a Control, and without
	# an explicit release the global Input singleton still reports "ui_accept" as
	# just-pressed on the first physics frame back in play -- a free jump on resume.
	Input.action_release(&"ui_accept")


func _on_music_volume_changed(value: float) -> void:
	if services != null:
		services.set_music_volume(value)


func _on_sfx_volume_changed(value: float) -> void:
	if services != null:
		services.set_sfx_volume(value)


func _on_restart_pressed() -> void:
	# Unpause before the reload: the tree-wide paused flag is not reset by
	# reload_current_scene(), so leaving it true would rebuild the scene into a frozen
	# world. The reloaded GameManager sets its own state in _ready().
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_coin_collected(value: int) -> void:
	var multiplier: float = powerup_manager.coin_multiplier if powerup_manager != null else 1.0
	coin_count += int(value * multiplier)
	update_coin_label()


func update_coin_label() -> void:
	coin_label.text = "Coins: %d" % coin_count
