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

# A battle starts when an enemy's body (its collision shape) is close to
# yours, measured edge to edge: at most encounter_range pixels of empty space
# sideways AND at most encounter_height pixels above/below - so you have to be
# at about the same height. Enemies on a ledge above you no longer start a
# battle from far away. (Edge to edge, so big enemies and small ones work alike.)
var encounter_range = 120.0   # sideways gap (pixels). 0 = no battles (used by tests)
var encounter_height = 60.0   # up/down gap (pixels); 0 = the bodies must overlap in height
var turn_delay = 1.0          # pause before a party member / enemy acts (seconds)
var after_turn_pause = 0.6    # pause after each turn so you can read what happened
var intro_time = 1.0          # how long "An enemy appears!" shows
var run_grace_time = 5.0      # after running, an enemy you stay close to attacks again after this many seconds
var group_join_range = 250.0  # enemies within this sideways gap of an enemy in the battle join it too...
var group_join_height = 60.0  # ...if they're also within this up/down gap

signal battle_started
signal battle_ended
signal turn_started(combatant)
signal player_turn_finished   # emitted by the player after a valid verse
signal round_ended            # after everyone has had their turn (the guard counts these)

const BATTLE_SOUND = "res://General/Sounds/battle1low.mp3"   # plays once when a battle starts
var battle_sound: AudioStreamPlayer

var in_battle = false
var encounters_paused = false # true during a cut-scene: walking near enemies starts no battle
var current = null            # whose turn it is right now
var battle_enemies = []       # enemies in this battle
var battle_id = 0             # changes every battle; stops old battles if the scene changes

var turn_label: Label
var run_button: Button
var items_button: Button
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
	
	# Run button, top-left beside the player's portrait (like the Unity HUD).
	# Only shown during battles.
	run_button = Button.new()
	run_button.text = "Run (R)"
	run_button.position = Vector2(HUD_RUN_POS)
	run_button.size = Vector2(120, 34)
	run_button.focus_mode = Control.FOCUS_NONE   # so Enter/Space don't press it by accident
	run_button.visible = false
	run_button.pressed.connect(run_away)
	layer.add_child(run_button)
	# Items button, top-left beside Run (or in Run's place outside battles).
	# Shown all through gameplay; click / tap = the inventory key.
	items_button = Button.new()
	items_button.name = "ItemsButton"
	items_button.position = Vector2(HUD_RUN_POS)
	items_button.custom_minimum_size = Vector2(120, 34)
	items_button.size = Vector2(120, 34)
	items_button.focus_mode = Control.FOCUS_NONE
	items_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # text is built (and translated) in _update_items_text
	items_button.visible = false
	items_button.pressed.connect(_on_items_pressed)
	layer.add_child(items_button)
	_update_items_text()
	GameSettings.bindings_changed.connect(_update_items_text)
	GameSettings.touch_controls_changed.connect(func(_on): _update_items_text())
	# Skip and Target buttons, bottom-right
	skip_button = _make_side_button("Skip (K)", -56, skip_turn)
	layer.add_child(skip_button)
	# (on a Mac the Alt key is called Option)
	target_button = _make_side_button("Target (Option)" if OS.get_name() == "macOS" else "Target (Alt)", -104, Targeting.cycle)
	layer.add_child(target_button)
	# Enemy name / portrait / HP in the top-right corner during battles
	enemy_hud = VBoxContainer.new()
	enemy_hud.name = "EnemyHUD"
	enemy_hud.anchor_left = 1.0
	enemy_hud.anchor_right = 1.0
	enemy_hud.offset_left = -270
	enemy_hud.offset_right = -10
	enemy_hud.offset_top = 10
	enemy_hud.add_theme_constant_override("separation", 6)
	enemy_hud.visible = false
	layer.add_child(enemy_hud)
	battle_started.connect(_build_enemy_hud)
	battle_ended.connect(func(): enemy_hud.visible = false)
	
	# Language switched mid-battle: redo the "your turn" message
	# (and hide an old message like "Got away safely!" when not in a battle)
	SaveManager.language_changed.connect(_on_language_changed)
	
	# Battle start sound (plays once, never loops)
	battle_sound = AudioStreamPlayer.new()
	battle_sound.stream = load(BATTLE_SOUND)
	if battle_sound.stream and "loop" in battle_sound.stream:
		battle_sound.stream.loop = false
	add_child(battle_sound)


