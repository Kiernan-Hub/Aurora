extends Node

class_name GameManager


@export var player_path: NodePath = NodePath("../Player")
@export var start_screen_path: NodePath = NodePath("../CanvasLayer/StartScreen")
@export var start_button_path: NodePath = NodePath("../CanvasLayer/StartScreen/CenterContainer/VBoxContainer/MenuButtons/StartButton")
@export var start_upgrades_button_path: NodePath = NodePath("../CanvasLayer/StartScreen/CenterContainer/VBoxContainer/MenuButtons/UpgradesButton")
@export var death_screen_path: NodePath = NodePath("../CanvasLayer/DeathScreen")
@export var death_stats_label_path: NodePath = NodePath("../CanvasLayer/DeathScreen/CenterContainer/VBoxContainer/StatsLabel")
@export var restart_button_path: NodePath = NodePath("../CanvasLayer/DeathScreen/CenterContainer/VBoxContainer/RestartButton")
@export var death_home_button_path: NodePath = NodePath("../CanvasLayer/DeathScreen/CenterContainer/VBoxContainer/DeathHomeButton")
@export var coin_spawner_path: NodePath = NodePath("../TerrainGenerator/CoinSpawner")
@export var coin_label_path: NodePath = NodePath("../CanvasLayer/CoinLabel")
@export var powerup_manager_path: NodePath = NodePath("../PowerupManager")
@export var sfx_player_path: NodePath = NodePath("../SfxPlayer")
@export var pause_screen_path: NodePath = NodePath("../CanvasLayer/PauseScreen")
@export var pause_button_path: NodePath = NodePath("../CanvasLayer/PauseButton")
@export var resume_button_path: NodePath = NodePath("../CanvasLayer/PauseScreen/CenterContainer/VBoxContainer/ResumeButton")
@export var pause_restart_button_path: NodePath = NodePath("../CanvasLayer/PauseScreen/CenterContainer/VBoxContainer/PauseRestartButton")
@export var pause_home_button_path: NodePath = NodePath("../CanvasLayer/PauseScreen/CenterContainer/VBoxContainer/PauseHomeButton")
@export var music_slider_path: NodePath = NodePath("../CanvasLayer/PauseScreen/CenterContainer/VBoxContainer/MusicSlider")
@export var sfx_slider_path: NodePath = NodePath("../CanvasLayer/PauseScreen/CenterContainer/VBoxContainer/SfxSlider")
# The shop is wired OPTIONALLY -- see the note above its block in _ready().
@export var shop_screen_path: NodePath = NodePath("../CanvasLayer/ShopScreen")
@export var shop_wallet_label_path: NodePath = NodePath("../CanvasLayer/ShopScreen/CenterContainer/VBoxContainer/WalletLabel")
@export var shop_jump_label_path: NodePath = NodePath("../CanvasLayer/ShopScreen/CenterContainer/VBoxContainer/JumpLabel")
@export var shop_jump_button_path: NodePath = NodePath("../CanvasLayer/ShopScreen/CenterContainer/VBoxContainer/BuyJumpButton")
@export var shop_close_button_path: NodePath = NodePath("../CanvasLayer/ShopScreen/CenterContainer/VBoxContainer/CloseButton")
@export var death_shop_button_path: NodePath = NodePath("../CanvasLayer/DeathScreen/CenterContainer/VBoxContainer/ShopButton")
@export var reset_progress_button_path: NodePath = NodePath("../CanvasLayer/ShopScreen/CenterContainer/VBoxContainer/ResetProgressButton")
@export var reset_confirm_dialog_path: NodePath = NodePath("../CanvasLayer/ShopScreen/ResetConfirmDialog")

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
var start_upgrades_button: Button
var death_screen: Control
var death_stats_label: Label
var restart_button: Button
var death_home_button: Button
var pause_screen: Control
var pause_button: Button
var resume_button: Button
var pause_restart_button: Button
var pause_home_button: Button
var music_slider: HSlider
var sfx_slider: HSlider
var coin_spawner: CoinSpawner
var coin_label: Label
var coin_count: int = 0
# Per completed 360 landed. Routed through _on_coin_collected so a trick reward gets
# the same coin_multiplier (doubler powerup) and coin SFX as a real coin -- one score
# path, not two.
const TRICK_COIN_REWARD: int = 5
var powerup_manager: PowerupManager
var sfx_player: SfxPlayer
var shop_screen: Control
var shop_wallet_label: Label
var shop_jump_label: Label
var shop_jump_button: Button
var shop_close_button: Button
var death_shop_button: Button
var reset_progress_button: Button
var reset_confirm_dialog: ConfirmationDialog

