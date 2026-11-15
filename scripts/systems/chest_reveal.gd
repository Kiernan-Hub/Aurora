extends VBoxContainer

class_name ChestReveal

# The chests a run collected, opened one after another on the death screen. Each one appears
# closed, rattles harder and harder, then bursts: a white flash, the lid thrown back, light rays,
# a spray of gold, and its reward counting up on a row beneath. COSMETIC ONLY -- the rewards are
# already in the save before this plays (GameManager._on_player_died), so quitting mid-reveal
# loses nothing, and the death screen's buttons work throughout.
#
# Built in code and added to the death screen's column by GameManager, like the shop's cards. It
# runs on a paused tree (the death screen's), hence PROCESS_MODE_ALWAYS. Everything is drawn by
# ChestStage below from a handful of tweened numbers: no textures, no scene.

# More chests than this share the last opening, so the column cannot push the buttons off screen.
const MAX_ROWS: int = 4
const START_DELAY: float = 0.7
const APPEAR_SECONDS: float = 0.18
const RATTLE_SECONDS: float = 0.55
const LID_SECONDS: float = 0.2
const FLASH_SECONDS: float = 0.4
const COUNT_SECONDS: float = 0.45
const HOLD_SECONDS: float = 0.45
# A jackpot or a skater: a bigger flash, more gold, a longer look.
const BIG_HOLD_SECONDS: float = 0.9
const POP_SECONDS: float = 0.25
const POP_SCALE: float = 1.7
const FONT_SIZE: int = 16
const COIN_COLOR: Color = Color(1.0, 0.86, 0.45)
const JACKPOT_COLOR: Color = Color(1.0, 0.72, 0.2)
const SKIN_COLOR: Color = Color(0.6, 1.0, 0.8)

var reveal_tween: Tween
var stage: ChestStage


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	alignment = BoxContainer.ALIGNMENT_CENTER
	visible = false


# on_open is called as each chest opens with whether it was a big one (jackpot or skater), for
# the sound.
func play(rewards: Array[Dictionary], on_open: Callable) -> void:
	if reveal_tween != null:
		reveal_tween.kill()
	for child: Node in get_children():
		child.queue_free()
	visible = not rewards.is_empty()
	if rewards.is_empty():
		return

	stage = ChestStage.new()
	add_child(stage)
	reveal_tween = create_tween()
	reveal_tween.tween_interval(START_DELAY)
	for row_index: int in range(mini(rewards.size(), MAX_ROWS)):
		var is_overflow_row: bool = row_index == MAX_ROWS - 1 and rewards.size() > MAX_ROWS
		var shown: Array[Dictionary] = []
		shown.assign(rewards.slice(row_index) if is_overflow_row else [rewards[row_index]])
		var is_big: bool = is_big_reward(shown)
		var row: Label = Label.new()
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_theme_font_size_override("font_size", FONT_SIZE)
		row.modulate = get_reward_color(shown)
		row.visible = false
		add_child(row)

		# Closed, then the rattle building to the burst.
		reveal_tween.tween_callback(stage.begin_chest)
		reveal_tween.tween_property(stage, "appear", 1.0, APPEAR_SECONDS).from(0.0) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		reveal_tween.tween_property(stage, "rattle", 1.0, RATTLE_SECONDS).from(0.0).set_ease(Tween.EASE_IN)
		# The burst, all at once.
		reveal_tween.tween_callback(open_row.bind(row, shown, is_big, on_open))
		reveal_tween.tween_property(stage, "lid_open", 1.0, LID_SECONDS).from(0.0) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		reveal_tween.parallel().tween_property(stage, "flash", 0.0, FLASH_SECONDS).from(1.0).set_ease(Tween.EASE_OUT)
		reveal_tween.parallel().tween_property(row, "scale", Vector2.ONE, POP_SECONDS) \
			.from(Vector2.ONE * POP_SCALE).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		# A lone coin reward counts up; anything else (a skater, several chests) is shown whole.
		if shown.size() == 1 and shown[0]["skin"] == "":
			reveal_tween.parallel().tween_method(set_coin_text.bind(row, bool(shown[0]["jackpot"])),
				0.0, float(shown[0]["coins"]), COUNT_SECONDS)
		reveal_tween.tween_interval(BIG_HOLD_SECONDS if is_big else HOLD_SECONDS)


