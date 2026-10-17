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
#     1-tile steps (130.6 px), but not over the raised step on the hill
#     (WeightLedge in Greed.tscn, 186 px above the step before it). Drop the
#     gold (Ctrl > click it > Drop) and you're back to normal at once.
#     (Unity's JumpModifier only did this in one spot.)
#     Money you pick up goes in the inventory too and flies away (inventory.gd).
#   - falling into a pit restarts the level
#   - breaking the Golden Calf (after beating the Greedwraith) wins the level

const PopupText = preload("res://popup_text.gd")

# Filled in by the converter: [{ "name", "start": Vector2, "rect": Rect2 }]
@export var rooms: Array = []
@export var music: AudioStream
@export var music_volume_db = -10.0
@export var carry_jump_height = 172.0  # highest jump with gold (pixels): feather block needs 156.8, WeightLedge 186, normal jump 201
@export var carry_speed_scale = 0.95   # walking speed with gold
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
var restarting = false
var prompt: Label
var music_player: AudioStreamPlayer


func _ready():
	add_to_group("greed_level")
	_build_hud()
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
	if event.is_action_pressed("interact") and room_to_enter != -1:
		enter_room(room_to_enter)
		get_viewport().set_input_as_handled()


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
	# Picking up / dropping gold changes how heavy you are
	Inventory.changed.connect(_update_weight)
	_update_weight.call_deferred()


func _on_language_changed(_new_language):
	prompt.text = tr("Press Up to enter")