# Was previously implicit in get_tree().paused plus which Control happened to be
# visible. That works for two screens and stops working at four -- a pause screen makes
# "paused" ambiguous (menu pause or death pause?) and the audio layer needs to know
# which transition it is reacting to. set_state() is now the ONE place that touches
# get_tree().paused or screen visibility.
#
# SHOP is entered only from DEAD (the between-runs upgrade screen) and returns there, so
# it needs no new pause semantics: `paused = new_state != PLAYING` below already covers
# it. Purchases apply to the NEXT run, because leaving the shop leads to a restart, and
# the rebuilt GameManager reads the save file in _ready(). There is deliberately no path
# that mutates player stats mid-run.
enum State { START, PLAYING, PAUSED, DEAD, SHOP }

signal state_changed(new_state: State)

var state: State = State.START
# Which screen SHOP is a modal over: the shop is reachable from either the START
# screen (the new Upgrades button) or the DEAD screen (the original entry point), and
# closing it must return to whichever one opened it -- otherwise closing the shop from
# the main menu would incorrectly reveal the (irrelevant, stale) death screen behind it.
var shop_return_state: State = State.DEAD

# Set right before a "quick restart" reload_current_scene() call and consumed by the
# next _ready(). A local var can't survive the reload -- the whole script instance is
# destroyed and rebuilt -- so this has to be static to cross that boundary. Always
# false except in the one-frame window between _on_quick_restart_pressed() and the
# rebuilt GameManager's _ready() reading it.
static var pending_quick_restart: bool = false
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
	sfx_player = get_node_or_null(sfx_player_path) as SfxPlayer
	if main == null or player == null or sfx_player == null:
		push_error("GameManager requires a Main parent, a Player node at %s, and an SfxPlayer at %s." % [player_path, sfx_player_path])
		return

	player.jumped.connect(_on_player_jumped)
	player.trick_completed.connect(_on_player_trick_completed)

	start_screen = get_node_or_null(start_screen_path) as Control
	start_button = get_node_or_null(start_button_path) as Button
	if start_screen == null or start_button == null:
		push_error("GameManager requires a start screen at %s." % start_screen_path)
		return

	start_button.pressed.connect(_on_start_pressed)

	death_screen = get_node_or_null(death_screen_path) as Control
	death_stats_label = get_node_or_null(death_stats_label_path) as Label
	restart_button = get_node_or_null(restart_button_path) as Button
	death_home_button = get_node_or_null(death_home_button_path) as Button
	if death_screen == null or death_stats_label == null or restart_button == null or death_home_button == null:
		push_error("GameManager requires a death screen at %s with restart and home buttons." % death_screen_path)
		return

	# "Restart" jumps straight back into a new run (see _on_quick_restart_pressed);
	# "Home" is the one that lands on the START/main screen, same as the pause
	# screen's Home button and the same handler.
	restart_button.pressed.connect(_on_quick_restart_pressed)
	death_home_button.pressed.connect(_on_restart_pressed)
	player.died.connect(_on_player_died)

	pause_screen = get_node_or_null(pause_screen_path) as Control
	pause_button = get_node_or_null(pause_button_path) as Button
	resume_button = get_node_or_null(resume_button_path) as Button
	pause_restart_button = get_node_or_null(pause_restart_button_path) as Button
	pause_home_button = get_node_or_null(pause_home_button_path) as Button
	music_slider = get_node_or_null(music_slider_path) as HSlider
	sfx_slider = get_node_or_null(sfx_slider_path) as HSlider
	if pause_screen == null or pause_button == null or resume_button == null or pause_restart_button == null or pause_home_button == null or music_slider == null or sfx_slider == null:
		push_error("GameManager requires a pause screen at %s with a pause button, resume/restart/home buttons and two volume sliders." % pause_screen_path)
		return

	# button_down, NOT pressed. BaseButton emits `pressed` on pointer-UP, which leaves
	# the game live for the whole down..up interval -- and the pointer-DOWN that started
	# it is also a jump, because InputSetup binds left-click to "ui_accept" and player.gd
	# polls that action. The old defence was Input.action_release() in Main._input, on the
	# assumption it cancels the just-pressed edge. Measured 2026-08-03, it does not: with a
	# verified control (press alone -> 1 jump), press+release issued before the same physics
	# frame STILL jumped, because is_action_just_pressed() compares the press FRAME STAMP
	# and does not re-check the pressed flag. That is why the reported symptom was "pauses
	# AND jumps" rather than one or the other.
	#
	# Pausing on the DOWN edge sidesteps the whole question: it runs during event flush,
	# before this frame's physics, so get_tree().paused is already true when the Player
	# would have polled and _physics_process never runs. Independent of any Input
	# frame-stamp semantics. The hit-test guard in Main._input stays -- it is what stops
	# the separate TOUCH path from calling buffer_jump() directly.
	#
	# The action_release() calls on the START and RESUME transitions are unaffected by the
	# finding above: there the press happened while the tree was paused on a menu, i.e. on
	# an EARLIER frame, so its stamp is already stale by the first gameplay frame.
	pause_button.button_down.connect(_on_pause_pressed)
	resume_button.pressed.connect(_on_resume_pressed)
	pause_restart_button.pressed.connect(_on_quick_restart_pressed)
	pause_home_button.pressed.connect(_on_restart_pressed)

	if services != null:
		music_slider.value = services.save_store.music_volume
		sfx_slider.value = services.save_store.sfx_volume
	music_slider.value_changed.connect(_on_music_volume_changed)
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	# value_changed applies the volume live; drag_ended is what persists it. See
	# GameServices.set_music_volume for why the two are separated. drag_ended does not
	# fire for a keyboard-driven slider, so set_state() flushes on leaving PAUSED too.
	music_slider.drag_ended.connect(_on_volume_drag_ended)
	sfx_slider.drag_ended.connect(_on_volume_drag_ended)

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

	# unbind(1) because the pickup SFX is the same for every kind -- this listener does not
	# care which effect started, and one connection now covers every future powerup.
	powerup_manager.effect_started.connect(_on_powerup_collected.unbind(1))

	# The shop is wired LAST and OPTIONALLY: push_error on failure but deliberately no
	# `return`. Every block above is a hard gate, and any one of them firing skips
	# set_state() entirely -- which leaves a fully running game underneath an
	# un-dismissable dark overlay, because no screen's visibility was ever initialised.
	# Eight of those already exist; a ninth for a between-runs convenience screen would
	# be a bad trade. A missing shop costs the shop, not the game.
	shop_screen = get_node_or_null(shop_screen_path) as Control
	shop_wallet_label = get_node_or_null(shop_wallet_label_path) as Label
	shop_jump_label = get_node_or_null(shop_jump_label_path) as Label
	shop_jump_button = get_node_or_null(shop_jump_button_path) as Button
	shop_close_button = get_node_or_null(shop_close_button_path) as Button
	death_shop_button = get_node_or_null(death_shop_button_path) as Button
	start_upgrades_button = get_node_or_null(start_upgrades_button_path) as Button
	reset_progress_button = get_node_or_null(reset_progress_button_path) as Button
	reset_confirm_dialog = get_node_or_null(reset_confirm_dialog_path) as ConfirmationDialog
	if shop_screen == null or shop_wallet_label == null or shop_jump_label == null or shop_jump_button == null or shop_close_button == null or death_shop_button == null or start_upgrades_button == null or reset_progress_button == null or reset_confirm_dialog == null:
		push_error("GameManager could not wire the upgrade shop at %s; the game runs without it." % shop_screen_path)
	else:
		shop_jump_button.pressed.connect(_on_buy_jump_pressed)
		shop_close_button.pressed.connect(_on_shop_close_pressed)
		death_shop_button.pressed.connect(_on_shop_pressed)
		start_upgrades_button.pressed.connect(_on_start_shop_pressed)
		reset_progress_button.pressed.connect(_on_reset_progress_pressed)
		reset_confirm_dialog.confirmed.connect(_on_reset_progress_confirmed)

	# Must run before the first gameplay frame. Safe here: Player is an earlier sibling
	# in main.tscn so its _ready() has already run, and upgrade_jump_multiplier is only
	# read inside _physics_process, which cannot start until every _ready() completes.
	apply_upgrades()

	# require_start_screen=false is the harness opt-out, and it has to skip straight to
	# PLAYING rather than sitting on START -- see the comment on that var. A quick
	# restart (see _on_quick_restart_pressed) takes the same PLAYING shortcut, via the
	# static flag rather than this instance var, because it has to survive the reload.
	var quick_restart: bool = GameManager.pending_quick_restart
	GameManager.pending_quick_restart = false
	if quick_restart:
		set_state(State.PLAYING)
		# Same reasoning as _on_start_pressed / _on_resume_pressed: the click that
		# triggered the reload is still "just pressed" on the Input singleton, which
		# survives reload_current_scene() because it isn't part of the scene tree.
		Input.action_release(&"ui_accept")
	else:
		set_state(State.START if require_start_screen else State.PLAYING)