func open_row(row: Label, shown: Array[Dictionary], is_big: bool, on_open: Callable) -> void:
	stage.burst(is_big)
	row.visible = true
	row.text = describe(shown)
	row.pivot_offset = row.size * 0.5
	if on_open.is_valid():
		on_open.call(is_big)


func set_coin_text(coins: float, row: Label, is_jackpot: bool) -> void:
	row.text = ("JACKPOT  +%d coins" if is_jackpot else "+%d coins") % int(round(coins))
	row.pivot_offset = row.size * 0.5


static func is_big_reward(shown: Array[Dictionary]) -> bool:
	for reward: Dictionary in shown:
		if reward["skin"] != "" or reward["jackpot"]:
			return true
	return false


static func get_reward_color(shown: Array[Dictionary]) -> Color:
	var color: Color = COIN_COLOR
	for reward: Dictionary in shown:
		if reward["skin"] != "":
			return SKIN_COLOR
		if reward["jackpot"]:
			color = JACKPOT_COLOR
	return color


static func describe(shown: Array[Dictionary]) -> String:
	var parts: PackedStringArray = []
	var coins: int = ChestRewards.get_total_coins(shown)
	var has_jackpot: bool = false
	for reward: Dictionary in shown:
		has_jackpot = has_jackpot or bool(reward["jackpot"])
		if reward["skin"] != "":
			parts.append("NEW SKATER: %s!" % Skins.get_skin(reward["skin"])["name"])
	if coins > 0:
		parts.append(("JACKPOT  +%d coins" if has_jackpot else "+%d coins") % coins)
	return "   ".join(parts)


