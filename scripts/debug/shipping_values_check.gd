extends SceneTree

# Fails if any "turn this off before you commit" knob is left on. ~0.2s, no scene instantiated
# for the flag checks, no physics, no seeds.
#
#   godot --headless --path . --script res://scripts/debug/shipping_values_check.gd
#
# WHY THIS EXISTS. Every debug knob in this project is a plain `var` rather than an `@export`,
# deliberately, so the editor cannot serialise it into main.tscn (CLAUDE.md, "Things that break
# silently" -- the world_rebase_enabled regression). That choice has a cost nobody had covered:
# a plain var is invisible to every other gate, so nothing at all catches one left flipped. The
# obstacle flag was explicitly documented as "check by hand", and biome_distance was described
# as having a "tripwire" that was only ever a printed number -- biome_schedule_check returns
# PASS at any value, which was verified against a live TEMP value of 7500.0.
#
# So this checks the things that are actually checkable without running the game:
#
#   1. THE SOURCE-LEVEL DEFAULTS of each knob, by instantiating the script and reading the
#      property. Not by parsing the .gd text -- that would be fragile to formatting, and the
#      declared default is exactly what a fresh node in a shipped build gets.
#   2. THAT main.tscn SERIALISES NO OVERRIDE for any of them, by scanning the scene as TEXT.
#      Deliberately a text scan and not a property read on an instantiated scene: the text
#      catches a property this file has never heard of, which is the whole failure mode (the
#      freeze bug was `world_rebase_enabled = false` appearing in the scene file on its own).
#      A property read can only ever confirm the values someone already thought to enumerate.
#   3. THE PINNED ENGINE SETTINGS, from both sides: their EFFECTIVE value via ProjectSettings,
#      and that project.godot still DECLARES each one, by scanning it as text. Four of them are
#      pinned at values equal to the engine default, so a stripped pin reads back identically --
#      the text scan is the only half that can see one go missing. See both functions below.
#
# WHAT IT CANNOT CHECK, and why that is fine: the two PowerupSpawner first-spawn overrides
# derive from OS.is_debug_build(), so they are legitimately non-shipping values in every
# context this gate can run in (a gate runs on the editor binary, which IS a debug build).
# They are reported for information and never failed on. See the note at the bottom of report().
#
# --allow-temp downgrades every failure to a warning and still exits 0, for deliberately
# eyeballing a run with knobs flipped. Same opt-out idiom as freeze_search's --chasms=1. The
# point of the flag is that silencing this has to be a thing you typed.

const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
const PROJECT_FILE_PATH: String = "res://project.godot"

# Every engine setting CLAUDE.md calls load-bearing, written as `section/key` -- which is both the
# ProjectSettings path and, split at the first "/", exactly how project.godot stores it (`[display]`
# + `window/size/viewport_width`). One list drives both the runtime check and the text scan.
const PINNED_SETTINGS: Array = [
	"display/window/size/viewport_width",
	"display/window/size/viewport_height",
	"physics/common/physics_ticks_per_second",
	"physics/common/physics_interpolation",
	"display/window/stretch/mode",
	"display/window/stretch/aspect",
	"display/window/handheld/orientation",
	"application/config/quit_on_go_back",
]

# [label, shipping value, actual value]. Built in check_flag_defaults().
var findings: Array[Array] = []
var failures: Array[String] = []


func _init() -> void:
	var allow_temp: bool = has_flag("--allow-temp")

	check_flag_defaults()
	check_scene_has_no_debug_overrides()
	check_project_settings()
	check_project_godot_declares_pins()
	report(allow_temp)