# ---------------- HUD (laid out like the Unity version) ----------------
# Top-left: the player's portrait, Run beside it, HP under it (see
# character_body_2d.gd _layout_hud). Top-right during a battle: each enemy's
# name, portrait and HP.
const HUD_RUN_POS = Vector2i(74, 14)
var enemy_hud: VBoxContainer
var enemy_rows = {}     # enemy -> [row, hp bar, hp label]

func _build_enemy_hud():
	for c in enemy_hud.get_children():
		c.queue_free()
	enemy_rows.clear()
	for e in battle_enemies:
		if not is_instance_valid(e):
			continue
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var col = VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 2)
		var name_label = Label.new()
		name_label.text = tr(e.display_name)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		name_label.add_theme_color_override("font_color", Color(1, 0.55, 0.5))
		name_label.add_theme_color_override("font_outline_color", Color.BLACK)
		name_label.add_theme_constant_override("outline_size", 5)
		col.add_child(name_label)
		var bar = ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 22)
		bar.show_percentage = false
		bar.max_value = e.max_hp
		bar.value = e.hp
		var fill = StyleBoxFlat.new()
		fill.bg_color = Color(0.8, 0.12, 0.15)
		bar.add_theme_stylebox_override("fill", fill)
		var hp_label = Label.new()
		hp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hp_label.add_theme_font_size_override("font_size", 14)
		hp_label.add_theme_color_override("font_outline_color", Color.BLACK)
		hp_label.add_theme_constant_override("outline_size", 4)
		bar.add_child(hp_label)
		col.add_child(bar)
		row.add_child(col)
		row.add_child(make_portrait(portrait_of(e), Color(0.8, 0.15, 0.15)))
		enemy_hud.add_child(row)
		enemy_rows[e] = [row, bar, hp_label]
	enemy_hud.visible = not enemy_rows.is_empty()
	_update_enemy_hud()

func _update_enemy_hud():
	for e in enemy_rows.keys():
		var r = enemy_rows[e]
		if not is_instance_valid(e) or e.hp <= 0:
			if is_instance_valid(r[0]):
				r[0].modulate.a = 0.35
			if is_instance_valid(r[1]):
				r[1].value = 0
				r[2].text = "0 / %d" % (r[1].max_value)
			continue
		r[1].value = e.hp
		r[2].text = "%d / %d" % [ceil(e.hp), e.max_hp]

func _process(_delta):
	if enemy_hud and enemy_hud.visible:
		_update_enemy_hud()

# A small framed portrait (like the Unity HUD's face boxes)
static func make_portrait(tex: Texture2D, border := Color(0.9, 0.9, 0.9)) -> Control:
	var frame = Panel.new()
	frame.custom_minimum_size = Vector2(56, 56)
	frame.size = Vector2(56, 56)
	var box = StyleBoxFlat.new()
	box.bg_color = Color(0.08, 0.08, 0.12, 0.85)
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(4)
	frame.add_theme_stylebox_override("panel", box)
	var pic = TextureRect.new()
	pic.name = "Picture"
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.position = Vector2(4, 4)
	pic.size = Vector2(48, 48)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(pic)
	return frame

# A still picture of a character for its portrait: one frame of its sprite,
# cropped to the drawn pixels. frame = -1: the sprite's current frame.
static func portrait_of(node: Node, frame := -1) -> Texture2D:
	var sprite = null
	if node is Sprite2D or node is AnimatedSprite2D:
		sprite = node
	else:
		for c in node.get_children():
			if (c is Sprite2D or c is AnimatedSprite2D) and c.visible:
				sprite = c
				break
	if sprite == null:
		return null
	var tex: Texture2D = null
	var region = Rect2()
	if sprite is AnimatedSprite2D:
		if sprite.sprite_frames == null:
			return null
		var f = sprite.frame if frame < 0 else frame
		tex = sprite.sprite_frames.get_frame_texture(sprite.animation, f)
	else:
		tex = sprite.texture
		if tex == null:
			return null
		if sprite.region_enabled:
			region = sprite.region_rect
		else:
			var size = tex.get_size() / Vector2(sprite.hframes, sprite.vframes)
			var f = sprite.frame if frame < 0 else frame
			region = Rect2(Vector2(f % sprite.hframes, f / sprite.hframes) * size, size)
	if tex is AtlasTexture:
		region = tex.region if region == Rect2() else region
		tex = tex.atlas
	if tex == null:
		return null
	if region == Rect2():
		region = Rect2(Vector2.ZERO, tex.get_size())
	var img = tex.get_image()
	if img:
		if img.is_compressed():
			img.decompress()
		var used = img.get_region(Rect2i(region)).get_used_rect()
		if used.size.x > 0:
			region = Rect2(region.position + Vector2(used.position), Vector2(used.size))
	var atlas = AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = region
	return atlas


