extends Node
# GameSettings (autoload / singleton)
# -----------------------------------
# Settings that are NOT part of a save game (they stay the same for every
# save): music / sound-effect volume and the key bindings. They're written to
# user://settings.cfg as soon as they change, and applied when the game starts.
#
#   Audio buses: "Music" and "SFX" (both feed "Master"). Every sound player in
#   the game is put on the SFX bus automatically, unless it's already on another
#   bus (the voice mic uses "Mic", Greed's music uses "Music").
#
#   Key bindings: one key per action (see ACTIONS). The remap screen in
#   Settings (menu_layer.gd) calls rebind().

const PATH = "user://settings.cfg"
const MUSIC_BUS = "Music"
const SFX_BUS = "SFX"

# [action, English label (translated in strings.csv), default key]
# Keys are PHYSICAL keys (the same spot on any keyboard layout).
const ACTIONS = [
	["move_left", "Move left", KEY_LEFT],
	["move_right", "Move right", KEY_RIGHT],
	["jump", "Jump", KEY_SPACE],
	["interact", "Talk / enter door", KEY_UP],
	["ram", "Ram (tap; hold to charge)", KEY_X],
	["recite", "Recite (type a verse)", KEY_ENTER],
	["push_to_talk", "Voice (hold and speak)", KEY_SHIFT],
	["toggle_verse_box", "Verse box", KEY_TAB],
	["toggle_inventory", "Inventory", KEY_CTRL],
	["cycle_target", "Choose target", KEY_ALT],
	["skip_turn", "Skip turn", KEY_K],
	["run_away", "Run away", KEY_R],
	["change_party", "Change Party", KEY_P],
	["dig", "Dig", KEY_D],
	["scroll_verses_up", "Scroll verses up", KEY_UP],
	["scroll_verses_down", "Scroll verses down", KEY_DOWN],
]
# These only work while the Tab verse list is open, so they may share a key
# with another action (Up = Talk / enter door): rebinding doesn't swap them.
const SHAREABLE = ["scroll_verses_up", "scroll_verses_down"]

var music_volume = 0.8   # 0..1
var sfx_volume = 1.0     # 0..1
var scroll_verses_with_arrows = true   # hold Up/Down to scroll the Tab verse list
var touch_controls = true               # on-screen buttons on phones / tablets (touch_controls.gd)
var boss_battles_3d = true              # boss fights (SinDeath) shown in 3D (battle_3d.gd); off = the 2D fight
# Baby Mode (baby_mode.gd): no typing or speaking verses - you defeat enemies
# by running into them and a matching verse is read out loud.
var baby_mode = false
signal baby_mode_changed(on)
# Language picked in Settings / the main menu ("" = not picked yet). Saved here
# so it survives restarts; SaveManager.set_language() applies it.
var language = ""

signal touch_controls_changed(on)
var bindings = {}        # action -> physical keycode

signal bindings_changed


func _ready():
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)
	for a in ACTIONS:
		bindings[a[0]] = a[2]
	_load()
	_apply_volumes()
	for action in bindings:
		_apply_binding(action)
	# Route every sound player that gets created to the SFX bus
	get_tree().node_added.connect(_on_node_added)


# ---------------- Audio ----------------

func _ensure_bus(bus_name: String):
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var i = AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, "Master")


func _on_node_added(node: Node):
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		_route.call_deferred(node)   # deferred: scripts often set .bus right after add_child


func _route(node):
	if not is_instance_valid(node):
		return
	if node.bus == "Master" or node.bus == "":
		node.bus = MUSIC_BUS if node.has_meta("music") or str(node.name).to_lower().contains("music") else SFX_BUS


func set_music_volume(v: float):
	music_volume = clampf(v, 0.0, 1.0)
	_apply_volumes()
	_save()


func set_sfx_volume(v: float):
	sfx_volume = clampf(v, 0.0, 1.0)
	_apply_volumes()
	_save()


# While a verse is read out loud (baby_mode.gd) the music and sound effects
# go quieter so the voice stands out.
const DUCK_MUSIC_DB = -12.0
const DUCK_SFX_DB = -6.0
var voice_ducking = false

func set_voice_ducking(on: bool):
	if on == voice_ducking:
		return
	voice_ducking = on
	_apply_volumes()


func _apply_volumes():
	for pair in [[MUSIC_BUS, music_volume, DUCK_MUSIC_DB], [SFX_BUS, sfx_volume, DUCK_SFX_DB]]:
		var i = AudioServer.get_bus_index(pair[0])
		if i == -1:
			continue
		AudioServer.set_bus_mute(i, pair[1] <= 0.001)
		AudioServer.set_bus_volume_db(i, linear_to_db(max(pair[1], 0.001)) + (pair[2] if voice_ducking else 0.0))


func set_scroll_verses_with_arrows(on: bool):
	scroll_verses_with_arrows = on
	_save()


