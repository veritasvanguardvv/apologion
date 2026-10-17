extends "res://Greed/scripts/greed_level.gd"
# ENDLESS MODE (Endless.tscn)
# ---------------------------
# Port of the Unity project's Endless mode (Assets/Scripts/Game/Endless.cs,
# EndlessPart.cs, UI/Windows/EndlessHighscore.cs, Overmind.AddEndlessScore):
#   - the level is made of "parts" (Unity prefabs EndlessPart0-5, extracted to
#     data/endless_parts.json by greed-unity/extract_endless_parts.py), each
#     1344 px wide, placed one after another to the right
#   - 8 parts exist at a time; once you've walked half of them, a new part is
#     added ahead every 1344 px you advance and the oldest one is removed
#   - part 0 is a plain floor; it comes up 25% of the time (never more than 3
#     in a row), otherwise the other parts are dealt like a shuffled deck
#   - every part turns on a random few of its traps (spikes) and puts 0-1
#     enemies on its spawn points (as Unity: minMaxEnemies 0..2, max excluded)
#   - which enemies: Greedog; from level 2 also Greedwolf; from level 6 also
#     Greedvorg; from level 10 no more Greedogs
#   - you gain exp for each enemy you defeat and level up like Unity's player
#     (100 exp for level 2, +15 more for each level after that)
#   - every 4 levels the new enemies get 10% more health, attack and exp and
#     the traps 10% more damage
#   - score = distance (Unity units: 400 px = 1), level and enemies defeated
#   - dying (a battle lost, a pit, a trap) ends the run: Game Over screen,
#     type your name, the run goes in the local leaderboard (endless_scores.gd)
# Your verses, items and party come along; health starts full.

const EndlessScores = preload("res://endless_scores.gd")
const PARTS_FILE = "res://data/endless_parts.json"
const ENEMY_SCENES = [preload("res://Greed/Greedog.tscn"), preload("res://Greed/Greedwolf.tscn"), preload("res://Greed/Greedvorg.tscn")]
# Same stats as the Greed level's enemies (Unity Greedog/Greedwolf/Greedvorg
# assets converted the same way); exp = Unity's Enemy1/2/3 prefabs' expAward
const ENEMY_STATS = [
	{"name": "Greedog", "max_hp": 69, "attack_damage": 2, "exp": 36},
	{"name": "Greedwolf", "max_hp": 183, "attack_damage": 5, "exp": 66},
	{"name": "Greedvorg", "max_hp": 367, "attack_damage": 12, "exp": 175},
]
const UNITS = 400.0   # px per Unity unit (distance is shown in Unity units, like Unity did)

@export var parts_count = 8              # Unity Endless.partsCount
@export var level_step = 4               # GameData.endlessLvlModif: difficulty goes up every 4 levels
@export var trap_damage_scale = 1.1      # GameData.trapEndlessDmgModif
@export var enemy_hp_scale = 1.1         # GameData.enemyHpEndlessModif
@export var enemy_damage_scale = 1.1     # GameData.enemyDmgEndlessModif
@export var enemy_exp_scale = 1.1        # GameData.enemyExpEndlessModif
@export var exp_to_level_base = 100      # Player.expToLevelBase
@export var exp_per_level = 15           # Player.expToLevel = base + (level-1) * 15
@export var safe_first_part = true       # the part you start on has no traps or enemies
@export var death_y = 760.0              # feet below this = fell into a pit (top of Unity's pit DamageAreas: 769)

var part_defs = []
var part_width = 1344.0
var parts = []                 # [{ "node": Node2D, "enemies": [] }], oldest first
var spawned = 0
var zero_count = 0
var available = []
var player_start_x = 0.0
var player_max_x = 0.0
var to_spawn_new_part = 0.0
var started = false
var dist = 0.0                 # px walked to the right of the start (best so far)
var level = 1
var exp_points = 0
var defeated = 0
var game_over = false
var best = 0.0
var rng = RandomNumberGenerator.new()

var hud_label: Label
var exp_bar: ProgressBar
var over_layer: CanvasLayer


