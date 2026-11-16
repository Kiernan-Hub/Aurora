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
@export var glide_coin_spawner_path: NodePath = NodePath("../TerrainGenerator/GlideCoinSpawner")
@export var rare_coin_spawner_path: NodePath = NodePath("../TerrainGenerator/RareCoinSpawner")
@export var coin_label_path: NodePath = NodePath("../CanvasLayer/CoinLabel")
@export var powerup_manager_path: NodePath = NodePath("../PowerupManager")
@export var biome_director_path: NodePath = NodePath("../BiomeDirector")
@export var sfx_player_path: NodePath = NodePath("../SfxPlayer")
@export var obstacle_spawner_path: NodePath = NodePath("../TerrainGenerator/ObstacleSpawner")
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
@export var shop_close_button_path: NodePath = NodePath("../CanvasLayer/ShopScreen/CenterContainer/VBoxContainer/CloseButton")
@export var death_shop_button_path: NodePath = NodePath("../CanvasLayer/DeathScreen/CenterContainer/VBoxContainer/ShopButton")
@export var reset_progress_button_path: NodePath = NodePath("../CanvasLayer/ShopScreen/CenterContainer/VBoxContainer/ResetProgressButton")
@export var reset_confirm_dialog_path: NodePath = NodePath("../CanvasLayer/ShopScreen/ResetConfirmDialog")
# The Stats screen, wired optionally like the shop.
@export var stats_screen_path: NodePath = NodePath("../CanvasLayer/StatsScreen")
@export var stats_grid_path: NodePath = NodePath("../CanvasLayer/StatsScreen/CenterContainer/VBoxContainer/StatsGrid")
@export var achievements_grid_path: NodePath = NodePath("../CanvasLayer/StatsScreen/CenterContainer/VBoxContainer/AchievementsGrid")
@export var stats_close_button_path: NodePath = NodePath("../CanvasLayer/StatsScreen/CenterContainer/VBoxContainer/CloseButton")
@export var start_stats_button_path: NodePath = NodePath("../CanvasLayer/StartScreen/CenterContainer/VBoxContainer/MenuButtons/StatsButton")
@export var achievement_manager_path: NodePath = NodePath("../AchievementManager")
# The Skaters screen, wired optionally like the shop.
@export var skins_screen_path: NodePath = NodePath("../CanvasLayer/SkinsScreen")
@export var skins_row_path: NodePath = NodePath("../CanvasLayer/SkinsScreen/CenterContainer/VBoxContainer/SkinsRow")
@export var skins_close_button_path: NodePath = NodePath("../CanvasLayer/SkinsScreen/CenterContainer/VBoxContainer/CloseButton")
@export var start_skins_button_path: NodePath = NodePath("../CanvasLayer/StartScreen/CenterContainer/VBoxContainer/MenuButtons/SkinsButton")
@export var sparkles_row_path: NodePath = NodePath("../CanvasLayer/SkinsScreen/CenterContainer/VBoxContainer/SparklesRow")
# What a sparkle tints. Optional: a missing one just keeps its authored white.
@export var landing_burst_path: NodePath = NodePath("../LandingBurst")

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
# TEMP knob for trying the air moves without buying them: true grants the slam and the double
# jump in apply_upgrades() (a play session only; headless still skips). A plain var, not
# @export, like require_start_screen; shipping_values_check fails the build if it is left true.
var debug_unlock_air_moves: bool = false
# TEMP knob for testing the shop without earning coins: above 0, every scene load (launch or
# restart) tops the SAVED wallet up to this many, so a purchase still visibly drops it. Buying
# everything costs 4,580 (2,330 of upgrades, 2,250 of skaters). Debug builds only, never headless; shipping_values_check fails the build
# if it is left above 0.
var debug_start_wallet: int = 0

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
var glide_coin_spawner: GlideCoinSpawner
var rare_coin_spawner: RareCoinSpawner
var coin_label: Label
var coin_count: int = 0
# Chests picked up this run, and what they held once the run ended (ChestRewards).
var chest_count: int = 0
var collected_chest_tiers: Array[int] = []
var geodes_broken: int = 0
var mission: Dictionary = {}
var mission_banked_amount: float = 0.0
var mission_reward_claimed: bool = false
var mission_display_amount: int = -1
var mission_hud: VBoxContainer
var mission_label: Label
var mission_bar: ProgressBar
var mission_menu_labels: Array[Label] = []
var chest_rewards: Array[Dictionary] = []
var chest_reveal: ChestReveal
# Per completed 360 landed. Routed through _on_coin_collected so a trick reward gets
# the same coin_multiplier (doubler powerup) and coin SFX as a real coin -- one score
# path, not two.
const TRICK_COIN_REWARD: int = 5

# --- Combo -----------------------------------------------------------------------------
# A run-total multiplier, not a streak: cross 50 coins and every coin from then on is worth
# double, cross 150 and it is triple. Nothing takes it away -- a missed coin costs you that
# coin and nothing else.
#
# The thresholds read the COIN COUNT ON SCREEN, the same multiplied number the player is
# watching, not a hidden raw tally. That makes the next tier something they can see coming, at
# the cost of the tiers arriving slightly sooner than the raw pickups would suggest (the x2 is
# already multiplying the number that decides when x3 lands). Legibility is worth more than
# that arithmetic purity on a screen moving at 750 px/s.
#
# An earlier version made this a CONSECUTIVE-coin streak that a missed coin reset, with the
# reach machinery to decide which misses were the player's fault. The project owner replaced it
# with these run totals, so a coin going past now costs only itself.
const COMBO_TIERS: Array[Dictionary] = [
	{"coins": 150, "multiplier": 3.0},
	{"coins": 50, "multiplier": 2.0},
]

var powerup_manager: PowerupManager
# Read on death only, to bank how far into the biome cycle this run got. Optional and
# null-guarded like the shop nodes: this is presentation state, and a run that cannot
# find the director should still record its coins.
var biome_director: BiomeDirector
var sfx_player: SfxPlayer
var shop_screen: Control
var shop_wallet_label: Label
# One {"label", "button"} per UpgradeStore.TRACKS row, keyed by track id. Built in code under the
# wallet line (build_shop_rows), so a new track is a table row and never a new node or NodePath.
var shop_rows: Dictionary[String, Dictionary] = {}
var shop_close_button: Button
var death_shop_button: Button
var reset_progress_button: Button
var reset_confirm_dialog: ConfirmationDialog
var stats_screen: Control
var stats_grid: GridContainer
var achievements_grid: GridContainer
var stats_close_button: Button
var start_stats_button: Button
# UNTYPED ON PURPOSE, like Player.obstacle_spawner: AchievementManager names FrozenLakeDirector,
# which names this class, so naming it back here would close a script load cycle (CLAUDE.md).
# Only asked get_rows() and is_earned(); null hides the Stats screen's achievement list.
var achievement_manager: Node
var skins_screen: Control
var skins_row: HBoxContainer
var skins_close_button: Button
var start_skins_button: Button
# One per Skins.SKINS row, keyed by id, built in code (build_skin_buttons) like the shop rows.
var skin_buttons: Dictionary[String, Button] = {}
var sparkles_row: HBoxContainer
var sparkle_buttons: Dictionary[String, Button] = {}
var collection_buttons: Dictionary[String, Button] = {}
var collection_labels: Dictionary[String, Label] = {}
var collection_tabs: TabContainer
const OUTFIT_SHADER: Shader = preload("res://shaders/outfit.gdshader")
var landing_burst: Node2D

# How far a run has gone, for the death screen and the Stats screen. The player's x never
# rebases (world rebasing moves y only), so distance is just x from where the run began.
# 32px to the metre puts the 48px-tall skater at 1.5m and MAX_SPEED at ~84 km/h.
const PIXELS_PER_METER: float = 32.0
# Locked achievements, and nothing else, are drawn at this alpha on the Stats screen.
const STATS_DIM_ALPHA: float = 0.45
# A skin button: room for the frame (150x180 source, drawn shrunk) above its name.
const SKIN_BUTTON_SIZE: Vector2 = Vector2(96, 150)
var run_start_x: float = 0.0