# The chest itself, drawn each frame from four numbers ChestReveal tweens (appear, rattle,
# lid_open, flash) plus the sparks burst() throws. The shapes are chest.tscn's, three times the
# size, so the thing that opens is the thing that was picked up.
class ChestStage extends Control:
	const STAGE_SIZE: Vector2 = Vector2(220, 118)
	const DRAW_SCALE: float = 3.0
	const RATTLE_ANGLE: float = 0.16
	const RATTLE_RATE: float = 46.0
	const RAY_COUNT: int = 10
	const RAY_LENGTH: float = 34.0
	const RAY_TURN_RATE: float = 0.5
	const SPARK_COUNT: int = 16
	const BIG_SPARK_COUNT: int = 34
	const SPARK_GRAVITY: float = 520.0
	const SPARK_LIFE: float = 0.9
	const FLASH_RADIUS: float = 150.0
	const BIG_FLASH_RADIUS: float = 260.0
	const FLASH_RINGS: int = 10
	const ICE: Color = Color(0.78, 0.9, 1.0)
	const ICE_SHADE: Color = Color(0.6, 0.76, 0.94)
	const ICE_LID: Color = Color(0.95, 0.98, 1.0)
	const GOLD: Color = Color(1.0, 0.8, 0.32)
	const GOLD_LIGHT: Color = Color(1.0, 0.92, 0.6)

	var appear: float = 0.0
	var rattle: float = 0.0
	var lid_open: float = 0.0
	var flash: float = 0.0
	var is_open: bool = false
	var is_big: bool = false
	var clock: float = 0.0
	# Each spark: {"position", "velocity", "age"} in stage pixels from the chest's middle.
	var sparks: Array[Dictionary] = []

	func _init() -> void:
		custom_minimum_size = STAGE_SIZE
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func begin_chest() -> void:
		rattle = 0.0
		lid_open = 0.0
		flash = 0.0
		is_open = false
		sparks.clear()

	func burst(big: bool) -> void:
		is_open = true
		is_big = big
		rattle = 0.0
		for index: int in range(BIG_SPARK_COUNT if big else SPARK_COUNT):
			# A fan upward out of the open lid, deterministic so it never clumps.
			var spread: float = lerpf(-1.25, 1.25, float(index) / float((BIG_SPARK_COUNT if big else SPARK_COUNT) - 1))
			var speed: float = 170.0 + 130.0 * absf(sin(float(index) * 12.9898))
			sparks.append({
				"position": Vector2(0, -10),
				"velocity": Vector2(sin(spread), -cos(spread)) * speed * (1.3 if big else 1.0),
				"age": 0.0,
			})

	func _process(delta: float) -> void:
		clock += delta
		for index: int in range(sparks.size() - 1, -1, -1):
			var spark: Dictionary = sparks[index]
			spark["age"] += delta
			spark["velocity"] += Vector2(0, SPARK_GRAVITY) * delta
			spark["position"] += spark["velocity"] * delta
			if spark["age"] >= SPARK_LIFE:
				sparks.remove_at(index)
		queue_redraw()

	func _draw() -> void:
		var center: Vector2 = Vector2(size.x * 0.5, size.y - 46.0)
		# The glow swells with the rattle and stays lit once open.
		var glow: float = appear * (1.0 if is_open else 0.35 + 0.65 * rattle)
		for ring: int in range(10):
			draw_circle(center, (20.0 + ring * 7.0) * (0.8 + 0.4 * glow), Color(GOLD_LIGHT, 0.04 * glow))
		if is_open:
			draw_rays(center + Vector2(0, -16))

		var angle: float = sin(clock * RATTLE_RATE) * RATTLE_ANGLE * rattle * rattle
		draw_set_transform(center, angle, Vector2.ONE * DRAW_SCALE * appear)
		# The light inside, seen once the lid lifts.
		if lid_open > 0.05:
			draw_colored_polygon(PackedVector2Array([Vector2(-13, -6), Vector2(-9, -6 - 9 * lid_open), Vector2(9, -6 - 9 * lid_open), Vector2(13, -6)]), GOLD_LIGHT)
		draw_colored_polygon(PackedVector2Array([Vector2(-15, -6), Vector2(15, -6), Vector2(15, 12), Vector2(-15, 12)]), ICE)
		draw_colored_polygon(PackedVector2Array([Vector2(3, -6), Vector2(15, -6), Vector2(15, 12), Vector2(9, 12)]), ICE_SHADE)
		draw_colored_polygon(PackedVector2Array([Vector2(-15, -7), Vector2(15, -7), Vector2(15, -3), Vector2(-15, -3)]), GOLD)
		# The lid, hinged at its back corner and thrown open.
		draw_set_transform(center + Vector2(15, -6).rotated(angle) * DRAW_SCALE * appear, angle + lid_open * 1.15, Vector2.ONE * DRAW_SCALE * appear)
		draw_colored_polygon(PackedVector2Array([Vector2(-30, 0), Vector2(-24, -8), Vector2(-6, -8), Vector2(0, 0)]), ICE_LID)
		draw_colored_polygon(PackedVector2Array([Vector2(-18, -2), Vector2(-12, -2), Vector2(-12, 7), Vector2(-15, 10), Vector2(-18, 7)]), GOLD_LIGHT)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		for spark: Dictionary in sparks:
			var fade: float = 1.0 - float(spark["age"]) / SPARK_LIFE
			var at: Vector2 = center + spark["position"]
			var half: float = 3.0 + 5.0 * fade
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -half), at + Vector2(half, 0), at + Vector2(0, half), at + Vector2(-half, 0)]), Color(GOLD if spark["age"] > 0.25 else GOLD_LIGHT, sqrt(fade)))
		if flash > 0.0:
			var radius: float = (BIG_FLASH_RADIUS if is_big else FLASH_RADIUS) * (1.15 - 0.75 * flash)
			# Stacked rings: white-hot in the middle, falling off to nothing, with no hard rim.
			for ring: int in range(FLASH_RINGS):
				draw_circle(center, radius * (1.0 - float(ring) / float(FLASH_RINGS)), Color(1.0, 1.0, 1.0, flash * 0.2))

	func draw_rays(origin: Vector2) -> void:
		var length: float = RAY_LENGTH * DRAW_SCALE * (1.25 if is_big else 1.0) * lid_open
		if length < 2.0:
			return
		for ray: int in range(RAY_COUNT):
			var direction: float = clock * RAY_TURN_RATE + TAU * float(ray) / float(RAY_COUNT)
			var tip: Vector2 = origin + Vector2.from_angle(direction) * length
			var side: Vector2 = Vector2.from_angle(direction + PI * 0.5) * 7.0
			draw_colored_polygon(PackedVector2Array([origin + side, tip, origin - side]), Color(GOLD_LIGHT, 0.16))
