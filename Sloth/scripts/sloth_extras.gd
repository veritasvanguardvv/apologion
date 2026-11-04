extends Node2D
# SLOTH LEVEL EXTRAS (a child of Sloth.tscn, builds its parts in code)
# --------------------------------------------------------------------
#  - Kill floor: falling below KILL_Y (missing a platform) = you die and are
#    put back on the last ground you stood on. Normal mode: costs
#    FALL_DAMAGE_PCT of your max HP (if that would be your last HP it's a real
#    death: back to the checkpoint / level start like any other death).
#    Baby Mode: nothing is lost, just put back. Party members come along.
#  - Zeal gaps: east of the big floor, platforms with gaps too wide to jump
#    (even ramming) unless Zeal is on (Romans 12:11 / Isaiah 40:31a / a Zeal
#    Scroll: 7 s of double speed and a much higher jump).
#  - Graveyard: open graves (pits) you can't jump out of without Zeal. A Zeal
#    Scroll lies before the first grave and between each two graves; if you
#    are stuck in a grave with no Zeal Scroll, one appears there (no
#    soft-lock). The kill floor is far below the graves.

const PopupText = preload("res://popup_text.gd")
const GROUND_Y = 566.5           # top of the big floor (Floor2)
const KILL_Y = 1350.0            # body below this = fell out of the level
const FALL_DAMAGE_PCT = 0.2
const GAP = 520.0                # normal max (ram-jump) ~360 px, Zeal ~570+
const PLATFORM_DEPTH = 160.0
# [left, right] of each piece of ground, top at GROUND_Y
const PLATFORMS = [[3365.0, 3665.0], [4185.0, 4485.0]]
const GRAVEYARD = [5005.0, 7900.0]
const PIT_W = 200.0
const PIT_DEPTH = 200.0          # normal jump ~82 px high, Zeal ~250 px
const PITS = [5500.0, 6200.0, 6900.0]   # left edge of each grave
const SCROLLS_X = [5300.0, 5950.0, 6650.0]   # before / between the graves

var player: CharacterBody2D
var last_safe = null             # player origin on solid ground
var falling_handled = false
var pit_time = 0.0
var pit_rescued = {}             # pit index -> true once a rescue scroll appeared
var marble: Texture2D

func _ready():
	player = get_parent().get_node_or_null("CharacterBody2D")
	if player == null:
		await get_parent().ready
		player = get_parent().get_node_or_null("CharacterBody2D")
	marble = load("res://Sloth/BG pngs/Marble stone.JPG")
	for p in PLATFORMS:
		_add_block(Rect2(p[0], GROUND_Y, p[1] - p[0], PLATFORM_DEPTH), "ZealPlatform")
	_build_graveyard()

# ---------------- building ----------------

func _add_block(r: Rect2, nm: String, tint := Color(1, 1, 1)) -> StaticBody2D:
	var b = StaticBody2D.new()
	b.name = nm
	b.position = r.get_center()
	var cs = CollisionShape2D.new()
	var sh = RectangleShape2D.new()
	sh.size = r.size
	cs.shape = sh
	b.add_child(cs)
	var s = Sprite2D.new()
	s.texture = marble
	s.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	s.region_enabled = true
	s.region_rect = Rect2(0, 0, r.size.x / 0.6, r.size.y / 0.6)
	s.scale = Vector2(0.6, 0.6)
	s.modulate = tint
	b.add_child(s)
	add_child(b)
	return b

func _build_graveyard():
	var g0 = GRAVEYARD[0]
	var g1 = GRAVEYARD[1]
	var stone = Color(0.72, 0.7, 0.78)
	# ground pieces between the graves, and each grave's floor and walls
	var x = g0
	for i in PITS.size():
		var px = PITS[i]
		_add_block(Rect2(x, GROUND_Y, px - x, PLATFORM_DEPTH + PIT_DEPTH), "GraveGround%d" % i, stone)
		_add_block(Rect2(px, GROUND_Y + PIT_DEPTH, PIT_W, PLATFORM_DEPTH), "GraveFloor%d" % i, Color(0.45, 0.38, 0.34))
		x = px + PIT_W
		# a tombstone at the head of the grave, and a sunken one inside it
		_add_tomb(Vector2(px - 40, GROUND_Y), 1.0)
		_add_tomb(Vector2(px + PIT_W * 0.5, GROUND_Y + PIT_DEPTH), 0.8)
	_add_block(Rect2(x, GROUND_Y, g1 - x, PLATFORM_DEPTH + PIT_DEPTH), "GraveGroundEnd", stone)
	for tx in [g0 + 90, g0 + 220, g1 - 300, g1 - 160]:
		_add_tomb(Vector2(tx, GROUND_Y), 1.0)
	var sign = Label.new()
	sign.text = tr("Graveyard")
	sign.position = Vector2(g0 + 60, GROUND_Y - 170)
	sign.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
	sign.add_theme_color_override("font_outline_color", Color.BLACK)
	sign.add_theme_constant_override("outline_size", 5)
	add_child(sign)
	for i in SCROLLS_X.size():
		_add_scroll(Vector2(SCROLLS_X[i], GROUND_Y - 18), "ZealScroll%d" % i)

