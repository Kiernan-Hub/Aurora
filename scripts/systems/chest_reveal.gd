extends VBoxContainer

class_name ChestReveal

# The chests a run collected, opened one after another on the death screen. Each one appears
# closed, waits for a tap, then rattles and bursts: a white flash, the lid thrown back, light rays,
# a spray of gold, and its reward counting up on a row beneath. COSMETIC ONLY -- the rewards are
# already in the save before this plays (GameManager._on_player_died), so quitting mid-reveal
# loses nothing, and the death screen's buttons work throughout.
#
# Built in code and added to the death screen's column by GameManager, like the shop's cards. It
# runs on a paused tree (the death screen's), hence PROCESS_MODE_ALWAYS. Everything is drawn by
# ChestStage below uses the same small sprites as the pickups.

# More chests than this share the last opening, so the column cannot push the buttons off screen.
const MAX_ROWS: int = 4
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
var open_button: Button
var open_label: Label
var pending_rewards: Array[Dictionary] = []
var next_reward: int = 0
var sound_callback: Callable


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	alignment = BoxContainer.ALIGNMENT_CENTER
	visible = false


# on_sound is called with &"rattle" as each chest starts to shake and &"open" or &"jackpot" (a
# jackpot or a skater) as it bursts: SfxPlayer.play_chest.
func play(rewards: Array[Dictionary], on_sound: Callable) -> void:
	if reveal_tween != null:
		reveal_tween.kill()
	for child: Node in get_children():
		child.queue_free()
	visible = not rewards.is_empty()
	if rewards.is_empty():
		return

	pending_rewards = rewards.duplicate()
	next_reward = 0
	sound_callback = on_sound
	open_button = Button.new()
	open_button.custom_minimum_size = Vector2(220, 154)
	open_button.pressed.connect(open_next)
	add_child(open_button)
	stage = ChestStage.new()
	open_button.add_child(stage)
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.offset_bottom = -36.0
	open_label = Label.new()
	open_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	open_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	open_button.add_child(open_label)
	open_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	open_label.offset_top = -32.0
	prepare_next()


func prepare_next() -> void:
	if next_reward >= pending_rewards.size():
		open_label.text = "Opened"
		return
	stage.begin_chest()
	stage.set_tier(int(pending_rewards[next_reward].get("tier", ChestTypes.Tier.NORMAL)))
	stage.appear = 1.0
	open_button.disabled = false
	open_label.remove_theme_font_size_override(&"font_size")
	open_label.offset_top = -32.0
	var tier_name: String = ChestTypes.get_type(stage.tier)["name"]
	open_label.text = "%s · Tap %d/%d" % [("Mission " + tier_name) if pending_rewards[next_reward].get("mission", false) else tier_name + " chest", next_reward + 1, pending_rewards.size()]
	if pending_rewards[next_reward].has("contents"):
		open_label.text = "%s\nTap %d/%d" % [pending_rewards[next_reward]["name"], next_reward + 1, pending_rewards.size()]
		open_label.add_theme_font_size_override(&"font_size", 12)
		open_label.offset_top = -40.0


# One tap opens one chest. Repeated taps during the animation cannot skip rewards.
func open_next() -> void:
	if open_button.disabled or next_reward >= pending_rewards.size():
		return
	open_button.disabled = true
	open_label.text = "Opening..."
	var is_overflow_row: bool = next_reward == MAX_ROWS - 1 and pending_rewards.size() > MAX_ROWS
	var shown: Array[Dictionary] = []
	shown.assign(pending_rewards.slice(next_reward) if is_overflow_row else [pending_rewards[next_reward]])
	next_reward = pending_rewards.size() if is_overflow_row else next_reward + 1
	var is_big: bool = is_big_reward(shown)
	var row: Label = Label.new()
	row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_theme_font_size_override("font_size", FONT_SIZE)
	row.modulate = get_reward_color(shown)
	row.visible = false
	add_child(row)

	reveal_tween = create_tween()
	reveal_tween.tween_property(stage, "appear", 1.0, APPEAR_SECONDS).from(0.85) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if sound_callback.is_valid():
		reveal_tween.tween_callback(sound_callback.bind(&"rattle"))
	reveal_tween.tween_property(stage, "rattle", 1.0, RATTLE_SECONDS).from(0.0).set_ease(Tween.EASE_IN)
	reveal_tween.tween_callback(open_row.bind(row, shown, is_big, sound_callback))
	reveal_tween.tween_property(stage, "lid_open", 1.0, LID_SECONDS).from(0.0) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	reveal_tween.parallel().tween_property(stage, "flash", 0.0, FLASH_SECONDS).from(1.0).set_ease(Tween.EASE_OUT)
	reveal_tween.parallel().tween_property(row, "scale", Vector2.ONE, POP_SECONDS) \
		.from(Vector2.ONE * POP_SCALE).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if shown.size() == 1 and not shown[0].has("contents") and shown[0]["skin"] == "" and shown[0].get("cosmetic", "") == "":
		reveal_tween.parallel().tween_method(set_coin_text.bind(row, bool(shown[0]["jackpot"])),
			0.0, float(shown[0]["coins"]), COUNT_SECONDS)
	reveal_tween.tween_interval(BIG_HOLD_SECONDS if is_big else HOLD_SECONDS)
	reveal_tween.tween_callback(prepare_next)


func open_row(row: Label, shown: Array[Dictionary], is_big: bool, on_sound: Callable) -> void:
	stage.burst(is_big)
	# Show a cosmetic's actual collection icon above the opened chest.
	for reward: Dictionary in ChestRewards.get_loot(shown):
		var item: Dictionary = Cosmetics.get_item(reward.get("cosmetic", ""))
		if not item.is_empty():
			stage.reward_icon = load(item.get("icon", Cosmetics.ICONS[item["kind"]])) as Texture2D
			stage.reward_color = item["color"]
			break
	row.visible = true
	row.text = describe(shown)
	row.pivot_offset = row.size * 0.5
	if on_sound.is_valid():
		on_sound.call(&"jackpot" if is_big else &"open")


