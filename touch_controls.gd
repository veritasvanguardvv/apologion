extends CanvasLayer
# TouchControls (autoload) - ON-SCREEN BUTTONS FOR PHONES AND TABLETS
# ---------------------------------------------------------------------
# Shown only on touchscreen devices (the iPhone app, a tablet, a touch
# laptop) and only while Settings > "Touch controls" is on. Each button is a
# TouchScreenButton that presses the same input action as the keyboard key,
# so everything that works with keys works with fingers:
#   left side : < and > (move_left / move_right), ^ (interact: talk, doors)
#   right side: Jump, Ram (hold until the bar fills, like holding X)
#   right edge: Pause (Esc), Verses (Tab), Bag (inventory), Type (opens the
#               phone keyboard in the verse box), Mic (hold to talk)
# In a battle the movement buttons hide (you can't move then); the battle's
# own Skip / Target buttons are made bigger for fingers.
# While the phone keyboard is up, the verse box moves up above it.

const BASE = Vector2(1152, 648)       # the game's view size (Project Settings > Display)

var force_show = false                # tests / screenshots on a computer
var buttons = {}                      # name -> TouchScreenButton
var move_buttons = []                 # hidden in battles
var root_node: Node2D
var _textures = {}
var _verse_box_y = {}                 # LineEdit -> its normal offset_top/bottom


func _ready():
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	root_node = Node2D.new()
	root_node.name = "Buttons"
	add_child(root_node)
	var R = BASE.x
	var B = BASE.y
	# movement (bottom-left, above the verse box)
	_add("Left", "move_left", "<", Vector2(18, B - 222), 96, true)
	_add("Right", "move_right", ">", Vector2(126, B - 222), 96, true)
	_add("Up", "interact", "^", Vector2(72, B - 320), 76, true)
	# jump / ram (bottom-right)
	_add("Jump", "jump", "Jump", Vector2(R - 128, B - 236), 108, true)
	_add("Ram", "ram", "Ram", Vector2(R - 236, B - 196), 92, true)
	# right edge column
	_add("Pause", "ui_cancel", "II", Vector2(R - 70, 96), 60, false)
	_add("Verses", "toggle_verse_box", "Verses", Vector2(R - 70, 164), 60, false)
	_add("Bag", "toggle_inventory", "Bag", Vector2(R - 70, 232), 60, false)
	_add("Type", "recite", "Type", Vector2(R - 70, 300), 60, false)
	_add("Mic", "push_to_talk", "Mic", Vector2(R - 140, 300), 60, false)
	GameSettings.touch_controls_changed.connect(func(_on): _update_visibility())
	_update_visibility()


static func is_touch_device() -> bool:
	return DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or OS.has_feature("web_ios") or OS.has_feature("web_android")


func wanted() -> bool:
	return GameSettings.touch_controls and (force_show or is_touch_device())


# A round see-through button with a label, pressing `action` while held
func _add(button_name: String, action: String, text: String, pos: Vector2, size: int, is_move: bool):
	var b = TouchScreenButton.new()
	b.name = button_name
	b.action = action
	b.texture_normal = _circle(size, Color(1, 1, 1, 0.22))
	b.texture_pressed = _circle(size, Color(1, 0.85, 0.4, 0.5))
	b.position = pos
	b.passby_press = action in ["move_left", "move_right"]   # slide a thumb between < and >
	var shape = CircleShape2D.new()
	shape.radius = size / 2.0
	b.shape = shape
	b.shape_centered = true
	var label = Label.new()
	label.name = "Label"
	label.text = text
	label.size = Vector2(size, size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 30 if text.length() <= 2 else (20 if size >= 90 else 15))
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(label)
	root_node.add_child(b)
	buttons[button_name] = b
	if is_move:
		move_buttons.append(b)


func _circle(size: int, color: Color) -> Texture2D:
	var key = "%d_%s" % [size, color.to_html()]
	if _textures.has(key):
		return _textures[key]
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c = (size - 1) / 2.0
	for y in size:
		for x in size:
			var d = Vector2(x - c, y - c).length()
			if d <= c:
				var edge = clamp(c - d, 0.0, 1.0)
				var ring = d > c - 3.0
				var col = Color(color.r, color.g, color.b, (min(color.a * 2.2, 0.9) if ring else color.a) * edge)
				img.set_pixel(x, y, col)
	var tex = ImageTexture.create_from_image(img)
	_textures[key] = tex
	return tex


func _process(_delta):
	_update_visibility()
	_keep_verse_box_above_keyboard()


func _menu_open() -> bool:
	var scene = get_tree().current_scene
	if scene == null:
		return true
	var menu = scene.get_node_or_null("MenuLayer")
	if menu == null:
		return false
	if menu.has_method("is_main_menu_open") and menu.is_main_menu_open():
		return true
	for n in ["pause_menu", "settings_menu", "remap_menu", "multiplayer_menu"]:
		var m = menu.get(n)
		if m != null and m.visible:
			return true
	return false


func _update_visibility():
	var on = wanted() and get_tree().get_first_node_in_group("player") != null and not _menu_open()
	root_node.visible = on
	if not on:
		return
	var battle = TurnManager.in_battle
	for b in move_buttons:
		b.visible = not battle
	# bigger battle buttons for fingers
	for n in ["skip_button", "target_button"]:
		var btn = TurnManager.get(n)
		if btn != null and btn.offset_left > -170:
			btn.offset_left = -180
			btn.offset_top -= (20 if n == "skip_button" else 40)
			btn.offset_bottom = btn.offset_top + 56


# The phone keyboard covers the bottom of the screen: lift the verse box.
func _keep_verse_box_above_keyboard():
	var player = get_tree().get_first_node_in_group("player")
	if player == null or player.get("verse_input") == null:
		return
	var box: Control = player.verse_input
	if not _verse_box_y.has(box):
		_verse_box_y = {box: Vector2(box.offset_top, box.offset_bottom)}
	var normal = _verse_box_y[box]
	var kb = DisplayServer.virtual_keyboard_get_height() if OS.get_name() in ["iOS", "Android"] else 0   # (the browser moves the page itself)
	var lift = 0.0
	if kb > 0 and box.has_focus():
		var scale = get_viewport().get_visible_rect().size.y / max(1.0, float(DisplayServer.window_get_size().y))
		var box_bottom = box.get_global_rect().end.y - (box.offset_top - normal.x)
		lift = max(0.0, box_bottom - (get_viewport().get_visible_rect().size.y - kb * scale) + 8.0)
	box.offset_top = normal.x - lift
	box.offset_bottom = normal.y - lift
