extends CanvasLayer
# The "Church" and "Leaderboards" screens (built in code, owned by
# online_service.gd). Opened from the main menu and the pause menu.
#   Church:       your display name, search + pick your church, or
#                 "Submit your church" (name, city, state/region, country).
#   Leaderboards: State / Country / World (your church's state and country),
#                 Churches (total enemies defeated by their members) or Players.
# Esc = Back (menu_layer.gd calls go_back()).

var church_panel: Panel
var form_panel: Panel
var board_panel: Panel
# Church screen
var name_edit: LineEdit
var current_label: Label
var search_edit: LineEdit
var results: ItemList
var church_note: Label
var found = []                   # churches shown in the list
var search_version = 0
# Submit form
var form_edits = {}              # "name"/"city"/"region"/"country" -> LineEdit
var form_note: Label
# Leaderboards screen
var scope = "world"
var board_type = "church"
var scope_buttons = {}
var type_buttons = {}
var board_title: Label
var board_list: RichTextLabel
var board_note: Label
var my_total_label: Label
var board_version = 0


func _ready():
	layer = 20
	visible = false
	church_panel = _panel()
	form_panel = _panel()
	board_panel = _panel()
	_build_church_screen()
	_build_form()
	_build_board_screen()
	SaveManager.language_changed.connect(func(_l): _refresh_texts())


func is_open() -> bool:
	return visible

func open_church():
	visible = true
	_show(church_panel)
	name_edit.text = SaveManager.profile_name
	search_edit.text = ""
	church_note.text = ""
	_update_current()
	_search()

func open_leaderboards():
	visible = true
	_show(board_panel)
	_load_board()

# Esc / Back
func go_back():
	if form_panel.visible:
		_show(church_panel)
	else:
		if church_panel.visible:
			_save_name()
		visible = false

func _show(panel):
	for p in [church_panel, form_panel, board_panel]:
		p.visible = p == panel


# ---------------- Church screen ----------------

func _build_church_screen():
	var p = church_panel
	_label(p, "Church & Profile", Vector2(40, 20), 36)
	_label(p, "Your name (shown on leaderboards):", Vector2(40, 85), 18)
	name_edit = _edit(p, Vector2(40, 112), Vector2(420, 44), "")
	name_edit.max_length = 20
	name_edit.text_submitted.connect(func(_t): _save_name())
	name_edit.focus_exited.connect(_save_name)
	current_label = _label(p, "", Vector2(500, 120), 20)
	current_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_label(p, "Find your church:", Vector2(40, 172), 18)
	search_edit = _edit(p, Vector2(40, 198), Vector2(640, 44), "Search by name or city...")
	search_edit.text_changed.connect(func(_t): _search())
	results = ItemList.new()
	results.position = Vector2(40, 252)
	results.size = Vector2(640, 280)
	results.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	results.add_theme_font_size_override("font_size", 18)
	results.item_activated.connect(func(_i): _choose_selected())
	p.add_child(results)
	_button(p, "Choose this church", Vector2(710, 252), _choose_selected)
	_button(p, "No church", Vector2(710, 322), _choose_none)
	_button(p, "Submit your church", Vector2(710, 392), _open_form)
	church_note = _label(p, "", Vector2(40, 545), 17)
	church_note.size = Vector2(800, 50)
	church_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	church_note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	church_note.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	_button(p, "Back", Vector2(880, 560), go_back)

func _update_current():
	var church = SaveManager.church
	current_label.text = tr("Your church: %s") % (church.name if not church.is_empty() else tr("(none)"))

func _church_line(c: Dictionary) -> String:
	var place = ", ".join(PackedStringArray([c.get("city", ""), c.get("region", ""), c.get("country", "")].filter(func(x): return str(x) != "")))
	var line = str(c.get("name", "")) + "  -  " + place
	if c.get("pending", false) or (c.has("approved") and not c.approved):
		line += "  (" + tr("waiting for approval") + ")"
	return line

func _search():
	search_version += 1
	var my_version = search_version
	var r = await OnlineService.search_churches(search_edit.text)
	if my_version != search_version:
		return   # an older search finished after a newer one
	found = r.churches
	results.clear()
	for c in found:
		results.add_item(_church_line(c))
	if r.note != "":
		church_note.text = r.note

func _save_name():
	if name_edit.text.strip_edges() != SaveManager.profile_name:
		OnlineService.set_profile(name_edit.text, SaveManager.church)

func _choose_selected():
	var selected = results.get_selected_items()
	if selected.is_empty():
		church_note.text = tr("Pick a church in the list first")
		return
	var church = found[selected[0]]
	OnlineService.set_profile(name_edit.text, church)
	_update_current()
	church_note.text = tr("Your church is now %s") % church.name

func _choose_none():
	OnlineService.set_profile(name_edit.text, {})
	_update_current()


# ---------------- Submit your church ----------------

