extends Node
# SaveManager (autoload / singleton)
# -----------------------------------
# Keeps track of progress that should survive scene changes and saving:
#   - player_hp            (player health)
#   - defeated_enemies     (which enemies were beaten, per level)
#   - unlocked_levels      (shared with menu_layer.gd)
# ...and writes everything (plus VerseManager's verse lists, the current
# level and the player's position) to a save file.
#
# The save file lives at user://savegame.cfg. On Windows that's
# %APPDATA%\Godot\app_userdata\<project name>\savegame.cfg
# (Editor menu: Project > Open User Data Folder).

const SAVE_PATH = "user://savegame.cfg"
const MAX_HP = 100

var player_hp = MAX_HP

# Example: { "res://Lust.tscn": ["Enemy"] }
# Key = level scene file, value = names/paths of enemies beaten in that level.
var defeated_enemies: Dictionary = {}

# menu_layer.gd uses this same array, so unlocking a level is remembered.
var unlocked_levels = ["Sloth", "Gluttony", "Lust"]

# "en" or "es" - set by the language button in the main menu (menu_layer.gd)
var language = "en"

# When a save is loaded we switch scenes first; the player then picks up
# its saved position from here in its _ready() (see apply_pending_player_state).
var pending_position = null


# ---------------- Enemies ----------------

# Builds the [level, enemy path] pair that identifies an enemy.
func _enemy_id(enemy: Node) -> Array:
	var level_root = enemy.owner if enemy.owner else get_tree().current_scene
	if level_root == null:
		return ["", str(enemy.name)]
	return [level_root.scene_file_path, str(level_root.get_path_to(enemy))]


func mark_enemy_defeated(enemy: Node) -> void:
	var id = _enemy_id(enemy)
	if not defeated_enemies.has(id[0]):
		defeated_enemies[id[0]] = []
	if not (id[1] in defeated_enemies[id[0]]):
		defeated_enemies[id[0]].append(id[1])


func is_enemy_defeated(enemy: Node) -> bool:
	var id = _enemy_id(enemy)
	return defeated_enemies.has(id[0]) and id[1] in defeated_enemies[id[0]]


func get_defeated_count() -> int:
	var count = 0
	for level in defeated_enemies:
		count += defeated_enemies[level].size()
	return count


# ---------------- Player ----------------

# Called from menu_layer when a level is started from Story Select,
# so a fresh level begins at full health (same as before saving existed).
func start_new_level() -> void:
	player_hp = MAX_HP
	pending_position = null


# Called by the player in _ready(). Puts the player where the save said.
func apply_pending_player_state(player: Node2D) -> void:
	if pending_position != null:
		player.global_position = pending_position
		pending_position = null


# ---------------- Save / Load ----------------

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> bool:
	var config = ConfigFile.new()
	var scene = get_tree().current_scene
	config.set_value("progress", "level", scene.scene_file_path if scene else "")
	config.set_value("progress", "player_hp", player_hp)
	var player = get_tree().get_first_node_in_group("player")
	if player:
		config.set_value("progress", "player_position", player.global_position)
	config.set_value("progress", "unlocked_levels", unlocked_levels)
	config.set_value("progress", "language", language)

	var verses = VerseManager.get_save_data()
	config.set_value("verses", "discovered", verses.discovered)
	config.set_value("verses", "used_this_cycle", verses.used_this_cycle)

	config.set_value("enemies", "defeated", defeated_enemies)
	config.set_value("enemies", "defeated_count", get_defeated_count())  # just for reading the file

	var err = config.save(SAVE_PATH)
	if err != OK:
		print("Save failed, error code: ", err)
		return false
	print("Game saved to ", ProjectSettings.globalize_path(SAVE_PATH))
	return true


# Reads the save file and restores everything. If change_level is true it
# also switches to the saved level (the normal case). Returns false if
# there is no save file.
func load_game(change_level := true) -> bool:
	var config = ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		print("No save file found")
		return false

	player_hp = config.get_value("progress", "player_hp", MAX_HP)
	pending_position = null
	if config.has_section_key("progress", "player_position"):
		pending_position = config.get_value("progress", "player_position")
	# Change the contents (not the array itself) so menu_layer keeps sharing it.
	unlocked_levels.clear()
	unlocked_levels.append_array(config.get_value("progress", "unlocked_levels", ["Sloth", "Gluttony", "Lust"]))

	language = config.get_value("progress", "language", "en")

	VerseManager.load_save_data({
		"discovered": config.get_value("verses", "discovered", []),
		"used_this_cycle": config.get_value("verses", "used_this_cycle", []),
	})

	defeated_enemies = config.get_value("enemies", "defeated", {})

	var level = config.get_value("progress", "level", "")
	if change_level and level != "" and ResourceLoader.exists(level):
		get_tree().change_scene_to_file.call_deferred(level)
	print("Game loaded")
	return true