# The single owner of get_tree().paused and of every screen's visibility. Nothing else
# in the project may set either; if a new transition is needed, add it to the enum.
func set_state(new_state: State) -> void:
	var previous_state: State = state
	state = new_state

	# START/DEAD stay visible underneath SHOP: the shop is a modal over whichever screen
	# opened it (see shop_return_state), and closing it returns there without a flicker.
	start_screen.visible = new_state == State.START or (new_state == State.SHOP and shop_return_state == State.START)
	pause_screen.visible = new_state == State.PAUSED
	death_screen.visible = new_state == State.DEAD or (new_state == State.SHOP and shop_return_state == State.DEAD)
	# Null-guarded because the shop is optional wiring -- see _ready().
	if shop_screen != null:
		shop_screen.visible = new_state == State.SHOP
	# Hidden on the menus so it can't be tapped while a screen is up, and hidden on
	# death because the death screen owns the input at that point.
	pause_button.visible = new_state == State.PLAYING

	get_tree().paused = new_state != State.PLAYING
	# Leaving the pause screen is the end of any settings interaction, and the only
	# flush point that also catches a slider moved by keyboard (which emits value_changed
	# but never drag_ended). Writing here rather than per-step is the whole point -- see
	# GameServices.set_music_volume.
	if previous_state == State.PAUSED and new_state != State.PAUSED and services != null:
		services.save_settings()
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
				# The shop is a modal over whichever screen opened it, so back means
				# "close the modal", exactly like its own Back button -- NOT quit.
				# Without this case it falls through to the default below and exits
				# the app from a menu.
				State.SHOP:
					set_state(shop_return_state)
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
	sfx_player.play_click()
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


