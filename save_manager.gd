extends Node
# SaveManager (autoload / singleton)
# -----------------------------------
# Keeps track of progress that should survive scene changes and saving:
#   - player_hp            (player health)
#   - defeated_enemies     (which enemies were beaten, per level)
#   - unlocked_levels      (shared with menu_layer.gd)
#   - collected_pickups    (items picked up from the floor, per level)
#   - profile_name, church, lifetime_defeats (leaderboards, also in user://profile.cfg)
#   (the inventory itself is in inventory.gd, party HP in party_manager.gd)
# ...and writes everything (plus VerseManager's verse lists, the current
# level and the player's position) to a save file.
#
# The save file lives at user://savegame.cfg. On Windows that's
# %APPDATA%\Godot\app_userdata\<project name>\savegame.cfg
# (Editor menu: Project > Open User Data Folder).

const SAVE_PATH = "user://savegame.cfg"
const MAX_HP = 100

var player_hp = MAX_HP

# Same idea for items picked up from the floor (item_pickup.gd), so they stay
# gone after saving and loading: { "res://Sloth.tscn": ["HealingScroll"] }
var collected_pickups: Dictionary = {}

# Example: { "res://Lust.tscn": ["Enemy"] }
# Key = level scene file, value = names/paths of enemies beaten in that level.
var defeated_enemies: Dictionary = {}

# menu_layer.gd uses this same array, so unlocking a level is remembered.
# Greed is open from the start for now (Anger, the level before it, isn't built yet).
const DEFAULT_UNLOCKED = ["Sloth", "Gluttony", "Lust", "Greed"]
var unlocked_levels = DEFAULT_UNLOCKED.duplicate()

# "en" or "es" - set by the English / Español buttons in the main menu.
# Always change it with set_language() so all the text switches too.
var language = "en"
signal language_changed(new_language)

# ---- Player profile + lifetime stat (church leaderboards, online_service.gd) ----
# Kept in their own small file (user://profile.cfg, written right away) AND
# in the save file. Loading an older save never LOWERS lifetime_defeats, so
# the leaderboard number only goes up.
const PROFILE_PATH = "user://profile.cfg"
var profile_name = ""            # the name shown on leaderboards and on phones
var church = {}                  # {"id", "name", "city", "region", "country"} or {} = none
var lifetime_defeats = 0         # every enemy you've ever defeated (never goes down)
signal profile_changed

# When a save is loaded we switch scenes first; the player then picks up
# its saved position from here in its _ready() (see apply_pending_player_state).
var pending_position = null


func _ready():
	TranslationServer.set_locale(language)
	load_profile()


# ---------------- Language ----------------

# Switches ALL the game's text (menus, messages, verse box...) and the verse
# language. Godot's TranslationServer picks the right column of
# translations/strings.csv; scripts listen to language_changed to redraw.
func set_language(new_language: String) -> void:
	language = new_language
	TranslationServer.set_locale(new_language)
	language_changed.emit(new_language)


# ---------------- Enemies ----------------

# Builds the [level, enemy path] pair that identifies an enemy.
func _enemy_id(enemy: Node) -> Array:
	var level_root = enemy.owner if enemy.owner else get_tree().current_scene
	if level_root == null:
		return ["", str(enemy.name)]
	return [level_root.scene_file_path, str(level_root.get_path_to(enemy))]


func mark_enemy_defeated(enemy: Node) -> void:
	# Lifetime stat: +1 for every defeat (counted once per enemy, even if it
	# takes extra hits on the way out)
	if not enemy.has_meta("defeat_counted"):
		enemy.set_meta("defeat_counted", true)
		add_lifetime_defeats(1)
	var id = _enemy_id(enemy)
	if not defeated_enemies.has(id[0]):
		defeated_enemies[id[0]] = []
	if not (id[1] in defeated_enemies[id[0]]):
		defeated_enemies[id[0]].append(id[1])


func is_enemy_defeated(enemy: Node) -> bool:
	var id = _enemy_id(enemy)
	return defeated_enemies.has(id[0]) and id[1] in defeated_enemies[id[0]]


