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
#   SKIP: on your turn the Skip button (or K, when you're not typing) ends
#      your turn without a verse, but costs 10% of your max HP
#      (skip_turn_cost in character_body_2d.gd).
#   TARGET: the Target button (or Alt / Option) chooses who your verse hits
#      or heals - see targeting.gd.
#   GROUPS: enemies standing close to an enemy that starts a battle join the
#      same battle (group_join_range), so two Umbrids fight you together.
#   5. RUN: on your turn press the Run button (or R, when you're not typing) to
#      leave the battle. Enemies keep their HP, type and status. The battle
#      won't start again until you walk out of the enemy's range - or, if you
#      stay close, after run_grace_time seconds.
#
# Every combatant needs:  battle_speed (number)  and  display_name (text).
# Party members and enemies also need a take_turn() function.
# The numbers below can be changed right here in this file.

var encounter_range = 450.0   # how close (pixels) an enemy must be to start a battle
var turn_delay = 1.0          # pause before a party member / enemy acts (seconds)
var after_turn_pause = 0.6    # pause after each turn so you can read what happened
var intro_time = 1.0          # how long "An enemy appears!" shows
var run_grace_time = 5.0      # after running, an enemy you stay close to attacks again after this many seconds
var group_join_range = 400.0  # enemies this close to an enemy in the battle join it too

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
var run_button: Button
var skip_button: Button
var target_button: Button
var escaped_from = {}         # enemy -> seconds left before it can start a battle again (after Run)


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
	turn_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # messages come in already translated
	layer.add_child(turn_label)
	
	# Run button, bottom-right next to the verse box. Only shown during battles.
	run_button = Button.new()
	run_button.text = "Run (R)"
	run_button.anchor_left = 1.0
	run_button.anchor_right = 1.0
	run_button.anchor_top = 1.0
	run_button.anchor_bottom = 1.0
	run_button.offset_left = -126
	run_button.offset_right = -10
	run_button.offset_top = -56
	run_button.offset_bottom = -12
	run_button.focus_mode = Control.FOCUS_NONE   # so Enter/Space don't press it by accident
	run_button.visible = false
	run_button.pressed.connect(run_away)
	layer.add_child(run_button)
	# Skip and Target buttons, stacked above Run
	skip_button = _make_side_button("Skip (K)", -104, skip_turn)
	layer.add_child(skip_button)
	# (on a Mac the Alt key is called Option)
	target_button = _make_side_button("Target (Option)" if OS.get_name() == "macOS" else "Target (Alt)", -152, Targeting.cycle)
	layer.add_child(target_button)
	
	# Language switched mid-battle: redo the "your turn" message
	# (and hide an old message like "Got away safely!" when not in a battle)
	SaveManager.language_changed.connect(_on_language_changed)
	
	# Battle start sound (plays once, never loops)
	battle_sound = AudioStreamPlayer.new()
	battle_sound.stream = load(BATTLE_SOUND)
	if battle_sound.stream and "loop" in battle_sound.stream:
		battle_sound.stream.loop = false
	add_child(battle_sound)