func set_coin_text(coins: float, row: Label, is_jackpot: bool) -> void:
	row.text = ("JACKPOT  +%d coins" if is_jackpot else "+%d coins") % int(round(coins))
	row.pivot_offset = row.size * 0.5


static func is_big_reward(shown: Array[Dictionary]) -> bool:
	for reward: Dictionary in shown:
		if reward["skin"] != "" or reward.get("cosmetic", "") != "" or reward["jackpot"]:
			return true
	return false


static func get_reward_color(shown: Array[Dictionary]) -> Color:
	var color: Color = COIN_COLOR
	for reward: Dictionary in shown:
		if reward["skin"] != "" or reward.get("cosmetic", "") != "":
			return SKIN_COLOR
		if reward["jackpot"]:
			color = JACKPOT_COLOR
	return color


static func describe(shown: Array[Dictionary]) -> String:
	shown = ChestRewards.get_loot(shown)
	var parts: PackedStringArray = []
	var coins: int = ChestRewards.get_total_coins(shown)
	var has_jackpot: bool = false
	var new_skaters: int = 0
	var new_cosmetics: int = 0
	for reward: Dictionary in shown:
		has_jackpot = has_jackpot or bool(reward["jackpot"])
		if reward["skin"] != "":
			new_skaters += 1
			if shown.size() == 1:
				parts.append("NEW SKATER: %s!" % Skins.get_skin(reward["skin"])["name"])
		var item: Dictionary = Cosmetics.get_item(reward.get("cosmetic", ""))
		if not item.is_empty():
			new_cosmetics += 1
			if shown.size() == 1:
				parts.append("NEW %s: %s!" % [String(item["kind"]).to_upper(), item["name"]])
	# The final row groups overflow chests: a summary stays on screen even on a long run.
	if shown.size() > 1:
		if new_skaters > 0:
			parts.append("%d new skaters" % new_skaters)
		if new_cosmetics > 0:
			parts.append("%d new finds" % new_cosmetics)
	if coins > 0:
		parts.append(("JACKPOT  +%d coins" if has_jackpot else "+%d coins") % coins)
	return "   ".join(parts)


# The chest itself, drawn each frame from four numbers ChestReveal tweens (appear, rattle,
# lid_open, flash) plus the sparks burst() throws. The aligned small sprite pair is the
# same chest the player picked up; a brief blend opens it without a new animation system.
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
	const CLOSED: Texture2D = preload("res://assets/sprites/chest/closed.png")
	const OPEN: Texture2D = preload("res://assets/sprites/chest/open.png")
	const GOLD: Color = Color(1.0, 0.8, 0.32)
	const GOLD_LIGHT: Color = Color(1.0, 0.92, 0.6)

	var tier: int = ChestTypes.Tier.NORMAL
	var closed_texture: Texture2D = CLOSED
	var open_texture: Texture2D = OPEN
	var tier_glow: Color = Color(1.0, 0.92, 0.6)
	var tier_glow_scale: float = 0.6
	var appear: float = 0.0
	var rattle: float = 0.0
	var lid_open: float = 0.0
	var flash: float = 0.0
	var is_open: bool = false
	var is_big: bool = false
	var clock: float = 0.0
	var reward_icon: Texture2D
	var reward_color: Color = Color.WHITE
	# Each spark: {"position", "velocity", "age"} in stage pixels from the chest's middle.
	var sparks: Array[Dictionary] = []

	func _init() -> void:
		custom_minimum_size = STAGE_SIZE
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_tier(value: int) -> void:
		tier = ChestTypes.normalize(value)
		var style: Dictionary = ChestTypes.get_type(tier)
		closed_texture = load(style["closed"]) as Texture2D
		open_texture = load(style["open"]) as Texture2D
		tier_glow = style["glow"]
		tier_glow_scale = style["glow_scale"]

	func begin_chest() -> void:
		rattle = 0.0
		lid_open = 0.0
		flash = 0.0
		is_open = false
		sparks.clear()
		reward_icon = null

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
			draw_circle(center, (20.0 + ring * 7.0) * (0.8 + 0.4 * glow) * tier_glow_scale, Color(tier_glow, 0.04 * glow))
		if tier == ChestTypes.Tier.AURORA:
			draw_set_transform(center, clock * 0.35, Vector2.ONE)
			draw_texture_rect(ChestTypes.AURA, Rect2(-65, -65, 130, 130), false, Color(1, 1, 1, 0.8 * appear))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if is_open:
			draw_rays(center + Vector2(0, -16))

		var angle: float = sin(clock * RATTLE_RATE) * RATTLE_ANGLE * rattle * rattle
		draw_set_transform(center, angle, Vector2.ONE * DRAW_SCALE * appear)
		var chest_rect: Rect2 = Rect2(-18, -20, 36, 36)
		var tint: Color = Color(0.8, 0.94, 1.0) if tier == ChestTypes.Tier.RARE else Color.WHITE
		if lid_open < 1.0:
			draw_texture_rect(closed_texture, chest_rect, false, Color(tint, 1.0 - lid_open))
		if lid_open > 0.0:
			draw_texture_rect(open_texture, chest_rect, false, Color(tint, lid_open))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		if reward_icon != null:
			draw_texture_rect(reward_icon, Rect2(center + Vector2(-22, -64), Vector2(44, 44)), false, reward_color)
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
