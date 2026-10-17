extends CanvasLayer
const EndlessScores = preload("res://endless_scores.gd")
# All the menus. Text on buttons/labels is translated automatically by Godot
# (translations/strings.csv), because the button text is the English "key".

@onready var pause_menu = $PauseMenu
@onready var main_menu = $MainMenu
@onready var mode_select = $ModeSelect
@onready var story_select = $StorySelect

var unlocked_levels = ["Sloth", "Gluttony", "Lust", "Greed"]

func _ready():
	add_to_group("menus")   # so the inventory can check if a menu is open
	# Use SaveManager's list so unlocked levels are remembered between
	# scenes and get saved (it starts with the same three levels as above).
	unlocked_levels = SaveManager.unlocked_levels
	
	# Save / load buttons (PauseMenu: Save Progress + Load Save, MainMenu: Continue)
	_connect_if_exists("PauseMenu/SaveButton", _on_save_pressed)
	_connect_if_exists("PauseMenu/LoadButton", _on_load_pressed)
	_connect_if_exists("MainMenu/LoadButton", _on_load_pressed)
	
	_connect_if_exists("PauseMenu/ContinueButton", _on_continue_pressed)
	_connect_if_exists("PauseMenu/QuitToMenuButton", _on_quit_to_menu)
	
	_connect_if_exists("MainMenu/PlayButton", _on_play_pressed)
	_connect_if_exists("MainMenu/Quit", _on_quit_pressed)  # the node is named "Quit" in the scenes
	
	_connect_if_exists("ModeSelect/StoryModeButton", _on_story_mode_pressed)
	# (the button is called "EndlessModeButton Mode" in the level scenes)
	_connect_if_exists("ModeSelect/EndlessModeButton Mode" if has_node("ModeSelect/EndlessModeButton Mode") else "ModeSelect/EndlessModeButton", _on_endless_pressed)
	_connect_if_exists("ModeSelect/Back", _on_mode_back_pressed)  # the node is named "Back" in the scenes
	
	_connect_if_exists("StorySelect/BackButton", _on_story_back_pressed)
	
	layer = 10   # menus are drawn above the game's HUD
	_build_black_background()
	_build_language_buttons()
	_build_change_party_button()
	_build_online_buttons()
	_build_multiplayer_menu()
	_build_settings_menu()
	_build_remap_menu()
	_build_endless_scores_button()
	_connect_if_exists("MainMenu/SettingsButton", _open_settings.bind(false))
	_connect_if_exists("PauseMenu/SettingsButton", _open_settings.bind(true))
	_style_pause_menu()
	
	for child in story_select.get_children():
		if child is Button and child.name != "BackButton":
			child.pressed.connect(_on_level_selected.bind(child.text))
	
	_update_story_buttons()
	_show_only(null)

func _connect_if_exists(path: String, callable: Callable):
	var node = get_node_or_null(path)
	if node:
		node.pressed.connect(callable)
	else:
		print("Missing button: ", path)

# Esc works like the "Back" button of whatever is open (top-most first):
#   Multiplayer lobby / Church / Leaderboards -> closed (form -> church list)
#   party selector / inventory -> closed
#   Story Select -> Mode Select -> Main Menu
#   pause menu -> closed (same as Continue)
#   playing with nothing open -> pause menu (the game keeps running)
func _input(event):
	# Remap screen waiting for a key: the next key press is the new binding
	if remap_waiting != "" and event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		if event.physical_keycode == KEY_ESCAPE:
			remap_waiting = ""   # cancelled
		else:
			GameSettings.rebind(remap_waiting, event.physical_keycode)
			remap_waiting = ""
		_refresh_remap_list()
		return
	if not event.is_action_pressed("ui_cancel") or event.is_echo():
		return
	if PhoneServer.is_lobby_open():
		PhoneServer.close_lobby()
	elif OnlineService.menu.is_open():
		OnlineService.menu.go_back()
	elif PartyManager.is_selector_open():
		PartyManager.close_selector()
	elif Inventory.is_open():
		Inventory.close()
	elif remap_menu.visible:
		_close_remap()
	elif settings_menu.visible:
		_close_settings()
	elif multiplayer_menu.visible:
		_close_multiplayer()
	elif story_select.visible:
		_on_story_back_pressed()
	elif mode_select.visible:
		_on_mode_back_pressed()
	elif pause_menu.visible:
		_on_continue_pressed()
	elif main_menu.visible:
		return   # nothing to go back to
	else:
		_show_only(pause_menu)
	get_viewport().set_input_as_handled()

