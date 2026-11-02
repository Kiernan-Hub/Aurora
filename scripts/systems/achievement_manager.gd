extends Node

class_name AchievementManager

# The one place in the project that decides an achievement has been earned, and the only thing
# that writes SaveStore.achievements. Set-piece directors emit completion signals; this listens.
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
# ADDING AN ACHIEVEMENT on a saved run stat is one row in ACHIEVEMENTS (see the table). Any other
# kind is two edits, both in this file: a row, and one `.connect(...)` in connect_triggers()
# pointing at a signal the relevant system ALREADY emits. If a system has no suitable signal, add
# the signal there -- do not add an achievement check there. The Aurora follows this rule through
# its existing `aurora_finished` signal, and run records through GameManager.run_recorded.
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
# dictionary precisely so ADDING a row needs no save-version bump -- that guarantee does not
# extend to changing a row. Names, hints, thresholds and the ORDER of rows are free to change.
#
# "hint" is the Records screen's how-to line. A row with "stat" is a RUN-RECORD achievement: it
# is checked after every recorded run, against the SaveStore field it names, and granted once
# that field reaches "at_least". Adding one is that row and nothing else -- the trigger
# (GameManager.run_recorded) is already wired. Rows without "stat" have their own trigger in
# connect_triggers(). Row order is the Records screen's order: roughly easiest first.
#
# The stats are SAVE fields, not this run's numbers, on purpose: best_score and longest_time
# already hold every earlier run, so a save from before these rows existed earns what it has
# already done on its next recorded run, with no migration.
const ACHIEVEMENTS: Dictionary = {
	"first_tracks": {
		"name": "First Tracks",
		"hint": "Finish your first run",
		"stat": "total_runs", "at_least": 1,
	},
	"glimmer": {
		"name": "Glimmer",
		"hint": "Score 50 in one run",
		"stat": "best_score", "at_least": 50,
	},
	"full_speed": {
		"name": "Full Speed",
		"hint": "Last 2:00 in one run",
		"stat": "longest_time", "at_least": 120,
	},
	"diamond_dust": {
		"name": "Diamond Dust",
		"hint": "Score 150 in one run",
		"stat": "best_score", "at_least": 150,
	},
	"still_water": {
		"name": "Still Water",
		"hint": "Cross a frozen lake",
	},
	"long_descent": {
		"name": "Long Descent",
		"hint": "Last 5:00 in one run",
		"stat": "longest_time", "at_least": 300,
	},
	"under_the_aurora": {
		"name": "Under the Aurora",
		"hint": "Skate through an aurora",
	},
	"glacier": {
		"name": "Glacier",
		"hint": "Collect 5,000 coins in total",
		"stat": "lifetime_coins", "at_least": 5000,
	},
}

const STILL_WATER: String = "still_water"
const UNDER_THE_AURORA: String = "under_the_aurora"

# Carries the display name as well as the id so the toast never has to know about this table.
signal achievement_granted(id: String, display_name: String)

@export var lake_director_path: NodePath = NodePath("../FrozenLakeDirector")
@export var aurora_director_path: NodePath = NodePath("../AuroraDirector")
@export var game_manager_path: NodePath = NodePath("../GameManager")

var services: GameServices
var lake_director: FrozenLakeDirector
var aurora_director: AuroraDirector
var game_manager: GameManager


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
	else:
		# lake_finished carries the running total, which is deliberately NOT what gates this.
		lake_director.lake_finished.connect(_on_lake_finished)

	aurora_director = get_node_or_null(aurora_director_path) as AuroraDirector
	if aurora_director == null:
		push_warning("AchievementManager: no AuroraDirector at %s; 'Under the Aurora' cannot be earned." % aurora_director_path)
	else:
		# Emitted only after a complete, non-preview encounter has advanced and saved progress.
		aurora_director.aurora_finished.connect(_on_aurora_finished)

	game_manager = get_node_or_null(game_manager_path) as GameManager
	if game_manager == null:
		push_warning("AchievementManager: no GameManager at %s; run-record achievements cannot be earned." % game_manager_path)
	else:
		# Every row with a "stat". Never emitted headless -- see the footer.
		game_manager.run_recorded.connect(_on_run_recorded)


func _on_lake_finished(_total_lakes: int) -> void:
	# GATED ON THE FLAG, NEVER ON `_total_lakes == 1`, and save_store.gd:59 spells out why the two
	# fields exist separately: the lake recurs every 20 minutes forever, the achievement fires
	# once. Counting would also re-fire it for anyone whose count is reset while their
	# achievements are not, and mis-fire if a lake is ever completed without incrementing.
	grant(STILL_WATER)


func _on_aurora_finished(_total_auroras: int) -> void:
	grant(UNDER_THE_AURORA)


# After record_run() has written the run, so every stat below already includes it.
func _on_run_recorded() -> void:
	if services == null or services.save_store == null:
		return
	for id: String in ACHIEVEMENTS:
		var row: Dictionary = ACHIEVEMENTS[id]
		if row.has("stat") and get_stat(services.save_store, String(row["stat"])) >= float(row["at_least"]):
			grant(id)


# A SaveStore field by name. Loud on a typo'd or non-numeric field, which would otherwise make
# its row silently unearnable. regression_probe's run_achievements case checks every row's stat.
static func get_stat(save_store: SaveStore, stat: String) -> float:
	var value: Variant = save_store.get(stat)
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		push_error("AchievementManager: '%s' is not a numeric SaveStore field." % stat)
		return 0.0
	return float(value)


# How many of the rows in ACHIEVEMENTS this save has earned. Ids in the save that no longer have
# a row (a newer build's, or a removed one) are not counted.
static func count_earned(save_store: SaveStore) -> int:
	var earned: int = 0
	for id: String in ACHIEVEMENTS:
		if save_store.achievements.get(id, false):
			earned += 1
	return earned


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


# ================= A TRAP FOR WHOEVER ADDS A TRIGGER =================
#
# THIS FILE HAS NO HEADLESS GUARD, AND THAT IS ONLY SAFE BECAUSE ALL THREE OF ITS TRIGGERS ARE
# headless-free at the source. The lake and Aurora directors hard-skip headless (their probes
# inject an in-memory SaveStore before driving the completion signals explicitly), and
# GameManager emits run_recorded only after record_run() really wrote a run -- which
# _on_player_died() never does headless. regression_probe calls _on_run_recorded() directly
# against its in-memory store, which is why the guard is at the emitter and not in the handler.
# There is also no per-frame work here to switch off.
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
