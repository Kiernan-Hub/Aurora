extends Control

class_name RecordsScreen

# The Records screen: a dashboard of lifetime stats, the achievement list and the last runs, on
# three tabs. A modal exactly like the shop (GameManager.State.RECORDS, over START or DEAD), so
# GameManager.set_state() owns its visibility and nothing here touches it or get_tree().paused.
#
# READ-ONLY OVER THE SAVE. GameManager hands refresh() the SaveStore on every open and this
# rebuilds what it shows from it; nothing here writes. AchievementManager stays the only writer
# of achievements, and its table is read here only for names, hints and order.
#
# THE CHILDREN ARE BUILT IN CODE, like AchievementToast and the shop rows: one node in main.tscn,
# so the layout cannot drift from the constants below. The LOOK comes from the theme main.tscn
# sets on this node (resources/ui/aura_theme.tres), through the type variations named here
# (RecordTile, ValueLabel, CaptionLabel, AccentLabel): this file holds structure and sizes, the
# theme holds colour. The run chart is the one exception -- it draws, so its colours are below.
#
# GameManager wires close_requested in ITS _ready(), which runs before this one (CanvasLayer is a
# later sibling of GameManager), so nothing outside may reach for a child built here before then.

signal close_requested

# 640 fits the pinned 1152 base with room to spare; height is what bounds this screen, and
# title + tabs + Back come to ~510 of the 648 every aspect ratio gets.
const CONTENT_WIDTH: float = 640.0
const TABS_HEIGHT: float = 400.0
const TITLE_FONT_SIZE: int = 32
const BACK_BUTTON_SIZE: Vector2 = Vector2(160.0, 44.0)
const TILE_COLUMNS: int = 4
const CHART_HEIGHT: float = 104.0
const LOCKED_ALPHA: float = 0.45
# Same as the shop's overlay, so the screen underneath is only just there.
const OVERLAY_COLOR: Color = Color(0.04, 0.06, 0.10, 0.94)

# The Overview tiles, in order. "stat" is a numeric SaveStore field (read through
# AchievementManager.get_stat, which is loud on a typo); "format" defaults to a plain count.
const TILES: Array[Dictionary] = [
	{"stat": "best_score", "caption": "Best score"},
	{"stat": "longest_time", "caption": "Longest run", "format": "run_time"},
	{"stat": "total_runs", "caption": "Runs"},
	{"stat": "total_playtime_seconds", "caption": "Time on ice", "format": "playtime"},
	{"stat": "lifetime_coins", "caption": "Coins collected"},
	{"stat": "coin_wallet", "caption": "Wallet"},
	{"stat": "frozen_lake_count", "caption": "Lakes crossed"},
	{"stat": "aurora_count", "caption": "Auroras"},
]

const HISTORY_HEADERS: Array[String] = ["Run", "When", "Coins", "Time", ""]
const MONTH_NAMES: Array[String] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep",
	"Oct", "Nov", "Dec"]

var tile_values: Array[Label] = []
var run_chart: RunChart
var chart_caption: Label
var achievement_summary: Label
# id -> {"panel": PanelContainer, "status": Label}
var achievement_rows: Dictionary[String, Dictionary] = {}
var history_grid: GridContainer
var history_empty: Label


func _ready() -> void:
	var overlay: ColorRect = ColorRect.new()
	overlay.color = OVERLAY_COLOR
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var column: VBoxContainer = VBoxContainer.new()
	column.custom_minimum_size = Vector2(CONTENT_WIDTH, 0.0)
	column.add_theme_constant_override(&"separation", 12)
	center.add_child(column)

	var title: Label = make_label("Records")
	title.add_theme_font_size_override(&"font_size", TITLE_FONT_SIZE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var tabs: TabContainer = TabContainer.new()
	tabs.custom_minimum_size = Vector2(0.0, TABS_HEIGHT)
	tabs.tab_alignment = TabBar.ALIGNMENT_CENTER
	column.add_child(tabs)
	# A TabContainer titles each tab with its child's node name.
	tabs.add_child(build_overview())
	tabs.add_child(build_achievements())
	tabs.add_child(build_history())

	var back: Button = Button.new()
	back.text = "Back"
	back.custom_minimum_size = BACK_BUTTON_SIZE
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_on_back_pressed)
	column.add_child(back)


func _on_back_pressed() -> void:
	close_requested.emit()


