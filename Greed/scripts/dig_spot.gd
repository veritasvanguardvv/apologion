extends Node2D
# DIG SPOT (Greed, just after the start)
# A small mound of soft dirt. Walk up to it and press Dig (D on a keyboard,
# the Dig button on a phone): the sheep digs (Greed/player-dig.png) and a
# hole with stairs opens. Up (the ^ button) goes down the stairs into a
# small underground chamber with 8 verse scrolls (Greed and healing sheet
# verses); the stairs in the chamber bring you back up to the hole.
# The chamber is built in code far away from the level (like ROOM1) and is
# added to the level's rooms, so the camera and the "fell off" check work.
# Saved: the dug hole (SaveManager pickup id of the "Mound" node) and each
# scroll (same id system as greed_pickup.gd), so both stay after loading.

const PopupText = preload("res://popup_text.gd")
const DIG_SHEET = preload("res://Greed/player-dig.png")
const DIG_FRAMES = 11
const PROPS = preload("res://Greed/TX Dungeon Props.png")
const BRICKS = preload("res://Greed/TX Tileset - Dungeon Ground Dirt.png")
const SCROLL_HEAL = preload("res://General/Items/fc112.png")   # green
const SCROLL_GREED = preload("res://General/Items/fc110.png")  # red
# a small grassy hill in the level's grass style (made from Greed/tiles_32x32.png),
# drawn at the ground tiles' pixel size; the open one has the burrow + stairs
const HILL = preload("res://Greed/dig-hill.png")
const HILL_OPEN = preload("res://Greed/dig-hill-open.png")
const HILL_SCALE = 4.0812
const HILL_SINK = 6.0
const HILL_TINT = Color(1.2, 1.2, 1.1)   # a touch brighter so it reads against the dark trees
const CHIME = preload("res://Greed/SUCCESS PICKUP Collect Chime 01.wav")

# 4 Greed attack verses + 4 healing verses from data/verses.json (sheet verses
# the player doesn't start with)
const VERSES = [
	["Luke 12:15b", "greed"], ["Psalm 23:1", "heal"],
	["Luke 16:11", "greed"], ["Psalm 103:3", "heal"],
	["Acts 8:20", "greed"], ["Philippians 4:19", "heal"],
	["1 Timothy 6:10", "greed"], ["Exodus 15:26", "heal"],
]

# 7 FREE Greed scrolls out in the open right after the start (no digging
# needed), between the hill and the first Greedog. Pure Greed sheet verses,
# different from the chamber's, at walking height (no jump needed).
# [verse, offset from the hill (its feet)]
const FREE_VERSES = [
	["Matthew 6:24b", Vector2(180, -60)],
	["Hebrews 13:5a", Vector2(340, -60)],
	["Proverbs 11:28", Vector2(500, -60)],
	["Luke 12:15a", Vector2(660, -60)],
	["Proverbs 23:4", Vector2(820, -60)],
	["Luke 12:34a", Vector2(980, -60)],
	["Proverbs 15:27", Vector2(1140, -60)],
]

@export var chamber_origin = Vector2(20000, -3000)   # the chamber floor (feet), centre
@export var dig_time = 1.6                           # seconds (the 11 frames play twice)
const ROOM_W = 1152.0
const ROOM_H = 560.0     # floor to ceiling

var dug = false
var digging = false
var near = ""            # "", "dig", "down" (at the hole) or "up" (chamber stairs)
var mound_id: Node       # SaveManager id holder for the dug state
var mound: Node2D
var hole: Node2D
var chamber: Node2D
var label: Label
var room_index = -1
var dig_sprite: Sprite2D
var scrolls_left = 0     # chamber scrolls not picked up yet
var free_scrolls: Node2D
var free_scrolls_left = 0   # the free scrolls above ground


func _ready():
	add_to_group("dig_spot")
	mound_id = Node.new()
	mound_id.name = "Mound"
	add_child(mound_id)
	mound_id.owner = _level()   # (save id = level + node path)
	dug = SaveManager.is_pickup_collected(mound_id)
	_build_mound()
	_build_hole()
	_build_chamber()
	_build_free_scrolls()
	_show_state()
	call_deferred("_late_setup")


