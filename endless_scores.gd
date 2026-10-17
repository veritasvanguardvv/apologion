extends RefCounted
# ENDLESS MODE HIGH SCORES (local leaderboard)
# --------------------------------------------
# Port of Unity's Overmind.AddEndlessScore / EndlessHighscore.cs: every run
# you save gets a row (name, distance, level, enemies defeated). Like Unity
# the list is sorted by level first, then distance. Kept on this computer in
# user://endless_scores.cfg (online leaderboards only count defeats so far).

const FILE = "user://endless_scores.cfg"
const MAX_ROWS = 50

# All saved runs, best first: [{ "id", "name", "distance", "level", "enemies", "date" }]
static func load_scores() -> Array:
	var config = ConfigFile.new()
	if config.load(FILE) != OK:
		return []
	return config.get_value("endless", "scores", [])

# Best distance ever (shown in the Endless HUD)
static func best_distance() -> float:
	var best = 0.0
	for s in load_scores():
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

# Adds a run and returns its id (to highlight "you" in the list)
static func add_score(player_name: String, distance: float, level: int, enemies: int) -> String:
	var scores = load_scores()
	var id = "%d_%d" % [Time.get_unix_time_from_system(), randi() % 100000]
	player_name = player_name.strip_edges().left(16)
	if player_name == "":
		player_name = "?"
	scores.append({"id": id, "name": player_name, "distance": snappedf(distance, 0.1), "level": level,
		"enemies": enemies, "date": Time.get_date_string_from_system()})
	scores.sort_custom(_better)
	if scores.size() > MAX_ROWS:
		scores.resize(MAX_ROWS)
	var config = ConfigFile.new()
	config.load(FILE)
	config.set_value("endless", "scores", scores)
	config.set_value("endless", "last_name", player_name)
	config.save(FILE)
	return id

# Rank (1 = best) a run with these numbers would get
static func rank_of(distance: float, level: int) -> int:
	var me = {"distance": distance, "level": level}
	var rank = 1
	for s in load_scores():
		if _better(s, me):
			rank += 1
	return rank

# The table of the top runs: "#  Name  Distance  Level (enemies)". The row
# with id 'highlight' is drawn in gold.
static func build_table(highlight: String, rows := 10) -> GridContainer:
	var grid = GridContainer.new()
	grid.name = "Scores"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 2)
	for h in ["#", "Name", "Distance", "Level (enemies)"]:
		grid.add_child(_cell(h, Color(0.7, 0.75, 0.9)))
	var scores = load_scores()
	if scores.is_empty():
		grid.add_child(_cell(""))
		grid.add_child(_cell("No scores yet", Color(0.8, 0.8, 0.8)))
		grid.add_child(_cell(""))
		grid.add_child(_cell(""))
	for i in min(rows, scores.size()):
		var s = scores[i]
		var c = Color(1, 0.85, 0.3) if s.get("id", "") == highlight else Color.WHITE
		grid.add_child(_cell("%d." % (i + 1), c))
		grid.add_child(_cell(str(s.get("name", "?")), c, false))
		grid.add_child(_cell("%.1f" % float(s.get("distance", 0.0)), c))
		grid.add_child(_cell("%d (%d)" % [int(s.get("level", 1)), int(s.get("enemies", 0))], c))
	return grid

static func _cell(text: String, color := Color.WHITE, translate := true) -> Label:
	var l = Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_ALWAYS if translate else Node.AUTO_TRANSLATE_MODE_DISABLED
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", color)
	return l

# A centred panel with the title and the table, added to 'parent' (a
# CanvasLayer or Control). Its VBoxContainer is "Box": add buttons there.
static func build_board_panel(parent: Node, highlight: String) -> Panel:
	var panel = Panel.new()
	panel.size = Vector2(520, 420)
	panel.position = Vector2((1152 - 520) / 2.0, (648 - 420) / 2.0)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.12, 0.96)
	style.border_color = Color(0.85, 0.7, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	var box = VBoxContainer.new()
	box.name = "Box"
	box.position = Vector2(20, 14)
	box.size = Vector2(480, 392)
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title = Label.new()
	title.text = "Endless high scores"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	box.add_child(title)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480, 290)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(build_table(highlight, MAX_ROWS))
	box.add_child(scroll)
	parent.add_child(panel)
	return panel