# True while the main menu, Mode Select or Story Select is on screen
# (inventory.gd won't open over them)
func is_main_menu_open() -> bool:
	if (settings_menu.visible or remap_menu.visible or multiplayer_menu.visible) and not sub_from_pause:
		return true
	return main_menu.visible or mode_select.visible or story_select.visible

func _on_continue_pressed():
	_show_only(null)

func _on_quit_to_menu():
	_show_only(main_menu)

func _on_play_pressed():
	_show_only(mode_select)

func _on_story_mode_pressed():
	_show_only(story_select)

# Endless mode (Endless.tscn, endless_level.gd): run right through random
# parts for as long as you can. Fresh health; your verses and items stay.
func _on_endless_pressed():
	print("Starting Endless mode")
	_show_only(null)
	SaveManager.begin_endless()    # story state is put aside; Endless never saves
	SaveManager.start_new_level()
	call_deferred("change_scene", "res://Endless.tscn")

# Mode Select > "Endless high scores": the local leaderboard (endless_scores.gd)
func _build_endless_scores_button():
	var endless = get_node_or_null("ModeSelect/EndlessModeButton Mode")
	if endless == null:
		endless = get_node_or_null("ModeSelect/EndlessModeButton")
	if endless == null or mode_select.has_node("EndlessScoresButton"):
		return
	var b = Button.new()
	b.name = "EndlessScoresButton"
	b.text = "Endless high scores"
	b.position = endless.position + Vector2(0, endless.size.y + 8)   # just under "Endless"
	b.size = Vector2(endless.size.x, 50)
	b.pressed.connect(_open_endless_scores)
	mode_select.add_child(b)

func _open_endless_scores():
	var board = EndlessScores.build_board_panel(self, "")
	board.name = "EndlessScoresPanel"
	var close = Button.new()
	close.text = "Close"
	close.pressed.connect(board.queue_free)
	board.get_node("Box").add_child(close)

func _on_quit_pressed():
	get_tree().quit()

func _on_mode_back_pressed():
	_show_only(main_menu)

func _on_story_back_pressed():
	_show_only(mode_select)

func _on_level_selected(level_name: String):
	if level_name not in unlocked_levels:
		print(level_name, " is locked")
		return
	
	print("Starting level: ", level_name)
	_show_only(null)
	SaveManager.end_endless()      # back from Endless: story state as it was
	SaveManager.start_new_level()  # fresh level = full health
	
	match level_name:
		"Sloth":
			call_deferred("change_scene", "res://Sloth.tscn")
		"Gluttony":
			call_deferred("change_scene", "res://Gluttony.tscn")
		"Lust":
			call_deferred("change_scene", "res://Lust.tscn")
		"Greed":
			call_deferred("change_scene", "res://Greed.tscn")
		_:
			print("No scene set up for ", level_name)

# Endless mode never saves: no Save/Load buttons in its pause menu or Settings.
func _update_save_buttons():
	var no_save = SaveManager.is_no_save_scene()
	for path in ["PauseMenu/SaveButton", "PauseMenu/LoadButton"]:
		var b = get_node_or_null(path)
		if b:
			b.visible = not no_save
	if settings_menu:
		var row = settings_menu.find_child("SaveRow", true, false)
		if row:
			row.visible = not no_save

func change_scene(path: String):
	get_tree().change_scene_to_file(path)

func _show_only(menu):
	_update_save_buttons()
	if pause_menu: pause_menu.visible = (menu == pause_menu)
	if main_menu: main_menu.visible = (menu == main_menu)
	if mode_select: mode_select.visible = (menu == mode_select)
	if story_select: story_select.visible = (menu == story_select)
	if settings_menu: settings_menu.visible = (menu == settings_menu)
	if remap_menu: remap_menu.visible = (menu == remap_menu)
	if multiplayer_menu: multiplayer_menu.visible = (menu == multiplayer_menu)
	if menu != remap_menu:
		remap_waiting = ""
	# The pause menu (and Settings / Multiplayer opened from it) dims the game
	# behind it: you still see it running (the game is NOT paused).
	# The main menu screens get solid black instead.
	var is_sub = menu == settings_menu or menu == remap_menu or menu == multiplayer_menu
	var over_game = menu == pause_menu or (is_sub and sub_from_pause)
	if dim_background:
		dim_background.visible = over_game
	if black_background:
		black_background.visible = menu != null and not over_game

