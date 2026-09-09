extends Node

class_name AuroraDirector

# Schedules and runs the aurora borealis: every 30 minutes of CUMULATIVE playtime,
# and only once the sky is actually night, three curtains of colour fade up across SkyBackdrop
# for ~45 seconds and fade back out. The first one earns an achievement (not wired yet).
#
# THE SIBLING OF FrozenLakeDirector, and read the two together -- this file is deliberately
# shaped like that one so the pair can be reasoned about at once. The differences are all
# consequences of one fact: THIS SET PIECE HAS NO GEOMETRY.
#
#   * No ARMED phase and no try_arm() call into TerrainGenerator, because there is nothing to
#     commit ahead of the player.
#   * No LAKE_MIN_RUN_TIME equivalent. That constant exists because the lake is a fixed
#     7500px, so its DURATION depends on how fast the player is moving -- 10.0s at MAX_SPEED,
#     nearly a minute during the ramp. This is measured in seconds, so it lasts what it says
#     at any speed, in any run, and needs no minimum-run gate at all.
#   * Nothing is suppressed and nothing is locked YET. Jumping, spawning, coins, obstacles and
#     chasms all carry on exactly as they were, and the player can ignore it entirely. THE CALM
#     BAND CHANGES THE LAST TWO OF THOSE and is not built -- see below.
#
# THE CALM BAND IS IN SCOPE, OWNER DECISION 2026-09-09, AND IT IS NOT BUILT. For the duration of
# an aurora the plan is that obstacles stop spawning and chasms are removed, so the player can
# look up without dying -- docs/development/aurora_borealis.md, "The calm". Until that phase
# lands, every line above stays literally true and this file touches no terrain at all.
#
# WHAT THAT PHASE MUST OBEY, and it is the load-bearing constraint on the whole feature.
# CLAUDE.md: get_terrain_height must stay pure in (session_seed, world_x), with EXACTLY ONE
# permitted runtime input today -- lake_segment_index -- and `arm_lake()` is its only writer,
# write-once and write-ahead so arming can only ever EXTEND the height field. Chunk visuals,
# collision, player tilt and the debug HUD all sample that field independently, so a range that
# moved after a sample would make them disagree inside one frame.
#
# The two halves of the calm are therefore NOT equally risky, and the plan splits them:
#
#   * NO OBSTACLES is free. Obstacles are spawned NODES, not terrain -- ObstacleSpawner already
#     skips a slot on is_lake_world_x, and the calm adds one more term to that same line. It
#     touches get_terrain_height not at all.
#   * NO CHASMS is terrain, and it is the part that needs care. A second write-once/write-ahead
#     range is one way; only starting over a stretch that is ALREADY chasm-free -- which is
#     queryable, since is_chasm_segment_index() is a pure function -- is the other, and it adds
#     no writer whatsoever. That choice is open and is recorded in the plan, not here.
#
# Division of labour, matching the lake exactly. This file owns WHEN and the state machine;
# SkyBackdrop owns the look; BiomeDirector owns what time of day it is; SaveStore owns the
# counters; AchievementManager listens. Nothing here reaches into a system to do that system's
# job, and nothing here reads a BiomePalette -- see NIGHT_THRESHOLD.
#
# IT IS NOT A GameManager.State. The game is still PLAYING throughout. GameManager.set_state()
# remains the only thing in the project allowed to touch get_tree().paused or a screen's
# visibility, and nothing here goes near either.
#
# Default process_mode (INHERIT), so this freezes on every menu for free -- the aurora cannot
# advance while the game is paused, and the playtime clock it reads stops for the same reason.

