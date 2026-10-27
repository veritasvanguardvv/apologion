extends Node2D
# GREED LEVEL (Greed.tscn)
# ------------------------
# Greed.tscn was generated from the Unity project by
# /workspace/greed-unity/convert_unity_to_godot.py. This script holds the
# level-wide bits that Unity's Game.cs / JumpModifier.cs did:
#   - rooms: the outdoor area and the treasure room (press Up at a door)
#   - camera limits per room (Unity used camera "Bounds" polygons)
#   - weight: carrying gold (1 or more bars in your inventory, anywhere in the
#     level) makes you a little heavier: you walk 5% slower and your jump
#     tops out at carry_jump_height (172 px instead of 201). That still gets
#     you onto the feather block before the hill (157 px up) and the normal
#     1-tile steps (130.6 px), so every step of the hill can still be climbed
#     with the gold - it just feels heavier. In the air you also can't go
#     sideways faster than carry_air_speed (340 instead of 400 - also when
#     dashing (ram) or with Zeal; a feather's speed boost raises the cap by
#     its factor, but not in water_jump_zone), so the jump from the hill top
#     to the tree platform over the water (TileMaps/TreePlatform_Tilemap: 2
#     tiles higher, 437 px gap) falls ~45 px short: you can't cross the water
#     with gold. Without it the same jump clears with ~60 px to spare.
#     Drop the gold (Ctrl > click it > Drop) and you're back to normal at once.
#     (Unity's JumpModifier only did this in one spot.)
#     Money you pick up goes in the inventory too and flies away (inventory.gd).
#   - falling into a pit / the water restarts the level - or, once you've
#     reached the hill (Triggers/CheckpointArea), puts you back on top of the
#     hill (checkpoint_feet). Your inventory stays as it was (gold too).
#   - POTS: clay pots on the path (pot.gd) - smash them for a Bible scroll
#     (a new verse), or in Baby Mode a healing item that reads a healing verse
#   - breaking the Golden Calf (after the SinDeath scene, Greed/scripts/sindeath_scene.gd) wins the level

const PopupText = preload("res://popup_text.gd")

# Filled in by the converter: [{ "name", "start": Vector2, "rect": Rect2 }]
@export var rooms: Array = []
@export var music: AudioStream
@export var music_volume_db = -10.0
@export var carry_jump_height = 172.0  # highest jump with gold (pixels): feather block needs 156.8, hill steps 130.6, normal jump 201
@export var carry_speed_scale = 0.95   # walking speed with gold
@export var carry_air_speed = 340.0    # top sideways speed in the air with gold (px/s; normal 400): with it the jump from the hill to the tree platform falls short
# Around the hill top and the tree platform over the water: a speed boost
# (feather) doesn't raise the gold's air speed cap here, so the water still
# can't be crossed with gold even right after a feather.
@export var water_jump_zone = Rect2(4550, -1500, 1650, 1100)
@export var checkpoint_feet = Vector2(5110, -855)   # where you respawn: on top of the hill (feet on the grass)
@export var fall_margin = 500.0        # this far below the room's bottom edge = fell into a pit
@export var use_camera_limits = true
# The Unity level was built for a player that walks 1 Unity unit per second
# (= 400 px/s at our 400 px-per-unit scale) and climbs 1-tile (130 px) steps,
# so in Greed the sheep walks faster and jumps higher than in Sloth/Lust.
# Set to 0 to keep the player's normal values.
@export var player_speed = 400.0
@export var player_jump_velocity = -620.0

# Clay pots to smash (pot.gd): [feet position on the floor, "sin" / "heal" scroll first].
# On the walking path, clear of the hill and its free scrolls (x -1000..140),
# the enemies and the other pickups.
const POTS = [
	[Vector2(1250, 320), "sin"], [Vector2(2500, 320), "heal"], [Vector2(3350, 320), "sin"],
	[Vector2(3900, -71), "heal"], [Vector2(4250, -332), "sin"], [Vector2(6200, -463), "heal"],
	[Vector2(7450, -69), "sin"], [Vector2(9200, 175), "heal"], [Vector2(10200, 307), "sin"],
]

var current_room = 0
var room_to_enter = -1
var restarting = false
var prompt: Label
var music_player: AudioStreamPlayer


func _ready():
	add_to_group("greed_level")
	_build_hud()
	# Records 2-second clips around money/gold pickups (SinDeath scene replay)
	var recorder = preload("res://Greed/scripts/play_of_the_game.gd").new()
	recorder.name = "PlayOfTheGame"
	add_child(recorder)
	if music:
		music_player = AudioStreamPlayer.new()
		music_player.stream = music
		music_player.volume_db = music_volume_db
		music_player.bus = "Music"   # the Music volume slider in Settings
		if "loop" in music_player.stream:
			music_player.stream.loop = true
		add_child(music_player)
		music_player.play()
	call_deferred("_apply_camera_limits")
	call_deferred("_apply_player_tuning")
	_build_pots()


