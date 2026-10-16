extends CharacterBody2D

var hp = 100
var speed = 200
var jump_velocity = -400
var gravity = 980
var language = "en"
# Verse box filter (see _build_verse_panel). Three groups of verse types:
const FILTER_GROUPS = {
	"Attacks": ["sloth", "lust"],               # left button (no Sloth verses exist yet)
	"Status": ["zeal", "guard", "faith", "fear"], # middle button
	"Special": ["light"],                       # right button
}
var filter_group = "all"   # "all", "Attacks", "Status" or "Special"
var filter_type = "all"    # "all" (whole group) or one type, e.g. "lust"

# Turn-based battles (see turn_manager.gd). Higher battle_speed = acts earlier
# in each round. ("speed" above is walking speed - a different thing.)
@export var battle_speed = 10
var display_name = "You"

# Guard (Psalm 17:8): while guarded, enemy damage is reduced.
# "+50% defense" = take 50% less damage (there was no defense stat before).
@export var guard_reduction = 0.5    # 0.5 = enemies do half damage
@export var guard_rounds = 3         # how many battle rounds the guard lasts
@export var guard_fx_scale = 4.0     # size of the guard animation
@export var guard_fx_fps = 12.0      # speed of the guard animation
var guard_rounds_left = 0            # 0 = not guarded
var guard_fx: AnimatedSprite2D       # the wings/dome animation (built in _ready)
var guard_label: Label               # "Guard 50% up (3)" (built in _ready)
@export var guard_linger_opacity = 0.5  # after the animation, the wings stay at this opacity while guarded

# Faith (Psalm 27:1b, Psalm 29:11, Isaiah 40:29): attack up.
# Each Faith verse adds faith_step (+50%) up to faith_max (+100%) and resets
# the duration to faith_rounds. Only the PLAYER's verse damage is boosted.
@export var faith_step = 0.5
@export var faith_max = 1.0
@export var faith_rounds = 3
@export var shofar_sound_path = "res://shofar.mp3"   # plays when Faith reaches the max
var faith_bonus = 0.0                # 0.5 = +50% attack
var faith_rounds_left = 0
var faith_label: Label
var shofar_player: AudioStreamPlayer
var shofar_plays = 0                 # how many times the shofar has played (for testing)
signal faith_maxed                   # emitted when Faith newly reaches the max

# Fear (Psalm 75:10): lowers enemy attack - see enemy.gd (fear_reduction)

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
var verse_panel: Panel          # the verse box (built in code, see _build_verse_panel)
var verse_text: RichTextLabel

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
	{"ref": "Psalm 119:105", "type": "light", "damage": 50, "discovered": false, "en": "your word is a lamp to my feet, and a light for my path."},
	# Guard verse: "damage" isn't used for guard verses. "alt" = other wordings
	# that also count (here the fuller KJV version).
	{"ref": "Psalm 17:8", "type": "guard", "damage": 0, "discovered": false, "en": "hide me under the shadow of your wings.", "es": "guárdame como a la niña de tus ojos; escóndeme bajo la sombra de tus alas.", "alt": ["keep me as the apple of the eye, hide me under the shadow of thy wings."]},
	# Faith verses (attack up). Spanish = RVR1960. "LORD" counts as "Yahweh" when matching.
	{"ref": "Psalm 27:1b", "type": "faith", "damage": 0, "discovered": false, "en": "Whom shall I fear? Yahweh is the strength of my life.", "es": "Jehová es la fortaleza de mi vida; ¿de quién he de atemorizarme?", "alt": ["The LORD is the strength of my life; of whom shall I be afraid?", "Yahweh is the strength of my life. Of whom shall I be afraid?"]},
	{"ref": "Psalm 29:11", "type": "faith", "damage": 0, "discovered": false, "en": "Yahweh will give strength to His people.", "es": "Jehová dará poder a su pueblo; Jehová bendecirá a su pueblo con paz.", "alt": ["The LORD will give strength unto his people; the LORD will bless his people with peace.", "Yahweh will give strength to his people. Yahweh will bless his people with peace."]},
	{"ref": "Isaiah 40:29", "type": "faith", "damage": 0, "discovered": false, "en": "He gives power to the weak.", "es": "Él da esfuerzo al cansado, y multiplica las fuerzas al que no tiene ningunas.", "alt": ["He giveth power to the faint; and to them that have no might he increaseth strength.", "He gives power to the weak. He increases the strength of him who has no might."]},
	# Fear verse (enemy attack down)
	{"ref": "Psalm 75:10", "type": "fear", "damage": 0, "discovered": false, "en": "God says, \"I will cut off the strength of the wicked.\"", "es": "Quebrantaré todo el poderío de los pecadores, y el poder del justo será exaltado.", "alt": ["I will cut off the strength of the wicked.", "All the horns of the wicked also will I cut off; but the horns of the righteous shall be exalted.", "All the horns of the wicked also will I cut off."]}
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

