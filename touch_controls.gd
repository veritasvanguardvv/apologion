extends CanvasLayer
# TouchControls (autoload) - ON-SCREEN BUTTONS FOR PHONES AND TABLETS
# ---------------------------------------------------------------------
# Shown only on touchscreen devices (the iPhone app, a tablet, a touch
# laptop) and only while Settings > "Touch controls" is on. Each button is a
# TouchScreenButton that presses the same input action as the keyboard key,
# so everything that works with keys works with fingers:
#   left side : a joystick (touch_joystick.gd): push left / right to walk
#               (move_left / move_right, a light push walks slowly), push it
#               up to talk / go through doors (interact); ^ does that too
#   right side: Jump, Ram (hold until the bar fills, like holding X)
#   right edge: Pause (Esc), Verses (Tab) - under the enemies' HP bars in a
#               battle; on a touch computer / the web
#               also Type (opens the keyboard in the verse box) and Mic (hold
#               to talk). The iPhone / Android app has no Type or Mic: you tap
#               the verse box itself and type, or use the keyboard's own
#               dictation (microphone) key. The inventory opens from the
#               always-visible "Items" box in the top-left corner.
# In a battle or a cut-scene the movement controls hide (you can't move then);
# the battle's own Skip / Target buttons are made bigger for fingers.
# While the phone keyboard is up, the verse box moves up above it.

const BASE = Vector2(1152, 648)       # the game's view size (Project Settings > Display)

var force_show = false                # tests / screenshots on a computer
var buttons = {}                      # name -> TouchScreenButton
var move_buttons = []                 # hidden in battles
var root_node: Node2D
var _textures = {}
var _verse_box_y = {}                 # LineEdit -> its normal offset_top/bottom
var joystick: Node2D
const Joystick = preload("res://touch_joystick.gd")


func _ready():
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	root_node = Node2D.new()
	root_node.name = "Buttons"
	add_child(root_node)
	var R = BASE.x
	var B = BASE.y
	# movement (bottom-left, above the verse box)
	joystick = Joystick.new()
	joystick.name = "Joystick"
	joystick.position = Vector2(118, B - 178)
	root_node.add_child(joystick)
	move_buttons.append(joystick)
	_add("Up", "interact", "^", Vector2(226, B - 300), 64, true)
	# jump / ram (bottom-right)
	_add("Jump", "jump", "Jump", Vector2(R - 128, B - 236), 108, true)
	_add("Ram", "ram", "Ram", Vector2(R - 236, B - 196), 92, true)
	# contextual: only next to something to dig (Greed/scripts/dig_spot.gd)
	_add("Dig", "dig", "Dig", Vector2(R - 232, B - 300), 84, true)
	# right edge column
	_add("Pause", "ui_cancel", "II", Vector2(R - 70, 96), 60, false)
	_add("Verses", "toggle_verse_box", "Verses", Vector2(R - 70, 164), 60, false)
	_add("Type", "recite", "Type", Vector2(R - 70, 232), 60, false)   # (hidden in the phone app)
	_add("Mic", "push_to_talk", "Mic", Vector2(R - 140, 232), 60, false)
	for n in ["Jump", "Ram", "Dig"]:
		var b = buttons[n]
		_normal_style[n] = [b.position, b.texture_normal, b.texture_pressed, b.shape.radius]
	GameSettings.touch_controls_changed.connect(func(_on): _update_visibility())
	_update_visibility()


static func is_touch_device() -> bool:
	return tap_to_type() or DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or OS.has_feature("web_ios") or OS.has_feature("web_android")


# The phone app (iOS, Android): the verse box says "Tap here to type or
# speak Scripture" and tapping it brings up the phone keyboard (its
# dictation key does the speaking); no Type / Mic buttons.
# simulate_os: tests and screenshots on a computer can act like the iPhone
# app (TouchControls.simulate_os = "iOS", or run with -- --simulate-os=iOS).
static var simulate_os = ""

static func os_name() -> String:
	if simulate_os != "":
		return simulate_os
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--simulate-os="):
			return a.get_slice("=", 1)
	return OS.get_name()

static func tap_to_type() -> bool:
	return os_name() in ["iOS", "Android"]


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
	_feed_movement()


