extends CanvasLayer

var language = "en"
@onready var pause_menu = $PauseMenu
@onready var main_menu = $MainMenu
@onready var mode_select = $ModeSelect
@onready var story_select = $StorySelect

var unlocked_levels = ["Sloth", "Gluttony", "Lust"]

func _ready():
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
	
	# The language button sits in the main menu (only Lust.tscn has one so far).
	# get_node_or_null = no error in scenes that don't have it.
	language = SaveManager.language  # keep the language chosen in an earlier scene
	var lang_button = get_node_or_null("MainMenu/LanguageButton")
	if lang_button:
		lang_button.pressed.connect(_on_language_button_pressed)
		_update_language_button()
	
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

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		if pause_menu.visible:
			_show_only(null)
		elif not main_menu.visible and not mode_select.visible and not story_select.visible:
			_show_only(pause_menu)

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
		_:
			print("No scene set up for ", level_name)

func change_scene(path: String):
	get_tree().change_scene_to_file(path)

func _show_only(menu):
	if pause_menu: pause_menu.visible = (menu == pause_menu)
	if main_menu: main_menu.visible = (menu == main_menu)
	if mode_select: mode_select.visible = (menu == mode_select)
	if story_select: story_select.visible = (menu == story_select)

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

# Switches between English and Spanish verses. The choice is stored in
# SaveManager (so it carries over to other levels and into saves) and is
# passed to the player, which uses it to check typed verses and to show
# the verse box in that language.
func _on_language_button_pressed():
	if language == "en":
		language = "es"
	else:
		language = "en"
	SaveManager.language = language
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_language"):
		player.set_language(language)
	_update_language_button()

# The button shows the language you'd switch TO.
func _update_language_button():
	var lang_button = get_node_or_null("MainMenu/LanguageButton")
	if lang_button:
		lang_button.text = "English" if language == "es" else "Español"

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
