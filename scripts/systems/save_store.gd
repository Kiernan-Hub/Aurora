extends RefCounted

class_name SaveStore

# Versioned read/write for user://save.dat. Owned by the Services autoload; nothing else touches
# the file. A file with no "version" key is v0 and is upgraded in place on the next write.
#
# FAILURE POLICY, deliberately asymmetric: a READ that fails for any reason yields defaults
# (field by field, see _is_number), because a corrupt save must never block play. A WRITE that
# fails calls push_error and returns false, and the live save on disk is left untouched.

const SAVE_PATH: String = "user://save.dat"
# Staging file for save_to_disk's write-then-rename. Never read back: if it exists at
# startup it is the debris of a write that failed after the payload landed but before the
# rename, and SAVE_PATH is still the last good save.
const TEMP_SAVE_PATH: String = "user://save.dat.tmp"
const CURRENT_VERSION: int = 3
const MAX_SAVED_COUNT: float = 9007199254740992.0

const DEFAULT_MUSIC_VOLUME: float = 0.8
const DEFAULT_SFX_VOLUME: float = 1.0

var best_score: int = 0
var best_time: float = 0.0
var music_volume: float = DEFAULT_MUSIC_VOLUME
var sfx_volume: float = DEFAULT_SFX_VOLUME

# Meta-progression (v2). The wallet is spendable currency every run banks into; best_score stays
# the run stat. upgrade_levels is an OPEN dictionary keyed by upgrade id, so a new upgrade needs
# no version bump; ids from a newer build are preserved and clamped by UpgradeStore.get_level.
# This file must NOT reference UpgradeStore -- see its header.
var coin_wallet: int = 0
var upgrade_levels: Dictionary[String, int] = {}

# Set pieces and achievements (v3).
#
# total_playtime_seconds is CUMULATIVE ACROSS EVERY RUN AND LAUNCH and only grows: the clock the
# frozen lake is scheduled against (GameManager.bank_playtime() owns the banking). achievements
# is open for the same reason upgrade_levels is. frozen_lake_count is lakes COMPLETED, which is
# also the index of the next 20-minute threshold -- safe only because it and the playtime clock
# were born together at v3, both 0.
var total_playtime_seconds: float = 0.0
var frozen_lake_count: int = 0
var achievements: Dictionary[String, bool] = {}

# Auroras COMPLETED: a statistic and the achievement's source, NEVER the schedule (that is
# next_aurora_due_seconds). Added without a version bump: a v3 file without the key reads 0, the
# correct state for a save that has never seen one.
var aurora_count: int = 0

# When the next aurora is due, as a cumulative-playtime timestamp; AuroraDirector is its only
# writer. A STORED DEADLINE, never (aurora_count + 1) x interval: the aurora arrived into saves
# already holding hours, and a multiple would pay that backlog out one aurora per run.
# -1.0 means UNSCHEDULED and every reader treats a negative as NOT DUE -- 0.0 would read as "due
# now". docs/development/aurora_borealis.md, "The schedule".
var next_aurora_due_seconds: float = -1.0


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
	load_from_data(parsed as Dictionary)


# Separate from the file read so regression_probe can test the field validation without
# touching user://.
func load_from_data(data: Dictionary) -> void:
	var version: int = _read_count(data, "version")

	# v0 -> v1: the pre-versioning file carried best_score and nothing else. Every
	# other field simply keeps its default, so there is no explicit conversion step --
	# reading the fields that exist IS the migration. The upgraded shape lands on disk
	# the next time save_to_disk() runs.
	best_score = _read_count(data, "best_score")

	if version >= 1:
		best_time = maxf(_read_number(data, "best_time", 0.0), 0.0)
		var settings: Dictionary = _read_dictionary(data, "settings")
		music_volume = clampf(_read_number(settings, "music_volume", DEFAULT_MUSIC_VOLUME), 0.0, 1.0)
		sfx_volume = clampf(_read_number(settings, "sfx_volume", DEFAULT_SFX_VOLUME), 0.0, 1.0)

	# v1 -> v2: same idiom as v0 -> v1 above. A v1 file has no wallet and no upgrades, so
	# the defaults (0 coins, level 0 everywhere) are exactly the correct new-player state
	# and there is nothing to convert.
	if version >= 2:
		coin_wallet = _read_count(data, "coin_wallet")
		# Copied key by key on purpose. JSON.parse_string returns an UNTYPED Dictionary,
		# and assigning one straight into a Dictionary[String, int] fails at runtime.
		# The int() casts are equally load-bearing: JSON round-trips every number as a
		# float, so the values arrive as 2.0, not 2.
		var stored_levels: Dictionary = _read_dictionary(data, "upgrades")
		for upgrade_id: Variant in stored_levels.keys():
			if _is_count(stored_levels[upgrade_id]):
				upgrade_levels[String(upgrade_id)] = int(stored_levels[upgrade_id])

	# v2 -> v3: same idiom again. A v2 file has never played a set piece, so 0 seconds
	# banked, 0 lakes seen and no achievements is the correct state for it -- an existing
	# player's 20-minute clock simply starts now rather than being back-dated, which is
	# the honest reading of "20 minutes of playtime" for a build that never measured it.
	if version >= 3:
		# maxf, and float() rather than int(): this is seconds, and a negative value could
		# only come from a hand-edited or corrupt file, where it would push the next lake
		# unreachably far away.
		total_playtime_seconds = maxf(_read_number(data, "total_playtime_seconds", 0.0), 0.0)
		frozen_lake_count = _read_count(data, "frozen_lake_count")
		# Read inside `version >= 3` rather than under a version of its own -- see the field's
		# note. Absent in a pre-aurora v3 file, where the 0 default is correct.
		aurora_count = _read_count(data, "aurora_count")
		# NO maxf CLAMP TO 0 HERE, unlike the seconds field above, because -1.0 is the
		# UNSCHEDULED sentinel and clamping it to 0.0 would mean "due immediately" -- the
		# backlog bug the sentinel exists to prevent. Absent in a pre-aurora save, where -1.0
		# is exactly right: AuroraDirector schedules it at load from where the player is.
		next_aurora_due_seconds = _read_number(data, "next_aurora_due_seconds", -1.0)
		# Copied key by key for the same reason upgrade_levels above is -- JSON hands back
		# an UNTYPED Dictionary, which cannot be assigned into a Dictionary[String, bool].
		var stored_achievements: Dictionary = _read_dictionary(data, "achievements")
		for achievement_id: Variant in stored_achievements.keys():
			if typeof(stored_achievements[achievement_id]) == TYPE_BOOL:
				achievements[String(achievement_id)] = stored_achievements[achievement_id]


