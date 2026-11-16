extends Node2D

class_name SkaterRig

# A continuous visual rig over the existing rest-pose artwork. Two short skinned
# leg strips and rigid boots move on smooth paths; the PNG never switches poses.
# The AnimatedSprite2D parent remains the carrier for tilt, tricks, tint and squash.
const CYCLE_SECONDS: float = 7.2
# Preview-only alternatives use the same rig; gameplay defaults to the phrased stroke.
# A cycle contains two alternating strokes, not one stroke per foot together.
const DEFAULT_STROKE: int = 4
const STROKES: Array[Dictionary] = [
	{"label": "Previous", "cycle": 2.8, "forward": 9.0, "back": -16.0, "drop": 4.0, "bob": 0.65, "lift": 10.0, "lean": 0.0, "shift": 0.0, "rock": 0.012},
	{"label": "A - Strong", "cycle": 3.6, "forward": 16.0, "back": -26.0, "drop": 8.0, "bob": 1.4, "lift": 14.0, "lean": 0.025, "shift": 1.8, "rock": 0.022},
	{"label": "B - Long push", "cycle": 4.2, "forward": 18.0, "back": -29.0, "drop": 11.0, "bob": 1.8, "lift": 17.0, "lean": 0.04, "shift": 2.6, "rock": 0.03},
	{"label": "C - Deep push", "cycle": 4.8, "forward": 21.0, "back": -32.0, "drop": 15.0, "bob": 2.2, "lift": 20.0, "lean": 0.055, "shift": 3.3, "rock": 0.038},
	{"label": "Sustained stroke", "cycle": CYCLE_SECONDS, "forward": 12.0, "back": -32.0, "drop": 15.0, "bob": 0.65, "lift": 15.0, "lean": 0.04, "shift": 2.6, "rock": 0.03, "phrased": true},
]
const DRIVE_END: float = 0.62
const RETURN_END: float = 0.94
const SOURCE_CENTER: Vector2 = Vector2(75.0, 90.0)
const GROUND_Y: float = 170.0
const PROFILES: Dictionary = {
	"kid": {"near": [Vector2(80,112), Vector2(78,134), Vector2(68,155)], "rear": [Vector2(66,111), Vector2(57,134), Vector2(43,154)], "seam": 117.0},
	"teen": {"near": [Vector2(78,111), Vector2(77,134), Vector2(68,155)], "rear": [Vector2(67,111), Vector2(57,134), Vector2(44,155)], "seam": 117.0},
	"twenties": {"near": [Vector2(77,111), Vector2(73,134), Vector2(64,155)], "rear": [Vector2(66,111), Vector2(54,133), Vector2(40,155)], "seam": 116.0},
	"mom": {"near": [Vector2(70,111), Vector2(67,135), Vector2(58,155)], "rear": [Vector2(58,110), Vector2(48,135), Vector2(36,155)], "seam": 116.0},
	"dad": {"near": [Vector2(72,112), Vector2(70,135), Vector2(60,155)], "rear": [Vector2(59,111), Vector2(47,135), Vector2(33,155)], "seam": 117.0},
}

var carrier: AnimatedSprite2D
var body: Node
var data: Dictionary = {}
var carrier_alpha: float = 1.0
var elapsed: float = 0.0
var stride_amount: float = 0.0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	carrier = get_parent() as AnimatedSprite2D
	if carrier == null:
		set_process(false)
		return
	body = carrier.get_parent()
	use_parent_material = true
	carrier_alpha = carrier.self_modulate.a
	carrier.sprite_frames_changed.connect(configure)
	configure()


func configure() -> void:
	data = create_draw_data(carrier.sprite_frames)
	carrier.self_modulate.a = carrier_alpha if data.is_empty() else 0.0
	if not data.is_empty():
		carrier.stop()
	queue_redraw()


func _process(delta: float) -> void:
	if data.is_empty():
		return
	if carrier.is_playing():
		carrier.stop()
	var target: float = 0.0
	if body != null and body.has_method("is_on_floor") and body.call("is_on_floor"):
		var coasting: bool = body.get("is_jump_suppressed") or body.get("is_glide_active") \
			or body.get("is_aurora_flight_active") or body.get("is_aurora_flight_landing") or body.get("is_boosting")
		if not coasting and not body.get("is_dead"):
			target = 1.0
	elapsed += delta
	stride_amount = lerpf(stride_amount, target, 1.0 - exp(-7.0 * delta))
	queue_redraw()