# A button in the bottom-right corner, "top" pixels from the bottom
# ---------------- Items button (top-left) ----------------
# "Items (Ctrl)": the key is the player's CURRENT inventory key (Settings >
# Controls), so it follows a rebind. With the on-screen touch buttons on
# there's no keyboard, so it just says "Items".
const HUD_GAP = 8

func _update_items_text():
	if items_button == null:
		return
	var touch = get_node_or_null("/root/TouchControls")
	if touch and touch.wanted():
		items_button.text = tr("Items")
	else:
		var key = GameSettings.key_name("toggle_inventory")
		items_button.text = tr("Items (%s)") % key if key != "-" else tr("Items")
	items_button.size = items_button.get_combined_minimum_size()

func _on_items_pressed():
	if _items_allowed(get_tree().get_first_node_in_group("player")):
		Inventory.toggle()

# When the Items button would be wrong to show: no player (menus, loading),
# the main / pause menu, a cut-scene (player.cutscene_lock - also covers the
# Idolatry Cam replay and SinDeath's dialogue), a full-screen overlay
# (group "hud_hidden_overlay"), or the inventory already open.
func _items_allowed(player) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if player.get("cutscene_lock"):
		return false
	var menus = get_tree().get_first_node_in_group("menus")
	if menus and (menus.is_main_menu_open() or menus.pause_menu.visible):
		return false
	for o in get_tree().get_nodes_in_group("hud_hidden_overlay"):
		if is_instance_valid(o) and o.get("visible") != false:
			return false
	return true

func _update_items_button(player):
	if items_button == null:
		return
	items_button.visible = _items_allowed(player) and not Inventory.is_open()
	# beside Run when Run is shown, otherwise in Run's spot
	var x = HUD_RUN_POS.x
	if run_button.visible:
		x = run_button.position.x + run_button.size.x + HUD_GAP
	items_button.position = Vector2(x, HUD_RUN_POS.y)
	# the level's Zeal countdown sits after the buttons (never under them)
	if player and "hp_bar" in player and is_instance_valid(player.hp_bar):
		var timer_label = player.hp_bar.get_parent().get_node_or_null("TimerLabel")
		if timer_label:
			var right = items_button.position.x + items_button.size.x if items_button.visible else (run_button.position.x + run_button.size.x if run_button.visible else float(HUD_RUN_POS.x))
			timer_label.position.x = right + HUD_GAP + 4


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

signal message_shown(text)   # phones show the battle messages too (phone_server.gd)

func show_message(text: String):
	message_count += 1
	turn_label.text = text
	turn_label.visible = true
	message_shown.emit(text)


func _on_language_changed(_new_language):
	_update_items_text()
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
var no_escape = false   # a boss fight (Greed's SinDeath): Run doesn't work

func run_away():
	if not is_players_turn():
		return
	if no_escape:
		show_message(tr("You can't run from this battle!"))
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
	_update_items_button(player)
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
	if player == null or encounters_paused:
		return
	# Look for enemies close enough to start a battle
	var enemies = []
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not _is_alive(enemy):
			continue
		var in_range = in_encounter_range(player, enemy)
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


# True if the enemy is close enough to the player to start a battle
func in_encounter_range(player: Node2D, enemy: Node2D) -> bool:
	if encounter_range <= 0.0:
		return false
	var gap = body_gap(player, enemy)
	return gap.x <= encounter_range and gap.y <= encounter_height