func _ready():
	rng.randomize()
	rooms = []
	use_camera_limits = false
	super._ready()
	var data = JSON.parse_string(FileAccess.get_file_as_string(PARTS_FILE))
	part_defs = data.parts
	part_width = float(data.part_width)
	best = EndlessScores.best_distance()
	_build_background()
	_build_start()
	_build_endless_hud()
	while parts.size() < parts_count:
		_spawn_new_part()
	call_deferred("_start_run")


func _start_run():
	var player = _player()
	if player == null:
		return
	var cam = player.get_node_or_null("Camera2D")
	if cam:
		cam.limit_left = -1700
		cam.limit_bottom = 900
		cam.reset_smoothing()
	player_start_x = _feet(player).x
	player_max_x = player_start_x
	to_spawn_new_part = part_width
	started = true
	_update_hud()


func _feet(player) -> Vector2:
	var cs = player.get_node("CollisionShape2D")
	return cs.global_position + Vector2(0, cs.shape.size.y / 2.0 * cs.global_scale.y)


# Endless.Update()
func _process(_delta):
	var player = _player()
	if player == null or not started or game_over:
		return
	var feet = _feet(player)
	var x = feet.x
	if x > player_start_x and x > player_max_x:
		dist = x - player_start_x
		if dist > parts_count * 0.5 * part_width:
			to_spawn_new_part += x - player_max_x
			if to_spawn_new_part > part_width:
				to_spawn_new_part = 0.0
				_spawn_new_part()
		player_max_x = x
	if feet.y > death_y:
		player_fell()
		return
	_update_hud()


# ---------------- Parts (Endless.SpawnNewPart) ----------------

func _next_index() -> int:
	if zero_count < 3 and rng.randf() < 0.25:
		zero_count += 1
		return 0
	zero_count = 0
	if available.is_empty():
		for i in range(1, part_defs.size()):
			available.append(i)
	return available.pop_at(rng.randi_range(0, available.size() - 1))


func _raise() -> int:
	# Unity wrote (level-1) % endlessLvlModif, which drops back to 0 every 4
	# levels; whole steps of 4 levels keep the game getting harder instead.
	return int((level - 1) / level_step)


func _pick(count: int, from: int) -> Array:
	var all = range(from)
	var picked = []
	count = clamp(count, 0, from)
	while picked.size() < count:
		picked.append(all.pop_at(rng.randi_range(0, all.size() - 1)))
	return picked


func _spawn_new_part():
	if parts.size() > parts_count:
		var old = parts.pop_front()
		for e in old.enemies:
			if is_instance_valid(e) and not TurnManager.battle_enemies.has(e):
				e.queue_free()
		old.node.queue_free()
	var first = spawned == 0
	var index = 0 if (first and safe_first_part) else _next_index()
	var def = part_defs[index]
	var node = Node2D.new()
	node.name = "Part%d_%s" % [spawned, def.name]
	node.position = Vector2(spawned * part_width, 0)
	add_child(node)
	var part = {"node": node, "enemies": []}
	parts.append(part)
	_build_tiles(node, def)
	# traps: Random.Range(min, max) like Unity (max excluded)
	var traps_def = def.get("traps", [])
	var mm = def.get("min_max_traps", [0, 2])
	var trap_count = 0 if (first and safe_first_part) else rng.randi_range(int(mm[0]), max(int(mm[0]), int(mm[1]) - 1))
	var raise = _raise()
	for i in _pick(trap_count, traps_def.size()):
		_build_trap(node, traps_def[i], int(round(traps_def[i].damage * pow(trap_damage_scale, raise))))
	# enemies
	var me = def.get("min_max_enemies", [0, 2])
	var enemy_count = 0 if (first and safe_first_part) else rng.randi_range(int(me[0]), max(int(me[0]), int(me[1]) - 1))
	var kinds = [0]
	if level >= 2: kinds.append(1)
	if level >= 6: kinds.append(2)
	if level >= 10: kinds.erase(0)
	var spawns = def.get("spawns", [])
	for i in _pick(enemy_count, spawns.size()):
		var kind = kinds[rng.randi_range(0, kinds.size() - 1)]
		var e = _spawn_enemy(kind, node, def, Vector2(spawns[i][0], spawns[i][1]), raise)
		if e:
			part.enemies.append(e)
	spawned += 1