# Emitted once per real run, after the death screen is up and the run is banked: the hook for
# run-based achievements (AchievementManager). Never in headless, where nothing is banked.
signal run_recorded(distance_meters: float, coins: int, total_distance_meters: float)

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
# that mutates player stats mid-run. STATS and SKINS are the same kind of modal, from START.
enum State { START, PLAYING, PAUSED, DEAD, SHOP, STATS, SKINS, BONUS }
var pause_return_state: State = State.PLAYING
var melt_view: Control
# How long the death screen takes to fade in from a death (set_state).
const DEATH_SCREEN_FADE_SECONDS: float = 0.6

signal state_changed(new_state: State)

var state: State = State.START
# Which screen a modal (SHOP, STATS, SKINS) is over: the shop is reachable from either the START
# screen (the new Upgrades button) or the DEAD screen (the original entry point), and
# closing it must return to whichever one opened it -- otherwise closing the shop from
# the main menu would incorrectly reveal the (irrelevant, stale) death screen behind it.
var modal_return_state: State = State.DEAD

# Set right before a "quick restart" reload_current_scene() call and consumed by the
# next _ready(). A local var can't survive the reload -- the whole script instance is
# destroyed and rebuilt -- so this has to be static to cross that boundary. Always
# false except in the one-frame window between _on_quick_restart_pressed() and the
# rebuilt GameManager's _ready() reading it.
static var pending_quick_restart: bool = false
# Null only off-tree. Under `--headless --script` the autoload node exists and this resolves,
# which is why every save-writing path here also checks DisplayServer (see apply_upgrades()).
var services: GameServices
# This run's record_run() verdict, kept for refresh_death_stats(): the death screen stays up
# under the shop, whose purchases and reset change the wallet and best it shows.
var last_run_is_new_best: bool = false

# How much of THIS run's Main.elapsed_time has already been folded into
# SaveStore.total_playtime_seconds. See bank_playtime() for why it exists.
var banked_run_seconds: float = 0.0


func _ready() -> void:
	# _notification below must still arrive while the tree is paused -- a focus-out that
	# happens on the pause screen, or a back press on the death screen, is exactly when
	# paused-ness is already true. This node has no _process/_physics_process, so ALWAYS
	# costs nothing.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# A WIRING FAILURE MUST STILL REACH set_state(). Every gate in wire_scene() used to
	# `return` straight out of _ready(), which skipped set_state() entirely -- and since
	# set_state() is the only thing that initialises any screen's visibility, the result was
	# a fully running game underneath an un-dismissable overlay, with only a log line to say
	# why. The comment that used to sit on the shop block described exactly this.
	#
	# PLAYING rather than START, deliberately: a build broken enough to get here may have no
	# start button to press, and START would pause the tree with no way to unpause it. PLAYING
	# leaves the game running and every screen it managed to find hidden, so the push_error is
	# the loudest thing about the session instead of the quietest.
	if not wire_scene():
		set_state(State.PLAYING)
		return

	# Must run before the first gameplay frame. Safe here: Player is an earlier sibling
	# in main.tscn so its _ready() has already run, and upgrade_jump_multiplier is only
	# read inside _physics_process, which cannot start until every _ready() completes.
	apply_upgrades()
	apply_skin()
	apply_sparkle()
	apply_debug_start_wallet()
	run_start_x = player.global_position.x
	build_mission_ui()
	prepare_mission()

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


# All the node lookups and signal connections, split out of _ready() so a failure can be
# HANDLED rather than escape as a bare `return`. Returns false on the first hard gate that
# fails, having already pushed the error describing it. See _ready() for what false costs.
func wire_scene() -> bool:
	services = GameServices.resolve(self)
	main = get_parent() as Main
	landing_burst = get_node_or_null(landing_burst_path) as Node2D
	player = get_node_or_null(player_path) as Player
	sfx_player = get_node_or_null(sfx_player_path) as SfxPlayer
	if main == null or player == null or sfx_player == null:
		push_error("GameManager requires a Main parent, a Player node at %s, and an SfxPlayer at %s." % [player_path, sfx_player_path])
		return false

	player.trick_completed.connect(_on_player_trick_completed)
	# Optional: a scene without obstacles just has no crack sound.
	var obstacle_spawner: ObstacleSpawner = get_node_or_null(obstacle_spawner_path) as ObstacleSpawner
	if obstacle_spawner != null:
		obstacle_spawner.thin_ice_cracked.connect(sfx_player.play_crack)
		obstacle_spawner.geode_broken.connect(_on_geode_broken)

	start_screen = get_node_or_null(start_screen_path) as Control
	start_button = get_node_or_null(start_button_path) as Button
	if start_screen == null or start_button == null:
		push_error("GameManager requires a start screen at %s." % start_screen_path)
		return false

	start_button.pressed.connect(_on_start_pressed)

	death_screen = get_node_or_null(death_screen_path) as Control
	death_stats_label = get_node_or_null(death_stats_label_path) as Label
	restart_button = get_node_or_null(restart_button_path) as Button
	death_home_button = get_node_or_null(death_home_button_path) as Button
	if death_screen == null or death_stats_label == null or restart_button == null or death_home_button == null:
		push_error("GameManager requires a death screen at %s with restart and home buttons." % death_screen_path)
		return false
	# The chest reveal sits under the stats, above the buttons.
	chest_reveal = ChestReveal.new()
	death_stats_label.add_sibling(chest_reveal)

	# "Restart" jumps straight back into a new run (see _on_quick_restart_pressed);
	# "Home" is the one that lands on the START/main screen, same as the pause
	# screen's Home button and the same handler.
	restart_button.pressed.connect(_on_quick_restart_pressed)
	death_home_button.pressed.connect(_on_home_pressed)
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
		return false

	# Main consumes pause pointer presses and pauses before GUI dispatch, so the touch
	# cannot reach the newly visible menu. Keep this down-edge fallback for activation
	# without a pointer; pausing on release would leave a gameplay jump edge live.
	pause_button.button_down.connect(_on_pause_pressed)
	resume_button.pressed.connect(_on_resume_pressed)
	pause_restart_button.pressed.connect(_on_quick_restart_pressed)
	pause_home_button.pressed.connect(_on_home_pressed)

	# MusicSlider and MusicLabel are visible because AuroraAudio now owns a scene-local ambient
	# stream on the existing Music bus. The control stays bus-level: it applies to this bed and any
	# future music without giving GameManager ownership of a stream.
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
		return false

	coin_spawner.coin_collected.connect(_on_coin_collected)

	# Optional, not required-and-return like coin_spawner/coin_label above: a missing
	# GlideCoinSpawner should never take down the whole coin/score system, it just means
	# no coins appear during a glide.
	glide_coin_spawner = get_node_or_null(glide_coin_spawner_path) as GlideCoinSpawner
	if glide_coin_spawner != null:
		glide_coin_spawner.coin_collected.connect(_on_coin_collected)

	# Optional for the same reason as the glide spawner above. Its coins are worth 25 each
	# and go through the identical path -- including the coin doubler, which is intended:
	# a max-jump grab under a doubler is the biggest single pickup in the game.
	rare_coin_spawner = get_node_or_null(rare_coin_spawner_path) as RareCoinSpawner
	if rare_coin_spawner != null:
		rare_coin_spawner.coin_collected.connect(_on_coin_collected)
		rare_coin_spawner.chest_collected.connect(_on_chest_collected)

	update_coin_label()

	powerup_manager = get_node_or_null(powerup_manager_path) as PowerupManager
	if powerup_manager == null:
		push_error("GameManager requires a PowerupManager at %s." % powerup_manager_path)
		return false

	# No push_error and no early return, unlike the nodes above: losing the biome phase
	# costs a run its colour continuity and nothing else, which is not worth refusing to
	# start a game over.
	biome_director = get_node_or_null(biome_director_path) as BiomeDirector

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
	shop_close_button = get_node_or_null(shop_close_button_path) as Button
	death_shop_button = get_node_or_null(death_shop_button_path) as Button
	start_upgrades_button = get_node_or_null(start_upgrades_button_path) as Button
	reset_progress_button = get_node_or_null(reset_progress_button_path) as Button
	reset_confirm_dialog = get_node_or_null(reset_confirm_dialog_path) as ConfirmationDialog
	if shop_screen == null or shop_wallet_label == null or shop_close_button == null or death_shop_button == null or start_upgrades_button == null or reset_progress_button == null or reset_confirm_dialog == null:
		push_error("GameManager could not wire the upgrade shop at %s; the game runs without it." % shop_screen_path)
	else:
		build_shop_rows()
		shop_close_button.pressed.connect(_on_shop_close_pressed)
		death_shop_button.pressed.connect(_on_shop_pressed)
		start_upgrades_button.pressed.connect(_on_start_shop_pressed)
		reset_progress_button.pressed.connect(_on_reset_progress_pressed)
		reset_confirm_dialog.confirmed.connect(_on_reset_progress_confirmed)

	# Optional too, for the shop's reason: a missing Stats screen costs the Stats screen.
	build_dev_buttons()

	stats_screen = get_node_or_null(stats_screen_path) as Control
	stats_grid = get_node_or_null(stats_grid_path) as GridContainer
	achievements_grid = get_node_or_null(achievements_grid_path) as GridContainer
	stats_close_button = get_node_or_null(stats_close_button_path) as Button
	start_stats_button = get_node_or_null(start_stats_button_path) as Button
	achievement_manager = get_node_or_null(achievement_manager_path)
	if stats_screen == null or stats_grid == null or achievements_grid == null or stats_close_button == null or start_stats_button == null:
		push_error("GameManager could not wire the Stats screen at %s; the game runs without it." % stats_screen_path)
		if start_stats_button != null:
			start_stats_button.visible = false
	else:
		start_stats_button.pressed.connect(_on_stats_pressed)
		stats_close_button.pressed.connect(_on_stats_close_pressed)

	skins_screen = get_node_or_null(skins_screen_path) as Control
	skins_row = get_node_or_null(skins_row_path) as HBoxContainer
	skins_close_button = get_node_or_null(skins_close_button_path) as Button
	start_skins_button = get_node_or_null(start_skins_button_path) as Button
	sparkles_row = get_node_or_null(sparkles_row_path) as HBoxContainer
	if skins_screen == null or skins_row == null or sparkles_row == null or skins_close_button == null or start_skins_button == null:
		push_error("GameManager could not wire the Skaters screen at %s; the game runs without it." % skins_screen_path)
		if start_skins_button != null:
			start_skins_button.visible = false
	else:
		build_skin_buttons()
		start_skins_button.pressed.connect(_on_skins_pressed)
		skins_close_button.pressed.connect(_on_skins_close_pressed)

	return true


