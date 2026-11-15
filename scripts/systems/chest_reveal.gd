extends VBoxContainer

class_name ChestReveal

# The chests a run collected, opened one after another on the death screen: each row rattles as
# a closed chest, then pops into what it held. COSMETIC ONLY -- the rewards are already in the
# save before this plays (GameManager._on_player_died), so quitting mid-reveal loses nothing.
#
# Built in code and added to the death screen's column by GameManager, like the shop's rows. It
# runs on a paused tree (the death screen's), hence PROCESS_MODE_ALWAYS.

# More chests than this share the last row, so the column cannot push the buttons off screen.
const MAX_ROWS: int = 4
const START_DELAY: float = 0.7
const RATTLE_SECONDS: float = 0.45
const RATTLE_ANGLE: float = 0.07
const POP_SECONDS: float = 0.25
const POP_SCALE: float = 1.7
const ROW_GAP_SECONDS: float = 0.2
const FONT_SIZE: int = 16
const CLOSED_COLOR: Color = Color(0.75, 0.86, 1.0)
const COIN_COLOR: Color = Color(1.0, 0.86, 0.45)
const JACKPOT_COLOR: Color = Color(1.0, 0.72, 0.2)
const SKIN_COLOR: Color = Color(0.6, 1.0, 0.8)

var reveal_tween: Tween


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	alignment = BoxContainer.ALIGNMENT_CENTER
	visible = false


# on_open is called as each chest opens with whether it was a big one (jackpot or skin), for
# the sound.
func play(rewards: Array[Dictionary], on_open: Callable) -> void:
	if reveal_tween != null:
		reveal_tween.kill()
	for row: Node in get_children():
		row.queue_free()
	visible = not rewards.is_empty()
	if rewards.is_empty():
		return

	reveal_tween = create_tween()
	reveal_tween.tween_interval(START_DELAY)
	for row_index: int in range(mini(rewards.size(), MAX_ROWS)):
		var is_overflow_row: bool = row_index == MAX_ROWS - 1 and rewards.size() > MAX_ROWS
		var shown: Array[Dictionary] = []
		shown.assign(rewards.slice(row_index) if is_overflow_row else [rewards[row_index]])
		var row: Label = Label.new()
		row.text = "Chest" if shown.size() == 1 else "%d chests" % shown.size()
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_theme_font_size_override("font_size", FONT_SIZE)
		row.modulate = CLOSED_COLOR
		row.modulate.a = 0.0
		add_child(row)

		# Once the column has laid the row out, so the rattle turns about its middle.
		reveal_tween.tween_callback(func() -> void: row.pivot_offset = row.size * 0.5)
		reveal_tween.tween_property(row, "modulate:a", 1.0, 0.1)
		for _rattle: int in range(3):
			reveal_tween.tween_property(row, "rotation", RATTLE_ANGLE, RATTLE_SECONDS / 6.0)
			reveal_tween.tween_property(row, "rotation", -RATTLE_ANGLE, RATTLE_SECONDS / 6.0)
		reveal_tween.tween_callback(open_row.bind(row, shown, on_open))
		reveal_tween.tween_property(row, "scale", Vector2.ONE, POP_SECONDS) \
			.from(Vector2.ONE * POP_SCALE).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		reveal_tween.tween_interval(ROW_GAP_SECONDS)


func open_row(row: Label, shown: Array[Dictionary], on_open: Callable) -> void:
	row.rotation = 0.0
	row.pivot_offset = row.size * 0.5
	row.text = describe(shown)
	var is_big: bool = false
	row.modulate = COIN_COLOR
	for reward: Dictionary in shown:
		if reward["skin"] != "":
			row.modulate = SKIN_COLOR
			is_big = true
		elif reward["jackpot"] and row.modulate != SKIN_COLOR:
			row.modulate = JACKPOT_COLOR
			is_big = true
	if on_open.is_valid():
		on_open.call(is_big)


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