# Instantiated with .new() and freed immediately: _ready() only runs on tree entry, so nothing
# resolves a NodePath, spawns a chunk or touches the seed here.
func check_flag_defaults() -> void:
	var terrain: TerrainGenerator = TerrainGenerator.new()
	expect_bool("TerrainGenerator.debug_chasm_disabled", terrain.debug_chasm_disabled, false)
	expect_bool("TerrainGenerator.debug_drop_chasm_rehearsal", terrain.debug_drop_chasm_rehearsal, false)
	expect_bool("TerrainGenerator.debug_log_segment_selection", terrain.debug_log_segment_selection, false)
	expect_int("TerrainGenerator.debug_replay_session_seed", terrain.debug_replay_session_seed, -1)
	# Left set, every run gets a frozen lake at a fixed index regardless of playtime -- and
	# the lake suppresses every spawner across 7500px, so a shipped build would have a silent
	# dead zone in it.
	expect_int("TerrainGenerator.debug_force_lake_segment_index", terrain.debug_force_lake_segment_index, -1)
	# mega_drop is SEGMENT CUT, not fixed (CLAUDE.md / camera_shake.md). A non-zero weight here
	# reintroduces the one feature with a known unfixed visible shake.
	expect_int("TerrainGenerator.debug_weight_mega_drop", terrain.debug_weight_mega_drop,
		TerrainGenerator.MEGA_DROP_SELECTION_WEIGHT)
	terrain.free()

	var obstacles: ObstacleSpawner = ObstacleSpawner.new()
	expect_bool("ObstacleSpawner.debug_spawning_disabled", obstacles.debug_spawning_disabled, false)
	obstacles.free()

	var powerups: PowerupSpawner = PowerupSpawner.new()
	expect_bool("PowerupSpawner.debug_spawning_disabled", powerups.debug_spawning_disabled, false)
	expect_string("PowerupSpawner.debug_forced_effect", String(powerups.debug_forced_effect), "")
	powerups.free()

	var main: Main = Main.new()
	expect_bool("Main.world_rebase_enabled", main.world_rebase_enabled, true)
	main.free()

	var game_manager: GameManager = GameManager.new()
	expect_bool("GameManager.require_start_screen", game_manager.require_start_screen, true)
	game_manager.free()

	expect_float("BiomeDirector.BIOME_DISTANCE", BiomeDirector.BIOME_DISTANCE, 75000.0)
	expect_float("BiomeDirector.TRANSITION_DISTANCE", BiomeDirector.TRANSITION_DISTANCE, 24000.0)
	# Left on, every run reopens on the intro biome and the day arc never advances across a
	# sitting -- which is the whole feature, silently gone.
	var director: BiomeDirector = BiomeDirector.new()
	expect_bool("BiomeDirector.debug_pin_intro_biome", director.debug_pin_intro_biome, false)
	# Left set, the day arc races -- one biome every few seconds for the whole run, which is a
	# review tool and reads as a strobing bug in a shipped build. No headless gate can see it
	# either: BiomeDirector returns early under --headless, so this is the only cover.
	expect_float("BiomeDirector.debug_biome_seconds", director.debug_biome_seconds, 0.0)
	director.free()

	# Left set, the 20-minute set piece fires on whatever the override says instead -- at a
	# playtest value that is a lake every few seconds, each one suppressing every spawner
	# across 7500px.
	var lake_director: FrozenLakeDirector = FrozenLakeDirector.new()
	expect_float("FrozenLakeDirector.debug_lake_interval_override", lake_director.debug_lake_interval_override, 0.0)
	# Left set, a lake can fire before the speed ramp has finished -- so the 7500px sheet takes
	# up to 39s to cross instead of 10, and the set piece ships at a pace nobody has judged.
	expect_float("FrozenLakeDirector.debug_lake_min_run_time_override", lake_director.debug_lake_min_run_time_override, 0.0)
	lake_director.free()


