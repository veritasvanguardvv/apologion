extends Node
# Inventory (autoload / singleton)
# --------------------------------
# The items you carry (scrolls, gold...). Item definitions live in items.gd.
#
#   Ctrl = open / close the inventory (not while typing in the verse box).
#   Esc  = close it.
#   Each kind of item has a slot with its icon. Click a slot (or press 1-9)
#   to see it, then Use (scrolls) or Drop. Keys: U = Use, Delete = Drop.
#   Drop leaves it on the ground (scrolls, gold) or throws it away (money).
#
#   MONEY (Greed level) flies away: every time you open the inventory, the
#   money in it flies off the screen in random directions and is gone
#   (Proverbs 23:5, like the flying money in the Unity Greed level).
#
# Using a scroll casts its verse:
#   - In a battle: only on your turn. It uses up your turn and the scroll.
#     Targets work like a recited verse (Alt / Target button, see targeting.gd).
#   - Outside a battle: only items with outside_battle = true (healing yes,
#     attacks no - those are greyed out).
#   - It does NOT use the verse in your verse cycle and does NOT discover it.
# Your items are kept between levels and in the save file (SaveManager).
#
# KEY ITEMS tab (items.gd KEY_ITEMS, e.g. V.'s letter about ramming): story
# items you keep for good. The inventory always opens on the regular Items
# tab; click "Key Items" to see them. Click one to read it again. They have
# no Use / Drop buttons, take no regular slot, weigh nothing, never fly away
# and are saved with the game (save_manager.gd "key_items").

const Items = preload("res://items.gd")

var items = {}          # item id -> how many you have, e.g. {"healing_scroll": 1}
var key_items = []      # key item ids you have (items.gd KEY_ITEMS), in the order you got them
var tab = "items"       # "items" or "key" (the Key Items tab)
var items_tab_button: Button
var key_tab_button: Button
var title_label: Label
var hint_label: Label
signal changed

var layer: CanvasLayer
var panel: Panel
var list: GridContainer          # the slots
var empty_label: Label
var detail_name: Label
var detail_info: Label
var use_button: Button
var drop_button: Button
var selected_id = ""             # the item whose Use / Drop buttons are shown
var money_pending = 0            # money pieces about to lift off (still in the slot)
const SLOT_COUNT = 12
const ItemPickupScene = preload("res://item_pickup.tscn")
signal money_flew_away           # one piece of money left the screen (and the inventory)


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
	if panel and panel.visible and id == "money":
		_fly_money_away_soon()   # money picked up while it's open flies off too

func remove(id: String, amount := 1):
	items[id] = count(id) - amount
	if items[id] <= 0:
		items.erase(id)
	changed.emit()
	_refresh()

# ---------------- Key items ----------------

func get_key_item(id: String) -> Dictionary:
	return Items.KEY_ITEMS.get(id, {})

func has_key_item(id: String) -> bool:
	return id in key_items

# Adds a key item (once - you can't have two of the same letter)
func add_key_item(id: String):
	if id in key_items or not Items.KEY_ITEMS.has(id):
		return
	key_items.append(id)
	changed.emit()
	_refresh()

# What the key item says, translated, with the player's current key filled in
func key_item_text(id: String) -> String:
	var item = get_key_item(id)
	var text = tr(item.get("text", ""))
	if item.has("text_key_action") and "%s" in text:
		var gs = get_node_or_null("/root/GameSettings")
		var key = gs.key_name(item.text_key_action) if gs else "X"
		text = text % (key if key != "-" else "X")
	return text

func get_key_save_data() -> Array:
	return key_items.duplicate()

func load_key_save_data(data):
	key_items.clear()
	for id in data:
		if Items.KEY_ITEMS.has(id) and not id in key_items:
			key_items.append(id)
	changed.emit()
	_refresh()

func set_tab(new_tab: String):
	tab = new_tab
	selected_id = ""
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
	if item.is_empty() or count(id) <= 0 or player == null or not item.has("verse"):
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


# True if the item has a Use button (scrolls)
func is_usable_kind(id: String) -> bool:
	return get_item(id).has("verse")