# FIELD-BY-FIELD VALIDATION, NEVER A CAST. A cast of the wrong type (`[] as Dictionary`,
# `int([])`) aborts load_from_disk halfway, so one bad field used to skip every field after
# it -- and the next save then wrote those defaults over recoverable progress. Each reader
# returns its fallback for a wrong type, so only the bad field is lost.
#
# Finite only: valid JSON like 1e309 parses to INF, which would poison a clock or the wallet.
static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value))


# A non-negative whole-number field. JSON hands every number back as a float, and int() of one
# past int64 saturates rather than failing, so out-of-range values are rejected before the cast.
# 2^53 is the largest integer a float carries exactly.
static func _is_count(value: Variant) -> bool:
	return _is_number(value) and value >= 0 and value <= MAX_SAVED_COUNT


static func _read_number(source: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = source.get(key, fallback)
	return float(value) if _is_number(value) else fallback


static func _read_count(source: Dictionary, key: String) -> int:
	var value: Variant = source.get(key, 0)
	return int(value) if _is_count(value) else 0


static func _read_dictionary(source: Dictionary, key: String) -> Dictionary:
	var value: Variant = source.get(key, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


# WRITES VIA A TEMP FILE AND A RENAME, NEVER STRAIGHT OVER THE LIVE SAVE. Opening SAVE_PATH for
# writing truncates it first, so an app killed mid-write (Android reclaiming a backgrounded app)
# would leave an empty file that the silent read policy loads as a fresh save. rename is atomic,
# so the live file is always the old payload or the new one. A failed store/flush abandons the
# write before the rename, and the temp file is NOT cleaned up after a failed rename: it is then
# the only complete copy of the payload.
#
# Returns whether the payload reached SAVE_PATH. Only a purchase acts on it (UpgradeStore rolls
# back); every other caller's next save simply retries.
func save_to_disk() -> bool:
	var file: FileAccess = FileAccess.open(TEMP_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveStore failed to open %s for writing." % TEMP_SAVE_PATH)
		return false

	var payload: Dictionary = {
		"version": CURRENT_VERSION,
		"best_score": best_score,
		"best_time": best_time,
		"coin_wallet": coin_wallet,
		"upgrades": upgrade_levels,
		"total_playtime_seconds": total_playtime_seconds,
		"frozen_lake_count": frozen_lake_count,
		"aurora_count": aurora_count,
		"next_aurora_due_seconds": next_aurora_due_seconds,
		"achievements": achievements,
		"settings": {
			"music_volume": music_volume,
			"sfx_volume": sfx_volume,
		},
	}
	# The rename only protects the SWAP, not the payload: a short write (full disk, a killed
	# write) renamed over the live save is the exact truncation the temp file exists to stop.
	# So a failed store or flush abandons the save and leaves the live file alone.
	var stored: bool = file.store_string(JSON.stringify(payload))
	file.flush()
	var write_error: Error = file.get_error()
	# Explicit, not left to the RefCounted going out of scope: the rename below must not
	# race a buffer that has not been flushed yet.
	file.close()
	if not stored or write_error != OK:
		push_error("SaveStore failed to write %s (error %d). The save on disk is unchanged."
				% [TEMP_SAVE_PATH, write_error])
		return false

	var rename_result: Error = DirAccess.rename_absolute(TEMP_SAVE_PATH, SAVE_PATH)
	if rename_result != OK:
		push_error("SaveStore failed to move %s over %s (error %d). The save on disk is unchanged."
				% [TEMP_SAVE_PATH, SAVE_PATH, rename_result])
		return false
	return true


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
	# Cleared too, so "reset progress" means a genuinely fresh save rather than one that
	# hands the next lake out minutes later than a new install would. The consequence is
	# deliberate: the 20-minute clock restarts and the achievement can be earned again.
	total_playtime_seconds = 0.0
	frozen_lake_count = 0
	aurora_count = 0
	# Back to UNSCHEDULED rather than to an interval, because this file does not own the
	# interval -- AuroraDirector reschedules from 0 on its next IDLE tick or scene load.
	# Until then is_aurora_due() reads the negative and answers false.
	next_aurora_due_seconds = -1.0
	achievements.clear()
	save_to_disk()
