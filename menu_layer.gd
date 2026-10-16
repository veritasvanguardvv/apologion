extends CanvasLayer
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
	_connect_if_exists("ModeSelect/EndlessModeButton", _on_endless_pressed)
	_connect_if_exists("ModeSelect/Back", _on_mode_back_pressed)  # the node is named "Back" in the scenes
	
	_connect_if_exists("StorySelect/BackButton", _on_story_back_pressed)
	
	layer = 10   # menus are drawn above the game's HUD
	_build_black_background()
	_build_language_buttons()
	_build_change_party_button()
	_build_online_buttons()
	
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
	return main_menu.visible or mode_select.visible or story_select.visible

func _on_continue_pressed():
	_show_only(null)

func _on_quit_to_menu():
	_show_only(main_menu)

func _on_play_pressed():
	_show_only(mode_select)

func _on_story_mode_pressed():
	_show_only(story_select)

func _on_endless_pressed():
	print("Endless Mode selected (not implemented yet)")
	_show_only(null)

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

func change_scene(path: String):
	get_tree().change_scene_to_file(path)

func _show_only(menu):
	if pause_menu: pause_menu.visible = (menu == pause_menu)
	if main_menu: main_menu.visible = (menu == main_menu)
	if mode_select: mode_select.visible = (menu == mode_select)
	if story_select: story_select.visible = (menu == story_select)
	# Solid black behind the main menu screens (not the pause menu, so you
	# can still see the game while paused)
	if black_background:
		black_background.visible = menu != null and menu != pause_menu

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

# "English" and "Español" buttons in the main menu's top-left corner.
# The language is kept in SaveManager (other levels + save file).
func _build_language_buttons():
	if not main_menu:
		return
	var row = HBoxContainer.new()
	row.name = "LanguageButtons"
	row.position = Vector2(16, 16)
	row.add_theme_constant_override("separation", 8)
	main_menu.add_child(row)
	for lang in [["en", "English"], ["es", "Español"]]:
		var button = Button.new()
		button.name = "EnglishButton" if lang[0] == "en" else "SpanishButton"
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
	row.get_node("EnglishButton").modulate = Color(1, 0.9, 0.5) if SaveManager.language == "en" else Color.WHITE
	row.get_node("SpanishButton").modulate = Color(1, 0.9, 0.5) if SaveManager.language == "es" else Color.WHITE

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

# "Multiplayer", "Church" and "Leaderboards" buttons: in the main menu under
# "Continue (Load Save)", and in the pause menu on the left.
# (Multiplayer = phones join as party members, see phone_server.gd;
#  Church / Leaderboards, see online_service.gd and online_menu.gd)
func _build_online_buttons():
	var buttons = [
		["MultiplayerButton", "Multiplayer", PhoneServer.open_lobby],
		["ChurchButton", "Church", OnlineService.menu.open_church],
		["LeaderboardsButton", "Leaderboards", OnlineService.menu.open_leaderboards],
	]
	for i in buttons.size():
		if main_menu:
			_add_button(main_menu, buttons[i], Vector2(750, 233 + i * 88), Vector2(250, 76))
		if pause_menu:
			_add_button(pause_menu, buttons[i], Vector2(130, 105 + i * 168.5), Vector2(260, 100))

func _add_button(parent: Control, info: Array, pos: Vector2, button_size: Vector2):
	var button = Button.new()
	button.name = info[0]
	button.text = info[1]
	button.position = pos
	button.size = button_size
	button.pressed.connect(info[2])
	parent.add_child(button)

# ---------------- Save / Load ----------------

func _on_save_pressed():
	var button = get_node_or_null("PauseMenu/SaveButton")
	if SaveManager.save_game():
		_flash_button_text(button, "Saved!", "Save Progress")
	else:
		_flash_button_text(button, "Save failed", "Save Progress")

func _on_load_pressed():
	if SaveManager.load_game():
		_show_only(null)  # the saved level is loaded right after this
	else:
		# No save yet: show it on whichever Load button is on screen
		var button = get_node_or_null("MainMenu/LoadButton") if main_menu.visible else get_node_or_null("PauseMenu/LoadButton")
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