# Drops one of the item: it's left on the ground behind you (scrolls, gold)
# or thrown away (money). Weight (gold) updates right away. Returns true if dropped.
func drop(id: String) -> bool:
	if count(id) - (money_pending if id == "money" else 0) <= 0:
		return false
	var item = get_item(id)
	remove(id)
	var player = get_tree().get_first_node_in_group("player")
	if player:
		_spawn_dropped(item.get("drop_pickup", ""), id, player)
		var popup = preload("res://popup_text.gd")
		popup.spawn(player, tr("Dropped: %s") % tr(item.name), Color(1, 0.9, 0.6))
	if count(id) <= 0 and selected_id == id:
		selected_id = ""
	_refresh()
	print("Dropped ", id)
	return true

func _spawn_dropped(kind: String, id: String, player: Node2D):
	var level = get_tree().current_scene
	if kind == "" or level == null:
		return
	var side = -1.0 if player.get("facing") == null else -float(player.facing)
	var pos = player.get_body_center() + Vector2(side * 110.0, 0)
	var node: Area2D
	if kind == "item":
		node = ItemPickupScene.instantiate()
		node.item_id = id
	elif kind.begins_with("greed:"):
		node = Area2D.new()
		node.set_script(load("res://Greed/scripts/greed_pickup.gd"))
		node.kind = kind.substr(6)
		var shape = CollisionShape2D.new()
		shape.shape = RectangleShape2D.new()
		shape.shape.size = Vector2(60, 60)
		node.add_child(shape)
		var icon = Sprite2D.new()
		icon.name = "Icon"
		icon.texture = _icon_texture(get_item(id))
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.scale = Vector2(4.8, 4.8)
		icon.z_index = 1
		node.add_child(icon)
	else:
		return
	node.name = "Dropped_%s_%d" % [id, Time.get_ticks_usec()]
	node.set_meta("dropped", true)        # not remembered by SaveManager
	node.set("pickup_delay", 1.0)         # so you don't pick it right back up
	level.add_child(node)
	node.global_position = pos

# The item's icon (a part of a sheet if it has icon_region)
func _icon_texture(item: Dictionary) -> Texture2D:
	var tex = load(item.get("icon", "res://icon.svg"))
	if item.has("icon_region"):
		var atlas = AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = item.icon_region
		return atlas
	return tex


# ---------------- Money flies away ----------------

# Every piece of money in the inventory flies off the screen in a random
# direction on WHITE WINGS (Proverbs 23:5). The moment a bill lifts off it
# leaves the inventory (the slot count drops / the slot goes away), and the
# flying bill starts exactly on top of the slot icon at the same size, so it's
# the item itself that grows wings:
#   1. "sprout": FlyingMoneySprout.png (3 frames of 141x141) - the wings sprout, once
#   2. "flap": Greed/flying_money.png ("Flying money loop.png" from the Unity
#      project, 7 frames of 141x141 from its .meta) looping while it flies
#   - 0.13 s per frame for both (the Unity UIMoney SpriteAnimData Speed; the
#     sprout sheet has no timing of its own), nearest filter
#   - flight: 2.5 s with InSine easing (DOTween ease 2) while growing to 1.1x,
#     like Unity's UIBezierPath; the bills lift off 0.12 s apart
const MONEY_SPROUT_SHEET = "res://FlyingMoneySprout.png"
const MONEY_SHEET = "res://Greed/flying_money.png"
const MONEY_FRAME = 141
const MONEY_FRAME_TIME = 0.13
const MONEY_FLY_TIME = 2.5
const MONEY_END_SCALE = 1.1
const MONEY_STAGGER = 0.12
# Where Greed/money.png sits inside a 141x141 frame (measured pixel-exact), so
# the flying bill lines up with the slot icon, and the flap frames with the sprout
const MONEY_ICON_OFFSET_SPROUT = Vector2(45, 55)
const MONEY_ICON_OFFSET_FLAP = Vector2(43, 59)
var money_frames: SpriteFrames

