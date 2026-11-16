extends Control

class_name MeltView

signal pause_requested
signal round_finished
signal reward_requested
signal return_finished

var round: MeltRound = MeltRound.new()
var running: bool = false
var finish_announced: bool = false
var camera_y: float = 0.0
var age: float = 0.0
var best_seconds: float = 0.0
var return_seconds: float = -1.0
var skater_frames: SpriteFrames
var skater_rig_data: Dictionary = {}
var skater_stride: float = 0.0
var title: Label
var subtitle: Label
var score: Label
var instruction: Label
var result: Label
var pause_button: Button
var continue_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = load("res://assets/ui/aura_theme.tres")
	title = make_label(30)
	title.text = "The Melt"
	subtitle = make_label(13)
	subtitle.text = "An ice rift · Your run is waiting"
	score = make_label(16)
	instruction = make_label(15)
	result = make_label(18)
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pause_button = Button.new()
	pause_button.text = "Pause"
	pause_button.pressed.connect(func(): pause_requested.emit())
	add_child(pause_button)
	continue_button = Button.new()
	continue_button.text = "Back to your run"
	continue_button.theme_type_variation = &"PrimaryButton"
	continue_button.pressed.connect(func(): reward_requested.emit())
	add_child(continue_button)
	resized.connect(layout_ui)
	layout_ui()


func make_label(font_size: int) -> Label:
	var label: Label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	add_child(label)
	return label


func layout_ui() -> void:
	title.position = Vector2(28.0, 22.0)
	subtitle.position = Vector2(29.0, 62.0)
	score.position = Vector2(size.x - 275.0, 30.0)
	pause_button.position = Vector2(size.x - 94.0, 25.0)
	pause_button.size = Vector2(70.0, 36.0)
	instruction.position = Vector2(28.0, size.y - 50.0)
	result.position = Vector2(size.x * 0.5 - 220.0, size.y * 0.40)
	result.size = Vector2(440.0, 120.0)
	continue_button.position = Vector2(size.x * 0.5 - 115.0, size.y * 0.63)
	continue_button.size = Vector2(230.0, 44.0)


func begin(frames: SpriteFrames, previous_best: float = 0.0) -> void:
	round = MeltRound.new()
	round.ensure_course()
	skater_frames = frames
	skater_rig_data = SkaterRig.create_draw_data(frames)
	skater_stride = 0.0
	finish_announced = false
	return_seconds = -1.0
	camera_y = 0.0
	age = 0.0
	best_seconds = previous_best
	result.text = "Tap to begin\nJump between ice ledges. Outlast the rising melt."
	continue_button.visible = false
	instruction.text = "Tap / Space to jump · 15s: Rare chest · 30s: Aurora chest"
	score.text = "0.0s\nBest %.1fs" % best_seconds
	queue_redraw()


func show_reward(text: String, saved: bool) -> void:
	result.text = text
	continue_button.text = "Back to your run" if saved else "Retry saving reward"
	continue_button.visible = true


func start_return() -> void:
	return_seconds = 2.0
	continue_button.visible = false


func _physics_process(delta: float) -> void:
	if not visible or not running:
		return
	if round.started and not round.finished and return_seconds < 0.0:
		age += delta
		var target_stride: float = 1.0 if round.grounded_index >= 0 else 0.0
		skater_stride = lerpf(skater_stride, target_stride, 1.0 - exp(-7.0 * delta))
	if return_seconds >= 0.0:
		return_seconds -= delta
		result.text = "Back to your run\n%d…" % maxi(1, ceili(return_seconds))
		if return_seconds <= 0.0:
			return_seconds = -1.0
			running = false
			return_finished.emit()
	else:
		round.advance(delta)
		update_camera(delta)
		score.text = "%.1fs · +%d coins\nBest %.1fs" % [round.elapsed, round.bonus_coins(), best_seconds]
		if round.finished and not finish_announced:
			finish_announced = true
			round_finished.emit()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible or not running:
		return
	var pointer: Vector2 = Vector2(-10000.0, -10000.0)
	var press: bool = event.is_action_pressed(&"ui_accept") and not event.is_echo()
	if event is InputEventScreenTouch:
		press = event.pressed
		pointer = event.position
	elif event is InputEventMouseButton:
		press = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
		pointer = event.position
	# Consume Pause before showing its menu: releasing this press must not hit Home.
	if event.is_action_pressed(&"ui_cancel") or (press and pause_button.get_global_rect().has_point(pointer)):
		get_viewport().set_input_as_handled()
		pause_requested.emit()
		return
	if not press or round.finished or return_seconds >= 0.0:
		return
	get_viewport().set_input_as_handled()
	if not round.started:
		round.start()
		result.text = ""
	else:
		round.request_jump()