func _update_story_buttons():
	for child in story_select.get_children():
		if child is Button and child.name != "BackButton":
			if child.text in unlocked_levels:
				child.disabled = false
				child.modulate = Color.WHITE
			else:
				child.disabled = true
				child.modulate = Color(0.5, 0.5, 0.5)

func unlock_next_level(completed: String):
	var order = ["Sloth", "Gluttony", "Lust", "Anger", "Greed", "Envy", "Pride"]
	var idx = order.find(completed)
	if idx != -1 and idx + 1 < order.size():
		var next_level = order[idx + 1]
		if next_level not in unlocked_levels:
			unlocked_levels.append(next_level)
			_update_story_buttons()
			print("Unlocked: ", next_level)

# ---------------- Built in code (same in every level) ----------------

var black_background: ColorRect
var dim_background: ColorRect
var settings_menu: Control
var remap_menu: Control
var multiplayer_menu: Control
var sub_from_pause = false     # Settings / Multiplayer were opened from the pause menu
var remap_waiting = ""         # action waiting for a new key on the remap screen
var remap_list: VBoxContainer
var bold_font: FontVariation

# A full-screen black rectangle behind the menu buttons
func _build_black_background():
	black_background = ColorRect.new()
	black_background.name = "BlackBackground"
	black_background.color = Color.BLACK
	black_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	black_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black_background.visible = false
	add_child(black_background)
	move_child(black_background, 0)   # first child = drawn behind the menus
	# See-through black over the game while the pause menu is open
	dim_background = ColorRect.new()
	dim_background.name = "DimBackground"
	dim_background.color = Color(0, 0, 0, 0.6)
	dim_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim_background.mouse_filter = Control.MOUSE_FILTER_STOP   # clicks don't reach the game's buttons behind it
	dim_background.visible = false
	add_child(dim_background)
	move_child(dim_background, 1)

const LANGUAGES = [["en", "English", "EnglishButton"], ["es", "Español", "SpanishButton"], ["pl", "Polski", "PolishButton"]]

# "English", "Español" and "Polski" buttons in the main menu's top-left corner.
# The language is kept in SaveManager (other levels + save file).
func _build_language_buttons():
	if not main_menu:
		return
	var row = HBoxContainer.new()
	row.name = "LanguageButtons"
	row.position = Vector2(16, 16)
	row.add_theme_constant_override("separation", 8)
	main_menu.add_child(row)
	for lang in LANGUAGES:
		var button = Button.new()
		button.name = lang[2]
		button.text = lang[1]
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # language names stay as they are
		button.custom_minimum_size = Vector2(110, 44)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_set_language.bind(lang[0]))
		row.add_child(button)
	_update_language_buttons()

func _set_language(lang: String):
	SaveManager.set_language(lang)   # switches every text in the game
	_update_language_buttons()

# The current language's button is highlighted
func _update_language_buttons():
	var row = main_menu.get_node_or_null("LanguageButtons") if main_menu else null
	if row == null:
		return
	for lang in LANGUAGES:
		row.get_node(lang[2]).modulate = Color(1, 0.9, 0.5) if SaveManager.language == lang[0] else Color.WHITE

# "Change Party" in the pause menu, under "Load Save"
func _build_change_party_button():
	if not pause_menu:
		return
	var button = Button.new()
	button.name = "ChangePartyButton"
	button.text = "Change Party"
	button.position = Vector2(750, 442)
	button.size = Vector2(250, 97)
	button.pressed.connect(PartyManager.open_selector)
	pause_menu.add_child(button)

# "Multiplayer" button: in the main menu under "Continue (Load Save)", and in
# the pause menu on the left. It opens the Multiplayer menu, which holds
# Local Multiplayer (phones join as party members, see phone_server.gd),
# Church and Leaderboards (online_service.gd and online_menu.gd).
func _build_online_buttons():
	if main_menu:
		_add_button(main_menu, ["MultiplayerButton", "Multiplayer", _open_multiplayer.bind(false)], Vector2(750, 233), Vector2(250, 76))
	if pause_menu:
		_add_button(pause_menu, ["MultiplayerButton", "Multiplayer", _open_multiplayer.bind(true)], Vector2(130, 105), Vector2(260, 100))

func _add_button(parent: Control, info: Array, pos: Vector2, button_size: Vector2):
	var button = Button.new()
	button.name = info[0]
	button.text = info[1]
	button.position = pos
	button.size = button_size
	button.pressed.connect(info[2])
	parent.add_child(button)