# Simple pixel-art tombstone (12x16 px, scaled x4), its feet at `feet`
static var _tomb_tex: Texture2D
func _add_tomb(feet: Vector2, sc: float):
	if _tomb_tex == null:
		var img = Image.create(12, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var light = Color(0.78, 0.78, 0.84)
		var dark = Color(0.45, 0.45, 0.52)
		var line = Color(0.15, 0.13, 0.18)
		for y in 16:
			for xx in 12:
				var inside = xx >= 1 and xx <= 10 and (y >= 3 or (y >= 1 and xx >= 2 and xx <= 9) or (y == 0 and xx >= 4 and xx <= 7))
				if inside:
					img.set_pixel(xx, y, dark if xx >= 8 else light)
		# outline
		for y in 16:
			for xx in 12:
				if img.get_pixel(xx, y).a > 0:
					continue
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q = Vector2i(xx, y) + d
					if q.x >= 0 and q.x < 12 and q.y >= 0 and q.y < 16 and img.get_pixelv(q).a > 0 and img.get_pixelv(q) != line:
						img.set_pixel(xx, y, line)
						break
		# a cross on it
		for y in range(4, 11):
			img.set_pixel(5, y, line); img.set_pixel(6, y, line)
		for xx in range(3, 9):
			img.set_pixel(xx, 6, line)
		_tomb_tex = ImageTexture.create_from_image(img)
	var s = Sprite2D.new()
	s.texture = _tomb_tex
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.scale = Vector2(4, 4) * sc
	s.centered = false
	s.offset = Vector2(-6, -16)
	s.position = feet
	s.add_to_group("tombstones")
	add_child(s)

func _add_scroll(pos: Vector2, nm: String) -> Node:
	var pk = load("res://item_pickup.tscn").instantiate()
	pk.name = nm
	pk.item_id = "zeal_scroll"
	pk.position = pos
	pk.modulate = Color(1.0, 0.85, 0.35)   # gold: Zeal
	add_child(pk)
	return pk

# ---------------- helpers ----------------

func pit_index(body: Vector2) -> int:
	for i in PITS.size():
		if body.x > PITS[i] and body.x < PITS[i] + PIT_W and body.y > GROUND_Y + 10 and body.y < GROUND_Y + PIT_DEPTH + 20:
			return i
	return -1

func _ground_under(x: float, feet_y: float) -> bool:
	var q = PhysicsRayQueryParameters2D.create(Vector2(x, feet_y - 4), Vector2(x, feet_y + 24))
	q.exclude = [player.get_rid()]
	return not get_world_2d().direct_space_state.intersect_ray(q).is_empty()

func _feet_y() -> float:
	var cs = player.get_node("CollisionShape2D")
	return cs.global_position.y + cs.shape.size.y * cs.global_scale.y / 2.0

# ---------------- every frame ----------------

func _physics_process(delta):
	if player == null or not is_instance_valid(player):
		return
	var body = player.get_body_center()
	var pit = pit_index(body)
	# remember solid ground (not a grave floor, not the very edge of a platform)
	if player.is_on_floor() and pit < 0 and _ground_under(body.x - 45, _feet_y()) and _ground_under(body.x + 45, _feet_y()):
		last_safe = player.global_position
	# stuck in a grave without a Zeal Scroll: one appears there
	if pit >= 0 and player.is_on_floor():
		pit_time += delta
		if pit_time > 4.0 and not pit_rescued.get(pit, false) and Inventory.count("zeal_scroll") <= 0 and player.zeal_left <= 0:
			pit_rescued[pit] = true
			var pk = _add_scroll(Vector2(PITS[pit] + PIT_W * 0.5, GROUND_Y + PIT_DEPTH - 18), "RescueScroll%d" % pit)
			pk.set_meta("dropped", true)   # not remembered by the save
	else:
		pit_time = 0.0
	if body.y > KILL_Y and not falling_handled:
		player_fell()
	# party members that fell too come back to you
	for m in get_tree().get_nodes_in_group("party"):
		if is_instance_valid(m) and m != player and m is Node2D and m.global_position.y > KILL_Y + 600:
			_bring_to_player(m)

func _bring_to_player(m):
	var spot = PartyManager._spot_next_to(player)
	if m.has_method("_move_to"):
		m._move_to(spot)   # (also resets his follow trail)
	else:
		m.global_position = spot
		if "velocity" in m:
			m.velocity = Vector2.ZERO

# ---------------- the kill floor ----------------

func player_fell():
	falling_handled = true
	var start = last_safe if last_safe != null else Vector2(-21, 23)
	if not GameSettings.baby_mode:
		var dmg = ceil(player.max_hp * FALL_DAMAGE_PCT)
		if player.hp - dmg <= 0:
			# a real death, like losing a battle
			TurnManager.show_message(tr("You fell... back to the checkpoint"))
			player.velocity = Vector2.ZERO
			player.set_physics_process(false)
			await get_tree().create_timer(1.2).timeout
			SaveManager.respawn_after_death()
			get_tree().reload_current_scene()
			return
		player.set_hp(player.hp - dmg)
		PopupText.spawn(player, "-" + str(int(dmg)), Color(1, 0.45, 0.4))
	TurnManager.show_message(tr("You fell! Back up you go."))
	player.global_position = start + Vector2(0, -6)
	player.velocity = Vector2.ZERO
	for m in get_tree().get_nodes_in_group("party"):
		if is_instance_valid(m) and m != player and m is Node2D:
			_bring_to_player(m)
	print("[Sloth] fell: back to ", start, " hp ", player.hp)
	await get_tree().physics_frame
	await get_tree().physics_frame
	falling_handled = false
