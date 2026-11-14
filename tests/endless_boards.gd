extends SceneTree
# Run: godot --headless --path . --script tests/endless_boards.gd
# Endless: separate Baby Mode / typing boards, verses heard / typed, no pots.
const S = preload("res://endless_scores.gd")
var backup = null

func _initialize():
	call_deferred("verify")

func _pots(n: Node) -> int:
	var c = 1 if (n.get_script() != null and n.get_script().resource_path == "res://pot.gd") or n.name == "Pots" else 0
	for k in n.get_children():
		c += _pots(k)
	return c

func verify():
	if FileAccess.file_exists(S.FILE):
		backup = FileAccess.get_file_as_string(S.FILE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(S.FILE))
	# --- legacy file (before the split): stays on the typing board only ---
	var cfg = ConfigFile.new()
	cfg.set_value("endless", "scores", [{"id": "old", "name": "Old", "distance": 5.0, "level": 2, "enemies": 1, "date": "2026-01-01"}])
	cfg.save(S.FILE)
	assert(S.load_scores(S.MODE_TYPING).size() == 1)
	assert(S.load_scores(S.MODE_BABY).is_empty())
	# --- saving goes to the right board ---
	var b = S.add_score("Kid", 9.0, 3, 2, S.MODE_BABY, 7)
	var t = S.add_score("Dev", 3.0, 1, 0, S.MODE_TYPING, 4)
	var baby = S.load_scores(S.MODE_BABY)
	var typing = S.load_scores(S.MODE_TYPING)
	assert(baby.size() == 1 and baby[0].id == b and baby[0].verses == 7 and baby[0].mode == "baby")
	assert(typing.size() == 2 and typing.any(func(r): return r.id == t) and not typing.any(func(r): return r.id == b))
	assert(S.best_distance(S.MODE_BABY) == 9.0 and S.best_distance(S.MODE_TYPING) == 5.0)
	assert(S.rank_of(10.0, 3, S.MODE_BABY) == 1 and S.rank_of(1.0, 1, S.MODE_BABY) == 2)
	print("PASS boards: legacy rows on typing only; baby/typing saves separate; best/rank per board")
	# --- the board panel: tabs switch boards, headers per mode ---
	var holder = Control.new()
	root.add_child(holder)
	var panel = S.build_board_panel(holder, b, S.MODE_BABY)
	var grid = panel.get_node("Box/Scroll").get_child(0)
	assert(grid.get_child(4).text == "Verses heard")
	panel.get_node("Box/Tabs/TabTyping").pressed.emit()
	await process_frame
	grid = panel.get_node("Box/Scroll").get_child(panel.get_node("Box/Scroll").get_child_count() - 1)
	assert(grid.get_child(4).text == "Verses typed")
	assert(panel.get_meta("mode") == "typing")
	holder.queue_free()
	print("PASS board panel: Typing / Baby Mode tabs, Verses typed / Verses heard columns")
	# --- BabyMode counts verses that start being read ---
	var bm = root.get_node("BabyMode")
	var before = bm.verses_heard
	bm.speak_aloud = false
	bm._start_line({"text": "John 3:16. For God so loved", "lang": "en", "v": {"ref": "John 3:16"}, "show": Callable(), "prio": 0})
	assert(bm.verses_heard == before + 1)
	# --- an Endless run in Baby Mode ---
	var gs = root.get_node("GameSettings")
	gs.baby_mode = true
	change_scene_to_file("res://Endless.tscn")
	for i in 20:
		await process_frame
	var lvl = get_first_node_in_group("endless")
	assert(lvl != null)
	assert(lvl.run_mode == "baby")
	for i in 12:
		lvl._spawn_new_part()
	await process_frame
	assert(_pots(lvl) == 0)
	print("PASS no pots in Endless after %d parts" % lvl.spawned)
	bm.verse_heard.emit({"ref": "x"})
	bm.verse_heard.emit({"ref": "y"})
	var player = get_first_node_in_group("player")
	player.verse_recited.emit({"ref": "z"})
	assert(lvl.verses_heard == 2 and lvl.verses_typed == 1 and lvl.run_verses() == 2)
	# switching to typing mid-run: the run stays a Baby Mode run
	gs.baby_mode = false
	await process_frame
	lvl._game_over("test")
	await process_frame
	lvl.over_layer.find_child("SaveScore", true, false).pressed.emit()
	await process_frame
	baby = S.load_scores(S.MODE_BABY)
	assert(baby.size() == 2 and baby.any(func(r): return r.verses == 2))
	assert(S.load_scores(S.MODE_TYPING).size() == 2)
	print("PASS Baby Mode run: verses heard counted and saved to the Baby board only (mode locked at start)")
	# --- the next run is a typing run ---
	change_scene_to_file("res://Endless.tscn")
	for i in 20:
		await process_frame
	lvl = get_first_node_in_group("endless")
	assert(lvl.run_mode == "typing")
	assert(_pots(lvl) == 0)
	player = get_first_node_in_group("player")
	player.verse_recited.emit({"ref": "z"})
	bm.verse_heard.emit({"ref": "x"})
	assert(lvl.run_verses() == 1)
	lvl._game_over("test")
	await process_frame
	lvl.over_layer.find_child("SaveScore", true, false).pressed.emit()
	await process_frame
	assert(S.load_scores(S.MODE_TYPING).size() == 3 and S.load_scores(S.MODE_BABY).size() == 2)
	assert(S.load_scores(S.MODE_TYPING).all(func(r): return r.get("mode", "typing") == "typing"))
	assert(S.load_scores(S.MODE_BABY).all(func(r): return r.mode == "baby"))
	print("PASS typing run: verses typed counted and saved to the typing board only")
	# --- the story level still has its pots ---
	change_scene_to_file("res://Greed.tscn")
	for i in 10:
		await process_frame
	assert(_pots(current_scene) > 0)
	print("PASS Greed story level still has pots")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(S.FILE))
	if backup != null:
		var f = FileAccess.open(S.FILE, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	print("ALL PASS")
	quit()