var bible_books = ["psalm", "psalms", "proverb", "proverbs", "matthew", "romans", "corinthians", "isaiah"]

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
	
	# The verse box is built in code (same in every level)
	_build_verse_panel()
	verse_panel.visible = false
	_update_verse_text()
	print("Player ready. Verse panel: ", verse_panel)
	if lamp:
		lamp.energy = lamp_base_energy
	
	_build_guard_effect()
	_build_status_labels()
	# Guard and Faith count down at the end of every battle round
	TurnManager.round_ended.connect(_on_round_ended)

# A group button was pressed (Attacks / Status / Special).
# First press shows the whole group; pressing again cycles through its types.
func _on_group_pressed(group: String):
	var types = FILTER_GROUPS[group]
	if filter_group != group:
		filter_group = group
		filter_type = "all"
	elif filter_type == "all":
		filter_type = types[0]
	else:
		var i = types.find(filter_type)
		filter_type = "all" if i + 1 >= types.size() else types[i + 1]
	_update_filter_buttons()
	_update_verse_text()

func _on_show_all_pressed():
	filter_group = "all"
	filter_type = "all"
	_update_filter_buttons()
	_update_verse_text()

# The active group's button shows what it's filtering and is highlighted.
func _update_filter_buttons():
	for group in FILTER_GROUPS:
		var button = verse_panel.get_node("FilterRow/" + group + "Button")
		if group == filter_group:
			button.text = group + ": " + ("All" if filter_type == "all" else filter_type.capitalize())
			button.modulate = Color(1, 0.9, 0.5)
		else:
			button.text = group
			button.modulate = Color.WHITE

# True if a verse type passes the current filter.
func _passes_filter(type: String) -> bool:
	if filter_group == "all":
		return true
	if filter_type == "all":
		return type in FILTER_GROUPS[filter_group]
	return type == filter_type

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
	
	# The player's verses hit the nearest enemy (no range limit, like before).
	# Faith boosts the damage (x1.5 at +50%, x2 at +100%).
	apply_verse_effects(lower, get_nearest_enemy(), 1.0 + faith_bonus)
	
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
	
	# Guard (Psalm 17:8)
	if only_type == "guard":
		activate_guard()
	
	# Faith: attack up for the player
	if only_type == "faith":
		activate_faith()
	
	# Fear: every enemy in the battle attacks weaker. Outside a battle it hits
	# the nearest enemy (and only starts counting down once a battle starts).
	if only_type == "fear":
		var targets = []
		for e in TurnManager.battle_enemies:
			if TurnManager._is_alive(e):
				targets.append(e)
		if targets.is_empty() and enemy and is_instance_valid(enemy):
			targets.append(enemy)
		for e in targets:
			if e.has_method("apply_fear"):
				e.apply_fear()
	
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
	var shown = 0
	for v in all_verses:
		if not _passes_filter(v.type):
			continue   # hidden by the filter buttons
		shown += 1
		var is_found = VerseManager.is_discovered(v.ref)
		if is_found:
			var verse_body = v.en if language == "en" else v.get("es", v.en)
			# Used verses are greyed out until the cycle resets; ready ones are green
			var used = VerseManager.is_used(v.ref)
			var color = "gray" if used else "lightgreen"
			var status = "(used)" if used else "(ready)"
			var power = _verse_power_text(v)
			display += "[color=%s]%s  %s\n%s  |  %s\n%s[/color]\n\n" % [color, v.ref, status, power, v.type.capitalize(), verse_body]
		else:
			display += "???\n??%  |  ???\n\n"
	if shown == 0:
		display += "(No verses of this kind yet)"
	verse_text.text = display