# Cumulative playtime BETWEEN SIGHTINGS. Owner decision 2026-09-09: 30 minutes, half the 60
# this file first shipped with. The lake is 20, so the aurora is not "three times the lake" --
# it is the next step up from it, and rarity here comes from the night gate as much as the
# clock, since a due aurora waits for a dark sky before it can start.
#
# NOT `(aurora_count + 1) * INTERVAL`, which is what LAKE_INTERVAL_SECONDS does and what this
# file did until the branches were reconciled. That device is safe for the lake only because
# frozen_lake_count and total_playtime_seconds were born together at v3; the aurora lands in
# saves that already hold hours, so a multiple is retroactively owed many times over and pays
# out back to back until the count catches up. The schedule is a stored deadline instead --
# SaveStore.next_aurora_due_seconds carries the full reasoning.
const AURORA_INTERVAL_SECONDS: float = 1800.0

# How long the ribbons hold at full strength, and how long they take to arrive and leave.
#
# PROPOSED, NOT MEASURED, and the owner should judge these in play rather than from the
# numbers -- they are the two values here most likely to move. The reasoning behind the
# starting point: the lake is 10s and is something you cross, this is something you watch, so
# it has to outlast a glance. The ceiling is the biome it needs: a night biome holds ~100s at
# MAX_SPEED, so 45 + two 8s ramps is 61s and fits inside one comfortably even if the aurora
# starts partway through. Raising the total past ~90s risks the sky brightening underneath it.
const AURORA_DURATION_SECONDS: float = 45.0
const AURORA_FADE_SECONDS: float = 8.0

# How dark the sky has to be before an aurora may begin, measured as BiomeDirector's blended
# star_density.
#
# NIGHT ONLY, AND THIS IS THE PART THAT IS EASY TO GET WRONG. The trigger above is cumulative
# playtime; the sky's colour is a pure function of world distance. The two are INDEPENDENT, so
# without this gate the first aurora a player ever sees can perfectly well arrive over
# pale_morning -- which does not read as a rare spectacle, it reads as a rendering bug.
#
# WHY star_density AND NOT A LIST OF PALETTE NAMES. It is already authored on all eight
# palettes, already blended every frame, and already means exactly "how much night is this":
#
#     starlit_night 1.00   twilight_blue 0.85   violet_dusk 0.30   arctic_dawn 0.28   rest 0.00
#
# So 0.8 is precisely the two night biomes -- 2/8 of the arc, matching the night-length
# decision already shipped -- with no second list to drift out of sync with the palettes. And
# reading the BLENDED value rather than the palette's identity excludes the crossfade
# shoulders for free: the aurora cannot begin while the sky is still on its way down.
#
# WHAT IT COSTS, and it is the same shape of cost LAKE_MIN_RUN_TIME already buys: the cadence
# is really "the first night biome after 30 minutes of playtime", not strictly every 30
# minutes. The arc is ~13.7 minutes, so night comes around within one cycle of the threshold
# being crossed. It also makes the event rarer, which is the goal, and it guarantees the
# starfield is up underneath the ribbons, which is the composition they were designed for.
const NIGHT_THRESHOLD: float = 0.8

# Playtest override for AURORA_INTERVAL_SECONDS. Any value > 0 replaces it, so an aurora can be
# reached in seconds instead of half an hour.
#
# Plain var, not @export, like every other knob in this project: an exported float serialises
# into main.tscn and ships silently, which is the world_rebase_enabled regression exactly
# (CLAUDE.md, "Things that break silently"). shipping_values_check fails on it.
#
# Note this does NOT bypass the night gate -- see the knob below, which is the one that does.
var debug_aurora_interval_override: float = 0.0

# Ignores NIGHT_THRESHOLD, so an aurora can be looked at without waiting for the day arc to
# reach night. Needed alongside the interval override, because that one alone cannot make an
# aurora happen in the ~10/13.7 minutes of the cycle that are not night.
#
# WHAT IT COSTS, and it is not nothing: the ribbons are authored to sit over a dark sky with
# the starfield up. Judging their colour against pale_morning is judging a composition the game
# never ships. Fine for checking that the state machine runs; wrong for judging the look.
# Pair it with BiomeDirector.debug_biome_seconds to reach a real night quickly instead.
var debug_aurora_ignore_night: bool = false