# ---------------- Save / Load ----------------

func _on_save_pressed(button: Button = null):
	if button == null:
		button = get_node_or_null("PauseMenu/SaveButton")
	if SaveManager.save_game():
		_flash_button_text(button, "Saved!", "Save Progress")
	else:
		_flash_button_text(button, "Save failed", "Save Progress")

func _on_load_pressed(button: Button = null):
	if SaveManager.load_game():
		_show_only(null)  # the saved level is loaded right after this
	else:
		# No save yet: show it on whichever Load button is on screen
		if button == null:
			button = get_node_or_null("MainMenu/LoadButton") if main_menu.visible else get_node_or_null("PauseMenu/LoadButton")
		var normal_text = button.text if button else ""
		_flash_button_text(button, "No save found", normal_text)

# Shows a short message on a button, then changes it back.
func _flash_button_text(button: Button, msg: String, normal_text: String):
	if not button:
		return
	button.text = msg
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(button):
		button.text = normal_text


# ---------------- Look: bold, bigger buttons ----------------

const MENU_FONT_SIZE = 28

func _get_bold_font() -> FontVariation:
	if bold_font == null:
		bold_font = FontVariation.new()
		bold_font.base_font = ThemeDB.fallback_font
		bold_font.variation_embolden = 0.9
	return bold_font

func _make_bold(button: Button, font_size := MENU_FONT_SIZE):
	button.add_theme_font_override("font", _get_bold_font())
	button.add_theme_font_size_override("font_size", font_size)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # long translations wrap instead of spilling out

# Pause menu: bold buttons with a larger font (the dim layer is dim_background)
func _style_pause_menu():
	if not pause_menu:
		return
	for child in pause_menu.get_children():
		if child is Button:
			_make_bold(child)

# A screen built in code: full-screen Control with a centred column
func _make_screen(screen_name: String, title_text: String) -> Array:
	var screen = Control.new()
	screen.name = screen_name
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.visible = false
	add_child(screen)
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(center)
	var column = VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 14)
	column.custom_minimum_size = Vector2(560, 0)
	center.add_child(column)
	var title = Label.new()
	title.name = "Title"
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", _get_bold_font())
	title.add_theme_font_size_override("font_size", 40)
	column.add_child(title)
	return [screen, column]

func _make_menu_button(button_name: String, text: String, callable: Callable) -> Button:
	var button = Button.new()
	button.name = button_name
	button.text = text
	button.custom_minimum_size = Vector2(0, 64)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callable)
	_make_bold(button)
	return button

# ---------------- Multiplayer menu (Local Multiplayer / Church / Leaderboards) ----------------

func _build_multiplayer_menu():
	var parts = _make_screen("MultiplayerMenu", "Multiplayer")
	multiplayer_menu = parts[0]
	var column = parts[1]
	column.add_child(_make_menu_button("LocalButton", "Local Multiplayer (Phones)", PhoneServer.open_lobby))
	column.add_child(_make_menu_button("ChurchButton", "Church", OnlineService.menu.open_church))
	column.add_child(_make_menu_button("LeaderboardsButton", "Leaderboards", OnlineService.menu.open_leaderboards))
	column.add_child(_make_menu_button("BackButton", "Back", _close_multiplayer))

func _open_multiplayer(from_pause: bool):
	sub_from_pause = from_pause
	_show_only(multiplayer_menu)

func _close_multiplayer():
	_show_only(pause_menu if sub_from_pause else main_menu)

# ---------------- Settings ----------------
# Save / Load, Music and SFX volume, Controls (key remapping). Volumes and
# keys are kept by GameSettings (settings_manager.gd) in user://settings.cfg.