func _money_sprite_frames() -> SpriteFrames:
	if money_frames:
		return money_frames
	money_frames = SpriteFrames.new()
	money_frames.remove_animation("default")
	var sprout = load(MONEY_SPROUT_SHEET)
	money_frames.add_animation("sprout")
	money_frames.set_animation_loop("sprout", false)
	money_frames.set_animation_speed("sprout", 1.0 / MONEY_FRAME_TIME)
	for i in sprout.get_width() / MONEY_FRAME:
		money_frames.add_frame("sprout", _atlas(sprout, Rect2(i * MONEY_FRAME, 0, MONEY_FRAME, MONEY_FRAME)))
	# Unity's rects count y from the bottom: frames 0-2 = top row, 3-5 = middle, 6 = bottom left
	var sheet = load(MONEY_SHEET)
	money_frames.add_animation("flap")
	money_frames.set_animation_loop("flap", true)
	money_frames.set_animation_speed("flap", 1.0 / MONEY_FRAME_TIME)
	for i in 7:
		money_frames.add_frame("flap", _atlas(sheet, Rect2((i % 3) * MONEY_FRAME, (i / 3) * MONEY_FRAME, MONEY_FRAME, MONEY_FRAME)))
	return money_frames

static func _atlas(sheet: Texture2D, region: Rect2) -> AtlasTexture:
	var a = AtlasTexture.new()
	a.atlas = sheet
	a.region = region
	return a

# Seconds one bill takes from liftoff until it's gone
func money_flight_time() -> float:
	return _money_sprite_frames().get_frame_count("sprout") * MONEY_FRAME_TIME + MONEY_FLY_TIME

func _fly_money_away():
	var waiting = count("money") - money_pending
	if waiting <= 0 or layer == null:
		return
	for i in waiting:
		money_pending += 1
		if i == 0:
			_lift_off_bill()
		else:
			get_tree().create_timer(i * MONEY_STAGGER).timeout.connect(_lift_off_bill)

# The slot icon's drawn rect on screen (TextureRect keeps the aspect, centered)
func _slot_icon_rect(id: String) -> Rect2:
	var slot = list.get_node_or_null(id) if list else null
	var icon = slot.get_node_or_null("Icon") if slot else null
	if icon == null or icon.texture == null:
		return Rect2()
	var tex_size = icon.texture.get_size()
	var k = min(icon.size.x / tex_size.x, icon.size.y / tex_size.y)
	var drawn = tex_size * k
	return Rect2(icon.global_position + (icon.size - drawn) / 2.0, drawn)

