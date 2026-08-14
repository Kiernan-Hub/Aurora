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
# Staging file for save_to_disk's write-then-rename. Never read back: if it exists at
# startup it is the debris of a write that failed after the payload landed but before the
# rename, and SAVE_PATH is still the last good save.
const TEMP_SAVE_PATH: String = "user://save.dat.tmp"
const CURRENT_VERSION: int = 3

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

# Set pieces and achievements (v3).
#
# total_playtime_seconds is CUMULATIVE ACROSS EVERY RUN AND EVERY LAUNCH, and it is the
# clock the frozen lake is scheduled against -- not run time, which resets, and not
# wall-clock time, which would tick while the app is closed. GameManager owns the banking;
# see its bank_playtime(). It only ever grows.
#
# achievements is an open dictionary keyed by achievement id, for exactly the reason
# upgrade_levels above is: adding an achievement then needs no version bump. Only the
# concept arriving needed one. An id written by a later build is preserved untouched here
# and simply reads as unknown to this one.
#
# frozen_lake_count is how many lakes have been COMPLETED, so it doubles as the index of
# the next 20-minute threshold. Kept separate from the achievement flag because the
# achievement fires once and the lake recurs forever.
var total_playtime_seconds: float = 0.0
var frozen_lake_count: int = 0
var achievements: Dictionary[String, bool] = {}


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

	# v2 -> v3: same idiom again. A v2 file has never played a set piece, so 0 seconds
	# banked, 0 lakes seen and no achievements is the correct state for it -- an existing
	# player's 20-minute clock simply starts now rather than being back-dated, which is
	# the honest reading of "20 minutes of playtime" for a build that never measured it.
	if version >= 3:
		# maxf, and float() rather than int(): this is seconds, and a negative value could
		# only come from a hand-edited or corrupt file, where it would push the next lake
		# unreachably far away.
		total_playtime_seconds = maxf(float(data.get("total_playtime_seconds", 0.0)), 0.0)
		frozen_lake_count = maxi(int(data.get("frozen_lake_count", 0)), 0)
		# Copied key by key for the same reason upgrade_levels above is -- JSON hands back
		# an UNTYPED Dictionary, which cannot be assigned into a Dictionary[String, bool].
		var stored_achievements: Dictionary = data.get("achievements", {}) as Dictionary
		for achievement_id: Variant in stored_achievements.keys():
			achievements[String(achievement_id)] = bool(stored_achievements[achievement_id])


# WRITES VIA A TEMP FILE AND A RENAME, NEVER STRAIGHT OVER THE LIVE SAVE.
#
# Opening SAVE_PATH with FileAccess.WRITE truncates it to zero length before a single byte
# of the new payload lands. A kill in that window -- the OS reclaiming a backgrounded app on
# Android is the realistic one, not a crash -- leaves a truncated or empty file, and
# load_from_disk's deliberately silent failure policy then reads it as a fresh save. The
# player loses their wallet, best score and every upgrade level, with no error anywhere.
#
# rename is atomic on POSIX, and Godot's Windows DirAccess uses MoveFileExW with
# MOVEFILE_REPLACE_EXISTING, so the live file is either the old payload or the new one and
# never a partial write. The cost is one extra file create per save, which is nothing next
# to what it protects: this is the only writer of every persisted field in the project.
#
# The temp file is deliberately NOT cleaned up on a failed write -- if the rename is what
# failed, that file is the only complete copy of the payload that exists.
func save_to_disk() -> void:
	var file: FileAccess = FileAccess.open(TEMP_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveStore failed to open %s for writing." % TEMP_SAVE_PATH)
		return

	var payload: Dictionary = {
		"version": CURRENT_VERSION,
		"best_score": best_score,
		"best_time": best_time,
		"coin_wallet": coin_wallet,
		"upgrades": upgrade_levels,
		"total_playtime_seconds": total_playtime_seconds,
		"frozen_lake_count": frozen_lake_count,
		"achievements": achievements,
		"settings": {
			"music_volume": music_volume,
			"sfx_volume": sfx_volume,
		},
	}
	file.store_string(JSON.stringify(payload))
	# Explicit, not left to the RefCounted going out of scope: the rename below must not
	# race a buffer that has not been flushed yet.
	file.close()

	var rename_result: Error = DirAccess.rename_absolute(TEMP_SAVE_PATH, SAVE_PATH)
	if rename_result != OK:
		push_error("SaveStore failed to move %s over %s (error %d). The save on disk is unchanged."
				% [TEMP_SAVE_PATH, SAVE_PATH, rename_result])


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
	achievements.clear()
	save_to_disk()
