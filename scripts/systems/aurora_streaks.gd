extends Node2D

class_name AuroraStreaks

# OCCASIONAL LIGHT STREAKS. One ribbon of light at a time sweeps across the view, fast, at a
# different height and angle each time, then is gone. Most of the time nothing is on screen at
# all -- that is the point. Owner request, 2026-09-13, against a screensaver-style reference:
# "how like light flashes across the screen for a second ... one at a time here and there".
#
# WHY THIS IS NOT THE WISPS AGAIN. The wisps (removed 2026-09-16) failed because they were
# PERSISTENT decoration: six ribbons hanging at mid-screen for the whole encounter, belonging to
# nothing. A streak is an EVENT -- it appears, crosses, and leaves. Nothing lingers to be
# scrutinised, and an occasional flash of motion reads as energy rather than as scribble. If
# this turns out to be wrong too, STREAKS_ENABLED is the single switch.
#
# IT REFLECTS FOR FREE. AuroraReflection reads the screen texture, and this node draws before
# it in tree order, so every streak is mirrored in the ice with no work here -- which is what
# the owner's reference image shows.
#
# ENTIRELY DERIVED FROM THE EVENT CLOCK, NO STATE, NO TIMERS. Which streak is running is
# floor(elapsed / INTERVAL) and how far along it is the remainder, so this node holds nothing
# that could drift, needs no reset on death, and is pause-frozen for free because the director's
# clock is. Every per-streak parameter comes from hashing that index, so a streak is the same
# streak whenever it plays.
#
# The RNG is a FIXED hash, never session_seed: background visuals must not read it (visuals.md),
# and a set piece should look the same every time it appears.

const STREAKS_ENABLED: bool = true
# One streak roughly this often, so about eight across a 61s encounter.
const STREAK_INTERVAL: float = 7.0
# How long one crossing lasts. Much shorter than the interval, so the usual state is an empty
# sky and the streak is a punctuation mark.
const STREAK_DURATION: float = 1.15
# Nothing before this: the sky should arrive first and be established before it gets weather.
const STREAK_FIRST_AT: float = 6.0

const POINT_COUNT: int = 15
# Fractions of the visible view.
const LENGTH_MIN: float = 0.55
const LENGTH_MAX: float = 1.05
# How far above the ice line a streak can sit, as a fraction of view height above centre.
const HEIGHT_MIN: float = 0.06
const HEIGHT_MAX: float = 0.46
const ANGLE_MAX_DEGREES: float = 24.0
# Bow across the ribbon's own length, as a fraction of that length.
const ARC_RATIO: float = 0.055
const WIDTH_MIN: float = 3.0
const WIDTH_MAX: float = 7.5
# How far off each side a streak starts and ends, as a fraction of view width. Above 0.5 so a
# ribbon is fully clear of the frame at both ends of its run.
const TRAVEL_OVERSHOOT: float = 0.95
const PEAK_ALPHA: float = 0.85
# Above 1 sharpens the flash: it spends less of its life near full brightness and more ramping.
const ALPHA_SHARPNESS: float = 1.35

# Drawn from the reference's magenta/violet/cyan rather than from the curtains' green, so a
# streak reads as a separate event and not as a piece of curtain that came loose.
const STREAK_COLORS: Array[Color] = [
	Color(0.55, 0.85, 1.00),
	Color(0.80, 0.45, 1.00),
	Color(1.00, 0.45, 0.90),
	Color(0.45, 1.00, 0.92),
]

const HASH_MIX_A: int = 374761393
const HASH_MIX_B: int = 668265263
const HASH_MASK: int = 0x7fffffff
const HASH_RESOLUTION: int = 100000

@export var camera_path: NodePath = NodePath("../Camera2D")

var camera: Camera2D
var streak: Line2D
var disabled: bool = false


func _ready() -> void:
	visible = false
	if not STREAKS_ENABLED or DisplayServer.get_name() == "headless":
		disabled = true
		return

	camera = get_node_or_null(camera_path) as Camera2D
	if camera == null:
		disabled = true
		push_warning("AuroraStreaks disabled: missing camera.")
		return

	# ONE Line2D, reused. Only one streak is ever visible, so a pool would be three idle nodes
	# and a lookup; the geometry is rewritten per streak anyway.
	var additive: CanvasItemMaterial = CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	streak = Line2D.new()
	streak.name = "Streak"
	streak.joint_mode = Line2D.LINE_JOINT_ROUND
	streak.begin_cap_mode = Line2D.LINE_CAP_ROUND
	streak.end_cap_mode = Line2D.LINE_CAP_ROUND
	streak.antialiased = true
	streak.material = additive
	add_child(streak)