# The short "what it does" line shown for each verse in the verse box.
func _verse_power_text(v) -> String:
	match v.type:
		"guard":
			return "+%d%% defense, %d rounds" % [int(guard_reduction * 100), guard_rounds]
		"faith":
			return "+%d%% attack (stacks to +%d%%), %d rounds" % [int(faith_step * 100), int(faith_max * 100), faith_rounds]
		"fear":
			return "All enemies in battle: attack -50%, 3 rounds"
		"zeal":
			return "Speed + jump boost"
		"light":
			return "Lights up the dark"
	return "%d%%" % v.damage

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
	lower = _normalize(lower)
	for v in all_verses:
		var text_score = max(lower.similarity(_normalize(v.en)), lower.similarity(_normalize(v.get("es", ""))))
		for alt in v.get("alt", []):
			text_score = max(text_score, lower.similarity(_normalize(alt)))
		var ref_score = lower.similarity(v.ref.to_lower())
		if text_score > 0.4 or ref_score > 0.6:
			var score = max(text_score, ref_score)
			if score > best_score:
				best_score = score
				best = v
	return best

# Lowercases text and treats "LORD" and "Yahweh" as the same word, so either
# wording matches.
func _normalize(text: String) -> String:
	return text.to_lower().replace("the lord", "yahweh").replace("lord", "yahweh")

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

# Returns how much damage was actually taken (after guard).
func take_damage(amount):
	if guard_rounds_left > 0:
		amount *= (1.0 - guard_reduction)
	set_hp(hp - amount)
	return amount

# ---------------- Guard (Psalm 17:8) ----------------

# Turns the guard on (or refreshes it back to the full guard_rounds - it
# doesn't stack). Outside a battle it doesn't count down, so it covers the
# first rounds of your next battle.
func activate_guard():
	guard_rounds_left = guard_rounds
	_update_guard_label()
	# Play the wings/dome animation once (fully visible)
	guard_fx.visible = true
	guard_fx.modulate.a = 1.0
	guard_fx.frame = 0
	guard_fx.play("guard")
	print("Guard up for ", guard_rounds, " rounds")

# When the animation ends, keep its last frame on screen (see-through)
# for as long as the guard lasts.
func _on_guard_fx_finished():
	if guard_rounds_left > 0:
		guard_fx.modulate.a = guard_linger_opacity
	else:
		guard_fx.visible = false

func _on_round_ended():
	if guard_rounds_left > 0:
		guard_rounds_left -= 1
		_update_guard_label()
		if guard_rounds_left == 0:
			guard_fx.visible = false   # guard over: hide the lingering wings
	if faith_rounds_left > 0:
		faith_rounds_left -= 1
		if faith_rounds_left == 0:
			faith_bonus = 0.0
		_update_faith_label()

func _update_guard_label():
	guard_label.visible = guard_rounds_left > 0
	guard_label.text = "Guard %d%% up (%d)" % [int(guard_reduction * 100), guard_rounds_left]

# ---------------- Faith (attack up) ----------------

# +faith_step attack (stacking up to faith_max) and reset the duration.
# Outside a battle it doesn't count down.
func activate_faith():
	var was_max = faith_bonus >= faith_max
	if faith_rounds_left > 0:
		faith_bonus = min(faith_bonus + faith_step, faith_max)
	else:
		faith_bonus = faith_step
	faith_rounds_left = faith_rounds
	_update_faith_label()
	print("Faith: attack +", int(faith_bonus * 100), "% for ", faith_rounds, " rounds")
	if faith_bonus >= faith_max and not was_max:
		_play_shofar()

func _update_faith_label():
	faith_label.visible = faith_rounds_left > 0
	faith_label.text = "Faith %d%% up (%d)" % [int(faith_bonus * 100), faith_rounds_left]

# The shofar plays when Faith newly reaches the max.
func _play_shofar():
	shofar_plays += 1
	faith_maxed.emit()
	if shofar_player.stream:
		shofar_player.play()
	else:
		print("Faith maxed! (No shofar sound yet: add a file at ", shofar_sound_path, ")")