# The single owner of get_tree().paused and of every screen's visibility. Nothing else
# in the project may set either; if a new transition is needed, add it to the enum.
func set_state(new_state: State) -> void:
	var previous_state: State = state
	if new_state == State.PAUSED and (previous_state == State.PLAYING or previous_state == State.BONUS):
		pause_return_state = previous_state
	state = new_state
	if melt_view != null:
		melt_view.visible = new_state == State.BONUS
		melt_view.set("running", new_state == State.BONUS)

	# START/DEAD stay visible underneath SHOP: the shop is a modal over whichever screen
	# opened it (see modal_return_state), and closing it returns there without a flicker.
	# EVERY SCREEN IS NULL-GUARDED, not just the optional shop, and that is what lets a failed
	# wire_scene() still come through here. On a correctly wired scene all four are always
	# present, so these guards never fire in a shipped build; on a broken one they are the
	# difference between "the game runs and the log says why" and a frozen overlay. The nulls
	# are not silently tolerated -- wire_scene() has already pushed an error naming the missing
	# node. This only keeps that error from being followed by a crash on the next line.
	var is_modal: bool = new_state == State.SHOP or new_state == State.STATS or new_state == State.SKINS
	if start_screen != null:
		start_screen.visible = new_state == State.START or (is_modal and modal_return_state == State.START)
	if pause_screen != null:
		pause_screen.visible = new_state == State.PAUSED
	if death_screen != null:
		death_screen.visible = new_state == State.DEAD or (is_modal and modal_return_state == State.DEAD)
		# Fade in on a death rather than snapping on, so the moment of death (the thin-ice
		# sink, a crash) is seen for a beat before the overlay dims it. Visible and live from
		# the first frame either way; only its alpha ramps.
		if previous_state == State.PLAYING and new_state == State.DEAD:
			death_screen.modulate.a = 0.0
			var fade: Tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			fade.tween_property(death_screen, "modulate:a", 1.0, DEATH_SCREEN_FADE_SECONDS)
	if shop_screen != null:
		shop_screen.visible = new_state == State.SHOP
	if stats_screen != null:
		stats_screen.visible = new_state == State.STATS
	if skins_screen != null:
		skins_screen.visible = new_state == State.SKINS
	# Hidden on the menus so it can't be tapped while a screen is up, and hidden on
	# death because the death screen owns the input at that point.
	if pause_button != null:
		pause_button.visible = new_state == State.PLAYING

	# Menus own their own information; the live HUD and debug overlay stay in the run.
	for hud_name: String in ["TimerLabel", "CoinLabel", "PowerupLabel", "PlayerStateDebugLabel"]:
		var hud: CanvasItem = get_node_or_null("../CanvasLayer/" + hud_name) as CanvasItem
		if hud != null:
			hud.visible = new_state == State.PLAYING
	if mission_hud != null:
		mission_hud.visible = new_state == State.PLAYING
	refresh_mission_ui()
	get_tree().paused = new_state != State.PLAYING
	# Leaving the pause screen is the end of any settings interaction, and the only
	# flush point that also catches a slider moved by keyboard (which emits value_changed
	# but never drag_ended). Writing here rather than per-step is the whole point -- see
	# GameServices.set_music_volume.
	if previous_state == State.PAUSED and new_state != State.PAUSED and services != null:
		services.save_settings()
	# Leaving PLAYING is the one moment this run's seconds stop accruing, so they are banked
	# here: pause (and so Home and Restart, reachable only from PAUSED or DEAD) and the Android
	# focus-out handler, which routes through set_state -- the backgrounded-app case a death-only
	# hook loses. On death bank_playtime() returns false: _on_player_died() already banked, and
	# record_run's one write carries it.
	if previous_state == State.PLAYING and new_state != State.PLAYING:
		var changed: bool = bank_mission_progress()
		changed = bank_playtime() or changed
		if changed and services != null:
			services.save_store.save_to_disk()
	state_changed.emit(new_state)


func owns_slam() -> bool:
	return services != null and services.upgrades.get_level(UpgradeStore.SLAM_UPGRADE_ID) > 0


func prepare_mission() -> void:
	mission = Missions.prepare(services.save_store, owns_slam()) if services != null and DisplayServer.get_name() != "headless" \
		else Missions.definition(Missions.FIRST_ID, 0, false)
	mission_banked_amount = get_mission_run_amount()
	mission_reward_claimed = false
	mission_display_amount = -1
	refresh_mission_ui()


func get_mission_run_amount() -> float:
	match mission.get("id", ""):
		"coins": return float(coin_count)
		"distance": return get_run_distance_meters()
		"chests": return float(chest_count)
		"geodes": return float(geodes_broken)
	return 0.0


func get_mission_progress() -> float:
	if mission.is_empty():
		return 0.0
	if mission_reward_claimed:
		return float(mission["target"])
	var stored: float = services.save_store.mission_progress if services != null and DisplayServer.get_name() != "headless" else 0.0
	return minf(stored + maxf(get_mission_run_amount() - mission_banked_amount, 0.0), float(mission["target"]))


func bank_mission_progress() -> bool:
	if services == null or mission.is_empty() or mission_reward_claimed or DisplayServer.get_name() == "headless":
		return false
	var amount: float = get_mission_run_amount()
	var changed: bool = Missions.bank(services.save_store, mission, maxf(amount - mission_banked_amount, 0.0))
	mission_banked_amount = amount
	return changed