func _level():
	return owner if owner else get_tree().current_scene


func _player():
	return get_tree().get_first_node_in_group("player")


# Adds the chamber to the level's rooms; after loading a save inside it,
# makes it the current room (camera limits).
func _late_setup():
	var level = _level()
	if level == null or not ("rooms" in level):
		return
	room_index = level.rooms.size()
	level.rooms.append({"name": "DIG CHAMBER", "start": stairs_bottom(), "rect": chamber_rect()})
	var p = _player()
	if p and chamber_rect().grow(200).has_point(p.global_position):
		level.current_room = room_index
		level._apply_camera_limits()
	_build_label(level)


func chamber_rect() -> Rect2:
	return Rect2(chamber_origin.x - ROOM_W / 2.0, chamber_origin.y - ROOM_H, ROOM_W, ROOM_H + 88)


func stairs_bottom() -> Vector2:
	return chamber_origin + Vector2(-300, 0)


func hole_top() -> Vector2:
	return global_position


func in_chamber() -> bool:
	var p = _player()
	return p != null and chamber_rect().has_point(p.global_position)


# ---------------- Visuals ----------------

func _atlas(tex: Texture2D, r: Rect2) -> AtlasTexture:
	var a = AtlasTexture.new()
	a.atlas = tex
	a.region = r
	return a


func _sprite(parent: Node, tex: Texture2D, r: Rect2, pos: Vector2, s: float, bottom := true) -> Sprite2D:
	var sp = Sprite2D.new()
	sp.texture = _atlas(tex, r)
	sp.scale = Vector2(s, s)
	sp.centered = true
	sp.position = pos - (Vector2(0, r.size.y * s / 2.0) if bottom else Vector2.ZERO)
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(sp)
	return sp


func _poly(parent: Node, pts: PackedVector2Array, col: Color) -> Polygon2D:
	var p = Polygon2D.new()
	p.polygon = pts
	p.color = col
	parent.add_child(p)
	return p


# soft round glow (lights are off in this level, so "light" = additive glow)
func _glow(parent: Node, pos: Vector2, radius: float, col: Color) -> Sprite2D:
	var g = Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, col.a))
	g.set_color(1, Color(col.r, col.g, col.b, 0))
	var t = GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	var s = Sprite2D.new()
	s.texture = t
	s.position = pos
	s.scale = Vector2.ONE * radius / 64.0
	var m = CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = m
	parent.add_child(s)
	return s


# The mound: a small dirt pile (TX Dungeon Props), tinted like the level's soil
func _build_mound():
	mound = Node2D.new()
	mound.name = "MoundArt"
	add_child(mound)
	_sprite(mound, HILL, Rect2(Vector2.ZERO, HILL.get_size()), Vector2(0, HILL_SINK), HILL_SCALE).modulate = HILL_TINT
	var area = _area(self, "DigArea", Vector2(0, -40), Vector2(190, 120))
	area.body_entered.connect(func(b): _set_near(b, "dig_or_down", true))
	area.body_exited.connect(func(b): _set_near(b, "dig_or_down", false))


# The opened hill: a burrow in its side with stone steps going down
func _build_hole():
	hole = Node2D.new()
	hole.name = "Hole"
	add_child(hole)
	_sprite(hole, HILL_OPEN, Rect2(Vector2.ZERO, HILL_OPEN.get_size()), Vector2(0, HILL_SINK), HILL_SCALE).modulate = HILL_TINT