func _draw() -> void:
	draw_into(self, data, elapsed, stride_amount)


static func create_draw_data(frames: SpriteFrames, stroke: int = DEFAULT_STROKE) -> Dictionary:
	if frames == null or not frames.has_animation(&"skate") or frames.get_frame_count(&"skate") == 0:
		return {}
	var skin: String = frames.resource_path.get_base_dir().get_file()
	if not PROFILES.has(skin):
		skin = "kid"
	var profile: Dictionary = PROFILES[skin]
	var texture: Texture2D = frames.get_frame_texture(&"skate", 0)
	var near: Array = profile["near"]
	var rear: Array = profile["rear"]
	var split: float = (near[2].x + rear[2].x) * 0.5
	var seam: float = profile["seam"]
	var body_source: PackedVector2Array = []
	var body_points: PackedVector2Array = []
	var body_uv: PackedVector2Array = []
	for y: float in [0.0, 90.0, 100.0, 108.0, seam]:
		for x: float in [0.0, 50.0, 58.0, 66.0, 74.0, 82.0, 90.0, 150.0]:
			var point: Vector2 = Vector2(x,y)
			body_source.append(point)
			body_points.append(point - SOURCE_CENTER)
			body_uv.append(point / texture.get_size())
	var body_indices: PackedInt32Array = []
	for row: int in range(4):
		for col: int in range(7):
			var a: int = row * 8 + col
			body_indices.append_array(PackedInt32Array([a,a+1,a+8,a+1,a+9,a+8]))
	return {"skin": skin, "stroke": STROKES[clampi(stroke, 0, STROKES.size() - 1)], "texture": texture, "size": texture.get_size(), "seam": seam, "body_points": body_points, "body_uv": body_uv,
		"body_source": body_source, "body_indices": body_indices,
		"hip": (near[0] + rear[0]) * 0.5,
		"near": build_leg(near, true, split, texture.get_size()),
		"rear": build_leg(rear, false, split, texture.get_size())}


static func build_leg(joints: Array, near: bool, split: float, size: Vector2) -> Dictionary:
	var hip: Vector2 = joints[0]
	var knee: Vector2 = joints[1]
	var ankle: Vector2 = joints[2]
	var centers: Array[Vector2] = [hip + Vector2(0,-3), hip.lerp(knee, 0.5), knee, knee.lerp(ankle, 0.55), ankle + Vector2(0,2)]
	var widths: Array[float] = [9.0, 8.5 if near else 10.0, 7.5, 6.5, 6.0]
	var source: PackedVector2Array = []
	var uv: PackedVector2Array = []
	for index: int in range(centers.size()):
		for side: float in [-1.0, 1.0]:
			var point: Vector2 = centers[index] + Vector2(widths[index] * side, 0.0)
			source.append(point)
			uv.append(point / size)
	# Clip the source ice line out of both boots. Full-frame UVs preserve outfit masks.
	var foot: PackedVector2Array
	if near:
		foot = PackedVector2Array([Vector2(ankle.x-7,ankle.y-6), Vector2(ankle.x+8,ankle.y-6),
			Vector2(ankle.x+20,ankle.y+3), Vector2(ankle.x+21,168), Vector2(split+1,168), Vector2(split+1,ankle.y+1)])
	else:
		foot = PackedVector2Array([Vector2(ankle.x-8,ankle.y-8), Vector2(ankle.x+6,ankle.y-4),
			Vector2(split,ankle.y+8), Vector2(split,168), Vector2(ankle.x-18,ankle.y+7), Vector2(ankle.x-12,ankle.y-1)])
	var foot_uv: PackedVector2Array = []
	for point: Vector2 in foot:
		foot_uv.append(point / size)
	var indices: PackedInt32Array = []
	for row: int in range(4):
		var a: int = row * 2
		indices.append_array(PackedInt32Array([a,a+1,a+2,a+1,a+3,a+2]))
	for index: int in Geometry2D.triangulate_polygon(foot):
		indices.append(source.size() + index)
	return {"hip": hip, "knee": knee, "ankle": ankle, "source": source, "uv": uv,
		"vertices": source.duplicate(), "foot": foot, "foot_uv": foot_uv, "foot_vertices": foot.duplicate(),
		"upper": hip.distance_to(knee), "lower": knee.distance_to(ankle), "indices": indices,
		"draw_vertices": source + foot, "draw_uv": uv + foot_uv}


