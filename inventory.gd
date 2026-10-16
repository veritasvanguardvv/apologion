extends Node
# Inventory (autoload / singleton)
# --------------------------------
# The items you carry (scrolls...). Item definitions live in items.gd.
#
#   Ctrl = open / close the inventory (not while typing in the verse box).
#   Esc  = close it.
#
# Using a scroll casts its verse:
#   - In a battle: only on your turn. It uses up your turn and the scroll.
#     Targets work like a recited verse (Alt / Target button, see targeting.gd).
#   - Outside a battle: only items with outside_battle = true (healing yes,
#     attacks no - those are greyed out).
#   - It does NOT use the verse in your verse cycle and does NOT discover it.
# Your items are kept between levels and in the save file (SaveManager).

const Items = preload("res://items.gd")

var items = {}          # item id -> how many you have, e.g. {"healing_scroll": 1}
signal changed

var layer: CanvasLayer
var panel: Panel
var list: VBoxContainer
var empty_label: Label


func _ready():
	_build_panel()
	SaveManager.language_changed.connect(func(_l): _refresh())


# ---------------- Items ----------------

func get_item(id: String) -> Dictionary:
	return Items.ITEMS.get(id, {})

func count(id: String) -> int:
	return items.get(id, 0)

func add(id: String, amount := 1):
	items[id] = count(id) + amount
	changed.emit()
	_refresh()

func remove(id: String, amount := 1):
	items[id] = count(id) - amount
	if items[id] <= 0:
		items.erase(id)
	changed.emit()
	_refresh()

# For SaveManager
func get_save_data() -> Dictionary:
	return items.duplicate()

func load_save_data(data: Dictionary):
	items = data.duplicate()
	changed.emit()
	_refresh()


# Can this item be used right now? Returns "" if yes, or the reason why not.
func why_not_usable(id: String) -> String:
	var item = get_item(id)
	var player = get_tree().get_first_node_in_group("player")
	if item.is_empty() or count(id) <= 0 or player == null:
		return "You can't use that now"
	var verse = player.get_verse(item.get("verse", ""))
	if TurnManager.in_battle:
		if not TurnManager.is_players_turn():
			return "Wait for your turn!"
		return ""
	if not item.get("outside_battle", false):
		return "Only in a battle"
	if verse and verse.type == "heal" and not player.anyone_hurt():
		return "Everyone is at full health"
	return ""

# Uses one of the item (see the top of this file). Returns true if it was used.
func use(id: String) -> bool:
	if why_not_usable(id) != "":
		return false
	var player = get_tree().get_first_node_in_group("player")
	var verse = player.get_verse(get_item(id).verse)
	remove(id)
	close()
	player.use_scroll(verse, tr(get_item(id).name))
	print("Used ", id)
	return true


# ---------------- Window ----------------

func open():
	_refresh()
	panel.visible = true

func close():
	panel.visible = false

func toggle():
	if panel.visible:
		close()
	else:
		open()

func is_open() -> bool:
	return panel.visible

# Ctrl = open/close. Not while typing, not on the main menu, and not with Alt
# held (AltGr on Spanish keyboards sends Ctrl+Alt to type @ or #).
func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.is_action("toggle_inventory") and not event.alt_pressed:
		var focus = get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit:
			return
		var menus = get_tree().get_first_node_in_group("menus")
		if menus and menus.is_main_menu_open():
			return
		if get_tree().get_first_node_in_group("player"):
			toggle()
	elif event.is_action_pressed("ui_cancel") and panel.visible:
		close()   # (normally menu_layer.gd handles Esc first)
		get_viewport().set_input_as_handled()

func _process(_delta):
	if panel.visible:
		_update_buttons()   # e.g. your turn started while it was open


func _build_panel():
	layer = CanvasLayer.new()
	layer.layer = 19   # above the HUD and menus, under the party selector
	add_child(layer)
	panel = Panel.new()
	panel.name = "InventoryPanel"
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -260
	panel.offset_top = -200
	panel.offset_right = 260
	panel.offset_bottom = 200
	panel.visible = false
	var look = StyleBoxFlat.new()   # solid dark window with a light border
	look.bg_color = Color(0.09, 0.08, 0.13, 0.97)
	look.border_color = Color(0.95, 0.88, 0.6)
	look.set_border_width_all(2)
	look.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", look)
	layer.add_child(panel)
	var title = Label.new()
	title.text = "Inventory (Ctrl)"
	title.position = Vector2(16, 10)
	title.add_theme_font_size_override("font_size", 20)
	panel.add_child(title)
	var close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "Close"
	close_button.position = Vector2(420, 8)
	close_button.custom_minimum_size = Vector2(84, 0)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	panel.add_child(close_button)
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(12, 50)
	scroll.size = Vector2(496, 338)
	panel.add_child(scroll)
	list = VBoxContainer.new()
	list.name = "ItemList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	empty_label = Label.new()
	empty_label.text = "No items yet. Look around the levels!"
	empty_label.position = Vector2(16, 60)
	panel.add_child(empty_label)


# Rebuilds the item rows: [icon] Name x2 / verse line [Use]
func _refresh():
	if list == null:
		return
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	var player = get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	empty_label.visible = items.is_empty()
	for id in Items.ITEMS:   # same order as items.gd
		if count(id) <= 0:
			continue
		var item = get_item(id)
		var verse = player.get_verse(item.verse) if player else null
		var row = HBoxContainer.new()
		row.name = id
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		list.add_child(row)
		var icon = TextureRect.new()
		icon.texture = load(item.icon)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.custom_minimum_size = Vector2(56, 56)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var texts = VBoxContainer.new()
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(texts)
		var name_label = Label.new()
		name_label.text = "%s  x%d" % [tr(item.name), count(id)]
		name_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		texts.add_child(name_label)
		var info = Label.new()
		info.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		info.add_theme_font_size_override("font_size", 13)
		info.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size.x = 300
		if verse:
			info.text = "%s - %s" % [VerseManager.ref_text(verse.ref), player.verse_power_text(verse)]
			# Hovering shows the whole verse
			row.tooltip_text = "%s\n\"%s\"\n%s" % [VerseManager.ref_text(verse.ref), player.verse_body(verse), player.verse_power_text(verse)]
			icon.tooltip_text = row.tooltip_text
		texts.add_child(info)
		var use_button = Button.new()
		use_button.name = "UseButton"
		use_button.text = "Use"
		use_button.custom_minimum_size = Vector2(80, 40)
		use_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		use_button.focus_mode = Control.FOCUS_NONE
		use_button.pressed.connect(use.bind(id))
		row.add_child(use_button)
	_update_buttons()

# Greys out items that can't be used right now (the reason shows on hover)
func _update_buttons():
	for row in list.get_children():
		var button = row.get_node_or_null("UseButton")
		if button == null:
			continue
		var reason = why_not_usable(str(row.name))
		button.disabled = reason != ""
		button.tooltip_text = tr(reason) if reason != "" else ""
		row.modulate = Color(1, 1, 1, 0.55) if reason != "" else Color.WHITE
