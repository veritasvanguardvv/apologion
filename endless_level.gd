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
# Your verses and items come along (no party companions); health starts full.
# Falling into a pit ends the run even in Baby Mode (no soft respawn).
# No clay pots in Endless (greed_level.gd builds them for the story level).
# Two separate leaderboards (endless_scores.gd): the run's mode (Baby Mode or
# typing) is locked when the run starts (run_mode) - switching Baby Mode in
# Settings mid-run doesn't move the run to the other board; the next run
# (Try again / Start Endless) goes on the new mode's board. Each run counts
# verses_heard (Baby Mode reading a verse out loud) and verses_typed (a verse
# typed or spoken that worked); the board shows its mode's count.

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
# Floating blocks (see _prepare_part): never less than this between a block
# and a floor/ledge it overlaps horizontally (player is 69.5 px tall and
# jumps 201 px, so a smaller gap is a wedge you can get stuck in).
@export var block_clearance = 200.0
@export var block_side_margin = 43.0     # half the player's width: closer than this counts as overlapping
@export var reach_rise = 185.0           # a moved block must stay reachable (gold jump: 172, steps are 56)
@export var reach_cols = 5               # ...from a ledge at most this many columns away
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
var prepared = {}              # part index -> part definition with floating blocks fixed
var run_mode = "typing"        # EndlessScores.MODE_TYPING / MODE_BABY, locked at run start
var verses_heard = 0           # this run: verses Baby Mode read out loud
var verses_typed = 0           # this run: verses typed / spoken that worked

var hud_label: Label
var exp_bar: ProgressBar
var over_layer: CanvasLayer


func _ready():
	rng.randomize()
	add_to_group("no_save")        # Endless never saves (save_manager.gd)
	add_to_group("endless")
	SaveManager.begin_endless()
	run_mode = EndlessScores.MODE_BABY if BabyMode.is_on() else EndlessScores.MODE_TYPING
	BabyMode.verse_heard.connect(_on_verse_heard)
	rooms = []
	use_camera_limits = false
	super._ready()
	var data = JSON.parse_string(FileAccess.get_file_as_string(PARTS_FILE))
	part_defs = data.parts
	part_width = float(data.part_width)
	best = EndlessScores.best_distance(run_mode)
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
	if player.has_signal("verse_recited") and not player.verse_recited.is_connected(_on_verse_recited):
		player.verse_recited.connect(_on_verse_recited)
	player_start_x = _feet(player).x
	player_max_x = player_start_x
	to_spawn_new_part = part_width
	started = true
	_update_hud()


func _feet(player) -> Vector2:
	var cs = player.get_node("CollisionShape2D")
	return cs.global_position + Vector2(0, cs.shape.size.y / 2.0 * cs.global_scale.y)


# No pots in Endless (the story level's pots are greed_level.gd POTS)
func _build_pots():
	pass


func _on_verse_heard(_v):
	if started and not game_over:
		verses_heard += 1
		_update_hud()


func _on_verse_recited(_v):
	if started and not game_over:
		verses_typed += 1
		_update_hud()


# The stat this run's board shows
func run_verses() -> int:
	return verses_heard if run_mode == EndlessScores.MODE_BABY else verses_typed


func run_verses_text() -> String:
	return (tr("Verses heard: %d") if run_mode == EndlessScores.MODE_BABY else tr("Verses typed: %d")) % run_verses()


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
	var def = _prepare_part(index)
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


# ---------------- Floating blocks ----------------
# The Unity parts have squares floating in the air. Some float only 56-168 px
# above a ledge: just enough room to get wedged under them. Here every
# floating group of squares (not touching the ground structure) is checked:
# it keeps at least block_clearance px of air above/below anything it overlaps
# horizontally, else it is moved up (or down) a few rows if it stays reachable,
# else removed. Groups that can't be reached any more are removed too. Spikes,
# enemy spawns and decorations sitting on a block go with it. Ground-connected
# squares (the floor, pillars, stepping stones) are never touched, so pits stay
# crossable. Floating blocks become endless_block.gd bodies that a Ram breaks.