func add_lifetime_defeats(amount: int) -> void:
	lifetime_defeats += amount
	save_profile()
	profile_changed.emit()
	if has_node("/root/OnlineService"):
		get_node("/root/OnlineService").record_defeats(amount)   # leaderboard (queued if offline)


# ---------------- Profile (name, church, lifetime defeats) ----------------

func set_profile(new_name: String, new_church: Dictionary) -> void:
	profile_name = new_name
	church = new_church.duplicate()
	save_profile()
	profile_changed.emit()

func save_profile() -> void:
	var config = ConfigFile.new()
	config.set_value("profile", "name", profile_name)
	config.set_value("profile", "church", church)
	config.set_value("profile", "lifetime_defeats", lifetime_defeats)
	config.save(PROFILE_PATH)

func load_profile() -> void:
	var config = ConfigFile.new()
	if config.load(PROFILE_PATH) != OK:
		return
	profile_name = config.get_value("profile", "name", "")
	church = config.get_value("profile", "church", {})
	lifetime_defeats = int(config.get_value("profile", "lifetime_defeats", 0))


# ---------------- Picked-up items ----------------

func mark_pickup_collected(pickup: Node) -> void:
	var id = _enemy_id(pickup)   # (same "level + node path" id as enemies)
	if not collected_pickups.has(id[0]):
		collected_pickups[id[0]] = []
	if not (id[1] in collected_pickups[id[0]]):
		collected_pickups[id[0]].append(id[1])


func is_pickup_collected(pickup: Node) -> bool:
	var id = _enemy_id(pickup)
	return collected_pickups.has(id[0]) and id[1] in collected_pickups[id[0]]


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
	PartyManager.reset_hp()   # party members back to full health too


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
	config.set_value("progress", "party", PartyManager.current)
	config.set_value("progress", "party_hp", PartyManager.member_hp)
	config.set_value("items", "inventory", Inventory.get_save_data())
	config.set_value("items", "key_items", Inventory.get_key_save_data())
	config.set_value("items", "collected_pickups", collected_pickups)

	var verses = VerseManager.get_save_data()
	config.set_value("verses", "discovered", verses.discovered)
	config.set_value("verses", "used_this_cycle", verses.used_this_cycle)

	config.set_value("enemies", "defeated", defeated_enemies)
	config.set_value("enemies", "defeated_count", get_defeated_count())  # just for reading the file
	config.set_value("profile", "name", profile_name)
	config.set_value("profile", "church", church)
	config.set_value("profile", "lifetime_defeats", lifetime_defeats)

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
	unlocked_levels.append_array(config.get_value("progress", "unlocked_levels", DEFAULT_UNLOCKED))
	# Levels added after the save was made are still open
	for level_name in DEFAULT_UNLOCKED:
		if level_name not in unlocked_levels:
			unlocked_levels.append(level_name)

	set_language(config.get_value("progress", "language", "en"))
	PartyManager.current = config.get_value("progress", "party", PartyManager.DEFAULT_MEMBER)
	PartyManager.member_hp = config.get_value("progress", "party_hp", {})
	Inventory.load_save_data(config.get_value("items", "inventory", {}))
	Inventory.load_key_save_data(config.get_value("items", "key_items", []))
	collected_pickups = config.get_value("items", "collected_pickups", {})

	VerseManager.load_save_data({
		"discovered": config.get_value("verses", "discovered", []),
		"used_this_cycle": config.get_value("verses", "used_this_cycle", []),
	})

	defeated_enemies = config.get_value("enemies", "defeated", {})
	profile_name = config.get_value("profile", "name", profile_name)
	church = config.get_value("profile", "church", church)
	lifetime_defeats = max(lifetime_defeats, int(config.get_value("profile", "lifetime_defeats", 0)))
	save_profile()
	profile_changed.emit()

	var level = config.get_value("progress", "level", "")
	if change_level and level != "" and ResourceLoader.exists(level):
		get_tree().change_scene_to_file.call_deferred(level)
	else:
		PartyManager.ensure_party()
	print("Game loaded")
	return true