func _build_pots():
	var holder = Node2D.new()
	holder.name = "Pots"
	add_child(holder)
	holder.owner = self
	# (verses the dig spot's scrolls teach: the pots' scrolls are other ones)
	var DigSpot = preload("res://Greed/scripts/dig_spot.gd")
	var skip = []
	for v in DigSpot.VERSES + DigSpot.FREE_VERSES:
		skip.append(v[0])
	for i in POTS.size():
		var pot = preload("res://pot.gd").new()
		pot.name = "Pot%d" % (i + 1)
		pot.position = POTS[i][0]
		pot.prefer = POTS[i][1]
		pot.skip_refs = skip
		holder.add_child(pot)
		pot.owner = self   # (save id = level + node path)


func _apply_player_tuning():
	var player = _player()
	if player == null:
		return
	if player_speed > 0:
		player.speed = player_speed
	if player_jump_velocity < 0:
		player.jump_velocity = player_jump_velocity


func _player():
	return get_tree().get_first_node_in_group("player")


func _process(_delta):
	var player = _player()
	if player == null or restarting or rooms.is_empty():
		return
	# (the body's middle - the player node's own origin is far off to the side)
	var cs = player.get_node_or_null("CollisionShape2D")
	player.speed_boost_air_capped = water_jump_zone.has_point(cs.global_position if cs else player.global_position)
	var r = rooms[current_room].get("rect")
	if r is Rect2 and player.global_position.y > r.end.y + fall_margin:
		player_fell()


func _unhandled_input(event):
	var player = _player()
	if player == null or TurnManager.in_battle:
		return
	var typing = player.verse_input and player.verse_input.has_focus()
	if typing:
		return
	if event.is_action_pressed("interact") and room_to_enter != -1:
		enter_room(room_to_enter)
		get_viewport().set_input_as_handled()


# ---------------- Rooms (Game.CanEnterRoom / TryEnterRoom) ----------------

func can_enter_room(n: int):
	room_to_enter = n
	prompt.text = _enter_text()
	prompt.visible = n != -1


func enter_room(i: int):
	if i < 0 or i >= rooms.size() or rooms[i].get("start") == null:
		return
	current_room = i
	room_to_enter = -1
	prompt.visible = false
	teleport_player(rooms[i].start)
	_apply_camera_limits()


# Puts the player's feet at 'pos' (a Unity transform position), party too.
func teleport_player(pos: Vector2):
	var player = _player()
	if player == null:
		return
	var shape = player.get_node_or_null("CollisionShape2D")
	var feet_offset = Vector2.ZERO
	if shape and shape.shape is RectangleShape2D:
		feet_offset = shape.global_position + Vector2(0, shape.shape.size.y / 2.0) - player.global_position
	player.global_position = pos - feet_offset + Vector2(0, -4)
	player.velocity = Vector2.ZERO
	for member in get_tree().get_nodes_in_group("party"):
		member.global_position = pos + Vector2(-90, -4)
	for cam in [player.get_node_or_null("Camera2D")]:
		if cam:
			cam.reset_smoothing()
	# the room may have changed (e.g. a teleport into another room's bounds)
	for idx in rooms.size():
		var r = rooms[idx].get("rect")
		if r is Rect2 and r.grow(200).has_point(pos) and idx != current_room:
			current_room = idx
			_apply_camera_limits()


func _apply_camera_limits():
	var player = _player()
	if player == null or rooms.is_empty() or not use_camera_limits:
		return
	var cam = player.get_node_or_null("Camera2D")
	var r = rooms[current_room].get("rect")
	if cam == null or not (r is Rect2):
		return
	var view = get_viewport_rect().size
	# small rooms: don't clamp tighter than one screen
	var cx = r.get_center()
	var w = max(r.size.x, view.x)
	var h = max(r.size.y, view.y)
	cam.limit_left = int(cx.x - w / 2.0)
	cam.limit_right = int(cx.x + w / 2.0)
	cam.limit_top = int(cx.y - h / 2.0)
	cam.limit_bottom = int(cx.y + h / 2.0)


# ---------------- Gold (weight) ----------------

# How many heavy items (gold bars) you carry (they're in the inventory)
func carried_gold() -> int:
	var n = 0
	for id in Inventory.items:
		if Inventory.get_item(id).get("heavy", false):
			n += Inventory.count(id)
	return n


# Any gold at all = heavy (more bars don't make it worse)
func _update_weight():
	var player = _player()
	if player == null:
		return
	var heavy = carried_gold() > 0
	player.carry_max_jump_height = carry_jump_height if heavy else 0.0
	player.carry_speed_scale = carry_speed_scale if heavy else 1.0
	player.carry_air_speed = carry_air_speed if heavy else 0.0


# ---------------- Letters / dialogs ----------------

# Letters that become key items once read (Inventory > Key Items tab, where
# you can read them again). letter_key in Greed.tscn -> items.gd KEY_ITEMS id
const KEY_ITEM_LETTERS = {"itemHint": "letter_v_ram"}