func _build_chamber():
	chamber = Node2D.new()
	chamber.name = "Chamber"
	add_child(chamber)
	chamber.position = chamber_origin - global_position   # (the dig spot doesn't move)
	var W = ROOM_W
	var H = ROOM_H
	# behind the walls (the screen is a bit taller than the room)
	var back = ColorRect.new()
	back.color = Color(0.03, 0.025, 0.02)
	back.position = Vector2(-W, -H - 400)
	back.size = Vector2(W * 2, H + 900)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chamber.add_child(back)
	# brick wall (the same golden dungeon bricks as the Greed rooms)
	var wall = NinePatchRect.new()
	wall.texture = BRICKS
	wall.region_rect = Rect2(0, 0, 96, 96)
	for m in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		wall.set_patch_margin(m, 32)
	wall.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
	wall.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE
	wall.position = Vector2(-W / 2.0, -H)
	wall.size = Vector2(W / 4.0, (H + 40) / 4.0)
	wall.scale = Vector2(4, 4)
	wall.modulate = Color(0.62, 0.55, 0.45)
	wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chamber.add_child(wall)
	# floor: a row of brick ledges
	var floor_art = NinePatchRect.new()
	floor_art.texture = BRICKS
	floor_art.region_rect = Rect2(0, 384, 96, 32)
	floor_art.set_patch_margin(SIDE_LEFT, 32)
	floor_art.set_patch_margin(SIDE_RIGHT, 32)
	floor_art.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
	floor_art.position = Vector2(-W / 2.0, -4)
	floor_art.size = Vector2(W / 4.0, 24)
	floor_art.scale = Vector2(4, 4)
	floor_art.modulate = Color(0.85, 0.78, 0.65)
	floor_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chamber.add_child(floor_art)
	# collision: floor, walls, ceiling
	var body = StaticBody2D.new()
	body.name = "ChamberBody"
	chamber.add_child(body)
	for r in [Rect2(-W / 2.0 - 40, 0, W + 80, 120), Rect2(-W / 2.0 - 60, -H - 60, 60, H + 180),
			Rect2(W / 2.0, -H - 60, 60, H + 180), Rect2(-W / 2.0, -H - 60, W, 60)]:
		var cs = CollisionShape2D.new()
		var rs = RectangleShape2D.new()
		rs.size = r.size
		cs.shape = rs
		cs.position = r.get_center()
		body.add_child(cs)
	# stairs up (left), with the daylight from the hole above them
	var stairs = _sprite(chamber, PROPS, Rect2(864, 350, 147, 98), Vector2(-W / 2.0 + 150, 0), 2.6)
	stairs.flip_h = true
	_poly(chamber, PackedVector2Array([Vector2(-W / 2.0 + 20, -H), Vector2(-W / 2.0 + 150, -H),
		Vector2(-W / 2.0 + 260, -250), Vector2(-W / 2.0 + 40, -250)]), Color(1.0, 0.95, 0.75, 0.10))
	_glow(chamber, Vector2(-W / 2.0 + 90, -H + 10), 260, Color(1.0, 0.95, 0.75, 0.35))
	var up = _area(chamber, "StairsUp", Vector2(-W / 2.0 + 200, -60), Vector2(330, 140))
	up.body_entered.connect(func(b): _set_near(b, "up", true))
	up.body_exited.connect(func(b): _set_near(b, "up", false))
	# lanterns, a chandelier, money sacks and a chest (Greed!)
	for x in [-60.0, 380.0]:
		_sprite(chamber, PROPS, Rect2(714, 298, 12, 22), Vector2(x, -250), 4.0)
		_glow(chamber, Vector2(x, -290), 300, Color(1.0, 0.7, 0.3, 0.45))
	_sprite(chamber, PROPS, Rect2(650, 289, 43, 29), Vector2(160, -H + 116), 4.0)
	_glow(chamber, Vector2(160, -H + 110), 380, Color(1.0, 0.75, 0.35, 0.35))
	_sprite(chamber, PROPS, Rect2(870, 134, 21, 26), Vector2(470, 0), 3.0)
	_sprite(chamber, PROPS, Rect2(900, 138, 25, 22), Vector2(520, 0), 3.0)
	_sprite(chamber, PROPS, Rect2(834, 225, 29, 31), Vector2(-160, 0), 3.0)
	_sprite(chamber, preload("res://Greed/TX Dungeon Props Animation.png"), Rect2(31, 548, 34, 28), Vector2(420, 0), 3.0)
	# the 8 scrolls
	for i in VERSES.size():
		_build_scroll(chamber, "Scroll%d" % (i + 1), VERSES[i][0], VERSES[i][1], Vector2(-130 + i * 80, -60 - (i % 2) * 70))