func _build_tiles(node: Node2D, def):
	var body = StaticBody2D.new()
	body.name = "Floors"
	node.add_child(body)
	for r in def.get("solid", []):
		var cs = CollisionShape2D.new()
		var shape = RectangleShape2D.new()
		shape.size = Vector2(r[2], r[3])
		cs.shape = shape
		cs.position = Vector2(r[0] + r[2] / 2.0, r[1] + r[3] / 2.0)
		body.add_child(cs)
	for t in def.get("tiles", []):
		var s = Sprite2D.new()
		s.texture = load(t.tex)
		s.region_enabled = true
		s.region_rect = Rect2(t.region[0], t.region[1], t.region[2], t.region[3])
		s.centered = false
		s.position = Vector2(t.pos[0], t.pos[1])
		s.scale = Vector2.ONE * (float(t.size) / float(t.region[2]))
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.z_index = -1
		node.add_child(s)
	for d in def.get("decor", []):
		node.add_child(_sprite(d, -2))


func _sprite(d, z := 0) -> Sprite2D:
	var s = Sprite2D.new()
	s.texture = load(d.tex)
	s.region_enabled = true
	s.region_rect = Rect2(d.region[0], d.region[1], d.region[2], d.region[3])
	s.centered = false
	s.offset = Vector2(d.offset[0], d.offset[1])
	s.position = Vector2(d.pos[0], d.pos[1])
	s.scale = Vector2(d.scale[0], d.scale[1])
	s.rotation_degrees = d.get("rot", 0.0)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.z_index = z
	return s


# A spike: greed_damage_area.gd (Unity's DamageArea), hurts once when touched
func _build_trap(node: Node2D, t, damage: int):
	var area = Area2D.new()
	area.name = t.name
	area.set_script(load("res://Greed/scripts/greed_damage_area.gd"))
	area.damage = damage
	area.hide_on_enter = false
	var cs = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(t.rect[2], t.rect[3])
	cs.shape = shape
	cs.position = Vector2(t.rect[0] + t.rect[2] / 2.0, t.rect[1] + t.rect[3] / 2.0)
	area.add_child(cs)
	node.add_child(area)
	if t.has("sprite"):
		node.add_child(_sprite(t.sprite, 0))


# Top of the floor right under a spawn point (from the part's solid boxes)
func _floor_under(def, p: Vector2) -> float:
	var top = INF
	for r in def.get("solid", []):
		if p.x >= r[0] and p.x <= r[0] + r[2] and r[1] >= p.y - 60.0 and r[1] < top:
			top = r[1]
	return top


func _spawn_enemy(kind: int, node: Node2D, def, p: Vector2, raise: int):
	var stats = ENEMY_STATS[kind]
	var e = ENEMY_SCENES[kind].instantiate()
	e.set_meta("no_save", true)   # made on the fly: SaveManager doesn't remember it
	e.name = "%s_%d_%d" % [stats.name, spawned, node.get_child_count()]
	e.display_name = stats.name
	e.max_hp = int(round(stats.max_hp * pow(enemy_hp_scale, raise)))
	e.attack_damage = max(1, int(round(stats.attack_damage * pow(enemy_damage_scale, raise))))
	e.defense = 0.5
	e.set_meta("exp", int(round(stats.exp * pow(enemy_exp_scale, raise))))
	# feet on the floor (Unity's spawn points are roughly at the enemy's middle)
	var top = _floor_under(def, p)
	var cs = e.get_node_or_null("CollisionShape2D")
	var foot = 72.0
	if cs and cs.shape is RectangleShape2D:
		foot = cs.position.y + cs.shape.size.y / 2.0
	if top != INF:
		p.y = top - foot + 2.0   # 2 px into the grass, like the Greed level's dogs
	e.position = node.position + p
	add_child(e)
	e.tree_exiting.connect(_on_enemy_gone.bind(e))
	return e


# ---------------- Exp and levels (Player.AddExp) ----------------