@export var player_path: NodePath = NodePath("../Player")
@export var biome_director_path: NodePath = NodePath("../BiomeDirector")
@export var sky_backdrop_path: NodePath = NodePath("../SkyBackdrop")

# ONE AURORA PER RUN, MAXIMUM. DONE is terminal, exactly as the lake's is, and nothing is lost
# by it: the deadline only moves in finish_aurora(), so a deadline crossed in a run that ended
# early is still crossed, and the next run is immediately due. Making it repeat within a run
# would mean re-entering IDLE, which is a design change, not a bug fix -- and it is also what
# keeps a future calm band's terrain reservation write-once for the life of a scene.
enum Phase { IDLE, ACTIVE, DONE }

signal aurora_started
signal aurora_finished(total_auroras: int)

var phase: Phase = Phase.IDLE
var player: Player
var biome_director: BiomeDirector
var sky_backdrop: Node
var main_node: Main
var services: GameServices
var is_headless: bool = false

# Seconds since the aurora began. Advanced in _physics_process, so it stops on every menu with
# the rest of the tree -- an aurora paused halfway through resumes halfway through rather than
# expiring behind the pause screen.
var active_elapsed: float = 0.0


func _ready() -> void:
	# Checked directly rather than through services.is_headless, which is assigned in
	# GameServices._ready() and can still read false here -- the ordering trap CLAUDE.md
	# records twice. This is not an optimisation: the trigger reads cumulative playtime out of
	# the developer's own save.dat, so an ungated director would behave differently depending
	# on how much the developer had played. That is the apply_upgrades() failure (48/48 -> 8)
	# with a different field.
	#
	# It is also what keeps AchievementManager safe. That file has no headless guard of its
	# own, and its closing note says so explicitly: that is only sound while every trigger it
	# listens to comes from a director that hard-skips headless. aurora_finished is about to
	# become its second trigger. This line is the reason that stays true.
	is_headless = DisplayServer.get_name() == "headless"
	if is_headless:
		set_physics_process(false)
		return

	player = get_node_or_null(player_path) as Player
	biome_director = get_node_or_null(biome_director_path) as BiomeDirector
	sky_backdrop = get_node_or_null(sky_backdrop_path)
	main_node = get_parent() as Main
	services = GameServices.resolve(self)
	if player == null or biome_director == null or main_node == null or services == null:
		# Null-guarded rather than fatal: a missing aurora is a missing spectacle, not a broken
		# game, and this must never be the thing that stops someone playing.
		push_warning("AuroraDirector disabled: missing player, biome director, Main or services.")
		set_physics_process(false)
		return

	player.died.connect(_on_player_died)
	schedule_if_unscheduled()


func _physics_process(delta: float) -> void:
	match phase:
		Phase.IDLE:
			if is_aurora_due() and is_sky_ready():
				begin_aurora()
		Phase.ACTIVE:
			active_elapsed += delta
			push_blend(get_aurora_blend())
			if active_elapsed >= get_total_seconds():
				finish_aurora()
		Phase.DONE:
			pass


# DELIBERATELY IGNORES debug_aurora_interval_override. Both callers WRITE a deadline to disk, and
# a playtest value must never land in a real save. The override is a read-side bypass instead --
# see is_aurora_due().
func get_interval_seconds() -> float:
	return AURORA_INTERVAL_SECONDS


