extends Node
# PartyManager (autoload / singleton)
# ------------------------------------
# Only ONE party member travels with you at a time (Pastor Ramuel or Baana).
# This keeps battles short and the screen tidy; you choose who comes along.
#
#   - "Change Party" in the pause menu (or the P key) opens a small selector.
#   - Picking someone puts them next to you and sends the other one away.
#   - Not during a battle (it would mix up the turn order).
#   - The choice is kept between levels and in the save file (SaveManager).
#
# To add another member: make a scene that uses party_member.gd (like
# baana.tscn) and add it to MEMBERS below.

const MEMBERS = {
	"ramuel": {"name": "Pastor Ramuel", "scene": "res://pastor_ramuel.tscn"},
	"baana": {"name": "Baana", "scene": "res://baana.tscn"},
}
const DEFAULT_MEMBER = "ramuel"

signal party_changed(member_id)

var current = DEFAULT_MEMBER   # id from MEMBERS
var member_hp = {}             # id -> HP (missing = full health). Saved by SaveManager.
var spawn_distance = 90.0      # how far behind the player a new member appears

var layer: CanvasLayer
var panel: Panel
var note: Label
var member_buttons = {}        # id -> Button


func _ready():
	_build_selector()


# Makes sure the level has exactly the chosen member (called by the player
# when a level starts, and after changing party or loading a save).
func ensure_party():
	var player = get_tree().get_first_node_in_group("player")
	var level = get_tree().current_scene
	if player == null or level == null:
		return
	var wanted = MEMBERS[current].scene
	var found = null
	for member in get_tree().get_nodes_in_group("party"):
		if member.scene_file_path == wanted and found == null:
			found = member
		else:
			member.remove_from_group("party")   # leaves battles right away
			member.queue_free()
	if found == null:
		var member = load(wanted).instantiate()
		member.global_position = _spot_next_to(player)
		level.add_child(member)


# On the floor, a little behind the player
func _spot_next_to(player) -> Vector2:
	var feet = player.get_body_center()
	var shape = player.get_node_or_null("CollisionShape2D")
	if shape and shape.shape is RectangleShape2D:
		feet.y = shape.global_position.y + shape.shape.size.y / 2.0
	return feet + Vector2(-spawn_distance, -2)


# Returns false if it can't be changed right now (during a battle).
func set_member(member_id: String) -> bool:
	if not MEMBERS.has(member_id) or TurnManager.in_battle:
		return false
	current = member_id
	ensure_party()
	party_changed.emit(current)
	_update_selector()
	print("Party: ", MEMBERS[current].name)
	return true


# ---------------- Health ----------------

# "res://baana.tscn" -> "baana"
func id_for_scene(path: String) -> String:
	for id in MEMBERS:
		if MEMBERS[id].scene == path:
			return id
	return path.get_file().get_basename()

func get_hp(id: String, max_hp: float) -> float:
	return member_hp.get(id, max_hp)

func set_hp(id: String, hp: float):
	member_hp[id] = hp

# Everyone back to full health (a level started fresh, or you were defeated)
func reset_hp():
	member_hp = {}


# ---------------- Selector window ----------------

func open_selector():
	_update_selector()
	panel.visible = true

func close_selector():
	panel.visible = false

func is_selector_open() -> bool:
	return panel.visible

# P = open/close the selector (not while typing in the verse box)
func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel") and panel.visible:
		close_selector()   # (normally menu_layer.gd handles Esc first)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("change_party") and not event.is_echo():
		var focus = get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit:
			return
		if panel.visible:
			close_selector()
		elif get_tree().get_first_node_in_group("player"):
			open_selector()


func _build_selector():
	layer = CanvasLayer.new()
	layer.layer = 20   # above the menus
	add_child(layer)
	panel = Panel.new()
	panel.name = "PartySelector"
	panel.size = Vector2(360, 230)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -180
	panel.offset_top = -115
	panel.offset_right = 180
	panel.offset_bottom = 115
	panel.visible = false
	layer.add_child(panel)
	var box = VBoxContainer.new()
	box.position = Vector2(20, 14)
	box.size = Vector2(320, 200)
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title = Label.new()
	title.text = "Change Party"   # translated automatically (strings.csv)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	note = Label.new()
	note.text = "Only one companion can travel with you."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 14)
	box.add_child(note)
	for id in MEMBERS:
		var button = Button.new()
		button.name = id.capitalize() + "Button"
		button.text = MEMBERS[id].name
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # names stay the same
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(set_member.bind(id))
		box.add_child(button)
		member_buttons[id] = button
	var close = Button.new()
	close.name = "CloseButton"
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(close_selector)
	box.add_child(close)


func _update_selector():
	var in_battle = TurnManager.in_battle
	note.text = "You can't change your party during a battle." if in_battle else "Only one companion can travel with you."
	for id in member_buttons:
		var button = member_buttons[id]
		button.disabled = in_battle or id == current
		button.modulate = Color(1, 0.9, 0.5) if id == current else Color.WHITE


func _process(_delta):
	if panel.visible:
		_update_selector()   # e.g. a battle started while it was open