func _on_player_jumped() -> void:
	# Jump SFX muted 2026-08-04: the placeholder WAV is grating on a run where you jump
	# constantly. The signal, the pool voice and SfxPlayer.play_jump() all stay wired, so
	# restoring it is uncommenting one line once there is a real sound.
	pass


func _on_powerup_collected() -> void:
	sfx_player.play_powerup()


func _on_player_trick_completed(spin_count: int) -> void:
	_on_coin_collected(spin_count * TRICK_COIN_REWARD)
	# Functional payoff on top of the coins: land a spin, get a real speed_boost, same
	# effect a pickup grants (PowerupManager.start_speed_boost -> start_effect). No new
	# velocity model -- this rides the existing LOAD-BEARING FOR CHASMS grounded-model
	# override, just from a different trigger. Obstacle.gd lets a boosting player break
	# through instead of dying, so a trick landed right before a cluster pays off Alto's-
	# style instead of being wasted.
	if powerup_manager != null:
		powerup_manager.start_speed_boost()


func _on_player_died() -> void:
	sfx_player.play_death()
	# record_run banks this run's coins into the wallet AND updates the best score, so
	# the label below always reads post-update values -- neither "(New Best!)" nor the
	# wallet total can be stale. Banking needs no separate call.
	var is_new_best: bool = false
	var best_score: int = 0
	var wallet: int = 0
	if services != null:
		is_new_best = services.save_store.record_run(coin_count, main.elapsed_time)
		best_score = services.save_store.best_score
		wallet = services.save_store.coin_wallet
	var best_suffix: String = " (New Best!)" if is_new_best else ""
	death_stats_label.text = "Coins: %d\nTime: %s\nBest: %d%s\nWallet: %d" % [coin_count, main.format_elapsed_time(main.elapsed_time), best_score, best_suffix, wallet]
	set_state(State.DEAD)