func show_letter(key: String):
	var player = _player()
	var text = tr(key)
	if KEY_ITEM_LETTERS.has(key):
		Inventory.add_key_item(KEY_ITEM_LETTERS[key])
		text = Inventory.key_item_text(KEY_ITEM_LETTERS[key])   # "Press X to ram."
	if player:
		PopupText.spawn(player, text, Color(1, 0.95, 0.75), Vector2(0, -130), 6.0)


# Unity opens a cut-scene dialog here (DialogCanvas). Not ported yet.
func start_dialog(n: int):
	print("[Greed] dialog ", n, " (Unity dialog not ported yet)")


func open_door():
	print("[Greed] door opens")


func play_door():
	pass


# ---------------- Losing / winning ----------------

func player_fell():
	if restarting:
		return
	if BabyMode.fall_back(_player()):
		return   # Baby Mode: back to where you last stood
	restarting = true
	var checkpoint = SaveManager.get_checkpoint() != null
	TurnManager.show_message(tr("You fell... back to the checkpoint") if checkpoint else tr("You fell... restarting the level"))
	await get_tree().create_timer(1.5).timeout
	SaveManager.respawn_after_death()
	get_tree().reload_current_scene()


# Baby Mode (baby_mode.gd): the water under the hill (Triggers/DamageArea (1))
# - put back down there again and again, the way out is LEFT, through the
# cave to the portal (Triggers/Teleport) that takes you back up the hill.
# (Put back up on the hill top, there's nothing to point at.)
const WATER_RECT = Rect2(5050, 300, 1400, 400)     # where a body falls into it
const BELOW_HILL = Rect2(4560, -200, 1900, 900)    # put back somewhere down here
func baby_fall_hint(fell_at: Vector2, respawned_at: Vector2) -> Dictionary:
	if not WATER_RECT.has_point(fell_at) or not BELOW_HILL.has_point(respawned_at):
		return {}
	var portal = get_node_or_null("Triggers/Teleport")
	var portal_x = portal.global_position.x if portal else 4560.0
	return {"id": "greed_water", "dir": -1, "done_x": portal_x + 260.0}


# Triggers/CheckpointArea (at the foot of the hill): from now on dying puts
# you on top of the hill. Stored as the player's position for SaveManager.
func reach_checkpoint():
	var player = _player()
	if player == null or SaveManager.get_checkpoint() != null:
		return
	var cs = player.get_node("CollisionShape2D")
	var feet_offset = cs.global_position + Vector2(0, cs.shape.size.y / 2.0 * cs.global_scale.y) - player.global_position
	SaveManager.set_checkpoint(checkpoint_feet - feet_offset - Vector2(0, 2))
	print("[Greed] checkpoint reached: respawn on top of the hill")


func win():
	TurnManager.show_message(tr("You defeated the forces of greed!"))
	_show_level_complete.call_deferred()
	var menus = get_tree().get_first_node_in_group("menus")
	if menus and menus.has_method("unlock_next_level"):
		menus.unlock_next_level("Greed")


# "Level Complete!" banner after the Golden Calf is smashed
func _show_level_complete():
	await get_tree().create_timer(1.2).timeout
	var layer = CanvasLayer.new()
	layer.name = "LevelComplete"
	layer.layer = 60
	add_child(layer)
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dim)
	var box = VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 14)
	layer.add_child(box)
	var title = Label.new()
	title.text = "Level Complete!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 12)
	box.add_child(title)
	var sub = Label.new()
	sub.text = "You defeated the forces of greed!"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 26)
	sub.add_theme_color_override("font_outline_color", Color.BLACK)
	sub.add_theme_constant_override("outline_size", 6)
	box.add_child(sub)
	var ok = Button.new()
	ok.text = "Continue"
	ok.custom_minimum_size = Vector2(220, 52)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.add_theme_font_size_override("font_size", 24)
	ok.pressed.connect(layer.queue_free)
	box.add_child(ok)
	box.modulate.a = 0.0
	box.scale = Vector2(0.8, 0.8)
	box.pivot_offset = box.size / 2
	var t = box.create_tween().set_parallel(true)
	t.tween_property(box, "modulate:a", 1.0, 0.5)
	t.tween_property(box, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ok.grab_focus.call_deferred()


# ---------------- HUD ----------------

func _build_hud():
	var layer = CanvasLayer.new()
	layer.name = "GreedHUD"
	add_child(layer)
	prompt = Label.new()
	prompt.text = _enter_text()
	prompt.anchor_left = 0.5
	prompt.anchor_right = 0.5
	prompt.position = Vector2(-120, 220)
	prompt.size = Vector2(240, 30)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	prompt.add_theme_constant_override("outline_size", 5)
	prompt.visible = false
	layer.add_child(prompt)
	SaveManager.language_changed.connect(_on_language_changed)
	# Picking up / dropping gold changes how heavy you are
	Inventory.changed.connect(_update_weight)
	_update_weight.call_deferred()


func _on_language_changed(_new_language):
	prompt.text = _enter_text()


# "Press Up to enter" on a computer, "Tap ^ to enter" on a phone (the ^ button)
func _enter_text() -> String:
	return GameSettings.control_prompt("Press %s to enter", "interact", "Tap ^ to enter", "Press Up to enter")