func world_point(point: Vector2) -> Vector2:
	return Vector2((point.x - round.x) * 0.95 + size.x * 0.30,
		(point.y - camera_y) * 0.95 + size.y * 0.50)


func update_camera(delta: float) -> void:
	# Follow the ascending course, so individual jumps do not push the melt off
	# the bottom of the screen. The approaching surface stays visible throughout.
	var course_y: float = 0.0
	for platform: Dictionary in round.platforms:
		if float(platform["x"]) <= round.x:
			course_y = float(platform["y"])
	var weight: float = 1.0 - exp(-5.0 * delta)
	camera_y = lerpf(camera_y, minf(course_y, 0.0), weight)


func _draw() -> void:
	# Native drawing keeps the rift light: no full-screen shader or particle system.
	for band: int in range(24):
		var t: float = float(band) / 23.0
		draw_rect(Rect2(0.0, size.y * band / 24.0, size.x, size.y / 24.0 + 1.0),
			Color(0.055, 0.085, 0.16).lerp(Color(0.22, 0.25, 0.36), t))
	for ribbon: int in range(3):
		var points: PackedVector2Array = []
		for i: int in range(40):
			var x: float = size.x * i / 39.0
			points.append(Vector2(x, size.y * 0.23 + sin(x * 0.004 + age * 0.12 + ribbon * 0.6) * 35.0 + ribbon * 12.0))
		draw_polyline(points, Color(0.4 + ribbon * 0.1, 0.8, 0.85, 0.045), 18.0, true)
	for ridge: int in range(2):
		var silhouette: PackedVector2Array = [Vector2(0.0, size.y)]
		for i: int in range(16):
			var x: float = size.x * i / 15.0
			silhouette.append(Vector2(x, size.y * (0.45 + ridge * 0.11) - absf(sin(i * 2.7 + ridge)) * 100.0))
		silhouette.append(Vector2(size.x, size.y))
		draw_colored_polygon(silhouette, Color(0.15 + ridge * 0.015, 0.21, 0.31, 0.75))
	for platform: Dictionary in round.platforms:
		var at: Vector2 = world_point(Vector2(float(platform["x"]), float(platform["y"])))
		var width: float = float(platform["width"]) * 0.95
		var wear: float = clampf(float(platform["stood"]) / MeltRound.crumble_limit(int(platform["index"])), 0.0, 1.0)
		if wear >= 1.0:
			continue
		var polygon: PackedVector2Array = [at, at + Vector2(width, 0.0), at + Vector2(width - 14.0, 18.0),
			at + Vector2(width * 0.6, 27.0), at + Vector2(12.0, 17.0)]
		draw_colored_polygon(polygon, Color(0.3, 0.48, 0.62).lerp(Color(0.57, 0.38, 0.49), wear))
		draw_line(at, at + Vector2(width, 0.0), Color(0.78, 0.94, 1.0), 2.0, true)
		if wear > 0.2:
			draw_polyline(PackedVector2Array([at + Vector2(width * 0.35, 0.0), at + Vector2(width * 0.43, 9.0), at + Vector2(width * 0.4, 20.0)]), Color(0.08, 0.18, 0.26, wear), 1.5, true)
	var foot: Vector2 = world_point(Vector2(round.x, round.feet_y))
	SkaterRig.draw_into(self, skater_rig_data, age, skater_stride, foot - Vector2(0.0,24.0), 0.30)
	var lava_top: float = world_point(Vector2(round.x, round.lava_y)).y
	var melt: PackedVector2Array = []
	for i: int in range(41):
		var x: float = size.x * i / 40.0
		melt.append(Vector2(x, lava_top + sin(x * 0.015 + age * 1.1) * 3.0))
	var surface: PackedVector2Array = melt.duplicate()
	melt.append(Vector2(size.x, maxf(size.y, lava_top + 200.0)))
	melt.append(Vector2(0.0, maxf(size.y, lava_top + 200.0)))
	draw_colored_polygon(melt, Color(0.24, 0.16, 0.25, 0.96))
	draw_polyline(surface, Color(0.75, 0.48, 0.48, 0.10), 22.0, true)
	draw_polyline(surface, Color(0.9, 0.63, 0.57, 0.8), 2.0, true)
	if not round.started or round.finished:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.045, 0.08, 0.55))