# Called beside the existing clock update. Only rebuild strings when a whole unit changes.
func refresh_mission_ui() -> void:
	if mission_label == null or mission.is_empty():
		return
	var progress: int = int(get_mission_progress())
	if progress == mission_display_amount:
		return
	mission_display_amount = progress
	var complete: bool = progress >= int(mission["target"])
	mission_label.text = "Mission complete · Rare chest earned" if complete else "%s  %d/%d" % [mission["title"], progress, int(mission["target"])]
	mission_label.modulate = Color(0.6, 1.0, 0.8) if complete else Color(0.85, 0.94, 1.0)
	mission_bar.max_value = float(mission["target"])
	mission_bar.value = progress
	for label: Label in mission_menu_labels:
		label.text = "Mission complete · Chest opens after your run" if complete else "Mission · %s  %d/%d\nReward: Rare chest" % [mission["title"], progress, int(mission["target"])]


func build_mission_ui() -> void:
	mission_hud = VBoxContainer.new()
	mission_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mission_hud.add_theme_constant_override("separation", 4)
	get_node("../CanvasLayer").add_child(mission_hud)
	mission_hud.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	mission_hud.offset_left = 16
	mission_hud.offset_right = 436
	mission_hud.offset_top = -58
	mission_hud.offset_bottom = -14
	mission_label = Label.new()
	mission_label.add_theme_font_size_override("font_size", 13)
	mission_hud.add_child(mission_label)
	mission_bar = ProgressBar.new()
	mission_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mission_bar.show_percentage = false
	mission_bar.custom_minimum_size = Vector2(240, 5)
	mission_bar.add_theme_stylebox_override("background", start_screen.theme.get_stylebox("slider", "HSlider"))
	mission_bar.add_theme_stylebox_override("fill", start_screen.theme.get_stylebox("grabber_area", "HSlider"))
	mission_hud.add_child(mission_bar)
	for anchor: Control in [start_button.get_parent(), resume_button]:
		var label: Label = Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 13)
		label.modulate = Color(0.7, 0.86, 0.95)
		anchor.add_sibling(label)
		anchor.get_parent().move_child(label, anchor.get_index())
		mission_menu_labels.append(label)


# Folds the unbanked part of this run into the cumulative playtime total, in memory only --
# the caller decides whether that warrants a disk write.
#
# Main.elapsed_time is monotonic within a run and accrues only while PLAYING (the tree is
# paused in every other state), so the unbanked amount is just the difference since the
# last call. Tracking it that way rather than adding deltas per frame means the two callers
# can fire in either order, or twice, without double-counting -- which matters because the
# death path banks and then immediately transitions out of PLAYING.
#
# Returns true when something was actually banked.
func bank_playtime() -> bool:
	if services == null or main == null:
		return false
	# Never in headless, for apply_upgrades()'s reason: a 60,000-frame probe would otherwise bank
	# 1,000s into the developer's save.dat and hand out lakes nobody earned.
	if DisplayServer.get_name() == "headless":
		return false
	var unbanked_seconds: float = main.elapsed_time - banked_run_seconds
	if unbanked_seconds <= 0.0:
		return false
	services.save_store.total_playtime_seconds += unbanked_seconds
	banked_run_seconds = main.elapsed_time
	return true


# The part of THIS run that bank_playtime() has not folded into
# SaveStore.total_playtime_seconds yet.
#
# Anything gating on CUMULATIVE playtime must add this to the saved total, never
# main.elapsed_time. Banking runs on every PLAYING -> not-PLAYING transition -- which on
# Android includes every notification and app switch (see _notification below) -- so adding
# the whole run again credits phantom playtime equal to elapsed-at-pause, and it compounds
# once per pause. FrozenLakeDirector shipped that way: three pauses at 3/6/9 minutes credited
# +18 phantom minutes, on their own enough to cross LAKE_INTERVAL_SECONDS and hand out a set
# piece that 20 minutes of real play had not earned.
#
# Correct in headless too, where bank_playtime() returns early and never advances
# banked_run_seconds: nothing was banked, so the whole run reads as unbanked.
func get_unbanked_seconds() -> float:
	if main == null:
		return 0.0
	return maxf(main.elapsed_time - banked_run_seconds, 0.0)


# CUMULATIVE playtime across every run and every launch, including the part of this run
# get_unbanked_seconds() above says is not on disk yet. This is the clock every playtime-gated
# set piece schedules against, and it lives here because this node owns both halves of it --
# the banking, and the save store the banked half is read from.
#
# IT WAS FrozenLakeDirector'S, and it moved here on 2026-09-05 because the aurora
# (docs/development/aurora_borealis.md) needs the identical number and a second copy of this
# arithmetic is a second chance to get it wrong. That is not hypothetical: the WRONG version of
# this sum is `save_store.total_playtime_seconds` alone, which is stale by the whole unbanked run
# and reads minutes low in the middle of an uninterrupted session. A scheduler that sets its next
# deadline from that number hands out its set piece again almost immediately. One owner, so there
# is one place for that to be right.
#
# Callers must still handle a MISSING GameManager themselves -- an absent node cannot answer for
# itself. FrozenLakeDirector.get_total_playtime_seconds() shows the shape and carries the reason
# the fallback is what it is.
#
# NO HEADLESS GUARD HERE, DELIBERATELY -- IT BELONGS IN THE CALLER. `services` resolves fine under
# `--headless --script` (only bank_playtime() early-returns), so this answers a gate with however
# many hours are in the DEVELOPER'S OWN save.dat. That is the apply_upgrades() failure (48/48 -> 8)
# with a different field.
#
# Guarding here would not actually fix it, which is why it is not done: a director that reached
# this call has already built its state machine and connected its signals inside a gate, and the
# lake's skip exists to stop it injecting terrain, not to stop it reading a number. So every
# playtime-gated consumer hard-skips headless as the FIRST statement in its _ready(), the way
# FrozenLakeDirector does. AuroraDirector owes the same -- docs/development/aurora_borealis.md,
# "The headless contract". This helper is now shared, so that rule travels with each new caller.
#
# Free to call every physics frame: it reads two floats and banks nothing.
func get_total_playtime_seconds() -> float:
	if services == null:
		return 0.0
	return services.save_store.total_playtime_seconds + get_unbanked_seconds()


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
				State.PLAYING, State.BONUS:
					set_state(State.PAUSED)
				State.PAUSED:
					_on_resume_pressed()
				# The shop is a modal over whichever screen opened it, so back means
				# "close the modal", exactly like its own Back button -- NOT quit.
				# Without this case it falls through to the default below and exits
				# the app from a menu.
				State.SHOP, State.STATS, State.SKINS:
					set_state(modal_return_state)
				_:
					get_tree().quit()
		# Focus loss: notification shade, incoming call, recents switcher. Only PLAYING
		# needs handling -- the other three states are already paused. Deliberately does
		# NOT auto-resume on focus-in: coming back to a running game you can't react to
		# yet is how you lose a run to the OS.
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			if state == State.PLAYING or state == State.BONUS:
				set_state(State.PAUSED)


func _on_start_pressed() -> void:
	sfx_player.play_start()
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
	#
	# GUARDRAIL B: not after a double jump. It buys up to 1.6s of air against a 0.9s flip, so
	# nearly every one would otherwise be a free 3s of can't-die. The coins still pay.
	if powerup_manager != null and not player.has_double_jumped:
		powerup_manager.start_speed_boost()


