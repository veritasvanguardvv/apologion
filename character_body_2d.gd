extends CharacterBody2D

var hp = 100
var speed = 200
var jump_velocity = -400
var gravity = 980
var language = "en"
var current_filter = "all"  # "all", "light", "zeal", "lust"

# Turn-based battles (see turn_manager.gd). Higher battle_speed = acts earlier
# in each round. ("speed" above is walking speed - a different thing.)
@export var battle_speed = 10
var display_name = "You"

var base_scale_light = 1.2
var base_scale_near = 0.6
var base_scale_halo = 2.5
var flicker_time = 0.0
var light_timer = 0.0
var light_duration = 0.0
var lamp_flicker_timer = 0.0
var lamp_next_flicker = 0.0
var lamp_base_energy = 0.9

@onready var hp_bar = get_parent().get_node("CanvasLayer/HPBar")
@onready var light = $PointLight2D
@onready var near_light = get_node_or_null("NearLight")
@onready var halo = get_node_or_null("Halo")
@onready var lamp = get_node_or_null("Lamp")
@onready var verse_input = get_parent().get_node("CanvasLayer/LineEdit")
@onready var verse_panel = get_parent().get_node_or_null("VerseListLayer/VersePanel")
@onready var verse_text = get_parent().get_node_or_null("VerseListLayer/VersePanel/VerseText")

# "discovered": true here means "the player starts the game knowing this verse".
# The live discovered / used-this-cycle lists are kept in VerseManager
# (verse_manager.gd) so they survive scene changes and saving.
# The last three entries were added so every verse that has an effect
# (lust_verses / light_verses below) also shows up in the verse box.
var all_verses = [
	{"ref": "Matthew 5:28", "type": "lust", "damage": 100, "discovered": true, "en": "everyone who gazes at a woman to lust after her has committed adultery in his heart.", "es": "todo el que mira a una mujer para codiciarla ya cometió adulterio en su corazón."},
	{"ref": "Psalm 18:28", "type": "light", "damage": 50, "discovered": false, "en": "the lord, my god, lights up my darkness."},
	{"ref": "Romans 12:11", "type": "zeal", "damage": 50, "discovered": false, "en": "never lag in diligence. let the spirit excite you as you serve the lord."},
	{"ref": "1 Corinthians 6:18", "type": "lust", "damage": 50, "discovered": false, "en": "flee sexual immorality!", "es": "¡huyan de la inmoralidad sexual!"},
	{"ref": "Proverbs 6:32", "type": "lust", "damage": 50, "discovered": false, "en": "he who commits adultery is a fool who destroys himself.", "es": "el que comete adulterio es un necio que se destruye a sí mismo."},
	{"ref": "Psalm 18:28a", "type": "light", "damage": 50, "discovered": false, "en": "you light a lamp for me."},
	{"ref": "Psalm 119:105", "type": "light", "damage": 50, "discovered": false, "en": "your word is a lamp to my feet, and a light for my path."}
]

var lust_verses = [
	{"ref": "matthew 5:28", "en": "Everyone who gazes at a woman to lust after her has committed adultery in his heart.", "es": "todo el que mira a una mujer para codiciarla ya cometió adulterio en su corazón.", "damage": 100},
	{"ref": "1 corinthians 6:18a", "en": "Flee sexual immorality!", "es": "¡huyan de la inmoralidad sexual!", "damage": 50},
	{"ref": "proverbs 6:32", "en": "He who commits adultery is a fool who destroys himself.", "es": "el que comete adulterio es un necio que se destruye a sí mismo.", "damage": 50}
]

var light_verses = [
	{"ref": "Psalm 18:28b", "text": "The lord, my god, lights up my darkness."},
	{"ref": "Psalm 18:28a", "text": "You light a lamp for me."},
	{"ref": "Psalm 119:105", "text": "Your word is a lamp to my feet, and a light for my path."}
]

var zeal_verses = [
	{"ref": "romans 12:11", "text": "never lag in diligence. let the spirit excite you as you serve the lord."}
]

var bible_books = ["psalm", "psalms", "proverb", "proverbs", "matthew", "romans", "corinthians"]

const DEFAULT_PLACEHOLDER = "Press 'Enter' or click here to start Scripture recitation"
var message_id = 0  # used by _show_verse_message so old messages don't overwrite new ones