# The freeze-bug check, generalised. Any of these appearing as a serialised property in the
# scene means the editor wrote a debug knob into it -- which is the exact mechanism that
# disabled world rebasing for weeks. Matched on the property name at the start of a line, so a
# mention inside a comment or a NodePath cannot trip it.
func check_scene_has_no_debug_overrides() -> void:
	var forbidden_prefixes: PackedStringArray = PackedStringArray([
		"debug_", "world_rebase_enabled", "require_start_screen",
	])

	var file: FileAccess = FileAccess.open(MAIN_SCENE_PATH, FileAccess.READ)
	if file == null:
		failures.append("could not open %s to scan for serialised debug overrides" % MAIN_SCENE_PATH)
		return

	var line_number: int = 0
	while not file.eof_reached():
		var line: String = file.get_line()
		line_number += 1
		for prefix: String in forbidden_prefixes:
			if not line.begins_with(prefix):
				continue
			failures.append("%s:%d serialises `%s` -- a debug knob must never reach the scene file. Delete the line in the editor (or by hand); this is the world_rebase_enabled regression's exact mechanism (docs/research/freeze_bug.md)"
				% [MAIN_SCENE_PATH, line_number, line.strip_edges()])
	file.close()


# THE PINNED ENGINE SETTINGS, half one. The EFFECTIVE value, read from ProjectSettings.
#
# Godot only serialises a setting that DIFFERS from the engine default, and four of the values
# CLAUDE.md calls load-bearing are currently equal to their defaults -- 1152x648, 60Hz,
# interpolation off. get_setting() returns the effective value either way: the file's, or the
# engine's when the file is silent. So this half catches the value drifting, whatever the file
# says, and it is the only half that can see a key whose line is present but edited.
#
# It cannot see the pin itself going missing, because a stripped key reads back identically.
# That is what check_project_godot_declares_pins() is for.
func check_project_settings() -> void:
	expect_int("ProjectSettings display/window/size/viewport_width",
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)), 1152)
	expect_int("ProjectSettings display/window/size/viewport_height",
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 0)), 648)
	expect_int("ProjectSettings physics/common/physics_ticks_per_second",
		int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 0)), 60)
	expect_bool("ProjectSettings physics/common/physics_interpolation",
		bool(ProjectSettings.get_setting("physics/common/physics_interpolation", true)), false)
	expect_string("ProjectSettings display/window/stretch/mode",
		str(ProjectSettings.get_setting("display/window/stretch/mode", "")), "canvas_items")
	expect_string("ProjectSettings display/window/stretch/aspect",
		str(ProjectSettings.get_setting("display/window/stretch/aspect", "")), "expand")
	expect_string("ProjectSettings display/window/handheld/orientation",
		str(ProjectSettings.get_setting("display/window/handheld/orientation", "")), "landscape")
	expect_bool("ProjectSettings application/config/quit_on_go_back",
		bool(ProjectSettings.get_setting("application/config/quit_on_go_back", true)), false)


