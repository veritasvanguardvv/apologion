extends Area2D
# POT (pot.gd) - a clay pot to smash (built by greed_level.gd: POTS).
#   Baby Mode: run into it.  Normal game: Ram into it (X / the Ram button)
#   or jump down onto it.
# It breaks (cracked pot frame, clay shards, the barrier-smash sound) and
# drops something that floats to you:
#   - Baby Mode: a healing item - heals HEAL_PCT of your HP and reads a
#     kid-safe healing verse out loud (baby_mode.gd)
#   - normal game: a Bible scroll that teaches a verse you don't know yet
#     (a verse of the level's sin or a healing verse, like the dig chamber's
#     scrolls); no new verse left -> a healing item
# A smashed pot stays smashed once you've picked up what was in it
# (SaveManager pickup id = level + node path, like the scrolls and pickups).

const PopupText = preload("res://popup_text.gd")
const PROPS = preload("res://Greed/TX Dungeon Props.png")
const POT_RECT = Rect2(327, 41, 17, 23)        # the tall clay pot
const POT_CRACKED_RECT = Rect2(327, 73, 17, 23)
const SCALE = 2.6
const SMASH_SOUND = preload("res://Greed/barrier-destroy.mp3")
const CHIME = preload("res://Greed/SUCCESS PICKUP Collect Chime 01.wav")
const SCROLL_HEAL = preload("res://General/Items/fc112.png")   # green
const SCROLL_SIN = preload("res://General/Items/fc110.png")    # red
const HEAL_ICON = preload("res://Greed/resources_basic.png")   # the level's healing item
const HEAL_ICON_RECT = Rect2(48, 217, 23, 22)
const HEAL_PCT = 30.0              # a healing item heals this % of max HP
const STOMP_SPEED = 150.0          # falling this fast onto it smashes it (normal game)

@export var prefer = "sin"         # "sin" or "heal": which scroll it tries first (normal game)
@export var skip_refs: Array = []  # verses other pickups in the level already teach

var broken = false
var sprite: Sprite2D
var drop: Area2D                   # (the tests read it)
var drop_kind = ""                 # "scroll" or "heal"
var drop_verse = ""                # the scroll's verse ref
static var _promised = {}          # refs a pot's scroll already offers (no two pots the same)


func _ready():
	add_to_group("pots")
	collision_mask = 1
	monitorable = false
	_setup.call_deferred()   # (after the level sets its owner: the save id)


func _setup():
	if SaveManager.is_pickup_collected(self):
		queue_free()
		return
	var cs = CollisionShape2D.new()
	var rs = RectangleShape2D.new()
	rs.size = Vector2(POT_RECT.size.x * SCALE + 8, POT_RECT.size.y * SCALE)
	cs.shape = rs
	cs.position = Vector2(0, -POT_RECT.size.y * SCALE / 2.0)
	add_child(cs)
	sprite = _atlas_sprite(PROPS, POT_RECT, SCALE)
	sprite.position = Vector2(0, -POT_RECT.size.y * SCALE / 2.0)
	add_child(sprite)


func _atlas_sprite(tex: Texture2D, r: Rect2, s: float) -> Sprite2D:
	var a = AtlasTexture.new()
	a.atlas = tex
	a.region = r
	var sp = Sprite2D.new()
	sp.texture = a
	sp.scale = Vector2(s, s)
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return sp


func _physics_process(_delta):
	if broken or sprite == null:
		return
	for b in get_overlapping_bodies():
		if b.is_in_group("player") and smashes(b):
			smash(b)
			return


# Does this touch break it?
func smashes(player) -> bool:
	if GameSettings.baby_mode:
		return true
	if player.has_method("is_ramming") and player.is_ramming():
		return true
	# landing on it from above
	var feet = player.get_node_or_null("CollisionShape2D")
	var feet_y = feet.global_position.y if feet else player.global_position.y
	return player.velocity.y >= STOMP_SPEED and feet_y < global_position.y - POT_RECT.size.y * SCALE * 0.5


func smash(player = null):
	if broken:
		return
	broken = true
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	_play(SMASH_SOUND, -4.0)
	_shards()
	# the cracked frame for a moment, then gone
	sprite.texture.region = POT_CRACKED_RECT
	var t = sprite.create_tween()
	t.tween_property(sprite, "scale", Vector2(SCALE * 1.15, SCALE * 0.8), 0.08)
	t.tween_property(sprite, "modulate:a", 0.0, 0.25)
	_make_drop(player)
	set_deferred("monitoring", false)
	get_tree().create_timer(0.6).timeout.connect(func():
		if is_instance_valid(sprite): sprite.visible = false)


# Clay shards flying out (simple squares, the pot's colours)
func _shards():
	var p = CPUParticles2D.new()
	p.position = Vector2(0, -POT_RECT.size.y * SCALE * 0.5)
	p.emitting = false
	p.one_shot = true
	p.amount = 18
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.direction = Vector2(0, -1)
	p.spread = 80.0
	p.initial_velocity_min = 140.0
	p.initial_velocity_max = 300.0
	p.gravity = Vector2(0, 900)
	p.scale_amount_min = 4.0
	p.scale_amount_max = 8.0
	var g = Gradient.new()
	g.set_color(0, Color(0.55, 0.42, 0.36))
	g.set_color(1, Color(0.33, 0.24, 0.21, 0.0))
	p.color_ramp = g
	p.z_index = 5
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