# Fade in, hold, fade out. One ramp, and EVERY cosmetic piece of this feature reads it -- ribbon
# opacity, ribbon drift, anything a later phase adds.
#
# The director owns it rather than SkyBackdrop for the reason get_lake_blend()'s note gives: it
# is a fact about where the player is in the set piece, which is this file's job, and two
# consumers computing the same ramp is two chances to compute it differently. Phase 2 must add
# its ribbons as readers of this value, never as a second timer.
func get_aurora_blend() -> float:
	if phase != Phase.ACTIVE:
		return 0.0
	var total: float = get_total_seconds()
	var fade_in: float = clampf(active_elapsed / AURORA_FADE_SECONDS, 0.0, 1.0)
	var fade_out: float = clampf((total - active_elapsed) / AURORA_FADE_SECONDS, 0.0, 1.0)
	return fade_in * fade_out


func get_total_seconds() -> float:
	return AURORA_DURATION_SECONDS + (AURORA_FADE_SECONDS * 2.0)


# Total playtime including the part of this run that has not been banked yet.
#
# THE ARITHMETIC LIVES IN GameManager and this is a wrapper, identical in shape to
# FrozenLakeDirector's. It was computed here until the branches were reconciled, which made two
# copies of a sum whose wrong version -- the saved total alone, stale by the whole unbanked run
# -- silently reschedules a set piece. GameManager.get_total_playtime_seconds() carries the full
# reasoning, and get_unbanked_seconds() next to it carries why the unbanked part cannot be
# main_node.elapsed_time: bank_playtime() fires on every PLAYING -> not-PLAYING transition,
# which on Android is every notification and app switch, so adding the whole run double-counts
# the banked part. The lake shipped that way -- three pauses at 3/6/9 minutes credited +18
# phantom minutes.
#
# WHAT STAYS HERE IS THE MISSING-GameManager CASE, because an absent node cannot answer for
# itself. The fallback is the full elapsed time, which is right for the same reason the sum is:
# with nothing banking, none of the run is banked.
#
# Still free to call every physics frame -- asking GameManager reads two floats and banks nothing.
func get_total_playtime_seconds() -> float:
	var game_manager: GameManager = main_node.game_manager
	if game_manager != null:
		return game_manager.get_total_playtime_seconds()
	return services.save_store.total_playtime_seconds + main_node.elapsed_time


# Sets the deadline if the save has never carried one. THE ONLY WRITER of
# next_aurora_due_seconds besides finish_aurora(), and it runs at _ready() for a reason: at
# scene load nothing of this run is banked yet, so the saved total IS the cumulative total, and
# scheduling from it needs no unbanked term. It is also after the headless skip, so no gate ever
# writes a deadline into the developer's save.dat.
#
# Persisted immediately rather than left in memory. Without the write, every launch would
# re-derive a LATER deadline from a larger playtime and the aurora would recede forever.
func schedule_if_unscheduled() -> void:
	if services.save_store.next_aurora_due_seconds >= 0.0:
		return
	services.save_store.next_aurora_due_seconds = \
		services.save_store.total_playtime_seconds + get_interval_seconds()
	services.save_store.save_to_disk()


# A NEGATIVE DEADLINE IS NOT DUE. That is the unscheduled sentinel, and answering true on it
# would fire an aurora on the first frame of a save that has never been scheduled -- exactly the
# backlog this design removes. schedule_if_unscheduled() normally makes this unreachable; it
# stays because reset_progress() can set the sentinel mid-run, after _ready() has already gone.
func is_aurora_due() -> bool:
	# THE OVERRIDE BYPASSES THE STORED DEADLINE RATHER THAN REWRITING IT, for two reasons that
	# both arrived with the deadline. Rewriting would persist a playtest cadence into a real
	# save; and it would not even work, because a save scheduled hours of playtime ago is still
	# waiting on that number, so shortening the interval changes nothing. Measured from the start
	# of THIS run instead, so an aurora arrives <override> seconds into every run and nothing
	# reaches disk. One per run still applies -- the phase machine ends in DONE either way.
	if debug_aurora_interval_override > 0.0:
		return main_node.elapsed_time >= debug_aurora_interval_override
	var due_seconds: float = services.save_store.next_aurora_due_seconds
	if due_seconds < 0.0:
		return false
	return get_total_playtime_seconds() >= due_seconds