func _on_player_died() -> void:
	sfx_player.play_death()
	# record_run banks this run's coins into the wallet AND updates the best score, so
	# the label below always reads post-update values -- neither "(New Best!)" nor the
	# wallet total can be stale. Banking needs no separate call.
	last_run_is_new_best = false
	bank_biome_phase()
	# Rolled here and banked below with the run, so the reveal on the death screen is only a show.
	var reward_tiers: Array[int] = collected_chest_tiers.duplicate()
	# Retain compatibility with harnesses that set chest_count directly.
	while reward_tiers.size() < chest_count:
		reward_tiers.append(ChestTypes.Tier.NORMAL)
	if services != null and DisplayServer.get_name() != "headless":
		bank_mission_progress()
		if not mission_reward_claimed and not mission.is_empty() and Missions.claim(services.save_store, mission, owns_slam()):
			mission_reward_claimed = true
			reward_tiers.append(Missions.REWARD_TIER)
	chest_rewards = ChestRewards.roll_all(reward_tiers.size(), get_unowned_skin_ids(), RandomNumberGenerator.new(),
		Cosmetics.get_unowned(services.save_store.cosmetics if services != null else {}), reward_tiers)
	if mission_reward_claimed and not chest_rewards.is_empty():
		chest_rewards[-1]["mission"] = true
	# Script harnesses can have a real Services autoload. bank_playtime() already
	# skips headless, but record_run() itself writes coins/bests even when banking
	# returned false. A regression probe's deliberate death must never save a run.
	if services != null and DisplayServer.get_name() != "headless":
		# BEFORE record_run, so this run's seconds ride record_run's single disk write
		# rather than costing a second one from set_state(DEAD) a few lines below.
		bank_playtime()
		services.save_store.grant_chest_rewards(chest_rewards)
		last_run_is_new_best = services.save_store.record_run(coin_count, main.elapsed_time, get_run_distance_meters())
	refresh_death_stats()
	set_state(State.DEAD)
	if chest_reveal != null:
		chest_reveal.play(chest_rewards, sfx_player.play_chest)
	# After set_state, so an achievement toast this grants starts on a paused tree and knows to
	# run over the death screen (AchievementToast.show_next_name).
	if services != null and DisplayServer.get_name() != "headless":
		run_recorded.emit(get_run_distance_meters(), coin_count, services.save_store.total_distance_meters)


func get_run_distance_meters() -> float:
	if player == null:
		return 0.0
	return maxf(player.global_position.x - run_start_x, 0.0) / PIXELS_PER_METER


# 850 m, then 1.24 km from a kilometre up.
static func format_distance(meters: float) -> String:
	return "%d m" % int(meters) if meters < 1000.0 else "%.2f km" % (meters / 1000.0)


# Coins and Time are this run's and fixed (the tree is paused and a dead player takes no
# pickups); Best and Wallet are read from the save, so a purchase or a reset made in the shop
# above this screen shows when it closes. Never re-run _on_player_died() for this: it banks.
func refresh_death_stats() -> void:
	var best_score: int = 0
	var wallet: int = 0
	if services != null:
		best_score = services.save_store.best_score
		wallet = services.save_store.coin_wallet
	# A reset since death zeroes the best, and "Best: 0 (New Best!)" would contradict itself.
	var best_suffix: String = " (New Best!)" if last_run_is_new_best and best_score == coin_count else ""
	death_stats_label.text = "Coins: %d\nTime: %s\nDistance: %s\nBest: %d%s\nWallet: %d" % [coin_count,
		main.format_elapsed_time(main.elapsed_time), format_distance(get_run_distance_meters()), best_score, best_suffix, wallet]


# Session state, not save state: where this run ended is where the next one picks the day
# arc up, but only until the process exits. See BiomeDirector.session_biome_phase for why it
# is not persisted. Called on death AND on both pause-menu reloads -- banking only on death
# let a mid-run Restart/Home rewind the day arc and replay the one-shot opening biome.
func bank_biome_phase() -> void:
	if biome_director != null:
		BiomeDirector.session_biome_phase = biome_director.get_persisted_phase(player.global_position.x)


func _on_pause_pressed() -> void:
	if state != State.PLAYING and state != State.BONUS:
		return
	sfx_player.play_click()
	set_state(State.PAUSED)


func _on_resume_pressed() -> void:
	sfx_player.play_click()
	set_state(pause_return_state)
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


# The "Home" button on both the pause and death screens. Lands on START because that's
# what a bare reload_current_scene() does -- see require_start_screen.
func _on_home_pressed() -> void:
	reload_scene(false)


# The "Restart" button on both the pause and death screens: reloads AND skips the
# START screen, straight into a new run, via the static flag that survives the reload --
# see pending_quick_restart.
func _on_quick_restart_pressed() -> void:
	reload_scene(true)


# Both menu reloads. A reload bypasses set_state(), so it is the one exit from PAUSED that
# set_state()'s settings flush cannot cover, and the one sanctioned get_tree().paused write
# outside it: the tree-wide paused flag is not reset by reload_current_scene(), so leaving it
# true would rebuild the scene into a frozen world. The reloaded GameManager sets its own
# state in _ready().
func reload_scene(quick_start: bool) -> void:
	# Restart starts a run; Home goes back. Played on the Services voice: the reload below frees
	# SfxPlayer's pool, which cut the old click off after a frame.
	sfx_player.play_across_reload(SfxPlayer.START_SOUND if quick_start else SfxPlayer.BACK_SOUND)
	# From DEAD, _on_player_died already banked it.
	if state == State.PAUSED:
		bank_biome_phase()
	if services != null:
		services.save_settings()
	GameManager.pending_quick_restart = quick_start
	get_tree().paused = false
	get_tree().reload_current_scene()


# The one place a coin turns into score. Every source routes through here -- ground coins, air
# lines, the rare coin and a landed trick -- so the doubler powerup and the combo apply to all
# of them from one line each, rather than four sites that drift apart.
#
# The two multipliers STACK: a doubler held at the top combo tier pays 6x. That is the
# deliberate ceiling of the whole system, and it is rare because the doubler is a timed powerup.
# A slam broke a geode: its coins ride the same path as any pickup (doubler and combo apply).
func _on_geode_broken(value: int) -> void:
	geodes_broken += 1
	sfx_player.play_crack()
	_on_coin_collected(value)


func _on_chest_collected(tier: int = ChestTypes.Tier.NORMAL) -> void:
	collected_chest_tiers.append(ChestTypes.normalize(tier))
	chest_count += 1
	update_coin_label()
	sfx_player.play_powerup()


func get_unowned_skin_ids() -> Array[String]:
	var ids: Array[String] = []
	for skin: Dictionary in Skins.SKINS:
		if not is_skin_owned(skin["id"]):
			ids.append(skin["id"])
	return ids


func _on_coin_collected(value: int) -> void:
	var multiplier: float = powerup_manager.coin_multiplier if powerup_manager != null else 1.0
	coin_count += int(value * multiplier * get_combo_multiplier())
	update_coin_label()
	sfx_player.play_coin()


# Highest tier the run has reached. Ordered high-to-low so the first match wins and adding a
# tier means adding a row, not editing a comparison chain.
func get_combo_multiplier() -> float:
	for tier: Dictionary in COMBO_TIERS:
		if coin_count >= int(tier["coins"]):
			return float(tier["multiplier"])
	return 1.0


func update_coin_label() -> void:
	var combo_multiplier: float = get_combo_multiplier()
	var text: String = "Coins: %d" % coin_count
	if combo_multiplier > 1.0:
		text += "   x%.1f" % combo_multiplier
	if chest_count > 0:
		text = "Chests: %d   %s" % [chest_count, text]
	coin_label.text = text


# The SINGLE choke point where a purchased stat reaches gameplay. Nothing else may write
# player.upgrade_jump_multiplier, or the powerup and the upgrade start clobbering each other.
#
# HEADLESS IS EXCLUDED, AND THAT IS LOAD-BEARING. The autoload node exists in a
# `--headless --script` probe, so ungated, every physics gate measures the jump level in the
# DEVELOPER'S OWN save.dat (chasm_probe went 48/48 -> 8 failures, 2026-08-04). Gates must measure
# the x1.00 default, and gating here means a new probe cannot forget it. DisplayServer, never
# services.is_headless: GameServices._ready() may not have assigned it yet.
func apply_upgrades() -> void:
	if services == null or player == null:
		return
	if DisplayServer.get_name() == "headless":
		return
	var jump_level: int = services.upgrades.get_level(UpgradeStore.JUMP_UPGRADE_ID)
	player.upgrade_jump_multiplier = UpgradeStore.get_jump_multiplier(jump_level)
	player.has_slam = debug_unlock_air_moves or services.upgrades.get_level(UpgradeStore.SLAM_UPGRADE_ID) > 0
	player.has_double_jump = debug_unlock_air_moves or services.upgrades.get_level(UpgradeStore.DOUBLE_JUMP_UPGRADE_ID) > 0


