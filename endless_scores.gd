extends RefCounted
# ENDLESS MODE HIGH SCORES (local leaderboards)
# ---------------------------------------------
# Port of Unity's Overmind.AddEndlessScore / EndlessHighscore.cs: every run
# you save gets a row (name, distance, level, enemies defeated, verses). Like
# Unity the list is sorted by level first, then distance. Kept on this
# computer in user://endless_scores.cfg (online leaderboards only count
# lifetime defeats, online_service.gd - they don't hold Endless runs).
#
# TWO SEPARATE BOARDS, one per way of playing (locked when the run starts,
# endless_level.gd run_mode):
#   MODE_TYPING ("typing") - verses typed or spoken; the row's "verses" is
#                            the verses recited ("Verses typed")
#   MODE_BABY   ("baby")   - Baby Mode (ram + read aloud); "verses" is the
#                            verses read out loud ("Verses heard")
# Each board has its own section in the file, its own best distance and
# ranks: a run is only ever written to (and compared with) its own board.
# Rows saved before the boards were split (section "endless", no "mode") had
# no way of telling which mode they came from; they stay on the typing board
# (the game's original mode) and show "-" for verses.

const FILE = "user://endless_scores.cfg"
const MAX_ROWS = 50
const MODE_TYPING = "typing"
const MODE_BABY = "baby"
const MODES = [MODE_TYPING, MODE_BABY]
const SECTIONS = {MODE_TYPING: "endless", MODE_BABY: "endless_baby"}   # "endless" = the old (pre-split) section
const VERSES_HEADER = {MODE_TYPING: "Verses typed", MODE_BABY: "Verses heard"}
const BOARD_TITLE = {MODE_TYPING: "Typing high scores", MODE_BABY: "Baby Mode high scores"}

# The board the game is set to right now (Settings > Baby Mode)
static func current_mode() -> String:
	var gs = Engine.get_main_loop().root.get_node_or_null("/root/GameSettings") if Engine.get_main_loop() else null
	return MODE_BABY if gs and gs.baby_mode else MODE_TYPING

static func _mode(mode: String) -> String:
	return mode if mode in MODES else MODE_TYPING

# All saved runs of one board, best first: [{ "id", "name", "distance", "level", "enemies", "verses", "mode", "date" }]
static func load_scores(mode := MODE_TYPING) -> Array:
	var config = ConfigFile.new()
	if config.load(FILE) != OK:
		return []
	return config.get_value(SECTIONS[_mode(mode)], "scores", [])

# Best distance ever on that board (shown in the Endless HUD)
static func best_distance(mode := MODE_TYPING) -> float:
	var best = 0.0
	for s in load_scores(mode):
		best = max(best, float(s.get("distance", 0.0)))
	return best

static func last_name() -> String:
	var config = ConfigFile.new()
	if config.load(FILE) != OK:
		return ""
	return config.get_value("endless", "last_name", "")

static func _better(a: Dictionary, b: Dictionary) -> bool:
	if int(a.level) != int(b.level):
		return int(a.level) > int(b.level)
	return float(a.distance) > float(b.distance)

# Adds a run to its mode's board and returns its id (to highlight "you" in the list)
static func add_score(player_name: String, distance: float, level: int, enemies: int, mode := MODE_TYPING, verses := 0) -> String:
	mode = _mode(mode)
	var scores = load_scores(mode)
	var id = "%d_%d" % [Time.get_unix_time_from_system(), randi() % 100000]
	player_name = player_name.strip_edges().left(16)
	if player_name == "":
		player_name = "?"
	scores.append({"id": id, "name": player_name, "distance": snappedf(distance, 0.1), "level": level,
		"enemies": enemies, "verses": verses, "mode": mode, "date": Time.get_date_string_from_system()})
	scores.sort_custom(_better)
	if scores.size() > MAX_ROWS:
		scores.resize(MAX_ROWS)
	var config = ConfigFile.new()
	config.load(FILE)
	config.set_value(SECTIONS[mode], "scores", scores)
	config.set_value("endless", "last_name", player_name)
	config.save(FILE)
	return id

# Rank (1 = best) a run with these numbers would get on that board
static func rank_of(distance: float, level: int, mode := MODE_TYPING) -> int:
	var me = {"distance": distance, "level": level}
	var rank = 1
	for s in load_scores(mode):
		if _better(s, me):
			rank += 1
	return rank