func build_overview() -> Control:
	var page: VBoxContainer = VBoxContainer.new()
	page.name = "Overview"
	page.add_theme_constant_override(&"separation", 12)

	var grid: GridContainer = GridContainer.new()
	grid.columns = TILE_COLUMNS
	grid.add_theme_constant_override(&"h_separation", 10)
	grid.add_theme_constant_override(&"v_separation", 10)
	page.add_child(grid)
	for tile: Dictionary in TILES:
		var panel: PanelContainer = PanelContainer.new()
		panel.theme_type_variation = &"RecordTile"
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var stack: VBoxContainer = VBoxContainer.new()
		stack.add_theme_constant_override(&"separation", 0)
		var value: Label = make_label("0", &"ValueLabel")
		stack.add_child(value)
		stack.add_child(make_label(String(tile["caption"]), &"CaptionLabel"))
		panel.add_child(stack)
		grid.add_child(panel)
		tile_values.append(value)

	chart_caption = make_label("", &"CaptionLabel")
	page.add_child(chart_caption)
	run_chart = RunChart.new()
	run_chart.custom_minimum_size = Vector2(0.0, CHART_HEIGHT)
	page.add_child(run_chart)
	return page


func build_achievements() -> Control:
	var page: VBoxContainer = VBoxContainer.new()
	page.name = "Achievements"
	page.add_theme_constant_override(&"separation", 8)

	achievement_summary = make_label("", &"CaptionLabel")
	page.add_child(achievement_summary)

	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", 6)
	page.add_child(make_scroll(list))
	for id: String in AchievementManager.ACHIEVEMENTS:
		var definition: Dictionary = AchievementManager.ACHIEVEMENTS[id]
		var panel: PanelContainer = PanelContainer.new()
		panel.theme_type_variation = &"RecordTile"
		var line: HBoxContainer = HBoxContainer.new()
		var text_stack: VBoxContainer = VBoxContainer.new()
		text_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_stack.add_theme_constant_override(&"separation", 0)
		text_stack.add_child(make_label(String(definition.get("name", id))))
		text_stack.add_child(make_label(String(definition.get("hint", "")), &"CaptionLabel"))
		line.add_child(text_stack)
		var status: Label = make_label("", &"AccentLabel")
		status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(status)
		panel.add_child(line)
		list.add_child(panel)
		achievement_rows[id] = {"panel": panel, "status": status}
	return page


func build_history() -> Control:
	var page: VBoxContainer = VBoxContainer.new()
	page.name = "History"
	page.add_theme_constant_override(&"separation", 8)

	page.add_child(make_label("Your last %d runs, newest first" % SaveStore.RUN_HISTORY_LIMIT, &"CaptionLabel"))
	# Above the scroll, which expands to fill the page even when its grid is hidden.
	history_empty = make_label("No runs yet.")
	page.add_child(history_empty)
	history_grid = GridContainer.new()
	history_grid.columns = HISTORY_HEADERS.size()
	history_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_grid.add_theme_constant_override(&"h_separation", 16)
	history_grid.add_theme_constant_override(&"v_separation", 6)
	page.add_child(make_scroll(history_grid))
	return page


func refresh(save: SaveStore) -> void:
	for index: int in TILES.size():
		var tile: Dictionary = TILES[index]
		var value: float = AchievementManager.get_stat(save, String(tile["stat"]))
		tile_values[index].text = format_stat(value, String(tile.get("format", "count")))
	refresh_chart(save)
	refresh_achievements(save)
	refresh_history(save)


func refresh_chart(save: SaveStore) -> void:
	var run_count: int = save.run_history.size()
	var oldest_first: PackedInt32Array = PackedInt32Array()
	for index: int in range(run_count - 1, -1, -1):
		oldest_first.append(int(save.run_history[index]["coins"]))
	run_chart.show_values(oldest_first)
	if run_count == 0:
		chart_caption.text = "Recent runs show up here"
	elif run_count == 1:
		chart_caption.text = "Last run  ·  coins"
	else:
		chart_caption.text = "Last %d runs  ·  coins" % run_count


func refresh_achievements(save: SaveStore) -> void:
	for id: String in achievement_rows:
		var earned: bool = bool(save.achievements.get(id, false))
		var row: Dictionary = achievement_rows[id]
		(row["status"] as Label).text = "Earned" if earned else get_progress_text(save, id)
		(row["panel"] as Control).modulate.a = 1.0 if earned else LOCKED_ALPHA
	achievement_summary.text = "%d of %d earned" % [
		AchievementManager.count_earned(save), AchievementManager.ACHIEVEMENTS.size()]


# "38 / 50" for a locked stat row, "Locked" for any other. The value is capped at the target: a
# save can already meet a threshold it has not been granted yet (it is granted on the next
# recorded run), and "128 / 50" would read as a bug.
static func get_progress_text(save: SaveStore, id: String) -> String:
	var definition: Dictionary = AchievementManager.ACHIEVEMENTS[id]
	if not definition.has("stat"):
		return "Locked"
	var target: float = float(definition["at_least"])
	var value: float = minf(AchievementManager.get_stat(save, String(definition["stat"])), target)
	var format: String = String(definition.get("format", "count"))
	return "%s / %s" % [format_stat(value, format), format_stat(target, format)]