# Empty space between two bodies (x = sideways, y = up/down; 0 = they overlap)
func body_gap(a: Node2D, b: Node2D) -> Vector2:
	var ra = body_rect(a)
	var rb = body_rect(b)
	return Vector2(
		max(0.0, max(ra.position.x - rb.end.x, rb.position.x - ra.end.x)),
		max(0.0, max(ra.position.y - rb.end.y, rb.position.y - ra.end.y)))

# A body's rectangle in the world (from its CollisionShape2D)
static func body_rect(node: Node2D) -> Rect2:
	var shape = node.get_node_or_null("CollisionShape2D")
	if shape and shape.shape:
		var r = shape.shape.get_rect()
		var sc = shape.global_transform.get_scale().abs()
		return Rect2(shape.global_position + r.position * sc, r.size * sc)
	return Rect2(node.global_position - Vector2(30, 30), Vector2(60, 60))

# Enemies close to the ones starting the battle join in (a group fight)
func _add_nearby_enemies(enemies: Array):
	var added = true
	while added:
		added = false
		for other in get_tree().get_nodes_in_group("enemies"):
			if other in enemies or not _is_alive(other) or escaped_from.has(other):
				continue
			for e in enemies:
				var gap = body_gap(e, other)
				if gap.x <= group_join_range and gap.y <= group_join_height:
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
		if _is_alive(enemy) and not enemy.get("optional_target"):
			return true
	return false


# Starts a battle with exactly these enemies (a scripted boss fight,
# e.g. Greed's SinDeath scene). Ignores the encounter range.
func start_battle(enemies: Array):
	var player = get_tree().get_first_node_in_group("player")
	if in_battle or player == null or enemies.is_empty():
		return
	_run_battle(player, enemies.duplicate())


# The whole battle, round after round. (A coroutine: it pauses at each await.)
func _run_battle(player, enemies):
	in_battle = true
	battle_id += 1
	var my_battle = battle_id
	battle_enemies = enemies
	battle_started.emit()
	battle_sound.play()
	var first_name = tr(enemies[0].display_name)
	show_message((tr("A %s appears!") % first_name) if enemies.size() == 1 else tr("%d enemies appear!") % enemies.size())
	print("Battle started against ", enemies.size(), " enemy(s)")
	await get_tree().create_timer(intro_time).timeout

	while my_battle == battle_id and _enemies_left():
		# Who's fighting this round (anyone defeated is left out)
		var order = [player]
		order.append_array(get_tree().get_nodes_in_group("party"))
		for enemy in battle_enemies:
			if _is_alive(enemy) and not enemy.get("passive"):
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
				show_message(tr("%s's turn") % tr(fighter.display_name))
				await get_tree().create_timer(turn_delay).timeout
				if my_battle != battle_id:
					return
				if _is_alive(fighter):
					# take_turn() may return how long to wait (e.g. Pastor's
					# speech bubble) so the next turn doesn't start too soon.
					# Phone players: wait for their phone (with a time limit).
					var asked = null
					if fighter.get("player_controlled"):
						asked = await fighter.take_phone_turn()
						if my_battle != battle_id:
							return
					else:
						asked = fighter.take_turn()
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
	no_escape = false
	current = null
	battle_enemies = []
	battle_id += 1   # stops the battle coroutine if it is still waiting
	turn_label.visible = false
	if was_in_battle:
		battle_ended.emit()


func _player_defeated(my_battle):
	# Endless mode: no checkpoint or restart - the run ends (Game Over screen)
	var level = get_tree().current_scene
	if level and level.has_method("on_player_defeated"):
		show_message(tr("You were defeated!"))
		await get_tree().create_timer(2.0).timeout
		if my_battle != battle_id:
			return
		_end_battle()
		level.on_player_defeated()
		return
	var checkpoint = SaveManager.get_checkpoint() != null
	show_message(tr("You were defeated... back to the checkpoint") if checkpoint else tr("You were defeated... restarting the level"))
	await get_tree().create_timer(2.0).timeout
	if my_battle != battle_id:
		return
	_end_battle()
	SaveManager.respawn_after_death()   # full health again (at the checkpoint, if any)
	get_tree().reload_current_scene()