func _build_form():
	var p = form_panel
	_label(p, "Submit your church", Vector2(40, 20), 36)
	var fields = [["name", "Church name"], ["city", "City"], ["region", "State / region"], ["country", "Country"]]
	var y = 100
	for f in fields:
		_label(p, f[1], Vector2(40, y), 18)
		form_edits[f[0]] = _edit(p, Vector2(40, y + 26), Vector2(560, 44), "")
		y += 88
	form_note = _label(p, "", Vector2(40, y + 6), 17)
	form_note.size = Vector2(1000, 50)
	form_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	form_note.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	_label(p, "New churches are checked by a moderator before they appear for everyone online. You can pick yours right away.", Vector2(640, 126), 16).size = Vector2(460, 120)
	_button(p, "Submit", Vector2(600, 560), _submit_form)
	_button(p, "Back", Vector2(880, 560), go_back)

func _open_form():
	for key in form_edits:
		form_edits[key].text = ""
	form_edits.name.text = search_edit.text
	form_note.text = ""
	_show(form_panel)

func _submit_form():
	var r = await OnlineService.submit_church(form_edits.name.text, form_edits.city.text, form_edits.region.text, form_edits.country.text)
	if not r.ok:
		form_note.text = r.get("error", "") if r.get("error", "") != "" else tr("Couldn't submit the church")
		return
	OnlineService.set_profile(name_edit.text, r.church)
	_show(church_panel)
	_update_current()
	search_edit.text = ""
	_search()
	church_note.text = tr("Thanks! %s was submitted and is now your church.") % r.church.name


# ---------------- Leaderboards ----------------

func _build_board_screen():
	var p = board_panel
	_label(p, "Leaderboards", Vector2(40, 20), 36)
	var x = 40
	for s in [["state", "State"], ["country", "Country"], ["world", "World"]]:
		scope_buttons[s[0]] = _button(p, s[1], Vector2(x, 80), _set_scope.bind(s[0]), Vector2(170, 50))
		x += 180
	x = 640
	for t in [["church", "Churches"], ["player", "Players"]]:
		type_buttons[t[0]] = _button(p, t[1], Vector2(x, 80), _set_type.bind(t[0]), Vector2(200, 50))
		x += 210
	board_title = _label(p, "", Vector2(40, 145), 22)
	board_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	board_list = RichTextLabel.new()
	board_list.bbcode_enabled = true
	board_list.position = Vector2(40, 180)
	board_list.size = Vector2(1070, 330)
	board_list.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	board_list.add_theme_font_size_override("normal_font_size", 20)
	board_list.add_theme_font_size_override("bold_font_size", 20)
	p.add_child(board_list)
	board_note = _label(p, "", Vector2(40, 515), 16)
	board_note.size = Vector2(800, 40)
	board_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	board_note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	board_note.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	my_total_label = _label(p, "", Vector2(40, 580), 20)
	my_total_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_button(p, "Back", Vector2(880, 560), go_back)

func _set_scope(s):
	scope = s
	_load_board()

func _set_type(t):
	board_type = t
	_load_board()

func _load_board():
	for s in scope_buttons:
		scope_buttons[s].modulate = Color(1, 0.9, 0.5) if s == scope else Color.WHITE
	for t in type_buttons:
		type_buttons[t].modulate = Color(1, 0.9, 0.5) if t == board_type else Color.WHITE
	var area = OnlineService.scope_area(scope)
	board_title.text = (tr("Churches") if board_type == "church" else tr("Players")) + "  -  " + (area if area != "" else "?")
	my_total_label.text = tr("Your enemies defeated: %d") % SaveManager.lifetime_defeats
	board_list.text = tr("Loading...")
	board_version += 1
	var my_version = board_version
	var r = await OnlineService.get_leaderboard(scope, board_type)
	if my_version != board_version:
		return
	board_note.text = r.get("note", "")
	var text = ""
	for e in r.entries:
		var line = "%d.  [b]%s[/b]   %s %s" % [int(e.get("rank", 0)), str(e.get("name", "")).replace("[", "("), str(int(e.get("score", 0))), tr("enemies defeated")]
		if str(e.get("detail", "")) != "":
			line += "   [color=#999](%s)[/color]" % str(e.detail).replace("[", "(")
		text += line + "\n"
	board_list.text = text if text != "" else tr("No entries yet")


func _refresh_texts():
	if church_panel.visible:
		_update_current()
	if board_panel.visible:
		_load_board()


# ---------------- Small helpers ----------------

func _panel() -> Panel:
	var p = Panel.new()
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.09, 1.0)
	p.add_theme_stylebox_override("panel", style)
	p.visible = false
	add_child(p)
	return p

func _label(parent, text: String, pos: Vector2, font_size: int) -> Label:
	var l = Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", font_size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if text.length() > 60 else TextServer.AUTOWRAP_OFF
	parent.add_child(l)
	return l

func _edit(parent, pos: Vector2, edit_size: Vector2, placeholder: String) -> LineEdit:
	var e = LineEdit.new()
	e.position = pos
	e.size = edit_size
	e.placeholder_text = placeholder
	e.add_theme_font_size_override("font_size", 20)
	parent.add_child(e)
	return e

func _button(parent, text: String, pos: Vector2, callback: Callable, button_size := Vector2(240, 60)) -> Button:
	var b = Button.new()
	b.text = text
	b.position = pos
	b.size = button_size
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(callback)
	parent.add_child(b)
	return b
