extends VBoxContainer
# Party HUD: the party's health in the top-left corner
# ----------------------------------------------------
# Under the player's portrait and HP bar, one compact row per party member
# who is with you (Pastor Ramuel or Baana, and every phone player):
#     [portrait] [ Name   80 / 100 ]  (green; red at 25% or less; grey and
#                                      "KO" when knocked out)
# It replaces the small HP bars that used to float over their heads. It
# follows the party live: damage, healing, knock-outs, a member switched in
# mid-battle (party_manager.gd), a phone player joining or leaving. Built by
# the player (character_body_2d.gd _layout_hud) in the level's HUD layer, so
# it shows wherever the player's own HP bar shows (2D, the 3D boss view).

const ROW_H = 38.0
const PORTRAIT = 36.0
const BAR_SIZE = Vector2(190, 20)
const HP_COLOR = Color(0.2, 0.75, 0.25)
const LOW_HP_COLOR = Color(0.85, 0.12, 0.12)
const KO_COLOR = Color(0.45, 0.45, 0.5)
const LOW_HP_RATIO = 0.25

var rows = []        # [{member, row, pic, bar, fill, label}]
var _members = []    # the members the rows were built for (in order)

func _init():
	name = "PartyHUD"
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

# Who is shown: everyone in the "party" group still in the level
func members() -> Array:
	var list = []
	if not is_inside_tree():
		return list
	for m in get_tree().get_nodes_in_group("party"):
		if is_instance_valid(m) and not m.is_queued_for_deletion() and "hp" in m and "max_hp" in m:
			list.append(m)
	return list

func _process(_delta):
	var now = members()
	if now != _members:
		_rebuild(now)
	for r in rows:
		_update_row(r)
	visible = not rows.is_empty()

func _rebuild(list: Array):
	for c in get_children():
		remove_child(c)
		c.queue_free()
	rows.clear()
	_members = list
	for m in list:
		var row = HBoxContainer.new()
		row.name = "Row_" + str(m.get("member_id") if m.get("member_id") else m.name)
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.custom_minimum_size = Vector2(0, ROW_H)
		var frame = Panel.new()
		frame.name = "Portrait"
		frame.custom_minimum_size = Vector2(PORTRAIT, PORTRAIT)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box = StyleBoxFlat.new()
		box.bg_color = Color(0.08, 0.08, 0.12, 0.85)
		box.border_color = Color(0.9, 0.9, 0.9)
		box.set_border_width_all(2)
		box.set_corner_radius_all(4)
		frame.add_theme_stylebox_override("panel", box)
		var pic = TextureRect.new()
		pic.name = "Picture"
		var sprite = m.get("idle_sprite")
		pic.texture = TurnManager.portrait_of(sprite if sprite else m, -1)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pic.position = Vector2(3, 3)
		pic.size = Vector2(PORTRAIT - 6, PORTRAIT - 6)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(pic)
		row.add_child(frame)
		var bar = ProgressBar.new()
		bar.name = "HPBar"
		bar.show_percentage = false
		bar.custom_minimum_size = BAR_SIZE
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fill = StyleBoxFlat.new()
		fill.bg_color = HP_COLOR
		fill.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", fill)
		var back = StyleBoxFlat.new()
		back.bg_color = Color(0.1, 0.1, 0.1, 0.8)
		back.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("background", back)
		var label = Label.new()
		label.name = "Text"
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.clip_text = true
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 4)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(label)
		row.add_child(bar)
		add_child(row)
		rows.append({member = m, row = row, pic = pic, bar = bar, fill = fill, label = label})
	reset_size()

func _update_row(r):
	var m = r.member
	if not is_instance_valid(m):
		return
	var max_hp = max(float(m.max_hp), 1.0)
	r.bar.max_value = max_hp
	r.bar.value = m.hp
	var ko = m.hp <= 0.0
	var c = KO_COLOR if ko else (LOW_HP_COLOR if m.hp <= max_hp * LOW_HP_RATIO else HP_COLOR)
	if r.fill.bg_color != c:
		r.fill.bg_color = c
	var who = tr(m.display_name)
	var text = ("%s  %s" % [who, tr("KO")]) if ko else ("%s  %d / %d" % [who, ceil(m.hp), max_hp])
	if r.label.text != text:
		r.label.text = text
	# Baana's golden tint, a phone sheep's colour (darker when knocked out)
	var tint = m.get("base_modulate")
	if tint == null and m.get("visual"):
		tint = m.visual.modulate
	tint = tint if tint != null else Color.WHITE
	tint.a = 1.0
	r.pic.modulate = tint.darkened(0.45) if ko else tint

# Height of the rows (0 when nobody is with you)
func used_height() -> float:
	return 0.0 if rows.is_empty() or not visible else get_combined_minimum_size().y