# Puts the saved skater on the Player. Looks only -- the capsule is the hitbox -- but headless is
# skipped all the same, for apply_upgrades()'s reason: a gate never reads the developer's save.
func apply_skin() -> void:
	if services == null or player == null or DisplayServer.get_name() == "headless":
		return
	var frames: SpriteFrames = load(String(Skins.get_skin(get_worn_skin_id())["frames"])) as SpriteFrames
	if frames != null and player.animated_sprite.sprite_frames != frames:
		player.animated_sprite.sprite_frames = frames
		player.animated_sprite.play(&"skate")
	apply_cosmetics()


# DevMode's two switches, at the bottom of the start screen's column. Debug builds only: in a
# release export is_available() is false and neither button exists. A press rewrites the flag
# and reloads, because every knob is applied as the scene enters the tree.
func build_dev_buttons() -> void:
	if not DevMode.is_available() or start_button == null:
		return
	var column: Node = start_button.get_parent()
	var dev_button: Button = Button.new()
	dev_button.text = "Dev mode: %s" % ("ON" if DevMode.is_on() else "OFF")
	dev_button.pressed.connect(_on_dev_toggled.bind(not DevMode.is_on(), DevMode.is_cant_die()))
	column.add_child(dev_button)
	if DevMode.is_on():
		var cant_die_button: Button = Button.new()
		cant_die_button.text = "Dev can't die: %s" % ("ON" if DevMode.is_cant_die() else "OFF")
		cant_die_button.pressed.connect(_on_dev_toggled.bind(true, not DevMode.is_cant_die()))
		column.add_child(cant_die_button)


func _on_dev_toggled(enabled: bool, cant_die: bool) -> void:
	DevMode.set_flags(enabled, cant_die)
	reload_scene(false)


# See debug_start_wallet. Headless is skipped for apply_upgrades()'s reason: a probe must never
# write the developer's own save.dat.
func apply_debug_start_wallet() -> void:
	if debug_start_wallet <= 0 or services == null or not OS.is_debug_build():
		return
	if DisplayServer.get_name() == "headless":
		return
	if services.save_store.coin_wallet < debug_start_wallet:
		services.save_store.coin_wallet = debug_start_wallet
		services.save_store.save_to_disk()


func _on_shop_pressed() -> void:
	sfx_player.play_click()
	modal_return_state = State.DEAD
	refresh_shop()
	set_state(State.SHOP)


# Upgrades button on the START screen -- the shop's other entry point. Purchases here
# apply immediately via apply_upgrades() same as from the death screen; there's no
# run in progress to desync from.
func _on_start_shop_pressed() -> void:
	sfx_player.play_click()
	modal_return_state = State.START
	refresh_shop()
	set_state(State.SHOP)


func _on_shop_close_pressed() -> void:
	sfx_player.play_back()
	set_state(modal_return_state)


func _on_stats_pressed() -> void:
	sfx_player.play_click()
	modal_return_state = State.START
	refresh_stats()
	set_state(State.STATS)


func _on_stats_close_pressed() -> void:
	sfx_player.play_back()
	set_state(modal_return_state)


# Rebuilt on every open: a handful of labels, and it can never show a stale number.
func refresh_stats() -> void:
	for grid: GridContainer in [stats_grid, achievements_grid]:
		for child: Node in grid.get_children():
			grid.remove_child(child)
			child.queue_free()
	if services != null:
		var save: SaveStore = services.save_store
		var rows: Array = [
			["Distance", format_distance(save.total_distance_meters)],
			["Longest run", format_distance(save.best_distance_meters)],
			["Runs", str(save.total_runs)],
			["Time played", format_playtime(save.total_playtime_seconds)],
			["Coins earned", str(save.total_coins_earned)],
			["Best score", "%d  (%s)" % [save.best_score, main.format_elapsed_time(save.best_time)]],
			["Frozen lakes", str(save.frozen_lake_count)],
			["Auroras", str(save.aurora_count)],
			["Missions completed", str(save.missions_completed)],
			["Best Melt", "%.1fs" % save.best_melt_seconds],
		]
		for row: Array in rows:
			add_stats_row(stats_grid, row[0], row[1], true)
	if achievement_manager == null:
		return
	for row: Dictionary in achievement_manager.get_rows():
		var earned: bool = achievement_manager.is_earned(row["id"])
		var value: String = "Earned" if earned else row["hint"]
		var reward: Dictionary = Skins.get_sparkle_for_achievement(row["id"])
		if not reward.is_empty():
			value += "  +%s sparkle" % reward["name"]
		add_stats_row(achievements_grid, row["name"], value, earned)


func add_stats_row(grid: GridContainer, title: String, value: String, is_lit: bool) -> void:
	for text: String in [title, value]:
		var label: Label = Label.new()
		label.text = text
		label.add_theme_font_size_override(&"font_size", 14)
		label.modulate.a = 1.0 if is_lit else STATS_DIM_ALPHA
		grid.add_child(label)


func _on_skins_pressed() -> void:
	sfx_player.play_click()
	modal_return_state = State.START
	refresh_skin_buttons()
	set_state(State.SKINS)


func _on_skins_close_pressed() -> void:
	sfx_player.play_back()
	set_state(modal_return_state)


# One toggle per skin, its first frame as the picture; a ButtonGroup makes them a radio set, and
# the theme's pressed style is what marks the current one.
func build_skin_buttons() -> void:
	var group: ButtonGroup = ButtonGroup.new()
	for skin: Dictionary in Skins.SKINS:
		var frames: SpriteFrames = load(String(skin["frames"])) as SpriteFrames
		var button: Button = Button.new()
		button.text = skin["name"]
		button.toggle_mode = true
		button.button_group = group
		button.icon = frames.get_frame_texture(&"skate", 0) if frames != null else null
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.custom_minimum_size = SKIN_BUTTON_SIZE
		button.pressed.connect(_on_skin_picked.bind(String(skin["id"])))
		skins_row.add_child(button)
		skin_buttons[String(skin["id"])] = button
	var sparkle_group: ButtonGroup = ButtonGroup.new()
	for sparkle: Dictionary in Skins.SPARKLES:
		var button: Button = Button.new()
		button.text = sparkle["name"]
		button.toggle_mode = true
		button.button_group = sparkle_group
		# The name is drawn in its own colour: the swatch is the label.
		for font_color: StringName in [&"font_color", &"font_pressed_color", &"font_hover_color", &"font_focus_color"]:
			button.add_theme_color_override(font_color, sparkle["color"])
		button.pressed.connect(_on_sparkle_picked.bind(String(sparkle["id"])))
		sparkles_row.add_child(button)
		sparkle_buttons[String(sparkle["id"])] = button
	build_collection()


# A skin not bought yet shows its price and cannot be picked: the shop sells it.
func refresh_skin_buttons() -> void:
	var worn: String = get_worn_skin_id()
	for skin: Dictionary in Skins.SKINS:
		var id: String = skin["id"]
		var button: Button = skin_buttons[id]
		var owned: bool = is_skin_owned(id)
		button.text = skin["name"] if owned \
			else "%s  %d" % [skin["name"], UpgradeStore.get_upgrade_cost(Skins.get_track_id(id), 0)]
		button.disabled = not owned
		button.set_pressed_no_signal(id == worn)
	var worn_sparkle: String = get_worn_sparkle_id()
	for id: String in sparkle_buttons:
		sparkle_buttons[id].disabled = not is_sparkle_unlocked(id)
		sparkle_buttons[id].set_pressed_no_signal(id == worn_sparkle)
	refresh_collection()