# The 7 free Greed scrolls above ground (same scrolls, saved the same way)
func _build_free_scrolls():
	free_scrolls = Node2D.new()
	free_scrolls.name = "FreeScrolls"
	add_child(free_scrolls)
	for i in FREE_VERSES.size():
		var s = _build_scroll(free_scrolls, "FreeScroll%d" % (i + 1), FREE_VERSES[i][0], "greed", FREE_VERSES[i][1])
		if s:
			s.set_meta("free", true)
			free_scrolls_left += 1


func _area(parent: Node, n: String, pos: Vector2, size: Vector2) -> Area2D:
	var a = Area2D.new()
	a.name = n
	a.position = pos
	a.monitorable = false
	var cs = CollisionShape2D.new()
	var rs = RectangleShape2D.new()
	rs.size = size
	cs.shape = rs
	a.add_child(cs)
	parent.add_child(a)
	return a


# A verse scroll (walk into it to pick it up). Returns it (null if it was
# already collected in this save). Chamber scrolls count in scrolls_left.
func _build_scroll(parent: Node, n: String, ref: String, kind: String, pos: Vector2) -> Area2D:
	var s = Area2D.new()
	s.name = n
	s.set_meta("verse", ref)
	s.set_meta("kind", kind)
	s.position = pos
	s.monitorable = false
	parent.add_child(s)
	s.owner = _level()
	if SaveManager.is_pickup_collected(s):
		s.queue_free()
		return null
	if parent == chamber:
		scrolls_left += 1
	var cs = CollisionShape2D.new()
	var cc = CircleShape2D.new()
	cc.radius = 34
	cs.shape = cc
	s.add_child(cs)
	_glow(s, Vector2.ZERO, 70, Color(0.5, 1.0, 0.55, 0.45) if kind == "heal" else Color(1.0, 0.45, 0.3, 0.45))
	var icon = Sprite2D.new()
	icon.name = "Icon"
	icon.texture = SCROLL_HEAL if kind == "heal" else SCROLL_GREED
	icon.scale = Vector2.ONE * (48.0 / max(icon.texture.get_width(), icon.texture.get_height()))
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.add_child(icon)
	var t = s.create_tween().set_loops()
	t.tween_property(icon, "position:y", -6.0, 1.0).set_trans(Tween.TRANS_SINE)
	t.tween_property(icon, "position:y", 6.0, 1.0).set_trans(Tween.TRANS_SINE)
	s.body_entered.connect(func(b): _collect(s, b))
	return s


func _collect(s: Area2D, body):
	if not body.is_in_group("player") or s.is_queued_for_deletion():
		return
	var ref = s.get_meta("verse")
	var was_new = not VerseManager.is_discovered(ref)
	if body.has_method("discover_verse"):
		body.discover_verse(ref)
	else:
		VerseManager.discover(ref)
	var msg = tr("New verse discovered: %s!") % VerseManager.ref_text(ref)
	if body.has_method("_show_verse_message"):
		body._show_verse_message(msg)
	PopupText.spawn(body, ("+ " if was_new else "") + VerseManager.ref_text(ref),
		Color(0.6, 1.0, 0.6) if s.get_meta("kind") == "heal" else Color(1.0, 0.75, 0.4))
	var p = AudioStreamPlayer.new()
	p.stream = CHIME
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
	SaveManager.mark_pickup_collected(s)
	if s.get_meta("free", false):
		free_scrolls_left -= 1
	else:
		scrolls_left -= 1
	s.queue_free()


func _build_label(level):
	label = Label.new()
	label.name = "DigPrompt"
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.position = Vector2(-220, 190)
	label.size = Vector2(440, 30)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	label.visible = false
	var layer = level.prompt.get_parent() if "prompt" in level and level.prompt else null
	if layer == null:
		layer = CanvasLayer.new()
		add_child(layer)
	layer.add_child(label)