# A button in the bottom-right corner (like Run), "top" pixels from the bottom
func _make_side_button(text: String, top: float, action: Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.anchor_left = 1.0
	button.anchor_right = 1.0
	button.anchor_top = 1.0
	button.anchor_bottom = 1.0
	button.offset_left = -126
	button.offset_right = -10
	button.offset_top = top
	button.offset_bottom = top + 44
	button.focus_mode = Control.FOCUS_NONE
	button.visible = false
	button.pressed.connect(func(): action.call())
	return button


# Shows a message at the top of the screen. Pass text that's already
# translated with tr() (it's often built from several parts).
var message_count = 0   # goes up with every message (so old timers don't hide new ones)

func show_message(text: String):
	message_count += 1
	turn_label.text = text
	turn_label.visible = true


func _on_language_changed(_new_language):
	if is_players_turn():
		show_message(tr("Your turn - type or say a verse"))
	elif not in_battle:
		turn_label.visible = false


func is_players_turn() -> bool:
	return in_battle and current != null and current.is_in_group("player")


# R (the "run_away" action in Project Settings > Input Map). When you're typing
# in the verse box the LineEdit takes the key, so typing "r" never runs away.
func _unhandled_input(event):
	var focus = get_viewport().gui_get_focus_owner()
	var typing = focus is LineEdit or focus is TextEdit
	if event.is_action_pressed("run_away") and not event.is_echo() and not typing:
		run_away()
	elif event.is_action_pressed("skip_turn") and not event.is_echo() and not typing:
		skip_turn()


# Skip your turn (only on your turn): costs some HP, see character_body_2d.gd
func skip_turn():
	if not is_players_turn():
		return
	var player = get_tree().get_first_node_in_group("player")
	var cost = player.pay_skip_cost()
	show_message(tr("You skipped your turn (-%s HP)") % str(snapped(cost, 0.1)))
	print("Skipped turn, -", cost, " HP")
	player_turn_finished.emit()


# Leave the battle (only on the player's turn). Enemies stay as they are.
func run_away():
	if not is_players_turn():
		return
	for enemy in battle_enemies:
		if _is_alive(enemy):
			escaped_from[enemy] = run_grace_time
	_end_battle()
	show_message(tr("Got away safely!"))
	var my_message = message_count
	print("Ran away")
	await get_tree().create_timer(1.5).timeout
	if not in_battle and message_count == my_message:
		turn_label.visible = false


func _physics_process(delta):
	var player = get_tree().get_first_node_in_group("player")
	# Run button: visible in battles, usable on your turn
	run_button.visible = in_battle
	run_button.disabled = not is_players_turn()
	skip_button.visible = in_battle
	skip_button.disabled = not is_players_turn()
	target_button.visible = in_battle
	target_button.disabled = not is_players_turn() or Targeting.get_options().size() <= 1
	if in_battle:
		# The level changed or the player disappeared: forget the battle
		if player == null or (current != null and not is_instance_valid(current)):
			_end_battle()
		# Every enemy was beaten while it was your turn (not by a verse of
		# yours): your turn is over, so the battle can end with a Victory
		elif is_players_turn() and not _enemies_left():
			player_turn_finished.emit()
		return
	if player == null:
		return
	# Look for enemies close enough to start a battle
	var enemies = []
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not _is_alive(enemy):
			continue
		var in_range = player.get_body_center().distance_to(enemy.get_center()) <= encounter_range
		# Recently escaped from? It waits until you leave its range or the grace time ends.
		if escaped_from.has(enemy):
			escaped_from[enemy] -= delta
			if not in_range or escaped_from[enemy] <= 0.0:
				escaped_from.erase(enemy)
			continue
		if in_range:
			enemies.append(enemy)
	# Forget enemies that were freed (level changed or defeated)
	for enemy in escaped_from.keys():
		if not is_instance_valid(enemy):
			escaped_from.erase(enemy)
	if not enemies.is_empty():
		_add_nearby_enemies(enemies)
		_run_battle(player, enemies)


# Enemies close to the ones starting the battle join in (a group fight)
func _add_nearby_enemies(enemies: Array):
	var added = true
	while added:
		added = false
		for other in get_tree().get_nodes_in_group("enemies"):
			if other in enemies or not _is_alive(other) or escaped_from.has(other):
				continue
			for e in enemies:
				if e.get_center().distance_to(other.get_center()) <= group_join_range:
					enemies.append(other)
					added = true
					break


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
	show_message((tr("A %s appears!") % first_name) if enemies.size() == 1 else tr("%d enemies appear!") % enemies.size())
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
				show_message(tr("Your turn - type or say a verse"))
				await player_turn_finished
				current = null   # your turn is over (no second verse or Run during the pause)
			else:
				show_message(tr("%s's turn") % fighter.display_name)
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
	show_message(tr("Victory!"))
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
	show_message(tr("You were defeated... restarting the level"))
	await get_tree().create_timer(2.0).timeout
	if my_battle != battle_id:
		return
	_end_battle()
	SaveManager.start_new_level()   # full health again
	get_tree().reload_current_scene()