func _prepare_part(index: int) -> Dictionary:
	if prepared.has(index):
		return prepared[index]
	var def = prepare_part_def(part_defs[index], part_width, block_clearance, block_side_margin, reach_rise, reach_cols)
	if def.block_log.size() > 0:
		print("Endless ", def.name, ": ", ", ".join(def.block_log))
	prepared[index] = def
	return def


# Static so tests can run it on every part without a level.
static func prepare_part_def(src: Dictionary, width: float, clearance: float, margin: float, rise: float, cols_reach: int) -> Dictionary:
	var def = src.duplicate(true)
	var c = float(src.get("cell", 56.0))
	var ox = -width - c                       # local x of column 0
	var ncols = int(round(width / c))
	var cells = {}
	for r in src.get("solid", []):
		var x0 = int(round((r[0] - ox) / c))
		var y0 = int(round(r[1] / c))
		for i in int(round(r[2] / c)):
			for j in int(round(r[3] / c)):
				cells[Vector2i(x0 + i, y0 + j)] = true
	# groups of touching squares
	var seen = {}
	var groups = []
	var keys = cells.keys()
	keys.sort()
	for k in keys:
		if seen.has(k):
			continue
		var g = []
		var stack = [k]
		seen[k] = true
		while stack.size() > 0:
			var a = stack.pop_back()
			g.append(a)
			for n in [a + Vector2i(1, 0), a + Vector2i(-1, 0), a + Vector2i(0, 1), a + Vector2i(0, -1)]:
				if cells.has(n) and not seen.has(n):
					seen[n] = true
					stack.append(n)
		groups.append(g)
	var ground_row = -1000
	for k in keys:
		if k.x == 0:
			ground_row = max(ground_row, k.y)
	if ground_row == -1000:
		for k in keys:
			ground_row = max(ground_row, k.y)
	var ground = {}
	var floating = []
	for g in groups:
		var bottom = -1000
		for a in g:
			bottom = max(bottom, a.y)
		if bottom >= ground_row:
			for a in g:
				ground[a] = true
		else:
			floating.append(g)
	floating.sort_custom(func(a, b): return _bottom_row(a) > _bottom_row(b))   # lowest first
	var placed = ground.duplicate()
	var kept = []      # [{ "src": group, "dy": rows moved, "cells": moved group }]
	var notes = []
	for g in floating:
		var done = false
		for dy in [0, -1, -2, -3, -4, 1, 2]:
			var ng = []
			for a in g:
				ng.append(a + Vector2i(0, dy))
			var min_x = 1000
			var max_x = -1000
			for a in ng:
				min_x = min(min_x, a.x)
				max_x = max(max_x, a.x)
			if min_x < 1 or max_x > ncols - 2:
				break       # next to the part's edge: the neighbour part is unknown
			if _clear_of(ng, placed, c, clearance, margin) and (dy == 0 or _reachable(ng, placed, c, rise, cols_reach)):
				for a in ng:
					placed[a] = true
				kept.append({"src": g, "dx": 0, "dy": dy, "cells": ng})
				if dy != 0:
					notes.append("block at %s moved %+d px" % [str(g[0]), dy * int(c)])
				done = true
				break
		if not done:
			notes.append("block at %s removed (too close to a ledge)" % str(g[0]))
	# drop blocks you can't get to any more
	var reach = _tops(ground.keys())
	var changed = true
	while changed:
		changed = false
		for k in kept:
			var t = _tops(k.cells)
			if reach.has(t.keys()[0]):
				continue
			var ok = false
			for b in t:
				for a in reach.keys():
					var up = (a.y - b.y) * c
					if (up <= rise and abs(a.x - b.x) <= cols_reach) or (up <= 0 and abs(a.x - b.x) <= cols_reach + 3):
						ok = true
						break
				if ok:
					break
			if ok:
				for b in t:
					reach[b] = true
				changed = true
	var final = []
	for k in kept:
		if reach.has(_tops(k.cells).keys()[0]):
			final.append(k)
		else:
			notes.append("block at %s removed (out of reach)" % str(k.src[0]))
	# Never lose the way across: if the part could be crossed before but not
	# now, a floating block was a stepping stone - put it somewhere nearby
	# that keeps the clearance AND keeps the part crossable.
	var cross_rise = 120.0      # stepping stones must stay easy to reach, also with gold (jump 172)
	var stone_clear = 110.0     # player is 69.5 px tall
	if _crossable(cells, cross_rise, ncols) and not _crossable(_with_blocks(ground, final), cross_rise, ncols):
		var fixed = false
		for g in floating:
			var others = []
			for k in final:
				if k.src != g:
					others.append(k)
			var base = _with_blocks(ground, others)
			for dy in [0, -1, 1, -2, 2, -3, 3]:
				for dx in [0, -1, 1, -2, 2]:
					var ng = []
					for a in g:
						ng.append(a + Vector2i(dx, dy))
					if not _clear_of(ng, base, c, clearance, margin):
						continue
					var trial = base.duplicate()
					for a in ng:
						trial[a] = true
					if _crossable(trial, cross_rise, ncols):
						final = others
						final.append({"src": g, "dx": dx, "dy": dy, "cells": ng})
						notes.append("stepping stone at %s placed at %+d,%+d px" % [str(g[0]), dx * int(c), dy * int(c)])
						fixed = true
						break
				if fixed:
					break
			if fixed:
				break
		if not fixed:
			# No spot keeps the full clearance: the stepping stone stays where
			# Unity had it, as long as there's still far more room under it than
			# the player is tall (stone_clearance), so you can't get wedged.
			for g in floating:
				var others = []
				for k in final:
					if k.src != g:
						others.append(k)
				var base = _with_blocks(ground, others)
				if not _clear_of(g, base, c, stone_clear, margin):
					continue
				var trial = base.duplicate()
				for a in g:
					trial[a] = true
				if _crossable(trial, cross_rise, ncols):
					final = others
					final.append({"src": g, "dx": 0, "dy": 0, "cells": g, "stone": true})
					notes.append("stepping stone at %s kept in place (needed to cross; at least %d px of room)" % [str(g[0]), int(stone_clear)])
					fixed = true
					break
		if not fixed:
			notes.append("could not keep the clearance without blocking the way: original kept")
			final = []
			for g in floating:
				final.append({"src": g, "dx": 0, "dy": 0, "cells": g, "stone": true})
	# build the new solid boxes, tiles, blocks; move or drop what sits on blocks
	var src_of = {}      # original cell -> index in final (or -1 = removed)
	for g in floating:
		for a in g:
			src_of[a] = -1
	for i in final.size():
		for a in final[i].src:
			src_of[a] = i
	def.solid = _row_runs(ground.keys(), ox, c)
	def.blocks = []
	for k in final:
		def.blocks.append({"solid": _row_runs(k.cells, ox, c), "tiles": [], "dx": k.dx, "dy": k.dy, "stone": k.get("stone", false)})
	var tiles = []
	for t in src.get("tiles", []):
		var cell = Vector2i(int(round((t.pos[0] - ox) / c)), int(round(t.pos[1] / c)))
		if not src_of.has(cell):
			tiles.append(t)
		elif src_of[cell] >= 0:
			var nt = t.duplicate(true)
			nt.pos = [t.pos[0] + final[src_of[cell]].dx * c, t.pos[1] + final[src_of[cell]].dy * c]
			def.blocks[src_of[cell]].tiles.append(nt)
	def.tiles = tiles
	var on_block = func(px: float, py: float) -> int:
		# -2 = not on a floating block, else the src_of value of the block under it
		var cx = int(floor((px - ox) / c))
		var first_row = int(ceil(py / c))       # the first square whose top is below the point
		for row in range(first_row, first_row + 3):
			var a = Vector2i(cx, row)
			if cells.has(a):
				return src_of[a] if src_of.has(a) else -2
		return -2
	var traps = []
	for t in src.get("traps", []):
		var w = on_block.call(t.rect[0] + t.rect[2] / 2.0, t.rect[1] + t.rect[3] / 2.0)
		if w == -2:
			traps.append(t)
		elif w >= 0:
			var nt = t.duplicate(true)
			var sx = final[w].dx * c
			var shift = final[w].dy * c
			nt.rect = [t.rect[0] + sx, t.rect[1] + shift, t.rect[2], t.rect[3]]
			if nt.has("sprite"):
				nt.sprite.pos = [t.sprite.pos[0] + sx, t.sprite.pos[1] + shift]
			traps.append(nt)
	def.traps = traps
	var spawns = []
	for p in src.get("spawns", []):
		var w = on_block.call(p[0], p[1])
		if w == -2:
			spawns.append(p)
		elif w >= 0:
			spawns.append([p[0] + final[w].dx * c, p[1] + final[w].dy * c])
	def.spawns = spawns
	var decor = []
	for d in src.get("decor", []):
		var w = on_block.call(d.pos[0], d.pos[1])
		if w == -2:
			decor.append(d)
		elif w >= 0:
			var nd = d.duplicate(true)
			nd.pos = [d.pos[0] + final[w].dx * c, d.pos[1] + final[w].dy * c]
			decor.append(nd)
	def.decor = decor
	def.block_log = notes
	return def