func _ready():
	add_to_group("player")  # lets SaveManager find the player when saving
	verse_input.text_submitted.connect(_on_verse_submitted)
	verse_input.placeholder_text = DEFAULT_PLACEHOLDER
	
	# Health comes from SaveManager (full HP on a new level, saved HP after loading)
	hp = SaveManager.player_hp
	hp_bar.value = hp
	language = SaveManager.language  # "en" or "es", chosen with the menu's language button
	# If we just loaded a save, move to the saved position
	SaveManager.apply_pending_player_state(self)
	
	# Tell VerseManager about the verses the player starts with
	for v in all_verses:
		if v.discovered:
			VerseManager.discover(v.ref)
		v.discovered = VerseManager.is_discovered(v.ref)
	# Redraw the verse box whenever a verse is discovered or used
	VerseManager.verses_changed.connect(_update_verse_text)
	
	# Sloth and Gluttony don't have a verse box in the scene, so build one
	if not verse_panel:
		_build_verse_panel()
	verse_panel.visible = false
	verse_text.bbcode_enabled = true  # allows colors in the verse list
	_update_verse_text()
	print("Player ready. Verse panel: ", verse_panel)
	var filter_btn = verse_panel.get_node_or_null("FilterButton")
	if filter_btn:
		filter_btn.focus_mode = Control.FOCUS_NONE  # so Enter/Space don't press it by accident
		filter_btn.pressed.connect(_on_filter_pressed)
	if lamp:
		lamp.energy = lamp_base_energy

func _on_filter_pressed():
	match current_filter:
		"all": current_filter = "light"
		"light": current_filter = "zeal"
		"zeal": current_filter = "lust"
		"lust": current_filter = "all"
	var filter_btn = verse_panel.get_node_or_null("FilterButton")
	if filter_btn:
		filter_btn.text = "Filter: " + current_filter.capitalize()
	_update_verse_text()

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER and not verse_input.has_focus():
		verse_input.grab_focus()
		get_viewport().set_input_as_handled()
	
	if event.is_action_pressed("ui_up") and not verse_input.has_focus():
		var prompt = get_parent().get_node_or_null("NPC/PromptLabel")
		if prompt and prompt.text == "Press Up to talk":
			prompt.text = "Life's so stressful..."
	
	# Tab = show/hide the verse box ("toggle_verse_box" in Project Settings > Input Map).
	# Works while typing too. set_input_as_handled() stops Godot from also using
	# Tab to move keyboard focus out of the LineEdit.
	if event.is_action_pressed("toggle_verse_box"):
		get_viewport().set_input_as_handled()
		if verse_panel:
			verse_panel.visible = not verse_panel.visible
			print("Tab pressed - panel visible: ", verse_panel.visible)
			if verse_panel.visible:
				_update_verse_text()

func _on_verse_submitted(text):
	var lower = text.to_lower().strip_edges()
	
	# --- Battles (see turn_manager.gd) ---
	# In a battle you can only recite on your own turn.
	if TurnManager.in_battle and not TurnManager.is_players_turn():
		_show_verse_message("Wait for your turn!")
		_finish_typing()
		return
	
	# --- Verse cycle (see verse_manager.gd) ---
	# Figure out which verse was typed. A new verse gets discovered (and can be
	# used right away). A verse already used this cycle is blocked until all
	# the other discovered verses have been used too.
	var typed_verse = _find_verse(lower)
	if typed_verse:
		if VerseManager.discover(typed_verse.ref):
			typed_verse.discovered = true
			_show_verse_message("New verse discovered: " + typed_verse.ref + "!")
			print("Discovered: ", typed_verse.ref)
		if not VerseManager.can_use(typed_verse.ref):
			_show_verse_message("%s was already used - recite your other %d verse(s) first (Tab to see them)" % [typed_verse.ref, VerseManager.remaining_count()])
			print(typed_verse.ref, " is on cooldown")
			_finish_typing()
			return   # in a battle this does NOT use up your turn
		VerseManager.mark_used(typed_verse.ref)
	elif TurnManager.in_battle:
		# Not a verse we recognise: let the player try again (turn not used)
		_show_verse_message("That's not a verse you know - try again")
		_finish_typing()
		return
	
	_finish_typing()
	
	# The player's verses hit the nearest enemy (no range limit, like before)
	apply_verse_effects(lower, get_nearest_enemy())
	
	# A real verse was recited: if it was our battle turn, the turn is over
	if TurnManager.is_players_turn():
		TurnManager.player_turn_finished.emit()

# Empties the verse box and gives keyboard control back to the game.
func _finish_typing():
	verse_input.clear()
	verse_input.release_focus()
	get_viewport().gui_release_focus()

