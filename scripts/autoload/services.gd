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
const MUSIC_BUS: StringName = &"Music"
const SFX_BUS: StringName = &"SFX"
# AudioServer floors to this well before 0.0 linear, and a real -80dB bus is
# inaudible anyway -- silences the slider's bottom end instead of leaving it at
# linear_to_db(0.0)'s -Inf, which the bus API accepts but is one dB literal
# away from breaking if that ever changes.
const MIN_VOLUME_DB: float = -80.0

var save_store: SaveStore = SaveStore.new()
var is_headless: bool = false
# Lives here, not in main.tscn, for the same reason save_store does: restart calls
# reload_current_scene() and destroys every node in that scene, but music
# transitioning between runs is exactly the case that must NOT restart.
# No stream is assigned yet -- CLAUDE.md build order still lists audio as
# not-started; this wires the bus and volume so a track can be dropped in later
# with no other changes.
var music_player: AudioStreamPlayer


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

	# Headless probes have no audio driver; touching AudioServer/AudioStreamPlayer
	# there is exactly the class of thing the HEADLESS TRAP note above warns about.
	if is_headless:
		return

	music_player = AudioStreamPlayer.new()
	music_player.name = "MusicPlayer"
	music_player.bus = MUSIC_BUS
	music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(music_player)
	apply_music_volume()
	apply_sfx_volume()


# Applies the new volume immediately but does NOT touch the disk. A slider drag emits
# value_changed on every step -- with step = 0.05 that is up to 20 writes for one sweep
# across the bar, and many more for a finger wobbling back and forth. Each write is a
# full open/stringify/store, i.e. synchronous flash I/O on the main thread mid-menu on
# Android. GameManager calls save_settings() below once the interaction is over.
func set_music_volume(value: float) -> void:
	save_store.music_volume = clampf(value, 0.0, 1.0)
	apply_music_volume()


func set_sfx_volume(value: float) -> void:
	save_store.sfx_volume = clampf(value, 0.0, 1.0)
	apply_sfx_volume()


# The single flush point for settings edited on the pause screen. Writes the whole save
# file, so a best score recorded earlier in the session rides along.
func save_settings() -> void:
	save_store.save_to_disk()


func apply_music_volume() -> void:
	if is_headless:
		return
	set_bus_volume(MUSIC_BUS, save_store.music_volume)


func apply_sfx_volume() -> void:
	if is_headless:
		return
	set_bus_volume(SFX_BUS, save_store.sfx_volume)


func set_bus_volume(bus_name: StringName, linear_value: float) -> void:
	var bus_index: int = AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return
	var volume_db: float = MIN_VOLUME_DB if linear_value <= 0.0 else linear_to_db(linear_value)
	AudioServer.set_bus_volume_db(bus_index, volume_db)