func _on_pause_pressed() -> void:
	if state != State.PLAYING:
		return
	sfx_player.play_click()
	set_state(State.PAUSED)


func _on_resume_pressed() -> void:
	sfx_player.play_click()
	set_state(State.PLAYING)
	# Same reasoning as _on_start_pressed: this tap dismissed a Control, and without
	# an explicit release the global Input singleton still reports "ui_accept" as
	# just-pressed on the first physics frame back in play -- a free jump on resume.
	Input.action_release(&"ui_accept")


func _on_volume_drag_ended(_has_value_changed: bool) -> void:
	if services != null:
		services.save_settings()


func _on_music_volume_changed(value: float) -> void:
	if services != null:
		services.set_music_volume(value)


func _on_sfx_volume_changed(value: float) -> void:
	if services != null:
		services.set_sfx_volume(value)


# Reloads back to the main/start screen -- this is the "Home" button on both the pause
# screen (which bypasses set_state(), so it is the one exit from PAUSED that the flush
# there cannot cover) and the death screen. Lands on START because that's what a bare
# reload_current_scene() does -- see require_start_screen.
func _on_restart_pressed() -> void:
	sfx_player.play_click()
	if services != null:
		services.save_settings()
	# Unpause before the reload: the tree-wide paused flag is not reset by
	# reload_current_scene(), so leaving it true would rebuild the scene into a frozen
	# world. The reloaded GameManager sets its own state in _ready().
	get_tree().paused = false
	get_tree().reload_current_scene()


# The "Restart" button on both the pause and death screens: reloads AND skips the
# START screen, straight into a new run. Same reload as _on_restart_pressed, plus the
# static flag that survives it -- see pending_quick_restart.
func _on_quick_restart_pressed() -> void:
	sfx_player.play_click()
	if services != null:
		services.save_settings()
	GameManager.pending_quick_restart = true
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_coin_collected(value: int) -> void:
	var multiplier: float = powerup_manager.coin_multiplier if powerup_manager != null else 1.0
	coin_count += int(value * multiplier)
	update_coin_label()
	sfx_player.play_coin()


func update_coin_label() -> void:
	coin_label.text = "Coins: %d" % coin_count


# The SINGLE choke point where a purchased stat reaches gameplay. Nothing else in the
# project may write player.upgrade_jump_multiplier -- a second writer is how the powerup
# and the upgrade would start clobbering each other.
#
# HEADLESS IS EXCLUDED, AND THAT IS LOAD-BEARING, NOT AN OPTIMISATION. The autoload NODE
# does exist in a `--headless --script` probe (only the global `Services` IDENTIFIER is
# missing there), so resolve() succeeds and this function runs. Ungated, every physics
# gate silently measures whatever jump level is in the DEVELOPER'S OWN save.dat --
# machine-dependent, and drifting every time they buy an upgrade in a real session.
#
# Measured 2026-08-04: ungated, chasm_probe went 48/48 -> 8 failures. A probe that has
# never played is level 0 (x0.60), and the 280px void stops being clearable on an early
# jump. Gates must measure the design baseline (x1.00), which is upgrade_jump_multiplier's
# own default -- so skipping is exactly right, and doing it here rather than as a
# per-probe opt-out flag means a NEW probe cannot forget it.
#
# The check is LOCAL rather than `services.is_headless`, and that distinction cost a
# debugging cycle: is_headless is assigned in GameServices._ready(), which a harness has
# not necessarily run by the time GameManager._ready() gets here -- it read false in the
# probe and the gate stayed broken. Same trap CLAUDE.md records for the audio path.
# Reading DisplayServer directly has no initialisation order at all.
func apply_upgrades() -> void:
	if services == null or player == null:
		return
	if DisplayServer.get_name() == "headless":
		return
	var jump_level: int = services.upgrades.get_level(UpgradeStore.JUMP_UPGRADE_ID)
	player.upgrade_jump_multiplier = UpgradeStore.get_jump_multiplier(jump_level)


