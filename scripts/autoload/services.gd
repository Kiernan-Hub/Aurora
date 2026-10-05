extends Node

class_name GameServices

# Registered in project.godot as the autoload "Services" -- the project's one autoload.
#
# NEVER write the global identifier `Services` in gameplay code; resolve it with
# GameServices.resolve(node), null-guarded. Under `--headless --script` the identifier does not
# exist (the NODE does, at /root/Services, from the script's first deferred call on), so
# `Services.x` is a COMPILE error: the class becomes Nil, every probe line configuring it fails,
# and the gate hangs on the start screen with no output (debugging.md, "Two ways a harness hangs
# instead of failing"). The class_name is GameServices because one equal to the autoload's name
# is a hard conflict.
#
# WHY AN AUTOLOAD IS ALLOWED: the no-autoload rule traces to an @export that main.tscn serialised
# to false (docs/research/freeze_bug.md). An autoload has no scene to serialise into, and nothing
# here is @export. WHY ONE IS NEEDED: restart reloads main.tscn, so the save and the volume
# settings must live outside it. Keep this a thin owner of per-concern components.
#
# HEADLESS TRAP: this node runs inside every probe in scripts/debug/. Anything touching audio,
# rendering or input must be gated on is_headless.

const AUTOLOAD_PATH: String = "/root/Services"
const MUSIC_BUS: StringName = &"Music"
const SFX_BUS: StringName = &"SFX"
# AudioServer floors to this well before 0.0 linear, and a real -80dB bus is
# inaudible anyway -- silences the slider's bottom end instead of leaving it at
# linear_to_db(0.0)'s -Inf, which the bus API accepts but is one dB literal
# away from breaking if that ever changes.
const MIN_VOLUME_DB: float = -80.0

var save_store: SaveStore = SaveStore.new()
# Meta-progression catalog + purchases. Reads and writes through save_store, which is
# injected in _ready() below rather than resolved, so UpgradeStore stays usable from
# headless probes that have no autoload at all.
var upgrades: UpgradeStore = UpgradeStore.new()
var is_headless: bool = false


# Returns null when the node is not in a tree with the autoload (an off-tree probe object).
# Under `--headless --script` the autoload node DOES exist, so this returns it. Callers
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
	upgrades.save_store = save_store

	# Headless probes have no audio driver; touching AudioServer there is exactly the
	# class of thing the HEADLESS TRAP note above warns about.
	if is_headless:
		return

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