func set_touch_controls(on: bool):
	touch_controls = on
	_save()
	touch_controls_changed.emit(on)


# (used when the next boss fight starts)
func set_boss_battles_3d(on: bool):
	boss_battles_3d = on
	_save()


func set_language(lang: String):
	if language == lang:
		return
	language = lang
	_save()

# Baby Mode on/off (saved). baby_mode.gd and the HUD react to the signal.
func set_baby_mode(on: bool):
	if baby_mode == on:
		return
	baby_mode = on
	_save()
	baby_mode_changed.emit(on)


# ---------------- Key bindings ----------------

func action_label(action: String) -> String:
	for a in ACTIONS:
		if a[0] == action:
			return a[1]
	return action


# The key's name, e.g. "Space", "X", "Shift"
# Prompts that name a control: the keyboard wording ("Press Up to enter",
# with the key the player bound) on a computer, the touch button's name on a
# phone / tablet ("Tap ^ to enter"). key_text has a %s for the key.
func touch_prompts() -> bool:
	var tm = get_node_or_null("/root/TurnManager")
	return tm != null and not tm.key_hints()

# up_text: the wording for the default Up arrow ("Press Up to enter", which
# reads "Pulsa Arriba..." / "strzałkę w górę" in Spanish / Polish).
func control_prompt(key_text: String, action: String, touch_text: String, up_text := "") -> String:
	if touch_prompts():
		return tr(touch_text)
	if up_text != "" and int(bindings.get(action, 0)) == KEY_UP:
		return tr(up_text)
	return tr(key_text) % key_name(action)


func key_name(action: String) -> String:
	var physical = int(bindings.get(action, 0))
	if physical == 0:
		return "-"
	# (browsers, phones and headless runs can't map physical keys to layout keys)
	var can_map = not (OS.get_name() in ["Web", "iOS", "Android"]) and DisplayServer.get_name() != "headless"
	var keycode = DisplayServer.keyboard_get_keycode_from_physical(physical) if can_map else KEY_NONE
	var text = OS.get_keycode_string(keycode if keycode != KEY_NONE else physical)
	return text if text != "" else str(physical)


# Gives "action" this key. If another action already used that key, the two
# swap keys (so nothing ends up with two actions on one key).
func rebind(action: String, physical_keycode: int):
	var old = int(bindings.get(action, 0))
	for other in bindings:
		# (a scroll action and a normal action may share a key)
		if (action in SHAREABLE) != (other in SHAREABLE):
			continue
		if other != action and int(bindings[other]) == physical_keycode:
			bindings[other] = old
			_apply_binding(other)
	bindings[action] = physical_keycode
	_apply_binding(action)
	_save()
	bindings_changed.emit()


func reset_bindings():
	for a in ACTIONS:
		bindings[a[0]] = a[2]
		_apply_binding(a[0])
	_save()
	bindings_changed.emit()


func _apply_binding(action: String):
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	# Keep joypad events, replace the keyboard key
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			InputMap.action_erase_event(action, e)
	var physical = int(bindings.get(action, 0))
	if physical == 0:
		return
	var ev = InputEventKey.new()
	ev.physical_keycode = physical
	InputMap.action_add_event(action, ev)
	# Enter on the number pad also recites
	if action == "recite" and physical == KEY_ENTER:
		var kp = InputEventKey.new()
		kp.physical_keycode = KEY_KP_ENTER
		InputMap.action_add_event(action, kp)


# ---------------- File ----------------

func _save():
	var c = ConfigFile.new()
	c.set_value("audio", "music", music_volume)
	c.set_value("audio", "sfx", sfx_volume)
	c.set_value("controls", "scroll_verses_with_arrows", scroll_verses_with_arrows)
	c.set_value("controls", "touch_controls", touch_controls)
	c.set_value("graphics", "boss_battles_3d", boss_battles_3d)
	c.set_value("gameplay", "baby_mode", baby_mode)
	if language != "":
		c.set_value("gameplay", "language", language)
	for action in bindings:
		c.set_value("keys", action, int(bindings[action]))
	c.save(PATH)


func _load():
	var c = ConfigFile.new()
	if c.load(PATH) != OK:
		return
	music_volume = float(c.get_value("audio", "music", music_volume))
	sfx_volume = float(c.get_value("audio", "sfx", sfx_volume))
	scroll_verses_with_arrows = bool(c.get_value("controls", "scroll_verses_with_arrows", scroll_verses_with_arrows))
	touch_controls = bool(c.get_value("controls", "touch_controls", touch_controls))
	boss_battles_3d = bool(c.get_value("graphics", "boss_battles_3d", boss_battles_3d))
	baby_mode = bool(c.get_value("gameplay", "baby_mode", baby_mode))
	language = str(c.get_value("gameplay", "language", language))
	for action in bindings.keys():
		bindings[action] = int(c.get_value("keys", action, bindings[action]))