# The table of the top runs: "#  Name  Distance  Level (enemies)  Verses". The
# row with id 'highlight' is drawn in gold.
static func build_table(highlight: String, rows := 10, mode := MODE_TYPING) -> GridContainer:
	mode = _mode(mode)
	var grid = GridContainer.new()
	grid.name = "Scores"
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 2)
	for h in ["#", "Name", "Distance", "Level (enemies)", VERSES_HEADER[mode]]:
		grid.add_child(_cell(h, Color(0.7, 0.75, 0.9)))
	var scores = load_scores(mode)
	if scores.is_empty():
		grid.add_child(_cell(""))
		grid.add_child(_cell("No scores yet", Color(0.8, 0.8, 0.8)))
		for i in 3:
			grid.add_child(_cell(""))
	for i in min(rows, scores.size()):
		var s = scores[i]
		var c = Color(1, 0.85, 0.3) if s.get("id", "") == highlight else Color.WHITE
		grid.add_child(_cell("%d." % (i + 1), c, false))
		grid.add_child(_cell(str(s.get("name", "?")), c, false))
		grid.add_child(_cell("%.1f" % float(s.get("distance", 0.0)), c, false))
		grid.add_child(_cell("%d (%d)" % [int(s.get("level", 1)), int(s.get("enemies", 0))], c, false))
		grid.add_child(_cell(str(int(s.verses)) if s.has("verses") else "-", c, false))   # "-" = saved before verses were counted
	return grid

static func _cell(text: String, color := Color.WHITE, translate := true) -> Label:
	var l = Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_ALWAYS if translate else Node.AUTO_TRANSLATE_MODE_DISABLED
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", color)
	return l

static func _tab_style(on: bool) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.85, 0.7, 0.3) if on else Color(0.16, 0.14, 0.22)
	s.border_color = Color(0.85, 0.7, 0.3)
	s.set_border_width_all(2)
	s.set_corner_radius_all(0)          # square corners: the 8-bit look
	s.content_margin_left = 10
	s.content_margin_right = 10
	return s

# A centred panel with the two boards' tabs ("Typing" / "Baby Mode"), the
# title and the table, added to 'parent' (a CanvasLayer or Control). It opens
# on 'mode'. Its VBoxContainer is "Box": add buttons there. Tabs are
# "Box/Tabs/TabTyping" and "Box/Tabs/TabBaby"; show_board(panel, mode) switches.
static func build_board_panel(parent: Node, highlight: String, mode := "") -> Panel:
	if mode == "":
		mode = current_mode()
	var panel = Panel.new()
	panel.size = Vector2(640, 460)
	panel.position = Vector2((1152 - 640) / 2.0, (648 - 460) / 2.0)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.12, 0.96)
	style.border_color = Color(0.85, 0.7, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	var box = VBoxContainer.new()
	box.name = "Box"
	box.position = Vector2(20, 12)
	box.size = Vector2(600, 436)
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var tabs = HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 10)
	box.add_child(tabs)
	for info in [["TabTyping", "Typing", MODE_TYPING], ["TabBaby", "Baby Mode", MODE_BABY]]:
		var b = Button.new()
		b.name = info[0]
		b.text = info[1]
		b.custom_minimum_size = Vector2(210, 44)   # big enough to tap on a phone
		b.add_theme_font_size_override("font_size", 20)
		b.set_meta("mode", info[2])
		b.pressed.connect(func(): show_board(panel, info[2]))
		tabs.add_child(b)
	var title = Label.new()
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	box.add_child(title)
	var scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.custom_minimum_size = Vector2(600, 270)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	panel.set_meta("highlight", highlight)
	parent.add_child(panel)
	show_board(panel, mode)
	return panel

# Shows one board in a panel made by build_board_panel
static func show_board(panel: Panel, mode: String):
	mode = _mode(mode)
	panel.set_meta("mode", mode)
	var box = panel.get_node("Box")
	box.get_node("Title").text = BOARD_TITLE[mode]
	for b in box.get_node("Tabs").get_children():
		var on = b.get_meta("mode") == mode
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, _tab_style(on))
		var fc = Color(0.08, 0.07, 0.12) if on else Color(0.85, 0.85, 0.9)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(c, fc)
	var scroll = box.get_node("Scroll")
	for c in scroll.get_children():
		scroll.remove_child(c)
		c.queue_free()
	scroll.add_child(build_table(str(panel.get_meta("highlight", "")), MAX_ROWS, mode))