static func smooth_phase(value: float) -> float:
	var t: float = clampf(value, 0.0, 1.0)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


static func leg_pose(data: Dictionary, near: bool, seconds: float, amount: float) -> Dictionary:
	var leg: Dictionary = data["near" if near else "rear"]
	var stroke: Dictionary = data["stroke"]
	var phase: float = fposmod(seconds / stroke["cycle"] + (0.0 if near else 0.5), 1.0)
	var recovery: float = 0.0
	var sweep: float
	if stroke.get("phrased", false):
		# One leg completes its whole phrase before the other starts. The supporting
		# blade stays planted, rather than both feet constantly cycling in opposition.
		var phrase: float = phase * 2.0
		if phrase < DRIVE_END:
			sweep = lerpf(stroke["forward"], stroke["back"], smooth_phase(phrase / DRIVE_END))
		elif phrase < RETURN_END:
			var progress: float = smooth_phase((phrase - DRIVE_END) / (RETURN_END - DRIVE_END))
			sweep = lerpf(stroke["back"], stroke["forward"], progress)
			recovery = sin(progress * PI)
		else:
			# Brief settle, then support the other foot's long drive and return.
			sweep = stroke["forward"]
	elif phase < 0.65:
		sweep = lerpf(stroke["forward"], stroke["back"], smooth_phase(phase / 0.65))
	else:
		var progress: float = smooth_phase((phase - 0.65) / 0.35)
		sweep = lerpf(stroke["back"], stroke["forward"], progress)
		recovery = sin(progress * PI)
	var hip: Vector2 = leg["hip"] + body_offset(stroke, seconds, amount)
	# The rear blade is tilted in the source rest pose. Level it during its long
	# contact glide; ankle height compensates for its rotated sole.
	var sole_height: float = 13.0 if near else 9.4
	var ankle: Vector2 = Vector2(hip.x + lerpf(-8.0, sweep, amount), GROUND_Y - sole_height - stroke["lift"] * recovery * amount)
	var direction: Vector2 = ankle - hip
	var distance: float = clampf(direction.length(), absf(leg["upper"] - leg["lower"]) + 0.01, leg["upper"] + leg["lower"] - 0.1)
	var unit: Vector2 = direction.normalized()
	ankle = hip + unit * distance
	var along: float = (leg["upper"] * leg["upper"] - leg["lower"] * leg["lower"] + distance * distance) / (2.0 * distance)
	var height: float = sqrt(maxf(leg["upper"] * leg["upper"] - along * along, 0.0))
	# Knees bend forward in the skating direction; the sign never flips at extension.
	var knee: Vector2 = hip + unit * along + Vector2(unit.y, -unit.x) * height
	return {"hip": hip, "knee": knee, "ankle": ankle, "pitch": (0.0 if near else -0.31) - 0.14 * recovery * amount}


static func body_offset(stroke: Dictionary, seconds: float, amount: float) -> Vector2:
	var wave: float = seconds / stroke["cycle"] * TAU
	return Vector2(stroke["shift"] * sin(wave) * amount,
		4.0 + (stroke["drop"] - 4.0 + stroke["bob"] * sin(wave * 2.0)) * amount)


