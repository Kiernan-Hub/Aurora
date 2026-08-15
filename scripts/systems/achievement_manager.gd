extends Node

class_name AchievementManager

# The one place in the project that decides an achievement has been earned, and the only thing
# that writes SaveStore.achievements. "Still Water" -- the first frozen lake -- is the first and
# currently only entry.
#
# WHY THIS IS ITS OWN NODE AND NOT PART OF GameManager OR FrozenLakeDirector. Two reasons, and
# the second is the load-bearing one.
#
# 1. GameManager is already ~700 lines and owns state, screens, score and the shop. This is
#    orthogonal, persistent, cross-run bookkeeping with its own vocabulary. BiomeDirector and
#    FrozenLakeDirector are the precedent: a sibling Node under Main that reads persisted state,
#    drives presentation, and stays out of everyone else's job.
#
# 2. THE TRIGGERS COME TO THIS FILE; THIS FILE NEVER GOES OUT TO THEM. FrozenLakeDirector does
#    not know achievements exist -- it emits lake_finished, which it already did before this file
#    was written, and this file listens. That direction is the whole design. The failure mode
#    being avoided is `if score > 1000: unlock(...)` sprouting in thirty scripts, at which point
#    nothing can answer "what unlocks this?" without a full-project grep. Every trigger in the
#    game is wired in connect_triggers() below, so that question has exactly one answer.
#
# ADDING AN ACHIEVEMENT is two edits, both in this file: a row in ACHIEVEMENTS, and one
# `.connect(...)` in connect_triggers() pointing at a signal the relevant system ALREADY emits.
# If a system has no suitable signal, add the signal there -- do not add an achievement check
# there. The aurora set piece planned as #2 is expected to land exactly this way.
#
# IT IS NOT A GameManager.State AND IT TOUCHES NO SCREEN. GameManager.set_state() remains the
# only thing allowed near get_tree().paused or a screen's visibility (CLAUDE.md states it as a
# hard rule). Nothing here goes near either; the toast owns its own visibility, the same way
# LakeReflection owns the mirror's.

# id -> definition. The value is a Dictionary rather than a bare display-name String so that a
# later field -- a description, an icon, an unlock payload for the biome/cosmetic unlocks the
# owner has in mind -- can be added without touching the shape of this table or any reader of
# it. There is deliberately no reward field yet: nothing in the game can consume one, and an
# unused hook is a thing to maintain, not a head start.
#
# THE KEYS ARE SAVE DATA. An id here is written verbatim into save.dat and read back forever, so
# renaming one silently un-earns it for every existing player. SaveStore.achievements is an OPEN
# dictionary (save_store.gd:63) precisely so ADDING a row needs no save-version bump -- that
# guarantee does not extend to changing a row.
const ACHIEVEMENTS: Dictionary = {
	"still_water": {
		"name": "Still Water",
	},
}

const STILL_WATER: String = "still_water"

# Carries the display name as well as the id so the toast never has to know about this table.
signal achievement_granted(id: String, display_name: String)

@export var lake_director_path: NodePath = NodePath("../FrozenLakeDirector")

var services: GameServices
var lake_director: FrozenLakeDirector


func _ready() -> void:
	# GameServices.resolve(self), never a bare `Services.x` -- the global identifier does not
	# exist under `--headless --script` even though the autoload NODE does, and reaching for it
	# breaks every probe. CLAUDE.md records this one twice.
	services = GameServices.resolve(self)
	if services == null or services.save_store == null:
		# Null-guarded rather than fatal, like the four lake files: a game that cannot record an
		# achievement is a game missing a line of text, not a broken one.
		push_warning("AchievementManager disabled: no GameServices/SaveStore.")
		return

	connect_triggers()


# EVERY ACHIEVEMENT TRIGGER IN THE GAME, in one function on purpose. See the header.
func connect_triggers() -> void:
	lake_director = get_node_or_null(lake_director_path) as FrozenLakeDirector
	if lake_director == null:
		push_warning("AchievementManager: no FrozenLakeDirector at %s; 'Still Water' cannot be earned." % lake_director_path)
		return

	# lake_finished carries the running total, which is deliberately NOT what gates this. See
	# _on_lake_finished.
	lake_director.lake_finished.connect(_on_lake_finished)


func _on_lake_finished(_total_lakes: int) -> void:
	# GATED ON THE FLAG, NEVER ON `_total_lakes == 1`, and save_store.gd:59 spells out why the two
	# fields exist separately: the lake recurs every 20 minutes forever, the achievement fires
	# once. Counting would also re-fire it for anyone whose count is reset while their
	# achievements are not, and mis-fire if a lake is ever completed without incrementing.
	grant(STILL_WATER)


# The single entry point. Idempotent by design -- callers may fire it on every occurrence of
# whatever they watch and let this decide, which is what keeps the trigger sites down to one line.
func grant(id: String) -> void:
	if not ACHIEVEMENTS.has(id):
		# Loud, because the only way to reach this is a typo'd id, and a typo'd id fails SILENTLY
		# otherwise: SaveStore.achievements is an open dictionary and would happily persist it.
		push_error("AchievementManager.grant: unknown achievement id '%s'." % id)
		return

	if services == null or services.save_store == null:
		return

	if services.save_store.achievements.get(id, false):
		return

	services.save_store.achievements[id] = true
	services.save_store.save_to_disk()

	var display_name: String = String(ACHIEVEMENTS[id].get("name", id))
	achievement_granted.emit(id, display_name)


func is_unlocked(id: String) -> bool:
	if services == null or services.save_store == null:
		return false
	return services.save_store.achievements.get(id, false)


# ================= A TRAP FOR WHOEVER ADDS ACHIEVEMENT #3 =================
#
# THIS FILE HAS NO HEADLESS GUARD, AND THAT IS ONLY SAFE BECAUSE OF WHAT ITS ONE TRIGGER IS.
# FrozenLakeDirector hard-skips headless, so lake_finished can never fire in a gate and grant()
# can never run there. There is also no per-frame work here to switch off.
#
# THE MOMENT A TRIGGER IS ADDED THAT DOES RUN HEADLESS -- anything hung off score, coins,
# distance or death, all of which the gates exercise for millions of frames -- THIS FILE STARTS
# WRITING TO THE DEVELOPER'S REAL save.dat DURING EVERY PROBE. That is the same class of bug as
# GameManager.apply_upgrades() reading upgrade levels in a gate (measured: 48/48 chasms -> 8
# failures), and this project has already lost one save file to a probe.
#
# So: a trigger that can fire headless needs the locally-computed guard the lake files use --
#
#     if DisplayServer.get_name() == "headless":
#         return
#
# -- computed here, never services.is_headless, which is assigned in GameServices._ready() and
# can still read false depending on node order.