func _lift_off_bill():
	money_pending = max(money_pending - 1, 0)
	if count("money") <= 0:
		return
	var icon_rect = _slot_icon_rect("money")
	var k = 1.4
	if icon_rect.size.x > 0:
		k = icon_rect.size.x / _icon_texture(get_item("money")).get_width()   # same size as the slot icon
	else:
		icon_rect = Rect2(panel.global_position + Vector2(22, 60), Vector2.ZERO)
	remove("money")     # the bill leaves the slot right now: it IS the flying one
	var bill = AnimatedSprite2D.new()
	bill.name = "FlyingMoney"
	bill.sprite_frames = _money_sprite_frames()
	bill.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bill.centered = false
	bill.offset = -MONEY_ICON_OFFSET_SPROUT
	bill.scale = Vector2(k, k)
	bill.position = icon_rect.position     # money.png's top left = slot icon's top left
	layer.add_child(bill)
	bill.play("sprout")
	var screen = get_viewport().get_visible_rect().size
	var target = bill.position + Vector2.RIGHT.rotated(randf() * TAU) * (screen.length() + MONEY_FRAME * k * 1.5)
	bill.animation_finished.connect(func():
		bill.offset = -MONEY_ICON_OFFSET_FLAP   # keep the bill in place across the sheets
		bill.play("flap")
		var tween = bill.create_tween()
		tween.tween_property(bill, "position", target, MONEY_FLY_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(bill, "scale", Vector2(k, k) * MONEY_END_SCALE, MONEY_FLY_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.chain().tween_callback(_money_gone.bind(bill)), CONNECT_ONE_SHOT)

func _fly_money_away_soon():
	await get_tree().process_frame
	_fly_money_away()

func _money_gone(bill: Node):
	bill.queue_free()
	money_flew_away.emit()


# ---------------- Window ----------------

func open():
	tab = "items"        # always opens on the regular items; Key Items is a click away
	selected_id = ""
	_refresh()
	panel.visible = true
	await get_tree().process_frame   # let the slots get their places first (the money starts from its slot)
	if panel.visible:
		_fly_money_away()

func close():
	panel.visible = false

func toggle():
	if panel.visible:
		close()
	else:
		open()

func is_open() -> bool:
	return panel.visible

func select(id: String):
	if tab == "key":
		selected_id = id if has_key_item(id) else ""
	else:
		selected_id = id if count(id) > 0 else ""
	_refresh()

# Ctrl = open/close. Not while typing, not on the main menu, and not with Alt
# held (AltGr on Spanish keyboards sends Ctrl+Alt to type @ or #).
# While it's open: 1-9 pick a slot, U = Use, Delete / Backspace = Drop.
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
	elif panel.visible and event is InputEventKey and event.pressed and not event.echo:
		var focus = get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit:
			return
		var ids = _owned_ids()
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var n = event.keycode - KEY_1
			if n < ids.size():
				select(ids[n])
				get_viewport().set_input_as_handled()
		elif tab == "key":
			pass   # key items: no Use / Drop
		elif event.keycode == KEY_U and selected_id != "":
			use(selected_id)
			get_viewport().set_input_as_handled()
		elif (event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE) and selected_id != "":
			drop(selected_id)
			get_viewport().set_input_as_handled()

func _process(_delta):
	if panel.visible:
		_update_buttons()   # e.g. your turn started while it was open

func _owned_ids() -> Array:
	if tab == "key":
		return key_items.duplicate()
	var ids = []
	for id in Items.ITEMS:   # same order as items.gd
		if count(id) > 0:
			ids.append(id)
	return ids


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
	panel.offset_top = -210
	panel.offset_right = 260
	panel.offset_bottom = 210
	panel.visible = false
	var look = StyleBoxFlat.new()   # solid dark window with a light border
	look.bg_color = Color(0.09, 0.08, 0.13, 0.97)
	look.border_color = Color(0.95, 0.88, 0.6)
	look.set_border_width_all(2)
	look.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", look)
	layer.add_child(panel)
	var title = Label.new()
	title_label = title
	title.text = "Inventory (Ctrl)"
	title.position = Vector2(16, 10)
	title.add_theme_font_size_override("font_size", 20)
	panel.add_child(title)
	# Tabs: regular Items / Key Items (mouse only; it always opens on Items)
	items_tab_button = Button.new()
	items_tab_button.name = "ItemsTab"
	items_tab_button.text = "Items"
	items_tab_button.toggle_mode = true
	items_tab_button.position = Vector2(196, 8)
	items_tab_button.focus_mode = Control.FOCUS_NONE
	items_tab_button.pressed.connect(func(): set_tab("items"))
	panel.add_child(items_tab_button)
	key_tab_button = Button.new()
	key_tab_button.name = "KeyItemsTab"
	key_tab_button.text = "Key Items"
	key_tab_button.toggle_mode = true
	key_tab_button.position = Vector2(280, 8)
	key_tab_button.focus_mode = Control.FOCUS_NONE
	key_tab_button.pressed.connect(func(): set_tab("key"))
	panel.add_child(key_tab_button)
	var close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "Close"
	close_button.position = Vector2(420, 8)
	close_button.custom_minimum_size = Vector2(84, 0)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	panel.add_child(close_button)
	# The slots: 6 x 2 squares with the item icon and how many
	list = GridContainer.new()
	list.name = "Slots"
	list.columns = 6
	list.position = Vector2(16, 50)
	list.add_theme_constant_override("h_separation", 8)
	list.add_theme_constant_override("v_separation", 8)
	panel.add_child(list)
	empty_label = Label.new()
	empty_label.text = "No items yet. Look around the levels!"
	empty_label.position = Vector2(16, 230)
	panel.add_child(empty_label)
	var hint = Label.new()
	hint_label = hint
	hint.text = "Click an item (or press 1-9): U = Use, Delete = Drop"
	hint.position = Vector2(16, 216)
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	panel.add_child(hint)
	# What's selected + its buttons
	detail_name = Label.new()
	detail_name.name = "DetailName"
	detail_name.position = Vector2(16, 244)
	detail_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	detail_name.add_theme_font_size_override("font_size", 18)
	panel.add_child(detail_name)
	detail_info = Label.new()
	detail_info.name = "DetailInfo"
	detail_info.position = Vector2(16, 272)
	detail_info.size = Vector2(300, 130)
	detail_info.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	detail_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_info.add_theme_font_size_override("font_size", 13)
	detail_info.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	panel.add_child(detail_info)
	use_button = Button.new()
	use_button.name = "UseButton"
	use_button.text = "Use"
	use_button.position = Vector2(330, 290)
	use_button.custom_minimum_size = Vector2(80, 44)
	use_button.focus_mode = Control.FOCUS_NONE
	use_button.pressed.connect(func(): use(selected_id))
	panel.add_child(use_button)
	drop_button = Button.new()
	drop_button.name = "DropButton"
	drop_button.text = "Drop"
	drop_button.position = Vector2(420, 290)
	drop_button.custom_minimum_size = Vector2(84, 44)
	drop_button.focus_mode = Control.FOCUS_NONE
	drop_button.pressed.connect(func(): drop(selected_id))
	panel.add_child(drop_button)


# Rebuilds the slots and the selected item's details
func _refresh():
	if list == null:
		return
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	var player = get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	var key_tab = tab == "key"
	var ids = _owned_ids()
	empty_label.visible = ids.is_empty()
	empty_label.text = "No key items yet." if key_tab else "No items yet. Look around the levels!"
	# (no keyboard hints in the phone app / with the touch buttons)
	var hints = TurnManager.key_hints()
	title_label.text = "Inventory (Ctrl)" if hints else "Inventory"
	hint_label.text = "Click a key item to read it" if key_tab else ("Click an item (or press 1-9): U = Use, Delete = Drop" if hints else "Tap an item, then Use or Drop")
	items_tab_button.button_pressed = not key_tab
	key_tab_button.button_pressed = key_tab
	if selected_id != "" and (not has_key_item(selected_id) if key_tab else count(selected_id) <= 0):
		selected_id = ""
	for n in SLOT_COUNT:
		var slot = Button.new()
		slot.custom_minimum_size = Vector2(72, 72)
		slot.focus_mode = Control.FOCUS_NONE
		slot.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		slot.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		list.add_child(slot)
		if n >= ids.size():
			slot.name = "Empty%d" % n
			slot.disabled = true
			continue
		var id = ids[n]
		var item = get_key_item(id) if key_tab else get_item(id)
		slot.name = id
		# icon (a TextureRect so we know exactly where it's drawn - the flying money starts there)
		var icon = TextureRect.new()
		icon.name = "Icon"
		icon.texture = _icon_texture(item)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.position = Vector2(6, 4)
		icon.size = Vector2(60, 44)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)
		var amount = Label.new()
		amount.name = "Count"
		amount.text = "" if key_tab else "x%d" % count(id)
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		amount.position = Vector2(0, 48)
		amount.size = Vector2(72, 22)
		amount.add_theme_font_size_override("font_size", 13)
		amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(amount)
		slot.pressed.connect(select.bind(id))
		var verse = player.get_verse(item.verse) if player and item.has("verse") and not key_tab else null
		slot.tooltip_text = tr(item.name)
		if verse:
			slot.tooltip_text = "%s\n%s\n\"%s\"\n%s" % [tr(item.name), VerseManager.ref_text(verse.ref), player.verse_body(verse), player.verse_power_text(verse)]
		if id == selected_id:
			slot.modulate = Color(1, 0.9, 0.5)
	# Details of the selected item
	var has_sel = selected_id != ""
	detail_name.visible = has_sel
	detail_info.visible = has_sel
	use_button.visible = has_sel and not key_tab and is_usable_kind(selected_id)
	drop_button.visible = has_sel and not key_tab
	if has_sel and key_tab:
		detail_name.text = tr(get_key_item(selected_id).name)
		detail_info.text = key_item_text(selected_id)
	elif has_sel:
		var item = get_item(selected_id)
		detail_name.text = "%s  x%d" % [tr(item.name), count(selected_id)]
		var verse = player.get_verse(item.verse) if player and item.has("verse") else null
		if verse:
			detail_info.text = "%s - %s" % [VerseManager.ref_text(verse.ref), player.verse_power_text(verse)]
		elif item.get("heavy", false):
			detail_info.text = tr("Heavy: you can't jump as high while you carry it.")
		elif item.get("flies_away", false):
			detail_info.text = tr("Riches make themselves wings and fly away (Proverbs 23:5).")
		else:
			detail_info.text = ""
	_update_buttons()

# Greys out the Use button when the item can't be used right now (the reason shows on hover)
func _update_buttons():
	if use_button == null or not use_button.visible:
		return
	var reason = why_not_usable(selected_id)
	use_button.disabled = reason != ""
	use_button.tooltip_text = tr(reason) if reason != "" else ""
