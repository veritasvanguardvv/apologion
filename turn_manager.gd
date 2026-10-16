extends Node
# TurnManager (autoload / singleton)
# -----------------------------------
# Turn-based battles, Pokémon-style.
#
# HOW A BATTLE WORKS
#   1. While exploring, if an enemy comes within encounter_range of the
#      player, a battle starts with: the player, every party member (group
#      "party", e.g. Pastor Ramuel) and every enemy in range (group "enemies").
#   2. Each round, everyone takes one turn, fastest first (highest
#      battle_speed). Ties go player first, then party, then enemies.
#   3. Player's turn: type a verse and press Enter (normal verse cycle rules).
#      A blocked or unknown verse does NOT use up your turn - just try again.
#      Party members and enemies take their turn automatically after a short
#      pause (turn_delay) so you can follow what's happening.
#   4. The battle ends when all the enemies in it are defeated.
#      If the player's HP reaches 0 the level restarts at full health.
#   During a battle the player and party can't walk or jump (typing still works).
#
# Every combatant needs:  battle_speed (number)  and  display_name (text).
# Party members and enemies also need a take_turn() function.
# The numbers below can be changed right here in this file.

var encounter_range = 450.0   # how close (pixels) an enemy must be to start a battle
var turn_delay = 1.0          # pause before a party member / enemy acts (seconds)
var after_turn_pause = 0.6    # pause after each turn so you can read what happened
var intro_time = 1.0          # how long "An enemy appears!" shows

signal battle_started
signal battle_ended
signal turn_started(combatant)
signal player_turn_finished   # emitted by the player after a valid verse
signal round_ended            # after everyone has had their turn (the guard counts these)

const BATTLE_SOUND = "res://battle1low.mp3"   # plays once when a battle starts
var battle_sound: AudioStreamPlayer

var in_battle = false
var current = null            # whose turn it is right now
var battle_enemies = []       # enemies in this battle
var battle_id = 0             # changes every battle; stops old battles if the scene changes

var turn_label: Label


func _ready():
	# Build the "whose turn is it" label. It lives on this autoload, so it
	# works in every level without adding anything to the scenes.
	var layer = CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	turn_label = Label.new()
	turn_label.anchor_left = 0.5
	turn_label.anchor_right = 0.5
	turn_label.offset_left = -300
	turn_label.offset_right = 300
	turn_label.offset_top = 20
	turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_label.add_theme_font_size_override("font_size", 24)
	turn_label.add_theme_color_override("font_outline_color", Color.BLACK)
	turn_label.add_theme_constant_override("outline_size", 6)
	turn_label.visible = false
	layer.add_child(turn_label)
	
	# Battle start sound (plays once, never loops)
	battle_sound = AudioStreamPlayer.new()
	battle_sound.stream = load(BATTLE_SOUND)
	if battle_sound.stream and "loop" in battle_sound.stream:
		battle_sound.stream.loop = false
	add_child(battle_sound)


func show_message(text: String):
	turn_label.text = text
	turn_label.visible = true


func is_players_turn() -> bool:
	return in_battle and current != null and current.is_in_group("player")


func _physics_process(_delta):
	var player = get_tree().get_first_node_in_group("player")
	if in_battle:
		# The level changed or the player disappeared: forget the battle
		if player == null or (current != null and not is_instance_valid(current)):
			_end_battle()
		return
	if player == null:
		return
	# Look for enemies close enough to start a battle
	var enemies = []
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if _is_alive(enemy) and player.get_body_center().distance_to(enemy.get_center()) <= encounter_range:
			enemies.append(enemy)
	if not enemies.is_empty():
		_run_battle(player, enemies)


func _is_alive(node) -> bool:
	return node != null and is_instance_valid(node) and not node.is_queued_for_deletion()


# Sort order: fastest first. On a tie: player, then party, then enemies.
func _group_rank(node) -> int:
	if node.is_in_group("player"): return 0
	if node.is_in_group("party"): return 1
	return 2

func _faster_first(a, b) -> bool:
	if a.battle_speed != b.battle_speed:
		return a.battle_speed > b.battle_speed
	return _group_rank(a) < _group_rank(b)


func _enemies_left() -> bool:
	for enemy in battle_enemies:
		if _is_alive(enemy):
			return true
	return false


# The whole battle, round after round. (A coroutine: it pauses at each await.)
func _run_battle(player, enemies):
	in_battle = true
	battle_id += 1
	var my_battle = battle_id
	battle_enemies = enemies
	battle_started.emit()
	battle_sound.play()
	var first_name = enemies[0].display_name
	show_message(("A %s appears!" % first_name) if enemies.size() == 1 else "%d enemies appear!" % enemies.size())
	print("Battle started against ", enemies.size(), " enemy(s)")
	await get_tree().create_timer(intro_time).timeout

	while my_battle == battle_id and _enemies_left():
		# Who's fighting this round (anyone defeated is left out)
		var order = [player]
		order.append_array(get_tree().get_nodes_in_group("party"))
		for enemy in battle_enemies:
			if _is_alive(enemy):
				order.append(enemy)
		order.sort_custom(_faster_first)

		for fighter in order:
			if my_battle != battle_id or not _enemies_left():
				break
			if not _is_alive(fighter):
				continue
			current = fighter
			turn_started.emit(fighter)
			var wait = after_turn_pause
			if fighter == player:
				show_message("Your turn - type a verse and press Enter")
				await player_turn_finished
			else:
				show_message("%s's turn" % fighter.display_name)
				await get_tree().create_timer(turn_delay).timeout
				if my_battle != battle_id:
					return
				if _is_alive(fighter):
					# take_turn() may return how long to wait (e.g. Pastor's
					# speech bubble) so the next turn doesn't start too soon
					var asked = fighter.take_turn()
					if asked is float or asked is int:
						wait = max(wait, asked)
			await get_tree().create_timer(wait).timeout
			if my_battle != battle_id:
				return
			# Player out of HP? Restart the level at full health.
			if _is_alive(player) and player.hp <= 0:
				_player_defeated(my_battle)
				return
		
		# Everyone has had a turn: the round is over
		if my_battle == battle_id and _enemies_left():
			round_ended.emit()

	if my_battle != battle_id:
		return  # an old battle from a previous scene: just stop
	print("Battle won")
	_end_battle()
	show_message("Victory!")
	await get_tree().create_timer(1.5).timeout
	if not in_battle:
		turn_label.visible = false


func _end_battle():
	var was_in_battle = in_battle
	in_battle = false
	current = null
	battle_enemies = []
	battle_id += 1   # stops the battle coroutine if it is still waiting
	turn_label.visible = false
	if was_in_battle:
		battle_ended.emit()


func _player_defeated(my_battle):
	show_message("You were defeated... restarting the level")
	await get_tree().create_timer(2.0).timeout
	if my_battle != battle_id:
		return
	_end_battle()
	SaveManager.start_new_level()   # full health again
	get_tree().reload_current_scene()
