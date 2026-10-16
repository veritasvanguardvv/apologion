extends Node2D
# GREED LEVEL (Greed.tscn)
# ------------------------
# Greed.tscn was generated from the Unity project by
# /workspace/greed-unity/convert_unity_to_godot.py. This script holds the
# level-wide bits that Unity's Game.cs / JumpModifier.cs did:
#   - rooms: the outdoor area and the treasure room (press Up at a door)
#   - camera limits per room (Unity used camera "Bounds" polygons)
#   - coins and gold you pick up (greed_pickup.gd) + a small counter
#   - "burden": carrying gold makes you too heavy in some spots (G drops it)
#   - falling into a pit restarts the level
#   - breaking the Golden Calf (after beating the Greedwraith) wins the level

const PopupText = preload("res://popup_text.gd")

# Filled in by the converter: [{ "name", "start": Vector2, "rect": Rect2 }]
@export var rooms: Array = []
@export var music: AudioStream
@export var music_volume_db = -10.0
@export var burden_gravity = 1.7       # JumpModifier.modif in Unity
@export var fall_margin = 500.0        # this far below the room's bottom edge = fell into a pit
@export var use_camera_limits = true
# The Unity level was built for a player that walks 1 Unity unit per second
# (= 400 px/s at our 400 px-per-unit scale) and climbs 1-tile (130 px) steps,
# so in Greed the sheep walks faster and jumps higher than in Sloth/Lust.
# Set to 0 to keep the player's normal values.
@export var player_speed = 400.0
@export var player_jump_velocity = -620.0

var current_room = 0
var room_to_enter = -1
var money = 0
var gold = 0
var in_burden_area = false
var burden_hints = 0
var base_gravity = -1.0
var restarting = false
var hud: Label
var prompt: Label
var music_player: AudioStreamPlayer


func _ready():
	add_to_group("greed_level")
	_build_hud()
	if music:
		music_player = AudioStreamPlayer.new()
		music_player.stream = music
		music_player.volume_db = music_volume_db
		if "loop" in music_player.stream:
			music_player.stream.loop = true
		add_child(music_player)
		music_player.play()
	call_deferred("_apply_camera_limits")
	call_deferred("_apply_player_tuning")


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
	if event.is_action_pressed("ui_up") and room_to_enter != -1:
		enter_room(room_to_enter)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_G and gold > 0:
		gold -= 1
		PopupText.spawn(player, tr("Dropped the gold"), Color(1, 0.85, 0.3))
		_update_gravity()
		_update_hud()


# ---------------- Rooms (Game.CanEnterRoom / TryEnterRoom) ----------------

func can_enter_room(n: int):
	room_to_enter = n
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


# ---------------- Coins, gold and the burden ----------------

func add_money(amount := 1):
	money += amount
	_update_hud()


func add_gold(amount := 1):
	gold += amount
	_update_hud()
	_update_gravity()


func set_burden_area(state: bool):
	in_burden_area = state
	_update_gravity()
	if state and gold > 0:
		var player = _player()
		if player:
			PopupText.spawn(player, tr("I guess I am too heavy..."), Color(1, 0.9, 0.6), Vector2(0, -110), 2.5)


func add_burden_hint():
	burden_hints += 1


func _update_gravity():
	var player = _player()
	if player == null:
		return
	if base_gravity < 0:
		base_gravity = player.gravity
	player.gravity = base_gravity * (burden_gravity if in_burden_area and gold > 0 else 1.0)


# ---------------- Letters / dialogs ----------------

func show_letter(key: String):
	var player = _player()
	if player:
		PopupText.spawn(player, tr(key), Color(1, 0.95, 0.75), Vector2(0, -130), 6.0)


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
	restarting = true
	TurnManager.show_message(tr("You fell... restarting the level"))
	await get_tree().create_timer(1.5).timeout
	SaveManager.start_new_level()
	get_tree().reload_current_scene()


func win():
	TurnManager.show_message(tr("You defeated the forces of greed!"))
	var menus = get_tree().get_first_node_in_group("menus")
	if menus and menus.has_method("unlock_next_level"):
		menus.unlock_next_level("Greed")


# ---------------- HUD ----------------

func _build_hud():
	var layer = CanvasLayer.new()
	layer.name = "GreedHUD"
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(15, 160)
	hud.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	hud.add_theme_color_override("font_color", Color(1, 0.88, 0.35))
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 5)
	layer.add_child(hud)
	prompt = Label.new()
	prompt.text = "Press Up to enter"
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
	_update_hud()


func _update_hud():
	var text = tr("Coins: %d") % money
	if gold > 0:
		text += "   " + tr("Gold: %d (G to drop)") % gold
	hud.text = text


func _on_language_changed(_new_language):
	_update_hud()
	prompt.text = tr("Press Up to enter")