func _play(stream: AudioStream, db := 0.0):
	var a = AudioStreamPlayer.new()
	a.stream = stream
	a.bus = "SFX"
	a.volume_db = db
	get_tree().current_scene.add_child(a)
	a.play()
	a.finished.connect(a.queue_free)


# ---------------- What's inside ----------------

func _make_drop(player):
	drop_kind = "heal"
	drop_verse = ""
	if not GameSettings.baby_mode:
		var ref = pick_scroll_verse(player)
		if ref != "":
			drop_kind = "scroll"
			drop_verse = ref
			_promised[ref] = true
	drop = Area2D.new()
	drop.name = name + "Drop"
	drop.collision_mask = 1
	drop.monitorable = false
	drop.position = position + Vector2(0, -POT_RECT.size.y * SCALE * 0.6)
	var cs = CollisionShape2D.new()
	var cc = CircleShape2D.new()
	cc.radius = 30
	cs.shape = cc
	drop.add_child(cs)
	var icon: Sprite2D
	if drop_kind == "scroll":
		var v = player.get_verse(drop_verse) if player and player.has_method("get_verse") else null
		var heal = v != null and _is_heal(v)
		drop.set_meta("kind", "heal" if heal else "sin")
		icon = Sprite2D.new()
		icon.texture = SCROLL_HEAL if heal else SCROLL_SIN
		icon.scale = Vector2.ONE * (44.0 / max(icon.texture.get_width(), icon.texture.get_height()))
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	else:
		icon = _atlas_sprite(HEAL_ICON, HEAL_ICON_RECT, 2.4)
	drop.add_child(icon)
	get_parent().add_child(drop)
	# pops up out of the pot, then floats to you (can't be missed)
	var t = drop.create_tween()
	t.tween_property(drop, "position:y", drop.position.y - 50, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(drop, "position:y", drop.position.y - 10, 0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	t.tween_callback(func(): drop.set_meta("homing", true))
	drop.body_entered.connect(func(b): _collect(b))
	var ref = drop_verse
	drop.tree_exiting.connect(func(): _promised.erase(ref))   # (not picked up: back in the pool)


func _process(delta):
	if drop == null or not is_instance_valid(drop) or not drop.get_meta("homing", false):
		return
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var target = player.get_body_center() if player.has_method("get_body_center") else player.global_position
	var d = target - drop.global_position
	if d.length() < 420.0:
		drop.global_position += d.normalized() * min(d.length(), 520.0 * delta)
		if d.length() < 26.0:
			_collect(player)


func _collect(body):
	if drop == null or not is_instance_valid(drop) or drop.is_queued_for_deletion() or not drop.get_meta("homing", false):
		return
	if not body.is_in_group("player"):
		return
	if drop_kind == "scroll":
		var was_new = not VerseManager.is_discovered(drop_verse)
		if body.has_method("discover_verse"):
			body.discover_verse(drop_verse)
		else:
			VerseManager.discover(drop_verse)
		if body.has_method("_show_verse_message"):
			body._show_verse_message(tr("New verse discovered: %s!") % VerseManager.ref_text(drop_verse))
		PopupText.spawn(body, ("+ " if was_new else "") + VerseManager.ref_text(drop_verse),
			Color(0.6, 1.0, 0.6) if drop.get_meta("kind", "") == "heal" else Color(1.0, 0.75, 0.4))
	else:
		body.heal(body.max_hp * HEAL_PCT / 100.0)
		if GameSettings.baby_mode:
			var v = BabyMode.heal_verse(body)
			if not v.is_empty():
				BabyMode.say_heal_verse(v, body)
	SaveManager.mark_pickup_collected(self)   # stays smashed (once you have what was in it)
	_play(CHIME)
	collected.emit(drop_kind, drop_verse)
	drop.queue_free()
	drop = null

signal collected(kind: String, ref: String)


# ---------------- The scroll's verse (normal game) ----------------

static func _is_heal(v) -> bool:
	var h = float(v.get("heal", 0))
	return h > 0 and (v.get("set", "") == "sheet" or v.get("type", "") == "heal")


# A sheet verse the player doesn't know yet: the level's sin (strongest sin)
# or a healing verse that isn't about another sin. Not one another pickup
# in the level teaches (skip_refs) or another pot already dropped. "" = none.
func pick_scroll_verse(player) -> String:
	if player == null or not ("all_verses" in player):
		return ""
	var PM = preload("res://party_member.gd")
	var sin = player.level_sin() if player.has_method("level_sin") else ""
	var sins = [sin] if sin != "" else []
	var sin_pool = []
	var heal_pool = []
	for v in player.all_verses:
		if v.get("set", "") != "sheet" or VerseManager.is_discovered(v.ref) or v.get("discovered", false):
			continue
		if v.ref in skip_refs or _promised.has(v.ref):
			continue
		if _is_heal(v):
			if PM._theme_ok_for_heal(v, sins):
				heal_pool.append(v.ref)
		elif sin != "" and sin in PM.verse_main_sins(v) and float(v.get("heal", 0)) >= 0:
			sin_pool.append(v.ref)
	var first = heal_pool if prefer == "heal" else sin_pool
	var second = sin_pool if prefer == "heal" else heal_pool
	if not first.is_empty():
		return first.pick_random()
	if not second.is_empty():
		return second.pick_random()
	return ""