func _on_shop_pressed() -> void:
	sfx_player.play_click()
	shop_return_state = State.DEAD
	refresh_shop()
	set_state(State.SHOP)


# Upgrades button on the START screen -- the shop's other entry point. Purchases here
# apply immediately via apply_upgrades() same as from the death screen; there's no
# run in progress to desync from.
func _on_start_shop_pressed() -> void:
	sfx_player.play_click()
	shop_return_state = State.START
	refresh_shop()
	set_state(State.SHOP)


func _on_shop_close_pressed() -> void:
	sfx_player.play_click()
	set_state(shop_return_state)


func _on_buy_jump_pressed() -> void:
	if services == null:
		return
	if not services.upgrades.purchase(UpgradeStore.JUMP_UPGRADE_ID):
		return
	sfx_player.play_powerup()
	# Applied immediately even though the current run is over: keeping this next to the
	# purchase means there is exactly one ordering to reason about, and the restart that
	# follows re-derives the same value from disk anyway.
	apply_upgrades()
	refresh_shop()


func refresh_shop() -> void:
	if shop_screen == null:
		return

	var wallet: int = 0
	var jump_level: int = 0
	var next_cost: int = UpgradeStore.NO_COST
	var can_buy: bool = false
	if services != null:
		wallet = services.upgrades.get_wallet()
		jump_level = services.upgrades.get_level(UpgradeStore.JUMP_UPGRADE_ID)
		next_cost = services.upgrades.get_next_cost(UpgradeStore.JUMP_UPGRADE_ID)
		can_buy = services.upgrades.can_purchase(UpgradeStore.JUMP_UPGRADE_ID)

	var max_level: int = UpgradeStore.get_max_level(UpgradeStore.JUMP_UPGRADE_ID)
	shop_wallet_label.text = "Wallet: %d" % wallet
	shop_jump_label.text = "Jump  Lv %d/%d  (x%.2f)" % [jump_level, max_level, UpgradeStore.get_jump_multiplier(jump_level)]

	if next_cost == UpgradeStore.NO_COST:
		shop_jump_button.text = "Jump  MAX"
	else:
		shop_jump_button.text = "Jump  ->  x%.2f   (%d)" % [UpgradeStore.get_jump_multiplier(jump_level + 1), next_cost]
	shop_jump_button.disabled = not can_buy


# Just opens the confirmation -- the actual wipe is in _on_reset_progress_confirmed,
# wired to the dialog's own `confirmed` signal, so a stray tap on the button can never
# delete a save. get_tree().paused is already true here (SHOP implies not-PLAYING),
# and ConfirmationDialog inherits process_mode from ShopScreen (PROCESS_MODE_ALWAYS),
# so the popup still opens and can still be dismissed while the game is paused.
func _on_reset_progress_pressed() -> void:
	sfx_player.play_click()
	reset_confirm_dialog.popup_centered()


func _on_reset_progress_confirmed() -> void:
	sfx_player.play_click()
	if services != null:
		services.save_store.reset_progress()
		# Same reasoning as _on_buy_jump_pressed: sync the now-reset jump level onto
		# the live player immediately rather than waiting for the next reload.
		apply_upgrades()
	refresh_shop()