func _build_settings_menu():
	var parts = _make_screen("SettingsMenu", "Settings")
	settings_menu = parts[0]
	var column = parts[1]
	var save_row = HBoxContainer.new()
	save_row.name = "SaveRow"
	save_row.add_theme_constant_override("separation", 12)
	column.add_child(save_row)
	var save_button = _make_menu_button("SaveButton", "Save Progress", _on_settings_save)
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(save_button)
	var load_button = _make_menu_button("LoadButton", "Load Save", _on_settings_load)
	load_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(load_button)
	_add_volume_slider(column, "MusicSlider", "Music volume", GameSettings.music_volume, GameSettings.set_music_volume)
	_add_volume_slider(column, "SfxSlider", "Sound effects volume", GameSettings.sfx_volume, GameSettings.set_sfx_volume)
	var scroll_toggle = CheckButton.new()
	scroll_toggle.name = "ScrollVersesToggle"
	scroll_toggle.text = "Scroll verses with arrow keys"
	scroll_toggle.button_pressed = GameSettings.scroll_verses_with_arrows
	scroll_toggle.focus_mode = Control.FOCUS_NONE
	scroll_toggle.add_theme_font_override("font", _get_bold_font())
	scroll_toggle.add_theme_font_size_override("font_size", 22)
	scroll_toggle.toggled.connect(GameSettings.set_scroll_verses_with_arrows)
	column.add_child(scroll_toggle)
	column.add_child(_make_menu_button("ControlsButton", "Controls (remap keys)", _open_remap))
	column.add_child(_make_menu_button("BackButton", "Back", _close_settings))

func _on_settings_save():
	_on_save_pressed(settings_menu.find_child("SaveButton", true, false))

func _on_settings_load():
	_on_load_pressed(settings_menu.find_child("LoadButton", true, false))

func _add_volume_slider(column: Control, slider_name: String, label_text: String, value: float, setter: Callable):
	var row = HBoxContainer.new()
	row.name = slider_name + "Row"
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(260, 0)
	label.add_theme_font_override("font", _get_bold_font())
	label.add_theme_font_size_override("font_size", 22)
	row.add_child(label)
	var slider = HSlider.new()
	slider.name = slider_name
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = value * 100.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(200, 32)
	slider.focus_mode = Control.FOCUS_NONE
	row.add_child(slider)
	var number = Label.new()
	number.custom_minimum_size = Vector2(60, 0)
	number.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	number.text = "%d%%" % int(slider.value)
	number.add_theme_font_size_override("font_size", 22)
	row.add_child(number)
	slider.value_changed.connect(func(v):
		number.text = "%d%%" % int(v)
		setter.call(v / 100.0))

func _open_settings(from_pause: bool):
	sub_from_pause = from_pause
	# Saving only makes sense from inside a level (the pause menu)
	var save_button = settings_menu.find_child("SaveButton", true, false)
	if save_button:
		save_button.disabled = not from_pause
	_show_only(settings_menu)

func _close_settings():
	_show_only(pause_menu if sub_from_pause else main_menu)

# ---------------- Controls (key remapping) ----------------

func _build_remap_menu():
	var parts = _make_screen("RemapMenu", "Controls")
	remap_menu = parts[0]
	var column = parts[1]
	column.custom_minimum_size = Vector2(620, 0)
	var hint = Label.new()
	hint.text = "Click an action, then press the new key (Esc cancels)."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	remap_list = VBoxContainer.new()
	remap_list.name = "List"
	remap_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	remap_list.add_theme_constant_override("separation", 6)
	scroll.add_child(remap_list)
	for a in GameSettings.ACTIONS:
		var row = HBoxContainer.new()
		row.name = a[0]
		remap_list.add_child(row)
		var label = Label.new()
		label.text = a[1]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 22)
		row.add_child(label)
		var key_button = Button.new()
		key_button.name = "Key"
		key_button.custom_minimum_size = Vector2(200, 40)
		key_button.focus_mode = Control.FOCUS_NONE
		key_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # key names; set in _refresh_remap_list
		key_button.pressed.connect(_start_remap.bind(a[0]))
		_make_bold(key_button, 22)
		row.add_child(key_button)
	var buttons = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	var reset = _make_menu_button("ResetButton", "Reset to defaults", func():
		GameSettings.reset_bindings()
		_refresh_remap_list())
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(reset)
	var back = _make_menu_button("BackButton", "Back", _close_remap)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(back)
	SaveManager.language_changed.connect(func(_l): _refresh_remap_list())
	_refresh_remap_list()

func _refresh_remap_list():
	if remap_list == null:
		return
	for row in remap_list.get_children():
		var key_button = row.get_node("Key")
		if row.name == remap_waiting:
			key_button.text = tr("Press a key...")
			key_button.modulate = Color(1, 0.9, 0.5)
		else:
			key_button.text = GameSettings.key_name(str(row.name))
			key_button.modulate = Color.WHITE

func _start_remap(action: String):
	remap_waiting = action
	_refresh_remap_list()

func _open_remap():
	_show_only(remap_menu)
	_refresh_remap_list()

func _close_remap():
	remap_waiting = ""
	_show_only(settings_menu)