func apply_aurora(blend: float, elapsed: float) -> void:
	if disabled:
		return
	var event_strength: float = clampf(blend, 0.0, 1.0)
	if event_strength <= 0.0 or elapsed < STREAK_FIRST_AT:
		visible = false
		return

	var since_first: float = elapsed - STREAK_FIRST_AT
	var index: int = int(floor(since_first / STREAK_INTERVAL))
	var progress: float = fposmod(since_first, STREAK_INTERVAL) / STREAK_DURATION
	if progress > 1.0:
		# The quiet stretch between streaks, which is most of the time.
		visible = false
		return

	# Follow the camera, so a streak is placed against the VIEW rather than against the world:
	# it is light crossing the frame, not an object the player skates past.
	global_position = camera.global_position
	var view: Vector2 = get_viewport_rect().size / camera.zoom

	var length: float = view.x * lerpf(LENGTH_MIN, LENGTH_MAX, hash_unit(index, 1))
	var arc: float = length * ARC_RATIO
	streak.points = build_streak_points(length, arc)
	streak.width = lerpf(WIDTH_MIN, WIDTH_MAX, hash_unit(index, 2))
	streak.gradient = build_taper_gradient(
		STREAK_COLORS[int(hash_unit(index, 3) * float(STREAK_COLORS.size())) % STREAK_COLORS.size()])

	# STRICT ALTERNATION, NOT A HASH. The hash is well distributed over many indices (111/200
	# below 0.5) but an encounter only ever plays the FIRST EIGHT, and there it happened to give
	# seven leftward streaks and one rightward -- in every single aurora, since the indices are
	# fixed. Small-sample bias a distribution test calls clean. Alternating guarantees the
	# balance that the randomness was only ever meant to approximate, and it reads better
	# anyway: one from the left, then one from the right.
	var rightward: bool = index % 2 == 0
	var span: float = view.x * TRAVEL_OVERSHOOT
	var from_x: float = -span if rightward else span
	var centre_x: float = lerpf(from_x, -from_x, progress)
	# Measured up from the view centre, which sits near the ice line during the encounter.
	var height: float = lerpf(HEIGHT_MIN, HEIGHT_MAX, hash_unit(index, 5))
	streak.position = Vector2(centre_x, -view.y * height)
	streak.rotation = deg_to_rad(
		lerpf(-ANGLE_MAX_DEGREES, ANGLE_MAX_DEGREES, hash_unit(index, 6)))

	# In and out within the crossing, so a streak never pops at either edge of the frame.
	var flash: float = pow(sin(PI * progress), ALPHA_SHARPNESS)
	streak.modulate = Color(1.0, 1.0, 1.0, event_strength * PEAK_ALPHA * flash)
	visible = true


# A long, shallow bow. Flat enough to read as a streak of light rather than as a drawn arc --
# ARC_RATIO is deliberately an order of magnitude below the removed wisps' curvature, which is
# part of why those read as squiggles.
func build_streak_points(length: float, arc: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	points.resize(POINT_COUNT)
	for point_index: int in range(POINT_COUNT):
		var u: float = float(point_index) / float(POINT_COUNT - 1)
		points[point_index] = Vector2((u - 0.5) * length, -sin(PI * u) * arc)
	return points


# Bright core fading to nothing at both tips, so the ribbon has no visible ends.
func build_taper_gradient(color: Color) -> Gradient:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.18, 0.5, 0.82, 1.0])
	gradient.colors = PackedColorArray([
		Color(color.r, color.g, color.b, 0.0),
		Color(color.r, color.g, color.b, 0.45),
		Color(color.r, color.g, color.b, 1.0),
		Color(color.r, color.g, color.b, 0.45),
		Color(color.r, color.g, color.b, 0.0),
	])
	return gradient


# Deterministic per (streak index, field). Same construction as background_generator.gd's
# get_hash_unit_float(), which is the project's existing idiom for "varied but fixed".
func hash_unit(index: int, field: int) -> float:
	var mixed: int = ((index * HASH_MIX_A) ^ (field * HASH_MIX_B)) & HASH_MASK
	mixed = (mixed ^ (mixed >> 13)) * HASH_MIX_A & HASH_MASK
	return float(mixed % HASH_RESOLUTION) / float(HASH_RESOLUTION)