# Whether the sky is somewhere it is sane to start from. A rejected frame simply retries on the
# next one -- the threshold stays crossed, so the aurora begins at the first frame that
# qualifies rather than being lost. Same retry shape as the lake's try_arm().
#
# DELIBERATELY NOT CHECKING FOR A NEARBY CHASM, unlike the lake's floor and jump checks. Those
# exist because the lake commits GEOMETRY and locks input, so entering one mid-jump is a real
# state problem. Nothing here locks anything: an aurora that begins while the player is over a
# void just means they look up a second later, and the 8-second fade-in already covers far more
# than a chasm takes to clear. Adding a proximity check would mean new TerrainGenerator API for
# a problem that does not exist.
func is_sky_ready() -> bool:
	if debug_aurora_ignore_night:
		return true
	return biome_director.get_night_amount() >= NIGHT_THRESHOLD


func begin_aurora() -> void:
	phase = Phase.ACTIVE
	active_elapsed = 0.0
	aurora_started.emit()


func finish_aurora() -> void:
	phase = Phase.DONE
	# The ramp has already carried this to 0 by the final frame; the explicit hand-back is so
	# the sky cannot keep a sliver of aurora for the rest of the run if the end line happened to
	# be crossed in a frame the ramp had not quite finished. Same belt-and-braces as
	# finish_lake()'s set_lake_ice_blend(0.0).
	push_blend(0.0)
	services.save_store.aurora_count += 1
	# PUSHED FORWARD FROM get_total_playtime_seconds(), NEVER FROM THE BARE SAVED FIELD, and
	# this is the one line where that distinction bites hardest. total_playtime_seconds is the
	# BANKED total, and bank_playtime() only fires on a PLAYING -> not-PLAYING transition -- so
	# in a long uninterrupted session it is stale by the entire run. Scheduling from it after a
	# 40-minute unbroken run writes a deadline already 10 minutes in the PAST, and the next
	# aurora fires as soon as the sky is dark again. Test this path on a run with no pause in it;
	# that is the only case that exposes it.
	services.save_store.next_aurora_due_seconds = \
		get_total_playtime_seconds() + get_interval_seconds()
	services.save_store.save_to_disk()
	aurora_finished.emit(services.save_store.aurora_count)


# THE ONE SEAM THE LOOK ARRIVES THROUGH. SkyBackdrop.apply_aurora() is the only thing this
# feature draws with, so a Phase 2b that replaces the curtains with a shader replaces what is
# behind this call and nothing else.
#
# has_method rather than a typed call because sky_backdrop.gd carries no class_name -- the same
# reason BiomeDirector routes its two unchecked consumers through resolve_palette_consumer().
# Checked per call rather than cached in _ready(): this is only reached during an aurora, which
# is about a minute per hour of play.
#
# BOTH ARGUMENTS COME FROM HERE, and neither may be recomputed on the far side. `blend` is this
# director's single cosmetic ramp; `elapsed` is the clock the ramp cannot be, since it rises and
# falls. Keeping the clock here is what lets sky_backdrop.gd keep its promise of having no
# _process at all -- which is what makes it free inside the six headless gates, every one of
# which instantiates main.tscn. Handing it a timer to advance would spend that.
func push_blend(blend: float) -> void:
	if sky_backdrop == null or not sky_backdrop.has_method("apply_aurora"):
		return
	sky_backdrop.call("apply_aurora", blend, active_elapsed)


# If the stall watchdog or anything else ends the run mid-aurora, the sky must not keep it.
# Nothing here locks input, so unlike the lake's version there is no lock to release -- but the
# scene reload a restart does would only clear this on restart, and the death screen does not
# reload until the player chooses to.
func _on_player_died() -> void:
	if phase == Phase.ACTIVE:
		push_blend(0.0)
	phase = Phase.DONE