# Two pages inside the existing Skaters modal; Back remains outside the tabs. Reparent only
# after wire_scene has resolved the authored paths. The scene is rebuilt on every reload.
func build_collection() -> void:
	var column: VBoxContainer = skins_row.get_parent() as VBoxContainer
	collection_tabs = TabContainer.new()
	collection_tabs.custom_minimum_size = Vector2(780, 448)
	collection_tabs.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(collection_tabs)
	column.move_child(collection_tabs, 1)
	var skaters: VBoxContainer = VBoxContainer.new()
	skaters.name = "Skaters"
	skaters.alignment = BoxContainer.ALIGNMENT_CENTER
	collection_tabs.add_child(skaters)
	skins_row.reparent(skaters)
	column.get_node("SparkleLabel").reparent(skaters)
	sparkles_row.reparent(skaters)
	var finds: VBoxContainer = VBoxContainer.new()
	finds.name = "Chest finds"
	finds.alignment = BoxContainer.ALIGNMENT_CENTER
	finds.add_theme_constant_override("separation", 8)
	collection_tabs.add_child(finds)
	for kind: String in Cosmetics.KINDS:
		var label: Label = Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		finds.add_child(label)
		collection_labels[kind] = label
		var row: HBoxContainer = HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		finds.add_child(row)
		var group: ButtonGroup = ButtonGroup.new()
		if kind != "charm":
			var original: Button = make_collection_button("Original", kind, "", group)
			original.icon = load(Cosmetics.ICONS[kind]) as Texture2D
			original.expand_icon = true
			original.add_theme_constant_override("icon_max_width", 36)
			original.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			original.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			row.add_child(original)
			collection_buttons[kind] = original
		for item: Dictionary in Cosmetics.ITEMS:
			if item["kind"] != kind:
				continue
			var button: Button = make_collection_button(item["name"], kind, item["id"], group)
			button.icon = load(item.get("icon", Cosmetics.ICONS[kind])) as Texture2D
			button.expand_icon = true
			button.add_theme_constant_override("icon_max_width", 36)
			button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			button.add_theme_color_override("icon_normal_color", item["color"])
			row.add_child(button)
			collection_buttons[item["id"]] = button


func make_collection_button(title: String, kind: String, id: String, group: ButtonGroup) -> Button:
	var button: Button = Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(168, 96)
	button.toggle_mode = kind != "charm"
	if not id.is_empty():
		var lock_badge: TextureRect = TextureRect.new()
		lock_badge.name = "LockBadge"
		lock_badge.texture = preload("res://assets/ui/icons/lock.svg")
		lock_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lock_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		lock_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock_badge.modulate = Color(0.7, 0.8, 0.9, 0.8)
		button.add_child(lock_badge)
		lock_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		lock_badge.offset_left = -24
		lock_badge.offset_right = -8
		lock_badge.offset_top = 8
		lock_badge.offset_bottom = 24
	if kind == "charm":
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.focus_mode = Control.FOCUS_NONE
	if button.toggle_mode:
		button.button_group = group
		button.pressed.connect(_on_cosmetic_picked.bind(kind, id))
	return button


func get_worn_cosmetic(kind: String) -> String:
	if services == null:
		return ""
	var id: String = services.save_store.selected_cosmetics.get(kind, "")
	var item: Dictionary = Cosmetics.get_item(id)
	return id if item.get("kind", "") == kind and services.save_store.cosmetics.get(id, false) else ""


func refresh_collection() -> void:
	if collection_buttons.is_empty():
		return
	var owned: Dictionary = services.save_store.cosmetics if services != null else {}
	for kind: String in Cosmetics.KINDS:
		var count: int = 0
		var total: int = 0
		var selected: String = get_worn_cosmetic(kind)
		if collection_buttons.has(kind):
			collection_buttons[kind].set_pressed_no_signal(selected.is_empty())
		for item: Dictionary in Cosmetics.ITEMS:
			if item["kind"] != kind:
				continue
			total += 1
			var unlocked: bool = owned.get(item["id"], false)
			count += int(unlocked)
			var button: Button = collection_buttons[item["id"]]
			button.text = "%s\n%s" % [item["name"], ("Collected" if kind == "charm" else ("Equipped" if selected == item["id"] else "Equip")) if unlocked else "In chests"]
			button.get_node("LockBadge").visible = not unlocked
			button.disabled = not unlocked
			button.set_pressed_no_signal(selected == item["id"])
		collection_labels[kind].text = "%s  %d/%d" % [Cosmetics.TITLES[kind], count, total]


func _on_cosmetic_picked(kind: String, id: String) -> void:
	if services == null or kind == "charm" or not Cosmetics.KINDS.has(kind):
		return
	var item: Dictionary = Cosmetics.get_item(id)
	if not id.is_empty() and (item.get("kind", "") != kind or not services.save_store.cosmetics.get(id, false)):
		refresh_collection()
		return
	var previous: Dictionary[String, String] = services.save_store.selected_cosmetics.duplicate()
	services.save_store.selected_cosmetics[kind] = id
	if not services.save_store.save_to_disk():
		services.save_store.selected_cosmetics = previous
	else:
		sfx_player.play_click()
		apply_cosmetics()
	refresh_collection()


func apply_cosmetics() -> void:
	if player == null or DisplayServer.get_name() == "headless":
		return
	var trail: Dictionary = Cosmetics.get_item(get_worn_cosmetic("trail"))
	player.flight_trail.configure(trail)
	player.flight_trail.modulate = trail.get("color", Skins.get_sparkle(get_worn_sparkle_id())["color"])
	var outfit: Dictionary = Cosmetics.get_item(get_worn_cosmetic("outfit"))
	if outfit.is_empty():
		player.animated_sprite.material = null
	else:
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = OUTFIT_SHADER
		material.set_shader_parameter("outfit_color", outfit["color"])
		material.set_shader_parameter("clothing_hue", Cosmetics.CLOTHING_HUES[get_worn_skin_id()])
		material.set_shader_parameter("hue_radius", Cosmetics.CLOTHING_HUE_RADIUS[get_worn_skin_id()])
		material.set_shader_parameter("saturation_floor", 0.025 if get_worn_skin_id() == "twenties" else 0.08)
		player.animated_sprite.material = material


func is_skin_owned(id: String) -> bool:
	return id == Skins.DEFAULT_ID or (services != null and services.upgrades.get_level(Skins.get_track_id(id)) > 0)


# The saved pick if it is still owned, else the default: Reset Progress un-buys every skin but
# keeps the pick, which is a preference.
func get_worn_skin_id() -> String:
	var selected: String = Skins.get_skin(services.save_store.selected_skin if services != null else Skins.DEFAULT_ID)["id"]
	return selected if is_skin_owned(selected) else Skins.DEFAULT_ID


func is_sparkle_unlocked(id: String) -> bool:
	var achievement: String = Skins.get_sparkle(id)["achievement"]
	return achievement.is_empty() or (services != null and services.save_store.achievements.get(achievement, false))


# Same rule as get_worn_skin_id(): the pick if still unlocked (a reset relocks), else Ice.
func get_worn_sparkle_id() -> String:
	var selected: String = Skins.get_sparkle(services.save_store.selected_sparkle if services != null else Skins.DEFAULT_SPARKLE_ID)["id"]
	return selected if is_sparkle_unlocked(selected) else Skins.DEFAULT_SPARKLE_ID


# Tints the landing glints and the glide trail. Both draw white by design, so Ice -- white -- is
# their authored look, and a modulate on the parent node colours every child it makes.
func apply_sparkle() -> void:
	if player == null or DisplayServer.get_name() == "headless":
		return
	var color: Color = Skins.get_sparkle(get_worn_sparkle_id())["color"]
	if landing_burst != null:
		landing_burst.modulate = color
	player.flight_trail.modulate = color
	apply_cosmetics()


func _on_sparkle_picked(id: String) -> void:
	sfx_player.play_click()
	if services == null or not is_sparkle_unlocked(id):
		refresh_skin_buttons()
		return
	services.save_store.selected_sparkle = id
	services.save_store.save_to_disk()
	apply_sparkle()


func _on_skin_picked(id: String) -> void:
	sfx_player.play_click()
	if services == null or not is_skin_owned(id):
		refresh_skin_buttons()
		return
	services.save_store.selected_skin = id
	services.save_store.save_to_disk()
	apply_skin()


