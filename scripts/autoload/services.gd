extends Node

class_name GameServices

# Registered in project.godot as the autoload "Services". The single exception to the
# project's otherwise-strict no-autoload rule.
#
# NEVER reference the global identifier `Services` from gameplay code -- always resolve
# it with GameServices.resolve(node) below. This is not a style preference, it is the
# difference between working harnesses and silently hanging ones:
#
#   `--headless --script` runs DO NOT REGISTER AUTOLOADS. A direct `Services.x` is a
#   COMPILE error there ("Identifier not found: Services"), not a runtime null -- so
#   the whole script fails to load, its class becomes Nil, and every probe line that
#   configures it (require_start_screen = false, debug_spawning_disabled = true) fails
#   against Nil. The gate then sits paused on the start screen and never terminates.
#   Measured 2026-08-03: one `Services.save_store` in game_manager.gd hung
#   camera_shake_probe indefinitely with no failure output.
#
# class_name is GameServices, not Services: a class_name identical to the autoload's
# global name is a hard conflict. The class_name is what makes the typed resolve()
# below compile with or without the autoload registered.
#
# WHY AN EXCEPTION IS SAFE HERE: the no-autoload rule in CLAUDE.md traces to the world
# rebasing regression (docs/research/freeze_bug.md) -- an @export flag that main.tscn
# silently serialized to false, disabling the fix for weeks. That failure mode is about
# SCENE SERIALIZATION of exported properties, not about globals. An autoload has no
# scene to serialize into and no Inspector to drift from. Nothing in this file is
# @export, for the same reason nothing in Main or GameManager is.
#
# WHY ONE IS NEEDED: restart is get_tree().reload_current_scene(), so every node in
# main.tscn is destroyed and rebuilt between runs. Anything that must outlive a run --
# the save file, volume settings, background music that shouldn't restart on every
# death -- cannot live in that scene. This is that layer, and it stays a thin owner of
# per-concern components rather than growing into a god object.
#
# HEADLESS TRAP -- read before adding anything here: autoloads are instantiated in
# `--headless --script` runs too, so this file runs inside every probe in
# scripts/debug/. Anything touching audio, rendering, or input must be gated on
# is_headless, the same way harnesses must set Main.world_rebase_enabled and
# GameManager.require_start_screen by hand. See docs/development/debugging.md.

const AUTOLOAD_PATH: String = "/root/Services"

var save_store: SaveStore = SaveStore.new()
var is_headless: bool = false


# Returns null in headless harness runs, where the autoload does not exist. Callers
# must null-guard; treat services as an optional convenience, never as a hard
# dependency, so no gameplay path can be made unrunnable by its absence.
static func resolve(from: Node) -> GameServices:
	return from.get_node_or_null(AUTOLOAD_PATH) as GameServices


func _ready() -> void:
	# Menus run while get_tree().paused is true (the start, pause and death screens all
	# use PROCESS_MODE_ALWAYS), and volume sliders on the pause screen call into here.
	process_mode = Node.PROCESS_MODE_ALWAYS

	is_headless = DisplayServer.get_name() == "headless"
	save_store.load_from_disk()


func set_music_volume(value: float) -> void:
	save_store.music_volume = clampf(value, 0.0, 1.0)
	save_store.save_to_disk()


func set_sfx_volume(value: float) -> void:
	save_store.sfx_volume = clampf(value, 0.0, 1.0)
	save_store.save_to_disk()