# ---------------- Walking: joystick -> move_left / move_right ----------------
var _fed = {"move_left": 0.0, "move_right": 0.0, "interact": false}

func _feed_movement():
	var axis = 0.0
	var up = false
	if root_node.visible and joystick.visible:
		axis = joystick.axis
		up = joystick.up
	else:
		joystick.release()
	_set_strength("move_left", max(-axis, 0.0))
	_set_strength("move_right", max(axis, 0.0))
	if up != _fed.interact:
		_fed.interact = up
		if up:
			Input.action_press("interact")
		else:
			Input.action_release("interact")

# Only touches the action when OUR value changes, so a keyboard / gamepad on
# the same device still works
func _set_strength(action: String, v: float):
	if is_equal_approx(v, _fed[action]):
		return
	_fed[action] = v
	if v > 0.0:
		Input.action_press(action, v)
	else:
		Input.action_release(action)


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


# Buttons that only show in some places: name -> shown (set by the level,
# e.g. contextual["Dig"] next to a dig spot)
var contextual = {}

func _update_visibility():
	var on = wanted() and get_tree().get_first_node_in_group("player") != null and not _menu_open()
	root_node.visible = on
	if not on:
		return
	var player = get_tree().get_first_node_in_group("player")
	var battle = TurnManager.in_battle or (player != null and player.get("cutscene_lock") == true)
	for b in move_buttons:
		b.visible = not battle
	for n in contextual:
		if buttons.has(n):
			buttons[n].visible = not battle and contextual[n]
	if not contextual.has("Dig"):
		buttons["Dig"].visible = false
	# the phone app types / dictates straight into the verse box
	for n in ["Type", "Mic"]:
		buttons[n].visible = not tap_to_type() and not GameSettings.baby_mode
	# Baby Mode (baby_mode.gd): no verses to pick or type - you ram enemies
	buttons["Verses"].visible = not GameSettings.baby_mode
	_apply_baby_style(GameSettings.baby_mode)
	# bigger battle buttons for fingers
	var lift = {"skip_button": 20, "target_button": 40, "switch_button": 60}
	for n in lift:
		var btn = TurnManager.get(n)
		if btn != null and btn.offset_left > -170:
			btn.offset_left = -180
			btn.offset_top -= lift[n]
			btn.offset_bottom = btn.offset_top + 56
	_place_right_column()


# Baby Mode: no words to read - Ram is a big red ball and Jump a big blue
# arrow pointing up (on a pale blue disc: the round hit area is exactly the
# disc you see). Both bigger, still clear of the joystick (bottom-left) and
# the edges; Dig moves up out of their way. Normal mode gets its own back.
const BABY_SIZE = 150
var _normal_style = {}   # name -> [position, texture_normal, texture_pressed, radius]
var _baby_style_on = false

func _apply_baby_style(on: bool):
	if on == _baby_style_on or _normal_style.is_empty():
		return
	_baby_style_on = on
	var R = BASE.x
	var B = BASE.y
	if on:
		_style("Jump", Vector2(R - 170, B - 300), _arrow_up(BABY_SIZE, false), _arrow_up(BABY_SIZE, true), BABY_SIZE / 2.0)
		_style("Ram", Vector2(R - 330, B - 215), _ball(BABY_SIZE, false), _ball(BABY_SIZE, true), BABY_SIZE / 2.0)
		_style("Dig", Vector2(R - 300, B - 330), null, null, -1.0)
	else:
		for n in _normal_style:
			var st = _normal_style[n]
			_style(n, st[0], st[1], st[2], st[3])
	for n in ["Jump", "Ram"]:
		buttons[n].get_node("Label").visible = not on

func _style(n: String, pos: Vector2, normal, pressed, radius: float):
	var b = buttons[n]
	b.position = pos
	if normal:
		b.texture_normal = normal
		b.texture_pressed = pressed
	if radius > 0.0:
		b.shape.radius = radius