func exp_to_level() -> int:
	return exp_to_level_base + (level - 1) * exp_per_level


func _on_enemy_gone(e):
	if game_over or not is_instance_valid(e) or e.hp > 0:
		return
	# (it's being removed right now: give the exp a moment later)
	call_deferred("add_exp", int(e.get_meta("exp", 0)), true)


func add_exp(award: int, kill := false):
	if game_over:
		return
	if kill:
		defeated += 1
	exp_points += award
	var player = _player()
	if player:
		PopupText.spawn(player, tr("+%d exp") % award, Color(0.6, 0.85, 1.0), Vector2(0, -150))
	var before = level
	while exp_points >= exp_to_level():
		exp_points -= exp_to_level()
		level += 1
	if level > before and player:
		PopupText.spawn(player, tr("Level up! Level %d") % level, Color(1, 0.85, 0.3), Vector2(0, -190), 3.0)
	_update_hud()


# ---------------- Look ----------------

func _build_background():
	# The dark castle wall from the Greed treasure room, repeating forever behind the parts
	var par = Parallax2D.new()
	par.name = "Background"
	par.scroll_scale = Vector2(0.35, 0.2)
	var tex = load("res://Greed/old-dark-castle-interior-background.png")
	var k = 3.5
	par.repeat_size = Vector2(tex.get_width() * k, 0)
	par.repeat_times = 3
	par.z_index = -100
	var s = Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.scale = Vector2(k, k)
	s.position = Vector2(-1800, -700)
	s.modulate = Color(0.55, 0.5, 0.6)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	par.add_child(s)
	add_child(par)


func _build_start():
	# A wall left of the start (Unity had a small block and the portal there)
	var body = StaticBody2D.new()
	body.name = "StartWall"
	var cs = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(200, 3000)
	cs.shape = shape
	cs.position = Vector2(-1400 - 100, -900)
	body.add_child(cs)
	add_child(body)
	var tex = load("res://Greed/TX Tileset - Dungeon Ground.png")
	for row in range(-12, 8):
		var s = Sprite2D.new()
		s.texture = tex
		s.region_enabled = true
		s.region_rect = Rect2(320, 352, 32, 32)
		s.centered = false
		s.scale = Vector2(1.75, 1.75)
		s.position = Vector2(-1456, 336 + row * 56)
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.z_index = -1
		add_child(s)


func _build_endless_hud():
	var layer = CanvasLayer.new()
	layer.name = "EndlessHUD"
	layer.layer = 5
	add_child(layer)
	hud_label = Label.new()
	hud_label.name = "Score"
	hud_label.position = Vector2(1152 - 330, 8)
	hud_label.size = Vector2(320, 60)
	hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud_label.add_theme_font_size_override("font_size", 16)
	hud_label.add_theme_color_override("font_outline_color", Color.BLACK)
	hud_label.add_theme_constant_override("outline_size", 5)
	layer.add_child(hud_label)
	exp_bar = ProgressBar.new()
	exp_bar.name = "ExpBar"
	exp_bar.position = Vector2(1152 - 170, 62)
	exp_bar.size = Vector2(160, 10)
	exp_bar.show_percentage = false
	var fill = StyleBoxFlat.new()
	fill.bg_color = Color(0.45, 0.75, 1.0)
	exp_bar.add_theme_stylebox_override("fill", fill)
	layer.add_child(exp_bar)


func _update_hud():
	if hud_label == null:
		return
	# (in a battle the enemies' health rows use the top right corner)
	hud_label.visible = not TurnManager.in_battle
	exp_bar.visible = hud_label.visible
	hud_label.text = tr("Distance: %s") % ("%.1f" % (dist / UNITS)) + "\n" \
		+ tr("Level %d") % level + "   " + tr("Defeated: %d") % defeated + "   " + tr("Best: %s") % ("%.1f" % max(best, dist / UNITS))
	exp_bar.max_value = exp_to_level()
	exp_bar.value = exp_points


# ---------------- Game over (Overmind.GameOver + EndlessHighscore) ----------------

func player_fell():
	_game_over(tr("You fell!"))