static func skin_leg(data: Dictionary, near: bool, pose: Dictionary) -> void:
	var leg: Dictionary = data["near" if near else "rear"]
	var upper_angle: float = (pose["knee"] - pose["hip"]).angle() - (leg["knee"] - leg["hip"]).angle()
	var lower_angle: float = (pose["ankle"] - pose["knee"]).angle() - (leg["ankle"] - leg["knee"]).angle()
	var upper_xf: Transform2D = Transform2D(upper_angle, pose["hip"] - (leg["hip"] as Vector2).rotated(upper_angle))
	var lower_xf: Transform2D = Transform2D(lower_angle, pose["knee"] - (leg["knee"] as Vector2).rotated(lower_angle))
	var boot_xf: Transform2D = Transform2D(pose["pitch"], pose["ankle"] - (leg["ankle"] as Vector2).rotated(pose["pitch"]))
	leg["upper_xf"] = upper_xf
	var vertices: PackedVector2Array = leg["vertices"]
	var source: PackedVector2Array = leg["source"]
	for index: int in range(source.size()):
		var point: Vector2 = source[index]
		var upper: Vector2 = upper_xf * point
		var lower: Vector2 = lower_xf * point
		var boot: Vector2 = boot_xf * point
		var blend: float = smoothstep(leg["knee"].y - 7.0, leg["knee"].y + 7.0, point.y)
		var ankle_blend: float = smoothstep(leg["ankle"].y - 5.0, leg["ankle"].y + 2.0, point.y)
		vertices[index] = upper.lerp(lower, blend).lerp(boot, ankle_blend) - SOURCE_CENTER
	leg["vertices"] = vertices
	var foot_vertices: PackedVector2Array = leg["foot_vertices"]
	var foot: PackedVector2Array = leg["foot"]
	for index: int in range(foot.size()):
		foot_vertices[index] = boot_xf * foot[index] - SOURCE_CENTER
	leg["foot_vertices"] = foot_vertices
	var draw_vertices: PackedVector2Array = leg["draw_vertices"]
	for index: int in range(vertices.size()):
		draw_vertices[index] = vertices[index]
	for index: int in range(foot_vertices.size()):
		draw_vertices[vertices.size()+index] = foot_vertices[index]
	leg["draw_vertices"] = draw_vertices


static func draw_into(canvas: CanvasItem, data: Dictionary, seconds: float, amount: float,
		origin: Vector2 = Vector2.ZERO, draw_scale: float = 1.0) -> void:
	if data.is_empty():
		return
	canvas.draw_set_transform(origin, 0.0, Vector2.ONE * draw_scale)
	var texture: Texture2D = data["texture"]
	for near: bool in [false, true]:
		var pose: Dictionary = leg_pose(data, near, seconds, amount)
		skin_leg(data, near, pose)
		var leg: Dictionary = data["near" if near else "rear"]
		RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), leg["indices"], leg["draw_vertices"],
			PackedColorArray([Color.WHITE]), leg["draw_uv"], PackedInt32Array(), PackedFloat32Array(), texture.get_rid())
	# The unchanged upper-body art covers the hip joins. Small continuous lean/bob
	# follows the weight shift, inherited beneath the carrier's existing slope tilt.
	var stroke: Dictionary = data["stroke"]
	var wave: float = seconds / stroke["cycle"] * TAU
	var offset: Vector2 = body_offset(stroke, seconds, amount)
	var pivot: Vector2 = data["hip"] - SOURCE_CENTER
	var angle: float = (stroke["lean"] + stroke["rock"] * sin(wave)) * amount
	var rigid_xf: Transform2D = Transform2D(angle, pivot + offset - pivot.rotated(angle))
	var body_points: PackedVector2Array = data["body_points"]
	var source: PackedVector2Array = data["body_source"]
	var hip_x: float = data["hip"].x
	for index: int in range(source.size()):
		var point: Vector2 = source[index]
		var rigid: Vector2 = rigid_xf * (point - SOURCE_CENTER)
		var blend: float = smoothstep(100.0, data["seam"], point.y) \
			* smoothstep(48.0, 58.0, point.x) * (1.0 - smoothstep(84.0, 94.0, point.x))
		var rear_point: Vector2 = data["rear"]["upper_xf"] * point
		var near_point: Vector2 = data["near"]["upper_xf"] * point
		var lower: Vector2 = rear_point.lerp(near_point, smoothstep(hip_x - 4.0, hip_x + 4.0, point.x)) - SOURCE_CENTER
		body_points[index] = rigid.lerp(lower, blend)
	data["body_points"] = body_points
	RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), data["body_indices"], body_points,
		PackedColorArray([Color.WHITE]), data["body_uv"], PackedInt32Array(), PackedFloat32Array(), texture.get_rid())
	canvas.draw_set_transform(Vector2.ZERO)