# Builds the Guard/Faith lines under the HP bar and the shofar sound player.
func _build_status_labels():
	var box = VBoxContainer.new()   # stacks the labels; hidden ones take no space
	box.position = hp_bar.position + Vector2(0, hp_bar.size.y + 4)
	box.add_child(guard_label)
	faith_label = Label.new()
	faith_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.45))
	faith_label.add_theme_color_override("font_outline_color", Color.BLACK)
	faith_label.add_theme_constant_override("outline_size", 4)
	faith_label.visible = false
	box.add_child(faith_label)
	hp_bar.get_parent().add_child.call_deferred(box)
	
	shofar_player = AudioStreamPlayer.new()
	if ResourceLoader.exists(shofar_sound_path):
		shofar_player.stream = load(shofar_sound_path)
		if "loop" in shofar_player.stream:
			shofar_player.stream.loop = false
	add_child(shofar_player)

# Builds the guard animation (Guardeffect.png: 12 frames of 78x78 in one row)
# and the "Guard 50% up" label under the HP bar.
func _build_guard_effect():
	var sheet = load("res://Guardeffect.png")
	var frames = SpriteFrames.new()
	frames.add_animation("guard")
	frames.set_animation_loop("guard", false)   # play once, don't repeat
	frames.set_animation_speed("guard", guard_fx_fps)
	for i in 12:
		var atlas = AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(i * 78, 0, 78, 78)
		frames.add_frame("guard", atlas)
	guard_fx = AnimatedSprite2D.new()
	guard_fx.sprite_frames = frames
	guard_fx.scale = Vector2(guard_fx_scale, guard_fx_scale)
	guard_fx.offset = Vector2(-11, -11)   # the dome is drawn a bit right/down of the frame centre
	# Put it on the player's body (the body is moved away from the origin in the scenes)
	var shape = get_node_or_null("CollisionShape2D")
	guard_fx.position = (shape.position if shape else Vector2.ZERO) + Vector2(0, -23)
	guard_fx.z_index = 5
	guard_fx.visible = false
	guard_fx.animation_finished.connect(_on_guard_fx_finished)
	add_child(guard_fx)
	
	guard_label = Label.new()
	guard_label.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	guard_label.add_theme_color_override("font_outline_color", Color.BLACK)
	guard_label.add_theme_constant_override("outline_size", 4)
	guard_label.visible = false

# Builds the verse box (Tab). It's made in code so it's the same in every
# level, and it's added under the player, so you won't see it in the editor.
#   Top:    title + "Show all" button
#   Row:    [Attacks] [Status] [Special] filter buttons (left / middle / right)
#   Below:  the verse list
func _build_verse_panel():
	var layer = CanvasLayer.new()
	layer.name = "VerseListLayer"
	add_child(layer)
	verse_panel = Panel.new()
	verse_panel.name = "VersePanel"
	verse_panel.position = Vector2(30, 230)
	verse_panel.size = Vector2(620, 330)
	layer.add_child(verse_panel)
	
	var title = Label.new()
	title.text = "Verses (Tab to close)"
	title.position = Vector2(10, 6)
	verse_panel.add_child(title)
	
	var show_all = Button.new()
	show_all.name = "ShowAllButton"
	show_all.text = "Show all"
	show_all.position = Vector2(530, 4)
	show_all.focus_mode = Control.FOCUS_NONE   # so Enter/Space don't press it by accident
	show_all.pressed.connect(_on_show_all_pressed)
	verse_panel.add_child(show_all)
	
	# Three equal buttons side by side
	var row = HBoxContainer.new()
	row.name = "FilterRow"
	row.position = Vector2(10, 38)
	row.size = Vector2(600, 31)
	row.add_theme_constant_override("separation", 8)
	verse_panel.add_child(row)
	for group in FILTER_GROUPS:
		var button = Button.new()
		button.name = group + "Button"
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_group_pressed.bind(group))
		row.add_child(button)
	
	verse_text = RichTextLabel.new()
	verse_text.name = "VerseText"
	verse_text.bbcode_enabled = true   # allows colors in the verse list
	verse_text.position = Vector2(10, 76)
	verse_text.size = Vector2(600, 246)
	verse_panel.add_child(verse_text)
	_update_filter_buttons()