static func _with_blocks(ground: Dictionary, blocks: Array) -> Dictionary:
	var out = ground.duplicate()
	for k in blocks:
		for a in k.cells:
			out[a] = true
	return out


# Coarse: can you get from the floor at the left edge to the floor at the
# right edge? Up to `rise` px up; how far across depends on how high
# (with gold: 56 px up -> 6 columns, 112 -> 5, 168 -> 3), dropping down is easy.
static func _crossable(cells: Dictionary, rise: float, ncols: int) -> bool:
	var tops = []
	for k in cells.keys():
		if not cells.has(k + Vector2i(0, -1)) and not cells.has(k + Vector2i(0, -2)):
			tops.append(k)
	var start = null
	for t in tops:
		if t.x == 0 and (start == null or t.y < start.y):
			start = t
	if start == null:
		return false
	var seen = {start: true}
	var queue = [start]
	while queue.size() > 0:
		var a = queue.pop_front()
		if a.x >= ncols - 4:
			return true
		for b in tops:
			if seen.has(b):
				continue
			var up = (a.y - b.y) * 56.0
			var dx = abs(a.x - b.x)
			if (up > 0 and up <= rise and dx <= _jump_cols(up)) or (up <= 0 and dx <= 6 + int(-up / 56.0)):
				seen[b] = true
				queue.append(b)
	return false