func on_player_defeated():
	_game_over(tr("You were defeated!"))


func _game_over(reason: String):
	if game_over:
		return
	game_over = true
	restarting = true
	_update_hud()
	var player = _player()
	if player:
		player.velocity = Vector2.ZERO
		player.process_mode = Node.PROCESS_MODE_DISABLED
	for e in get_tree().get_nodes_in_group("enemies"):
		e.remove_from_group("enemies")   # no new battles behind the screen
	var distance = snappedf(dist / UNITS, 0.1)
	over_layer = CanvasLayer.new()
	over_layer.name = "GameOver"
	over_layer.layer = 9
	add_child(over_layer)
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.size = Vector2(1152, 648)
	over_layer.add_child(dim)
	var panel = Panel.new()
	panel.name = "Panel"
	panel.size = Vector2(460, 260)
	panel.position = Vector2((1152 - 460) / 2.0, (648 - 260) / 2.0)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.12, 0.96)
	style.border_color = Color(0.85, 0.7, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	over_layer.add_child(panel)
	var box = VBoxContainer.new()
	box.name = "Box"
	box.position = Vector2(24, 16)
	box.size = Vector2(412, 230)
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(_label(tr("Game over"), 26, Color(1, 0.45, 0.4)))
	box.add_child(_label(reason, 15, Color(0.85, 0.85, 0.9)))
	box.add_child(_label(tr("Distance: %s") % ("%.1f" % distance) + "   " + tr("Level %d") % level + "   " + tr("Defeated: %d") % defeated, 17, Color.WHITE))
	var rank = EndlessScores.rank_of(distance, level)
	var record = distance > best and distance > 0
	box.add_child(_label(tr("New record!") if record else tr("Place %d in the high scores") % rank, 16, Color(1, 0.85, 0.3)))
	var name_row = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	var name_edit = LineEdit.new()
	name_edit.name = "NameEdit"
	name_edit.placeholder_text = tr("Your name")
	name_edit.max_length = 16
	name_edit.custom_minimum_size = Vector2(250, 34)
	var last = EndlessScores.last_name()
	if last == "":
		last = SaveManager.profile_name   # the leaderboard name from the online menu, if set
	name_edit.text = last
	name_row.add_child(name_edit)
	var save = Button.new()
	save.name = "SaveScore"
	save.text = "Save score"
	save.custom_minimum_size = Vector2(150, 34)
	name_row.add_child(save)
	box.add_child(name_row)
	var buttons = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	var again = Button.new()
	again.name = "TryAgain"
	again.text = "Try again"
	again.custom_minimum_size = Vector2(150, 40)
	again.pressed.connect(_try_again)
	var menu = Button.new()
	menu.name = "MainMenu"
	menu.text = "Main menu"
	menu.custom_minimum_size = Vector2(150, 40)
	menu.pressed.connect(_to_main_menu)
	buttons.add_child(again)
	buttons.add_child(menu)
	box.add_child(buttons)
	var submit = func():
		var id = EndlessScores.add_score(name_edit.text, distance, level, defeated)
		panel.queue_free()
		_show_board(id)
	save.pressed.connect(submit)
	name_edit.text_submitted.connect(func(_t): submit.call())
	name_edit.call_deferred("grab_focus")


# The leaderboard with your run highlighted (Unity: the "me" marker)
func _show_board(id: String):
	var board = EndlessScores.build_board_panel(over_layer, id)
	board.name = "Board"
	var buttons = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	for b in [["Try again", _try_again], ["Main menu", _to_main_menu]]:
		var button = Button.new()
		button.text = b[0]
		button.custom_minimum_size = Vector2(150, 36)
		button.pressed.connect(b[1])
		buttons.add_child(button)
	board.get_node("Box").add_child(buttons)


func _label(text: String, size: int, color: Color) -> Label:
	var l = Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _try_again():
	SaveManager.start_new_level()
	get_tree().reload_current_scene()


func _to_main_menu():
	if over_layer:
		over_layer.visible = false
	var menus = get_tree().get_first_node_in_group("menus")
	if menus and menus.has_method("_show_only"):
		menus._show_only(menus.main_menu)