func _show_state():
	mound.visible = not dug
	hole.visible = dug


# ---------------- Prompt / input ----------------

var _near_dig = false
var _near_up = false
func _set_near(b, which, on):
	if not b.is_in_group("player"):
		return
	if which == "up":
		_near_up = on
	else:
		_near_dig = on


func _touch() -> bool:
	return TouchControls.has_method("wanted") and TouchControls.wanted()


func _process(_delta):
	var p = _player()
	var busy = p == null or digging or TurnManager.in_battle or p.get("cutscene_lock") == true
	near = ""
	if not busy:
		if _near_up and in_chamber():
			near = "up"
		elif _near_dig:
			near = "down" if dug else "dig"
	if label:
		label.visible = near != ""
		match near:
			"dig":
				label.text = GameSettings.control_prompt("Press %s to dig", "dig", "Tap Dig to dig")
			"down":
				label.text = GameSettings.control_prompt("Press %s to go down", "interact", "Tap ^ to go down", "Press Up to go down")
			"up":
				label.text = GameSettings.control_prompt("Press %s to go up", "interact", "Tap ^ to go up", "Press Up to go up")
	if "contextual" in TouchControls:
		TouchControls.contextual["Dig"] = near == "dig"


func _unhandled_input(event):
	if near == "" or event.is_echo():
		return
	var p = _player()
	if p and p.verse_input and p.verse_input.has_focus():
		return
	if near == "dig" and event.is_action_pressed("dig"):
		get_viewport().set_input_as_handled()
		dig()
	elif near == "down" and event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		go_down()
	elif near == "up" and event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		go_up()


# ---------------- Actions ----------------

signal dig_frame(frame: int)
signal dug_open

func dig():
	if dug or digging:
		return
	var p = _player()
	if p == null:
		return
	digging = true
	p.cutscene_lock = true
	p.velocity.x = 0
	var body = p.get_node_or_null("Sprite2D")
	dig_sprite = Sprite2D.new()
	dig_sprite.name = "DigSprite"
	dig_sprite.texture = DIG_SHEET
	dig_sprite.hframes = DIG_FRAMES
	dig_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if body:
		dig_sprite.position = body.position
		dig_sprite.scale = body.scale * 5.0   # 256 px frames vs the 1280 px walk frames
		dig_sprite.z_index = body.z_index
		body.visible = false
	p.add_child(dig_sprite)
	var per = dig_time / (DIG_FRAMES * 2)
	for loop in 2:
		for f in DIG_FRAMES:
			dig_sprite.frame = f
			dig_frame.emit(f)
			if f == 7 and loop == 1:
				dug = true       # the dirt flies: the hole opens
				_show_state()
			await get_tree().create_timer(per).timeout
			if not is_instance_valid(p):
				return
	p.remove_child(dig_sprite)
	dig_sprite.queue_free()
	dig_sprite = null
	if body:
		body.visible = true
	p.cutscene_lock = false
	digging = false
	dug = true
	_show_state()
	SaveManager.mark_pickup_collected(mound_id)
	PopupText.spawn(p, tr("A secret stairway!"), Color(1, 0.9, 0.5))
	dug_open.emit()


func go_down():
	_move_party_to(stairs_bottom())


func go_up():
	_move_party_to(hole_top() + Vector2(30, 0))


func _move_party_to(pos: Vector2):
	var level = _level()
	if level and level.has_method("teleport_player"):
		level.teleport_player(pos)
	# spread the followers out a little (teleport_player stacks them)
	var i = 0
	for m in get_tree().get_nodes_in_group("party"):
		m.global_position = pos + Vector2(-90 - 55 * i, -4)
		if "velocity" in m:
			m.velocity = Vector2.ZERO
		i += 1
	_near_dig = false
	_near_up = false


func _exit_tree():
	if "contextual" in TouchControls:
		TouchControls.contextual.erase("Dig")