# THE PINNED ENGINE SETTINGS, half two. That project.godot still DECLARES each one, as text.
#
# WHY THIS EXISTS, and why it was argued against for months. The reasoning this file used to
# carry was: the editor strips the default-equal keys every time it opens the project, so a text
# scan would fail constantly while nothing was wrong, and a gate that cries wolf gets disabled.
#
# THAT PREMISE WAS WRONG, measured 2026-08-26 on a throwaway copy. A cold import with .godot/
# deleted, and a full signed --export-debug APK, both left project.godot byte-identical. The
# real trigger is a project-setting SAVE -- editing a setting in the editor, or any
# ProjectSettings.save(). So the file is stable across ordinary work, this scan sits quiet, and
# it fires exactly when a pin has actually been dropped. See docs/development/debugging.md,
# "Engine commands that rewrite `project.godot`".
#
# WHAT IT PROTECTS. Four of these keys are pinned AT their engine defaults, so once stripped
# they are invisible: half one above reads back the identical value and passes, and nothing else
# in the repo looks. Several terrain constants derive from 1.0/physics_ticks_per_second, so that
# number is level geometry (CLAUDE.md, "Editing rules"), and base size and Camera2D.zoom are one
# decision whose ratio is the player's reaction time. If an engine default ever moves under a
# stripped key, both change silently. This is the only thing that would notice.
#
# Presence only, deliberately -- not the value. A pin that is present but edited already fails
# half one, and parsing typed values here would duplicate that for no extra coverage.
func check_project_godot_declares_pins() -> void:
	var file: FileAccess = FileAccess.open(PROJECT_FILE_PATH, FileAccess.READ)
	if file == null:
		failures.append("could not open %s to scan for the pinned settings" % PROJECT_FILE_PATH)
		return

	# project.godot is `[section]` headers over `key=value`, where the ProjectSettings path is
	# the two joined by "/". Rebuild that path per line so the list above can be matched whole.
	var declared: PackedStringArray = PackedStringArray()
	var section: String = ""
	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		if line.is_empty() or line.begins_with(";"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2)
			continue
		var equals: int = line.find("=")
		if equals > 0:
			declared.append("%s/%s" % [section, line.substr(0, equals).strip_edges()])
	file.close()

	for setting: String in PINNED_SETTINGS:
		var is_declared: bool = declared.has(setting)
		findings.append(["project.godot declares %s" % setting, "present",
			"present" if is_declared else "STRIPPED", is_declared])
		if not is_declared:
			failures.append("project.godot no longer declares `%s` -- a project-setting save stripped the pin. The engine default currently equals it, so nothing else in the repo can see the difference. Restore it with `git checkout -- project.godot` (the comment above it is the only record of why it exists)" % setting)


func expect_bool(label: String, actual: bool, shipping: bool) -> void:
	record(label, str(shipping), str(actual), actual == shipping)


func expect_int(label: String, actual: int, shipping: int) -> void:
	record(label, str(shipping), str(actual), actual == shipping)


func expect_float(label: String, actual: float, shipping: float) -> void:
	record(label, "%.1f" % shipping, "%.1f" % actual, is_equal_approx(actual, shipping))


func expect_string(label: String, actual: String, shipping: String) -> void:
	record(label, "\"%s\"" % shipping, "\"%s\"" % actual, actual == shipping)


func record(label: String, shipping: String, actual: String, is_ok: bool) -> void:
	findings.append([label, shipping, actual, is_ok])
	if not is_ok:
		failures.append("%s is %s, shipping value is %s" % [label, actual, shipping])


func report(allow_temp: bool) -> void:
	print("")
	for finding: Array in findings:
		print("  %-48s %-10s %s" % [finding[0], finding[2], "" if finding[3] else "!= %s" % finding[1]])

	# Reported, never failed on: both derive from OS.is_debug_build(), so a gate (which runs on
	# the editor binary) always sees the debug value. They are the reason an editor playtest
	# never exercises the real first-spawn draw -- worth seeing, not worth blocking on.
	var powerups: PowerupSpawner = PowerupSpawner.new()
	print("")
	print("  editor-only (is_debug_build, not checked):")
	print("    first powerup time override    %.1f" % powerups.debug_first_powerup_time_override)
	print("    first powerup effect override  \"%s\"" % powerups.debug_first_powerup_effect_override)
	powerups.free()
	print("")

	if failures.is_empty():
		print("SHIPPING_VALUES_CHECK PASS  ", findings.size(), " knobs at shipping values, scene clean, project.godot pinned")
		quit(0)
		return

	if allow_temp:
		print("SHIPPING_VALUES_CHECK WARN  ", failures.size(), " knob(s) not at shipping values (--allow-temp)")
		for failure: String in failures:
			print("    ", failure)
		print("  NOT SHIPPABLE. Revert before committing.")
		quit(0)
		return

	print("SHIPPING_VALUES_CHECK FAIL  ", failures.size(), " knob(s) not at shipping values")
	for failure: String in failures:
		print("    ", failure)
	print("  Re-run with --allow-temp if these are deliberate for an eyeballing session.")
	quit(1)


func has_flag(flag_name: String) -> bool:
	return OS.get_cmdline_user_args().has(flag_name)