static func _jump_cols(up: float) -> int:
	if up <= 60.0:
		return 6
	if up <= 115.0:
		return 5
	return 3


static func _bottom_row(g: Array) -> int:
	var b = -1000
	for a in g:
		b = max(b, a.y)
	return b


# The top squares of a group (nothing right above them): where you stand.
static func _tops(g: Array) -> Dictionary:
	var members = {}
	for a in g:
		members[a] = true
	var tops = {}
	for a in g:
		if not members.has(a + Vector2i(0, -1)):
			tops[a] = true
	return tops


# Is the group clear of everything placed so far? Squares overlapping it
# horizontally (closer than margin) must be at least `clearance` px away
# vertically; squares in the same row must not touch it.
static func _clear_of(g: Array, placed: Dictionary, c: float, clearance: float, margin: float) -> bool:
	for a in g:
		for b in placed.keys():
			if b.x * c < (a.x + 1) * c + margin and (b.x + 1) * c > a.x * c - margin:
				if b.y == a.y:
					if abs(b.x - a.x) <= 1:
						return false
					continue
				var gap = (b.y - a.y - 1) * c if b.y > a.y else (a.y - b.y - 1) * c
				if gap < clearance:
					return false
	return true


# Can you jump onto the group from some surface already placed?
static func _reachable(g: Array, placed: Dictionary, c: float, rise: float, cols_reach: int) -> bool:
	var surfaces = _tops(placed.keys())
	for b in _tops(g).keys():
		for a in surfaces.keys():
			var up = (a.y - b.y) * c
			if up > 0 and up <= rise and abs(a.x - b.x) <= cols_reach:
				return true
	return false


# Squares -> boxes [x, y, w, h], one per run of squares in a row
static func _row_runs(g: Array, ox: float, c: float) -> Array:
	var sorted = g.duplicate()
	sorted.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var out = []
	var i = 0
	while i < sorted.size():
		var start = sorted[i]
		var n = 1
		while i + n < sorted.size() and sorted[i + n].y == start.y and sorted[i + n].x == start.x + n:
			n += 1
		out.append([ox + start.x * c, start.y * c, n * c, c])
		i += n
	return out