# Runs the effects of a recited verse. Used by the player (above) and by party
# members like Pastor Ramuel (party_member.gd), so the effects live in one place.
#   lower        = the verse text in lowercase
#   enemy        = the enemy lust verses should hit (can be null)
#   damage_scale = multiplies lust damage (party members can hit softer/harder)
# Light and zeal verses always power up the player.
func apply_verse_effects(lower: String, enemy, damage_scale := 1.0):
	# Only run the effect type of the verse that matches best. (Without this,
	# Matthew 5:28 was similar enough to Romans 12:11 to also trigger zeal.)
	var best = _find_verse(lower)
	var only_type = best.type if best else ""   # "" = unknown, try them all like before
	
	# Lust damage
	for verse in (lust_verses if only_type in ["", "lust"] else []):
		var target = verse.en if language == "en" else verse.es
		if lower.similarity(target) > 0.5 or lower.similarity(verse.ref) > 0.6:
			if enemy and is_instance_valid(enemy) and enemy.has_method("take_damage"):
				enemy.take_damage(verse.damage * damage_scale)
				print("Hit for ", verse.damage * damage_scale, "%")
			break
	
	# Light
	var matched = false
	var duration = 70.0
	for verse in (light_verses if only_type in ["", "light"] else []):
		if lower.similarity(verse.text) > 0.4 or lower.similarity(verse.ref) > 0.6:
			matched = true
			break
	if matched:
		light_timer = 0.0
		light_duration = duration
		if light: light.energy = 1.0
		if near_light: near_light.energy = 1.0
		if halo: halo.energy = 0.8
		if lamp:
			lamp.energy = 0.8
	
	# Zeal
	for verse in (zeal_verses if only_type in ["", "zeal"] else []):
		if lower.similarity(verse.text) > 0.4 or lower.similarity(verse.ref) > 0.6:
			jump_velocity = -700
			speed = 400
			var timer_label = get_parent().get_node_or_null("CanvasLayer/TimerLabel")
			if timer_label:
				for i in range(3, 0, -1):
					timer_label.text = str(i)
					await get_tree().create_timer(1.0).timeout
				timer_label.text = ""
			jump_velocity = -400
			speed = 200
			break

func _physics_process(delta):
	if not is_on_floor():
		velocity.y += gravity * delta
	# During a battle you stay where you are (no walking or jumping)
	var in_battle = TurnManager.in_battle
	if Input.is_action_just_pressed("ui_select") and is_on_floor() and not verse_input.has_focus() and not in_battle:
		velocity.y = jump_velocity
	var direction = 0.0 if in_battle else Input.get_axis("ui_left", "ui_right")
	velocity.x = direction * speed if direction else move_toward(velocity.x, 0, speed)
	move_and_slide()

func _process(delta):
	flicker_time += delta
	var flicker_amount = 0.94 + sin(flicker_time * 8.0) * 0.04 + randf_range(-0.02, 0.02)
	
	if light_duration > 0.0:
		light_timer += delta
		var t = clamp(light_timer / light_duration, 0.0, 1.0)
		var fade = 1.0 - t
		var wave = sin(light_timer * 3.0) * 0.08 * fade
		
		if light:
			light.energy = fade * flicker_amount
			light.texture_scale = base_scale_light * (fade + wave)
		if near_light:
			near_light.energy = fade * flicker_amount
			near_light.texture_scale = base_scale_near * (fade + wave)
		if halo:
			halo.energy = fade * flicker_amount * 0.7
			halo.texture_scale = base_scale_halo * (fade + wave)
		# Neon-style random flicker for the Lamp (always on)
	if lamp:
		lamp_flicker_timer += delta
		if lamp_flicker_timer >= lamp_next_flicker:
			lamp_flicker_timer = 0.0
			lamp_next_flicker = randf_range(0.02, 0.15)  # lower = more frequent flickers
		if randf() < 0.6:                             # higher = more often it dips
			lamp.energy = lamp_base_energy * randf_range(0.1, 0.5)  # lower numbers = stronger/darker dips
		else:
			lamp.energy = lamp_base_energy * randf_range(0.7, 1.2)
			
		
		if light_timer >= light_duration:
			light_duration = 0.0
			if light: light.energy = 0
			if near_light: near_light.energy = 0
			if halo: halo.energy = 0
		

func _update_verse_text():
	if not verse_text:
		return
	var display = "Ready this cycle: %d of %d\n\n" % [VerseManager.remaining_count(), VerseManager.discovered.size()]
	var sorted = all_verses.duplicate()
	if current_filter != "all":
		sorted.sort_custom(func(a, b):
			var a_match = a.type == current_filter
			var b_match = b.type == current_filter
			if a_match and not b_match: return true
			if b_match and not a_match: return false
			return false
		)
	for v in sorted:
		var is_found = VerseManager.is_discovered(v.ref)
		if current_filter != "all" and v.type != current_filter and is_found:
			continue  # optional: hide non-matching when filtering
		if is_found:
			var verse_body = v.en if language == "en" else v.get("es", v.en)
			# Used verses are greyed out until the cycle resets; ready ones are green
			var used = VerseManager.is_used(v.ref)
			var color = "gray" if used else "lightgreen"
			var status = "(used)" if used else "(ready)"
			display += "[color=%s]%s  %s\n%d%%  |  %s\n%s[/color]\n\n" % [color, v.ref, status, v.damage, v.type.capitalize(), verse_body]
		else:
			display += "???\n??%  |  ???\n\n"
	verse_text.text = display