# Rebuilt from scratch: at most RUN_HISTORY_LIMIT rows, only on open.
func refresh_history(save: SaveStore) -> void:
	for child: Node in history_grid.get_children():
		history_grid.remove_child(child)
		child.queue_free()
	var has_runs: bool = not save.run_history.is_empty()
	history_empty.visible = not has_runs
	history_grid.visible = has_runs
	if not has_runs:
		return

	add_history_row(HISTORY_HEADERS, true)
	for index: int in save.run_history.size():
		var run: Dictionary = save.run_history[index]
		var coins: int = int(run["coins"])
		# Runs are counted from total_runs, which grows with every entry pushed. A save whose
		# count is behind its history (hand-edited, or a corrupt count read back as 0) loses the
		# number rather than showing a zero or negative one.
		var run_number: int = save.total_runs - index
		# The run that SET the best, not every tie: record_run writes the same seconds to best_time.
		var is_best: bool = coins > 0 and coins == save.best_score \
			and is_equal_approx(float(run["seconds"]), save.best_time)
		var cells: Array[String] = [
			"#%d" % run_number if run_number > 0 else "",
			format_date(String(run.get("date", ""))),
			format_count(coins),
			Main.format_elapsed_time(float(run["seconds"])),
			"Best" if is_best else "",
		]
		add_history_row(cells, false)


# One label per column: the run number and day read left-aligned, the figures right-aligned. The
# last column is the "Best" marker, so it takes the accent.
func add_history_row(cells: Array[String], is_header: bool) -> void:
	for column: int in cells.size():
		var variation: StringName = &"CaptionLabel" if is_header else (&"AccentLabel" if column == cells.size() - 1 else &"")
		var label: Label = make_label(cells[column], variation)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if column <= 1 else HORIZONTAL_ALIGNMENT_RIGHT
		history_grid.add_child(label)


func make_scroll(content: Control) -> ScrollContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(content)
	return scroll


static func make_label(text: String, variation: StringName = &"") -> Label:
	var label: Label = Label.new()
	label.text = text
	label.theme_type_variation = variation
	return label


# One number, as a TILES row or an achievement's progress names it.
static func format_stat(value: float, format: String) -> String:
	match format:
		"run_time":
			return Main.format_elapsed_time(value)
		"playtime":
			return format_playtime(value)
	return format_count(int(value))


# "2026-11-02" -> "Today" or "Nov 2". The year is left off: these are the last ten runs. Anything
# else (an entry from before dates were saved) reads as blank.
static func format_date(date: String) -> String:
	if date.is_empty():
		return ""
	if date == Time.get_date_string_from_system():
		return "Today"
	var parts: PackedStringArray = date.split("-")
	var month: int = parts[1].to_int() if parts.size() == 3 else 0
	if month < 1 or month > MONTH_NAMES.size():
		return ""
	return "%s %d" % [MONTH_NAMES[month - 1], parts[2].to_int()]


# 12345 -> "12,345".
static func format_count(value: int) -> String:
	var digits: String = str(absi(value))
	var grouped: String = ""
	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(digits.length() - 3)
	return ("-" if value < 0 else "") + digits + grouped


# Cumulative playtime: "42m", then "3h 07m".
static func format_playtime(seconds: float) -> String:
	var minutes: int = int(seconds / 60.0)
	if minutes < 60:
		return "%dm" % minutes
	return "%dh %02dm" % [minutes / 60, minutes % 60]


# Coins per recent run as bars, oldest left, newest (the run just finished, from the death
# screen) highlighted at the right edge. Bars are scaled to the tallest shown, and the slot width
# is fixed at RUN_HISTORY_LIMIT so the bars do not change width as the history fills.
class RunChart extends Control:
	const BAR_GAP: float = 6.0
	const MIN_BAR_HEIGHT: float = 2.0
	const BAR_COLOR: Color = Color(0.72, 0.84, 0.96, 0.32)
	const LATEST_COLOR: Color = Color(0.62, 0.86, 1.0, 0.95)
	const BASELINE_COLOR: Color = Color(0.72, 0.84, 0.96, 0.25)

	var values: PackedInt32Array = PackedInt32Array()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func show_values(oldest_first: PackedInt32Array) -> void:
		values = oldest_first
		queue_redraw()

	func _draw() -> void:
		draw_line(Vector2(0.0, size.y), Vector2(size.x, size.y), BASELINE_COLOR, 1.0)
		if values.is_empty():
			return
		var tallest: int = 1
		for value: int in values:
			tallest = maxi(tallest, value)
		var slots: int = maxi(SaveStore.RUN_HISTORY_LIMIT, values.size())
		var bar_width: float = (size.x - BAR_GAP * float(slots - 1)) / float(slots)
		var first_slot: int = slots - values.size()
		for index: int in values.size():
			var height: float = maxf(size.y * float(values[index]) / float(tallest), MIN_BAR_HEIGHT)
			var x: float = float(first_slot + index) * (bar_width + BAR_GAP)
			var color: Color = LATEST_COLOR if index == values.size() - 1 else BAR_COLOR
			draw_rect(Rect2(x, size.y - height, bar_width, height), color)
