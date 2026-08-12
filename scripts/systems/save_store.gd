extends RefCounted

class_name SaveStore

# Versioned read/write for user://save.dat. Owned by the Services autoload; nothing
# else should touch the file directly.
#
# This replaces GameManager's load_best_score()/save_best_score(), which stored a bare
# {"best_score": N} with no version field. That shape is fine for exactly one field and
# becomes a migration for every field after it, so the version key goes in now while
# there is only one payload to migrate. A file with no "version" key is treated as v0
# and upgraded in place on the next write.
#
# Failure policy is deliberately asymmetric and matches what GameManager already did:
# a READ that fails for any reason (missing file, unreadable, malformed JSON, wrong
# type) silently yields defaults, because a corrupt save must never block someone from
# playing. A WRITE that fails calls push_error, because that one is a real bug and
# silently losing a new best score is worse than a log line.

const SAVE_PATH: String = "user://save.dat"
const CURRENT_VERSION: int = 2

const DEFAULT_MUSIC_VOLUME: float = 0.8
const DEFAULT_SFX_VOLUME: float = 1.0

var best_score: int = 0
var best_time: float = 0.0
var music_volume: float = DEFAULT_MUSIC_VOLUME
var sfx_volume: float = DEFAULT_SFX_VOLUME

# Meta-progression (v2). best_score stays the run-score stat; the wallet is separate
# spendable currency that every run banks into.
#
# upgrade_levels is intentionally an open dictionary keyed by upgrade id rather than a
# named field per upgrade: adding an upgrade TYPE then needs no version bump, only a new
# top-level concept does. Unknown ids read from a newer build's file are preserved as-is
# and clamped to a legal level by UpgradeStore.get_level, so saves stay compatible in
# both directions. This file must NOT reference UpgradeStore -- see its header.
var coin_wallet: int = 0
var upgrade_levels: Dictionary[String, int] = {}


# Not named load(): that would shadow GDScript's global load() inside this class.
func load_from_disk() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	var data: Dictionary = parsed as Dictionary
	var version: int = int(data.get("version", 0))

	# v0 -> v1: the pre-versioning file carried best_score and nothing else. Every
	# other field simply keeps its default, so there is no explicit conversion step --
	# reading the fields that exist IS the migration. The upgraded shape lands on disk
	# the next time save_to_disk() runs.
	best_score = int(data.get("best_score", 0))

	if version >= 1:
		best_time = float(data.get("best_time", 0.0))
		var settings: Dictionary = data.get("settings", {}) as Dictionary
		music_volume = clampf(float(settings.get("music_volume", DEFAULT_MUSIC_VOLUME)), 0.0, 1.0)
		sfx_volume = clampf(float(settings.get("sfx_volume", DEFAULT_SFX_VOLUME)), 0.0, 1.0)

	# v1 -> v2: same idiom as v0 -> v1 above. A v1 file has no wallet and no upgrades, so
	# the defaults (0 coins, level 0 everywhere) are exactly the correct new-player state
	# and there is nothing to convert.
	if version >= 2:
		coin_wallet = maxi(int(data.get("coin_wallet", 0)), 0)
		# Copied key by key on purpose. JSON.parse_string returns an UNTYPED Dictionary,
		# and assigning one straight into a Dictionary[String, int] fails at runtime.
		# The int() casts are equally load-bearing: JSON round-trips every number as a
		# float, so the values arrive as 2.0, not 2.
		var stored_levels: Dictionary = data.get("upgrades", {}) as Dictionary
		for upgrade_id: Variant in stored_levels.keys():
			upgrade_levels[String(upgrade_id)] = maxi(int(stored_levels[upgrade_id]), 0)


func save_to_disk() -> void:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveStore failed to open %s for writing." % SAVE_PATH)
		return

	var payload: Dictionary = {
		"version": CURRENT_VERSION,
		"best_score": best_score,
		"best_time": best_time,
		"coin_wallet": coin_wallet,
		"upgrades": upgrade_levels,
		"settings": {
			"music_volume": music_volume,
			"sfx_volume": sfx_volume,
		},
	}
	file.store_string(JSON.stringify(payload))


# Returns true when this run beat the stored best, so the caller can show "New Best!".
# Time is recorded alongside but does not by itself qualify as a new best -- coins are
# the score, matching what the death screen has always reported.
#
# This ALWAYS writes now, where it used to write only on a new best. Every run banks its
# coins into the wallet, so there is always something to persist; a run that failed to
# beat the best but earned 40 coins toward an upgrade must not be silently dropped. It
# is still exactly one disk write per death.
func record_run(coin_count: int, elapsed_time: float) -> bool:
	var is_new_best: bool = coin_count > best_score
	if is_new_best:
		best_score = coin_count
		best_time = elapsed_time

	coin_wallet += maxi(coin_count, 0)
	save_to_disk()
	return is_new_best


# Wipes every progress field back to a fresh save -- best score, wallet, upgrade
# levels -- but deliberately leaves music_volume/sfx_volume untouched: those are a
# device preference, not progress, and a player resetting their save has no reason to
# expect their volume to jump back to the defaults too.
func reset_progress() -> void:
	best_score = 0
	best_time = 0.0
	coin_wallet = 0
	upgrade_levels.clear()
	save_to_disk()