func discover_verse(ref_name: String):
	for v in all_verses:
		if v.ref == ref_name:
			v.discovered = true
			VerseManager.discover(v.ref)
			break
	_update_verse_text()
	
func mark_discovered_by_text(text: String):
	var lower = text.to_lower()
	for v in all_verses:
		if lower.similarity(v.en.to_lower()) > 0.45 or lower.similarity(v.ref.to_lower()) > 0.55:
			v.discovered = true
			VerseManager.discover(v.ref)
			_update_verse_text()
			print("Discovered: ", v.ref)
			return


# Where the player's body really is. The sprite and collision shape are moved
# away from the player's origin in the scenes, so use the collision shape.
func get_body_center() -> Vector2:
	var shape = get_node_or_null("CollisionShape2D")
	return shape.global_position if shape else global_position

# Finds the closest living enemy (every enemy using enemy.gd is in the
# "enemies" group). Returns null if there are none. If max_distance is more
# than 0, enemies further away than that are ignored.
# from_position defaults to the player's body (its collision shape).
func get_nearest_enemy(from_position = null, max_distance := 0.0):
	if from_position == null:
		from_position = get_body_center()
	var nearest = null
	var nearest_distance = INF
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.is_queued_for_deletion():
			continue
		var distance = from_position.distance_to(enemy.get_center())
		if max_distance > 0.0 and distance > max_distance:
			continue
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = enemy
	return nearest

# Returns the entry from all_verses that best matches what the player typed
# (by verse text or by reference), or null if nothing matches well enough.
# Uses the same kind of similarity check as the verse effects above.
func _find_verse(lower: String):
	var best = null
	var best_score = 0.0
	for v in all_verses:
		var text_score = max(lower.similarity(v.en.to_lower()), lower.similarity(v.get("es", "").to_lower()))
		var ref_score = lower.similarity(v.ref.to_lower())
		if text_score > 0.4 or ref_score > 0.6:
			var score = max(text_score, ref_score)
			if score > best_score:
				best_score = score
				best = v
	return best

# Shows a short message in the verse input box (as its grey placeholder text),
# then puts the normal placeholder back after a few seconds.
func _show_verse_message(msg: String):
	message_id += 1
	var my_id = message_id
	verse_input.placeholder_text = msg
	await get_tree().create_timer(3.0).timeout
	if my_id == message_id and is_instance_valid(verse_input):
		verse_input.placeholder_text = DEFAULT_PLACEHOLDER

# Called by the menu's language button ("en" or "es").
# Typed lust verses are then checked against the Spanish text, and the
# verse box shows Spanish where a translation exists.
func set_language(new_language: String):
	language = new_language
	_update_verse_text()

# Player health. Use this (instead of changing hp directly) so the HP bar
# and SaveManager stay up to date. Nothing damages the player yet, but
# enemies can call player.take_damage(10) later.
func set_hp(value):
	hp = clamp(value, 0, SaveManager.MAX_HP)
	hp_bar.value = hp
	SaveManager.player_hp = hp

func take_damage(amount):
	set_hp(hp - amount)

# Builds the same verse box that Lust.tscn has, for scenes that don't have one.
# (It's added under the player, so you won't see it in the editor's scene tree.)
func _build_verse_panel():
	var layer = CanvasLayer.new()
	layer.name = "VerseListLayer"
	add_child(layer)
	verse_panel = Panel.new()
	verse_panel.name = "VersePanel"
	verse_panel.position = Vector2(30, 187)
	verse_panel.size = Vector2(574, 180)
	layer.add_child(verse_panel)
	verse_text = RichTextLabel.new()
	verse_text.name = "VerseText"
	verse_text.size = Vector2(571, 177)
	verse_panel.add_child(verse_text)
	var title = Label.new()
	title.text = "Verses (Tab to close)"
	title.position = Vector2(207, -31)
	verse_panel.add_child(title)
	var filter_btn = Button.new()
	filter_btn.name = "FilterButton"
	filter_btn.text = "Filter: All"
	filter_btn.position = Vector2(470, -35)
	verse_panel.add_child(filter_btn)
