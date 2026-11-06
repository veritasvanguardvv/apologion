extends Node
# PartyManager (autoload / singleton)
# ------------------------------------
# Only ONE party member travels with you at a time (Pastor Ramuel or Baana).
# This keeps battles short and the screen tidy; you choose who comes along.
#
#   - "Change Party" in the pause menu (or the P key) opens a small selector.
#   - Picking someone puts them next to you and sends the other one away.
#   - IN A BATTLE: on your turn, the Switch button (or P) opens the same
#     window as "Switch party member": pick the companion on the bench (the
#     one not travelling with you) to swap them in where the other one stands.
#     It uses your turn, like a Pokemon switch. The one who comes in acts from
#     the next round. Each keeps their own HP and their Guard / Faith /
#     Wisdom / Zeal: whoever goes to the bench keeps theirs (frozen, no
#     rounds count down) for if they come back in this battle; the battle's
#     end clears them as usual. A knocked-out companion can be switched OUT
#     but not back IN. Phone players (friends' sheep) are never switched -
#     only the computer-controlled companion.
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
var title: Label
var bench_status = {}          # id -> statuses kept while on the bench (this battle)


func _ready():
	_build_selector()
	TurnManager.battle_ended.connect(func(): bench_status.clear())


# Makes sure the level has exactly the chosen member (called by the player
# when a level starts, and after changing party or loading a save).
func ensure_party():
	var player = get_tree().get_first_node_in_group("player")
	var level = get_tree().current_scene
	if player == null or level == null:
		return
	# Endless mode: solo run — no Pastor Ramuel / Baana (phone friends OK)
	if level.is_in_group("no_save") or level.is_in_group("endless"):
		for member in get_tree().get_nodes_in_group("party"):
			if member.is_in_group("phone_players"):
				continue
			member.remove_from_group("party")
			member.queue_free()
		PhoneServer.ensure_phone_members()
		return
	var wanted = MEMBERS[current].scene
	var found = null
	for member in get_tree().get_nodes_in_group("party"):
		if member.is_in_group("phone_players"):
			continue   # friends on phones are handled by phone_server.gd
		if member.scene_file_path == wanted and found == null:
			found = member
		else:
			member.remove_from_group("party")   # leaves battles right away
			member.queue_free()
	if found == null:
		var member = load(wanted).instantiate()
		member.global_position = _spot_next_to(player)
		level.add_child(member)
	PhoneServer.ensure_phone_members()   # and the phone players (if hosting)


# On the floor, a little behind the player
func _spot_next_to(player) -> Vector2:
	var feet = player.get_body_center()
	var shape = player.get_node_or_null("CollisionShape2D")
	if shape and shape.shape is RectangleShape2D:
		feet.y = shape.global_position.y + shape.shape.size.y / 2.0
	return feet + Vector2(-spawn_distance, -2)


# A member button: outside battles = change party, in a battle = switch in
func _on_member_pressed(member_id: String):
	if TurnManager.in_battle:
		if switch_in(member_id):
			close_selector()
	else:
		set_member(member_id)

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


# ---------------- Switching mid-battle ----------------

# The computer-controlled companion with you now (not a phone player), or null
func active_member():
	for m in get_tree().get_nodes_in_group("party"):
		if is_instance_valid(m) and not m.is_queued_for_deletion() and not m.is_in_group("phone_players") and not m.get("player_controlled"):
			return m
	return null

# The companions on the bench: everyone in MEMBERS who isn't travelling with you
func bench() -> Array:
	var list = []
	for id in MEMBERS:
		if id != current:
			list.append(id)
	return list

func has_bench() -> bool:
	return not bench().is_empty() and active_member() != null

func is_knocked_out(id: String) -> bool:
	return member_hp.has(id) and float(member_hp[id]) <= 0.0

# Who can come in right now (your turn, not knocked out)
func can_switch_to(id: String) -> bool:
	return TurnManager.is_players_turn() and id in bench() and not is_knocked_out(id) and active_member() != null

func can_switch() -> bool:
	for id in bench():
		if can_switch_to(id):
			return true
	return false

signal switched(out_id, in_id)

# Swaps the companion in the battle for `id` from the bench, in the same spot.
# Uses up your turn. Returns false if it can't happen now.
func switch_in(id: String) -> bool:
	if not can_switch_to(id):
		return false
	var old = active_member()
	var level = get_tree().current_scene
	if old == null or level == null:
		return false
	var out_id = old.member_id
	bench_status[out_id] = old.battle_status()   # kept for if they come back
	old.save_hp()
	current = id
	var member = load(MEMBERS[id].scene).instantiate()
	member.global_position = old.global_position
	# right where the other one was in the tree, so the party's order (3D
	# lanes, the phones' target list) stays the same
	old.add_sibling(member)
	old.remove_from_group("party")   # out of the battle right away
	old.queue_free()
	if bench_status.has(id):
		member.restore_battle_status(bench_status[id])
		bench_status.erase(id)
	member.face_battle()
	party_changed.emit(current)
	switched.emit(out_id, id)
	_update_selector()
	TurnManager.show_message(tr("%s comes in for %s!") % [tr(MEMBERS[id].name), tr(MEMBERS[out_id].name if MEMBERS.has(out_id) else old.display_name)])
	print("Switch: ", out_id, " -> ", id)
	TurnManager.player_turn_finished.emit()   # (it costs your turn)
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
	var sb = StyleBoxFlat.new()   # solid, so it reads over the 3D boss view
	sb.bg_color = Color(0.08, 0.08, 0.1, 0.94)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 1, 1, 0.25)
	panel.add_theme_stylebox_override("panel", sb)
	panel.size = Vector2(360, 260)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -180
	panel.offset_top = -130
	panel.offset_right = 180
	panel.offset_bottom = 130
	panel.visible = false
	layer.add_child(panel)
	var box = VBoxContainer.new()
	box.position = Vector2(20, 14)
	box.size = Vector2(320, 230)
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	title = Label.new()
	title.name = "Title"
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
		button.custom_minimum_size = Vector2(0, 44)   # finger-sized
		button.pressed.connect(_on_member_pressed.bind(id))
		box.add_child(button)
		member_buttons[id] = button
	var close = Button.new()
	close.name = "CloseButton"
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(0, 44)
	close.pressed.connect(close_selector)
	box.add_child(close)


func _update_selector():
	var in_battle = TurnManager.in_battle
	var t = "Switch party member" if in_battle else "Change Party"
	if title.text != t:
		title.text = t
	var n = "Only one companion can travel with you."
	if in_battle:
		if active_member() == null or bench().is_empty():
			n = "You can't change your party during a battle."
		elif TurnManager.is_players_turn():
			n = "Pick who comes in. Switching uses your turn."
		else:
			n = "You can switch on your turn."
	if note.text != n:
		note.text = n
	for id in member_buttons:
		var button = member_buttons[id]
		var label = MEMBERS[id].name
		if in_battle and id == current:
			label += "  (" + tr("fighting") + ")"
		elif in_battle and is_knocked_out(id):
			label += "  (" + tr("knocked out") + ")"
		if button.text != label:
			button.text = label
		button.disabled = (not can_switch_to(id)) if in_battle else id == current
		button.modulate = Color(1, 0.9, 0.5) if id == current else Color.WHITE


func _process(_delta):
	if panel.visible:
		_update_selector()   # e.g. a battle started while it was open