func _build_tiles(node: Node2D, def):
	_build_blocks(node, def)
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
		node.add_child(_tile_sprite(t))
	for d in def.get("decor", []):
		node.add_child(_sprite(d, -2))


func _tile_sprite(t) -> Sprite2D:
	var s = Sprite2D.new()
	s.texture = load(t.tex)
	s.region_enabled = true
	s.region_rect = Rect2(t.region[0], t.region[1], t.region[2], t.region[3])
	s.centered = false
	s.position = Vector2(t.pos[0], t.pos[1])
	s.scale = Vector2.ONE * (float(t.size) / float(t.region[2]))
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.z_index = -1
	return s


# Floating blocks: each one its own body so a Ram can break it
func _build_blocks(node: Node2D, def):
	var i = 0
	for b in def.get("blocks", []):
		var body = StaticBody2D.new()
		body.name = "Block%d" % i
		body.set_script(load("res://endless_block.gd"))
		body.add_to_group("endless_blocks")
		body.set_meta("stepping_stone", b.get("stone", false))
		node.add_child(body)
		for r in b.solid:
			var cs = CollisionShape2D.new()
			var shape = RectangleShape2D.new()
			shape.size = Vector2(r[2], r[3])
			cs.shape = shape
			cs.position = Vector2(r[0] + r[2] / 2.0, r[1] + r[3] / 2.0)
			body.add_child(cs)
		for t in b.tiles:
			body.add_child(_tile_sprite(t))
		i += 1


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
	var rects = def.get("solid", []).duplicate()
	for b in def.get("blocks", []):
		rects.append_array(b.solid)
	for r in rects:
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
	par.scroll_scale = Vector2(1, 1)
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
	hud_label.size = Vector2(320, 80)
	hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud_label.add_theme_font_size_override("font_size", 16)
	hud_label.add_theme_color_override("font_outline_color", Color.BLACK)
	hud_label.add_theme_constant_override("outline_size", 5)
	layer.add_child(hud_label)
	exp_bar = ProgressBar.new()
	exp_bar.name = "ExpBar"
	exp_bar.position = Vector2(1152 - 170, 84)
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
		+ tr("Level %d") % level + "   " + tr("Defeated: %d") % defeated + "   " + tr("Best: %s") % ("%.1f" % max(best, dist / UNITS)) \
		+ "\n" + run_verses_text()
	exp_bar.max_value = exp_to_level()
	exp_bar.value = exp_points


# ---------------- Game over (Overmind.GameOver + EndlessHighscore) ----------------

func player_fell():
	# Pit = run over (high score). Baby Mode must NOT put you back up here.
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
	panel.size = Vector2(460, 290)
	panel.position = Vector2((1152 - 460) / 2.0, (648 - 290) / 2.0)
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
	box.size = Vector2(412, 260)
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(_label(tr("Game over"), 26, Color(1, 0.45, 0.4)))
	box.add_child(_label(reason, 15, Color(0.85, 0.85, 0.9)))
	box.add_child(_label(tr("Distance: %s") % ("%.1f" % distance) + "   " + tr("Level %d") % level + "   " + tr("Defeated: %d") % defeated, 17, Color.WHITE))
	box.add_child(_label(run_verses_text() + "   (" + tr(EndlessScores.BOARD_TITLE[run_mode]) + ")", 15, Color(0.85, 0.85, 0.9)))
	var rank = EndlessScores.rank_of(distance, level, run_mode)
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
		var id = EndlessScores.add_score(name_edit.text, distance, level, defeated, run_mode, run_verses())
		panel.queue_free()
		_show_board(id)
	save.pressed.connect(submit)
	name_edit.text_submitted.connect(func(_t): submit.call())
	name_edit.call_deferred("grab_focus")


# The leaderboard with your run highlighted (Unity: the "me" marker)
func _show_board(id: String):
	var board = EndlessScores.build_board_panel(over_layer, id, run_mode)
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