# A big red ball (brighter while held)
func _ball(size: int, pressed: bool) -> Texture2D:
	var key = "ball_%d_%s" % [size, pressed]
	if _textures.has(key):
		return _textures[key]
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c = (size - 1) / 2.0
	var base = Color(1.0, 0.35, 0.3) if pressed else Color(0.88, 0.12, 0.12)
	for y in size:
		for x in size:
			var d = Vector2(x - c, y - c).length()
			if d <= c:
				var edge = clamp(c - d, 0.0, 1.0)
				# a little shine at the top-left, a darker rim
				var shine = clamp(1.0 - Vector2(x - c * 0.6, y - c * 0.55).length() / (c * 0.7), 0.0, 1.0)
				var col = base.lerp(Color(1, 0.75, 0.7), shine * 0.45)
				if d > c - 5.0:
					col = base.darkened(0.35)
				img.set_pixel(x, y, Color(col.r, col.g, col.b, 0.92 * edge))
	var tex = ImageTexture.create_from_image(img)
	_textures[key] = tex
	return tex

# A big blue arrow pointing up, on a pale blue disc (the hit area)
func _arrow_up(size: int, pressed: bool) -> Texture2D:
	var key = "arrow_%d_%s" % [size, pressed]
	if _textures.has(key):
		return _textures[key]
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c = (size - 1) / 2.0
	var s = float(size)
	var arrow = PackedVector2Array([
		Vector2(0.5, 0.10), Vector2(0.86, 0.50), Vector2(0.64, 0.50), Vector2(0.64, 0.88),
		Vector2(0.36, 0.88), Vector2(0.36, 0.50), Vector2(0.14, 0.50)])
	for i in arrow.size():
		arrow[i] *= s
	var blue = Color(0.35, 0.65, 1.0) if pressed else Color(0.1, 0.4, 0.95)
	var disc = Color(0.55, 0.78, 1.0, 0.45 if pressed else 0.28)
	for y in size:
		for x in size:
			var d = Vector2(x - c, y - c).length()
			if d > c:
				continue
			var edge = clamp(c - d, 0.0, 1.0)
			var p = Vector2(x + 0.5, y + 0.5)
			var col = disc
			if d > c - 3.0:
				col = Color(blue.r, blue.g, blue.b, 0.7)
			if Geometry2D.is_point_in_polygon(p, arrow):
				col = Color(blue.r, blue.g, blue.b, 0.95)
				# a white outline so it shows on dark backgrounds too
				for o in [Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3)]:
					if not Geometry2D.is_point_in_polygon(p + o, arrow):
						col = Color(1, 1, 1, 0.95)
						break
			img.set_pixel(x, y, Color(col.r, col.g, col.b, col.a * edge))
	var tex = ImageTexture.create_from_image(img)
	_textures[key] = tex
	return tex


# Where the visible buttons / joystick are (screen pixels): floating popups
# keep clear of them (hud_layout.gd), e.g. "Ram the idol!" over the Ram button
func screen_rects() -> Array:
	var out = []
	if root_node == null or not root_node.visible:
		return out
	for n in buttons:
		var b = buttons[n]
		if is_instance_valid(b) and b.is_visible_in_tree() and b.texture_normal:
			out.append(Rect2(b.global_position, b.texture_normal.get_size()))
	if joystick and joystick.is_visible_in_tree():
		var r = float(joystick.get("radius")) if joystick.get("radius") != null else 70.0
		out.append(Rect2(joystick.global_position - Vector2(r, r), Vector2(r, r) * 2.0))
	return out


# Pause / Verses (and Type / Mic) on the right edge: under the enemies' HP
# panel in a battle (it grows with every enemy), so they never cover a boss's
# HP bar. The game's view is always 1152 x 648 (it keeps its 16:9 shape on
# a 19.5:9 phone, with bars at the sides), so this works on every phone.
const COLUMN_TOP = 96.0
const COLUMN_STEP = 68.0
func _place_right_column():
	var top = COLUMN_TOP
	var hud = TurnManager.get("enemy_hud")
	if hud != null and hud.is_visible_in_tree() and hud.get_child_count() > 0:
		var r = hud.get_global_rect()
		top = max(top, r.end.y + 10.0)
	var R = BASE.x
	buttons["Pause"].position = Vector2(R - 70, top)
	buttons["Verses"].position = Vector2(R - 70, top + COLUMN_STEP)
	buttons["Type"].position = Vector2(R - 70, top + COLUMN_STEP * 2)
	buttons["Mic"].position = Vector2(R - 140, top + COLUMN_STEP * 2)


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