# 2h 14m, or 9m under an hour.
static func format_playtime(seconds: float) -> String:
	var minutes: int = int(seconds / 60.0)
	return "%dh %dm" % [minutes / 60, minutes % 60] if minutes >= 60 else "%dm" % minutes


func _on_buy_pressed(upgrade_id: String) -> void:
	if services == null:
		return
	if not services.upgrades.purchase(upgrade_id):
		# The button is disabled when unaffordable, so a refusal here is a save that failed
		# and was rolled back. The next refresh_shop() restores the wallet line.
		shop_wallet_label.text = "Couldn't save. Try again."
		return
	sfx_player.play_purchase()
	# A bought skater is worn at once: the purchase's payoff is seeing it.
	var skin_id: String = String(UpgradeStore.get_track(upgrade_id).get("skin", ""))
	if not skin_id.is_empty():
		services.save_store.selected_skin = skin_id
		services.save_store.save_to_disk()
		apply_skin()
	# Applied immediately even though the current run is over: keeping this next to the
	# purchase means there is exactly one ordering to reason about, and the restart that
	# follows re-derives the same value from disk anyway.
	apply_upgrades()
	refresh_shop()
	refresh_death_stats()


# THE SHOP IS CARDS, built from UpgradeStore.TRACKS (2026-11-15; it was one column of identical
# buttons). Upgrades in one row, skaters with their picture in a second, each card a name, one
# line of what it does, level pips for a track with more than one level, and its price button.
# shop_rows keeps "label" and "button" per track id, which air_move_probe reads.
const UPGRADE_ICONS: Dictionary = {
	"jump": "res://assets/ui/icons/jump.svg", "slam": "res://assets/ui/icons/slam.svg",
	"double_jump": "res://assets/ui/icons/double_jump.svg",
}
const SHOP_CARD_WIDTH: float = 176.0
const SHOP_CARD_COLOR: Color = Color(0.09, 0.13, 0.2)
const SHOP_CARD_BORDER: Color = Color(0.36, 0.52, 0.72)
const SHOP_PIP_SIZE: Vector2 = Vector2(18, 6)
const SHOP_PIP_ON: Color = Color(1.0, 0.82, 0.4)
const SHOP_PIP_OFF: Color = Color(1.0, 1.0, 1.0, 0.16)
const SHOP_SKATER_PICTURE_SIZE: Vector2 = Vector2(72, 96)
# A card the wallet cannot buy yet is dimmed to this.
const SHOP_CARD_DIM_ALPHA: float = 0.7


func build_shop_rows() -> void:
	var container: Node = shop_wallet_label.get_parent()
	var upgrades_row: HBoxContainer = make_shop_row()
	var skaters_title: Label = make_shop_label("Skaters", 16)
	var skaters_row: HBoxContainer = make_shop_row()
	var insert_index: int = shop_wallet_label.get_index() + 1
	for node: Control in [upgrades_row, skaters_title, skaters_row]:
		container.add_child(node)
		container.move_child(node, insert_index)
		insert_index += 1

	var card_style: StyleBoxFlat = StyleBoxFlat.new()
	card_style.bg_color = SHOP_CARD_COLOR
	card_style.border_color = SHOP_CARD_BORDER
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(8)
	card_style.set_content_margin_all(12)

	for track: Dictionary in UpgradeStore.TRACKS:
		var upgrade_id: String = String(track["id"])
		var card: PanelContainer = PanelContainer.new()
		card.custom_minimum_size = Vector2(SHOP_CARD_WIDTH, 0)
		card.add_theme_stylebox_override(&"panel", card_style)
		var column: VBoxContainer = VBoxContainer.new()
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		card.add_child(column)

		if track.has("skin"):
			var frames: SpriteFrames = load(String(Skins.get_skin(track["skin"])["frames"])) as SpriteFrames
			var picture: TextureRect = TextureRect.new()
			picture.texture = frames.get_frame_texture(&"skate", 0) if frames != null else null
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			picture.custom_minimum_size = SHOP_SKATER_PICTURE_SIZE
			column.add_child(picture)
		else:
			var picture: TextureRect = TextureRect.new()
			picture.texture = load(UPGRADE_ICONS[upgrade_id]) as Texture2D
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			picture.custom_minimum_size = Vector2(48, 48)
			picture.modulate = Color(0.7, 0.88, 1.0)
			column.add_child(picture)
		column.add_child(make_shop_label(String(track["name"]).trim_suffix(" skater"), 17))
		var label: Label = make_shop_label("", 12)
		label.modulate.a = 0.65
		column.add_child(label)

		var pips: Array[ColorRect] = []
		var max_level: int = UpgradeStore.get_max_level(upgrade_id)
		if max_level > 1:
			var pip_row: HBoxContainer = HBoxContainer.new()
			pip_row.alignment = BoxContainer.ALIGNMENT_CENTER
			for _level: int in range(max_level):
				var pip: ColorRect = ColorRect.new()
				pip.custom_minimum_size = SHOP_PIP_SIZE
				pip_row.add_child(pip)
				pips.append(pip)
			column.add_child(pip_row)

		var button: Button = Button.new()
		button.icon = preload("res://assets/ui/icons/coin.svg")
		button.add_theme_constant_override("icon_max_width", 16)
		button.pressed.connect(_on_buy_pressed.bind(upgrade_id))
		column.add_child(button)
		(skaters_row if track.has("skin") else upgrades_row).add_child(card)
		shop_rows[upgrade_id] = {"label": label, "button": button, "pips": pips, "card": card}

	# Back is the way out; Reset Progress is quiet and last, where a thumb leaving does not land.
	shop_close_button.custom_minimum_size = Vector2(260, 0)
	shop_close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	container.move_child(reset_progress_button, -1)
	reset_progress_button.flat = true
	reset_progress_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	reset_progress_button.add_theme_font_size_override(&"font_size", 11)
	reset_progress_button.modulate.a = 0.55


func make_shop_row() -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 12)
	return row


func make_shop_label(text: String, font_size: int) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", font_size)
	return label


func refresh_shop() -> void:
	if shop_screen == null or shop_rows.is_empty():
		return

	shop_wallet_label.text = "Wallet: %d coins" % (services.upgrades.get_wallet() if services != null else 0)
	var worn_skin: String = get_worn_skin_id()
	for track: Dictionary in UpgradeStore.TRACKS:
		var upgrade_id: String = String(track["id"])
		var level: int = services.upgrades.get_level(upgrade_id) if services != null else 0
		var next_cost: int = UpgradeStore.get_upgrade_cost(upgrade_id, level)
		var is_complete: bool = next_cost == UpgradeStore.NO_COST
		var row: Dictionary = shop_rows[upgrade_id]
		var label: Label = row["label"]
		var button: Button = row["button"]
		if upgrade_id == UpgradeStore.JUMP_UPGRADE_ID:
			label.text = "jump height x%.2f" % UpgradeStore.get_jump_multiplier(level)
			button.text = "MAX" if is_complete else "x%.2f for %d" % [UpgradeStore.get_jump_multiplier(level + 1), next_cost]
		elif track.has("skin"):
			label.text = "wearing" if worn_skin == track["skin"] else ("owned" if is_complete else "skater")
			button.text = "OWNED" if is_complete else "%d coins" % next_cost
		else:
			# A one-level track is an unlock.
			label.text = String(track["hint"])
			button.text = "OWNED" if is_complete else "%d coins" % next_cost
		for pip_index: int in range(row["pips"].size()):
			(row["pips"][pip_index] as ColorRect).color = SHOP_PIP_ON if pip_index < level else SHOP_PIP_OFF
		var can_buy: bool = services != null and services.upgrades.can_purchase(upgrade_id)
		button.disabled = not can_buy
		(row["card"] as Control).modulate.a = 1.0 if can_buy or is_complete else SHOP_CARD_DIM_ALPHA


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
		# Same reasoning as _on_buy_pressed: sync the now-reset levels onto the live
		# player immediately rather than waiting for the next reload.
		apply_upgrades()
		apply_skin()
		apply_sparkle()
		prepare_mission()
	refresh_shop()
	refresh_death_stats()
