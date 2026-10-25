extends CharacterBody2D
const Battle3D = preload("res://battle_3d.gd")   # 3D boss battle: 2D spots seen through its camera

const EnemyVerses = preload("res://enemy_verses.gd")
const SpeechBubble = preload("res://speech_bubble.gd")

const PopupText = preload("res://popup_text.gd")

@export var max_hp = 100           # health (each enemy can have its own)
var hp = 100

# Hidden defense stat (never shown to the player): every verse that hits this
# enemy does (1 - defense) of its damage.  0 = full damage, 0.65 = 35% damage.
# Kept between 0 and 0.9 so verses always do something.
@export_range(0.0, 0.9, 0.05) var defense = 0.0

# --- Turn-based battles (see turn_manager.gd) ---
@export var display_name = ""      # shown as "<name>'s turn"; empty = use the node's name
@export var battle_speed = 5       # lower than the player (10) and Pastor Ramuel (8), so it acts last
# PLACEHOLDER ATTACK: enemies don't have real attacks yet, so on its turn the
# enemy just does a little damage to the player. Untick can_attack in the
# Inspector to make enemies skip their turn instead.
@export var can_attack = true
@export var attack_damage = 5
# Chance (0 to 1) that the basic attack hits your party member instead of you
# (enemy VERSES always hit you). 0 = always attack the player.
@export_range(0.0, 1.0, 0.05) var party_target_chance = 0.25

# Fear (Psalm 75:10): this enemy's attack is lowered for a few rounds.
# Recasting refreshes the duration (it doesn't stack).
@export var fear_reduction = 0.5   # 0.5 = attacks do half damage
@export var fear_rounds = 3
var fear_rounds_left = 0
var fear_label: Label              # "Attack 50% down (3)" above the HP bar

# --- Enemy verses (see enemy_verses.gd) ---
# On its turn the enemy either recites one of its verses or does the basic
# attack above. They take turns: verse, attack, verse, attack...
# (verse first, so you see it early and can try to counter it).
@export var verses: Array[String] = []   # refs from enemy_verses.gd, e.g. ["Genesis 3:17"]. Empty = basic attack only
# Lines from the design sheet (data/enemy_lines.json): the sets this enemy
# says, e.g. ["silver_wolf"]. If set, it says ONLY these lines (plus any refs
# in "verses" above). See enemy_verses.gd.
@export var line_sets: Array[String] = []
@export var verse_every = 2              # recite a verse every Nth turn (1 = every turn, 2 = every other turn)
@export var verse_read_time = 2.0        # pause after a verse so you can read it (seconds)
@export var verse_bubble_time = 3.5      # how long a NON-counterable verse bubble stays up
@export var popup_time = 1.5             # how long "Countered! x3" / "No effect" float above it
var turns_taken = 0
# The enemy's type. "" = no type yet: any attack verse hurts it (like before).
# After reciting e.g. a Sloth verse it becomes "sloth": then only Sloth and
# Universal ("all") attack verses can hurt it.
var enemy_type = ""
# The enemy's own sin. "greed" for the Greed level's enemies: they start as
# Greed type, and the sheet's Greed verses (data/verses.json) do their Greed %
# damage to them even if a recited verse changed their type tag.
@export var base_type = ""
# --- Boss-fight extras (the SinDeath fight in Greed, sindeath_scene.gd) ---
# only_vs: if set, ONLY verses with this sheet "Dmg to" column hurt it (e.g.
#   "sindeath" = the 'Dmg to SinDeath boss' column, "idol" = 'Dmg to Idol');
#   every other verse has no effect. See character_body_2d.gd verse_damage_against.
@export var only_vs = ""
# Boss talk: its bubbles type out with the boss voice blips (speech_bubble.gd).
# On for every boss-only enemy (only_vs set: SinDeath, the Idol).
@export var boss_voice = false
func talks_like_boss() -> bool:
	return boss_voice or only_vs != ""
# dormant: not in the level yet (hidden, can't start a battle) until awaken()
@export var dormant = false
# passive: never takes a turn (the Idol just stands there)
@export var passive = false
# optional_target: the battle can be won without beating it
@export var optional_target = false
# survives_defeat: at 0 HP it isn't removed, it just leaves the battle
#   ("cracked"); emits cracked. (The Idol still has to be rammed.)
@export var survives_defeat = false
@export var hide_while_dormant = true   # false: stays visible (just no HP bar) while dormant
# head_bar: the small grey HP bar + type tag over its head. upd29: no enemy
# shows it any more (every battle type, 2D and 3D) - enemy HP is only in the
# enemies' panel at the top right (turn_manager.gd). Kept as a switch.
@export var head_bar = false
const HEAD_BARS = false
func shows_head_bar() -> bool:
	return HEAD_BARS and head_bar and only_vs == ""
signal cracked
var counter_refs = []     # player verses that counter what it just recited (only during your next turn)
var type_label: Label     # small "Sloth" tag under the HP bar
var bubble                # speech bubble (speech_bubble.gd)

@onready var hp_bar = $EnemyHP

func _ready():
	# If this enemy was already beaten (in this play session or in a loaded
	# save), remove it so it stays defeated.
	if SaveManager.is_enemy_defeated(self):
		queue_free()
		return
	if not dormant:
		add_to_group("enemies")  # lets the player and party members find enemies
	else:
		visible = not hide_while_dormant
		_show_battle_ui.call_deferred(false)
	hp = max_hp
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	if not shows_head_bar():
		hp_bar.visible = false
	if display_name == "":
		display_name = str(name)
	
	# Fear label, just above the HP bar
	fear_label = Label.new()
	fear_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fear_label.position = hp_bar.position + Vector2(0, -26)
	fear_label.size = Vector2(hp_bar.size.x, 24)
	fear_label.add_theme_color_override("font_color", Color(0.75, 0.55, 1.0))
	fear_label.add_theme_color_override("font_outline_color", Color.BLACK)
	fear_label.add_theme_constant_override("outline_size", 4)
	fear_label.visible = false
	add_child(fear_label)
	TurnManager.round_ended.connect(_on_round_ended)
	SaveManager.language_changed.connect(func(_l): _update_fear_label())
	
	# Type tag, just under the HP bar
	type_label = Label.new()
	type_label.position = hp_bar.position + Vector2(0, hp_bar.size.y + 1)
	type_label.add_theme_font_size_override("font_size", 14)
	type_label.add_theme_color_override("font_color", Color(0.6, 0.85, 0.65))
	type_label.add_theme_color_override("font_outline_color", Color.BLACK)
	type_label.add_theme_constant_override("outline_size", 4)
	type_label.visible = false
	add_child(type_label)
	
	if base_type != "":
		set_enemy_type(base_type)
	
	bubble = SpeechBubble.new()
	bubble.target = self
	bubble.head_offset = hp_bar.position + Vector2(hp_bar.size.x / 2.0, -30)
	add_child(bubble)
	# The counter chance is only your very next turn: close it after you act,
	# or if the battle ends (won or ran away).
	TurnManager.player_turn_finished.connect(close_counter_window)
	TurnManager.battle_ended.connect(close_counter_window)

# Brings a dormant enemy into the level (it can be fought from now on)
func awaken():
	dormant = false
	visible = true
	_show_battle_ui(true)
	if not is_in_group("enemies"):
		add_to_group("enemies")

func _show_battle_ui(on: bool):
	on = on and shows_head_bar()
	if hp_bar:
		hp_bar.visible = on
	if type_label:
		type_label.visible = on and type_label.text != ""

# Takes it out of the fighting again (e.g. the calf after the boss is beaten,
# so walking up to it doesn't start a new battle)
func make_dormant():
	dormant = true
	_show_battle_ui(false)
	if is_in_group("enemies"):
		remove_from_group("enemies")

func apply_fear():
	fear_rounds_left = fear_rounds
	_update_fear_label()
	print(display_name, " is afraid: attack -", int(fear_reduction * 100), "% for ", fear_rounds, " rounds")

func _on_round_ended():
	if fear_rounds_left > 0:
		fear_rounds_left -= 1
		_update_fear_label()

func _update_fear_label():
	fear_label.visible = fear_rounds_left > 0
	fear_label.text = tr("Attack -%d%% (%d)") % [int(fear_reduction * 100), fear_rounds_left]

# Called by TurnManager when it's this enemy's turn in a battle.
func take_turn():
	turns_taken += 1
	play_anim("attack")
	if (not verses.is_empty() or not line_sets.is_empty()) and (turns_taken - 1) % max(verse_every, 1) == 0:
		return recite_verse()
	var player = get_tree().get_first_node_in_group("player")
	if can_attack and player and player.has_method("take_damage"):
		var damage = attack_damage
		if fear_rounds_left > 0:
			damage *= (1.0 - fear_reduction)   # Fear: weaker attack
		# Sometimes it goes for your party member (if they're still standing)
		var party = _party_member_to_attack()
		if party and randf() < party_target_chance:
			var hit = party.enemy_hit(damage) if party.has_method("enemy_hit") else party.take_damage(damage)   # (their Wisdom may dodge it)
			if hit < 0:
				TurnManager.show_message(tr("%s attacks %s... Dodged!") % [tr(display_name), tr(party.display_name)])
				return
			TurnManager.show_message(tr("%s attacks %s! -%s HP") % [tr(display_name), tr(party.display_name), str(snapped(hit, 0.1))])
			print(display_name, " attacks ", party.display_name, " for ", hit)
			return
		# take_damage returns the damage after the player's guard (Psalm 17:8),
		# so Fear and Guard together = 5 x 0.5 x 0.5 = 1.25
		# (enemy_hit: your Wisdom may dodge it - see character_body_2d.gd)
		var dealt = _hit_player(player, damage)
		if dealt < 0:
			TurnManager.show_message(tr("%s attacks... Dodged!") % tr(display_name))
			return
		TurnManager.show_message(tr("%s attacks! -%s HP") % [tr(display_name), str(snapped(dealt, 0.1))])
		print(display_name, " attacks for ", dealt)
	else:
		TurnManager.show_message(tr("%s waits...") % tr(display_name))

# Hits the player: their Wisdom (evasion) may dodge it. -1 = dodged.
func _hit_player(player, damage) -> float:
	if player.has_method("enemy_hit"):
		return player.enemy_hit(damage)
	return player.take_damage(damage)

# A party member in this battle who can still be hit (or null). With phone
# players in the party it picks one of them at random.
func _party_member_to_attack():
	var options = []
	for member in get_tree().get_nodes_in_group("party"):
		if TurnManager._is_alive(member) and member.has_method("take_damage") and not member.knocked_out:
			options.append(member)
	return null if options.is_empty() else options.pick_random()

# Recites one of its verses: hurts the player, changes its type and maybe
# opens a counter chance. Returns how long the battle should wait.
func recite_verse():
	# Pick from its verse refs and its sheet lines (each counts once)
	var lines = EnemyVerses.lines_for(line_sets)
	var n = verses.size() + lines.size()
	if n == 0:
		return null
	var pick = randi() % n
	if pick >= verses.size():
		return say_line(lines[pick - verses.size()])
	var ref = verses[pick]
	var v = EnemyVerses.VERSES.get(ref)
	if v == null:
		push_warning("%s: unknown enemy verse '%s' (add it to enemy_verses.gd)" % [display_name, ref])
		return null
	var player = get_tree().get_first_node_in_group("player")
	var dealt = 0.0
	if player and player.has_method("take_damage"):
		var damage = v.damage
		if fear_rounds_left > 0:
			damage *= (1.0 - fear_reduction)
		dealt = max(_hit_player(player, damage), 0.0)   # the player's Guard reduces it too (Wisdom may dodge it)
	var text = v.get(SaveManager.language, v.en) if SaveManager.language != "en" else v.en
	var title = VerseManager.ref_text(v.title)   # "Genesis 3" / "Génesis 3"
	set_enemy_type(v.type)
	counter_refs = v.get("counters", []).duplicate()
	if counter_refs.is_empty():
		bubble.say(title, text, false, verse_bubble_time)
	else:
		bubble.say(title, text, true, 0.0)   # stays up through your next turn
	if talks_like_boss():
		bubble.start_typing()   # typewriter + boss voice blips
	TurnManager.show_message(tr("%s recites %s! -%s HP - it's %s type now!") % [tr(display_name), title, str(snapped(dealt, 0.1)), tr(type_name(v.type))])
	print(display_name, " recites ", ref, " for ", dealt, " (counters: ", counter_refs, ")")
	return verse_read_time

# Says one of its sheet lines (enemy_lines.json): hurts the player, may heal
# itself, may change its type (the sin of the line's set) and may open a
# counter chance (the line's "Countered By" refs).
var last_line = {}
func say_line(line: Dictionary):
	last_line = line
	var player = get_tree().get_first_node_in_group("player")
	var dealt = 0.0
	if player and player.has_method("take_damage"):
		var damage = EnemyVerses.line_damage(line)
		if fear_rounds_left > 0:
			damage *= (1.0 - fear_reduction)
		dealt = max(_hit_player(player, damage), 0.0)   # (Wisdom may dodge it)
	var lang = SaveManager.language
	var text = line.get(lang, "") if lang != "en" else ""
	if text == "":
		text = line.en
	var title = VerseManager.ref_text(line.title) if line.get("title", "") != "" else ""
	if line.get("type", "") != "":
		set_enemy_type(line.type)
	var heal_pct = float(line.get("heal_pct", 0))
	if heal_pct > 0:
		hp = min(hp + max_hp * heal_pct / 100.0, max_hp)
		hp_bar.value = hp
	counter_refs = []
	if player:
		for ref in line.get("counters", []):
			if player.get_verse(ref) != null:
				counter_refs.append(ref)
	if counter_refs.is_empty():
		bubble.say(title, text, false, verse_bubble_time)
	else:
		bubble.say(title, text, true, 0.0)
	if talks_like_boss():
		bubble.start_typing()   # typewriter + boss voice blips
	TurnManager.show_message(tr("%s: -%s HP") % [tr(display_name), str(snapped(dealt, 0.1))])
	print(display_name, " says [", line.set, "] ", line.en.substr(0, 60), " for ", dealt)
	return verse_read_time

func set_enemy_type(new_type: String):
	enemy_type = new_type
	type_label.visible = enemy_type != "" and shows_head_bar()
	type_label.text = type_name(enemy_type)   # e.g. "Sloth": translated automatically

static func type_name(t: String) -> String:
	return "Universal" if t == "all" else t.capitalize()

# A Greed enemy (Greed verses do their Greed % to it)
func is_greed() -> bool:
	return has_sin("greed")

# The sins (types) that count for this enemy: its own (base_type) and what it
# is right now (enemy_type). Sheet verses do their sin % if it has that sin.
func enemy_sins() -> Array:
	var out = []
	for t in [base_type, enemy_type]:
		if t != "" and not t in out:
			out.append(t)
	return out

func has_sin(sin: String) -> bool:
	return sin in enemy_sins()

# Can a player attack verse of this type hurt it?
const SIN_TYPES = ["sloth", "lust", "greed", "wrath", "gluttony", "envy", "pride"]
func can_be_hurt_by(verse_type: String) -> bool:
	# A type that isn't a sin (e.g. "atheist") doesn't block any attack verse
	return not enemy_type in SIN_TYPES or verse_type == "all" or verse_type == enemy_type

# Is this verse a counter to what it just recited (during your next turn)?
func is_countered_by(ref: String) -> bool:
	return ref in counter_refs

func close_counter_window():
	if not counter_refs.is_empty():
		counter_refs = []
		bubble.hide_bubble()

# A little text that floats up above the enemy and fades (e.g. "Countered! x3")
func show_popup(text: String, color := Color.WHITE):
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(320, 30)
	label.position = hp_bar.position + Vector2(hp_bar.size.x / 2.0 - 160, -60)
	label.z_index = 10
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	# Added to the level (not the enemy) so it stays visible even if this hit
	# defeats it. Placed in GLOBAL coordinates after adding it: the parent may
	# be moved (the SinDeath scene node sits at (11690, 192)).
	# Long texts ("No effect - only SinDeath verses can hurt it") widen the
	# label, so centre it again and keep it on the screen.
	var center = global_transform * (label.position + Vector2(160, 15))
	get_parent().add_child(label)
	label.size.x = max(320.0, label.get_combined_minimum_size().x)
	var tween = label.create_tween()
	tween.set_parallel(true)
	if Battle3D.is_on():   # the 3D boss battle: rises over where it shows (follows the camera)
		Battle3D.current.track_popup(label, self, center, popup_time)
	else:
		var xf = get_viewport().get_canvas_transform()
		var rise = 40.0 * xf.get_scale().y
		var at = xf.affine_inverse() * Battle3D.keep_on_screen(get_viewport(), label, xf * center, rise)
		label.global_position = at - Vector2(label.size.x / 2.0, 15)
		tween.tween_property(label, "global_position:y", label.global_position.y - 40, popup_time)
	tween.tween_property(label, "modulate:a", 0.0, popup_time).set_delay(popup_time * 0.5)
	tween.chain().tween_callback(label.queue_free)
	return label

# Where the enemy's body actually is. In some scenes the sprite and collision
# are moved away from the enemy's origin, so use the collision shape.
func get_center() -> Vector2:
	var shape = get_node_or_null("CollisionShape2D")
	return shape.global_position if shape else global_position

# Returns the damage actually done (after defense).
func take_damage(amount):
	amount *= (1.0 - clamp(defense, 0.0, 0.9))
	hp = max(hp - amount, 0)
	hp_bar.value = hp
	if hp <= 0 and survives_defeat:
		_crack()
	elif hp <= 0:
		_die()
	elif amount > 0:
		play_anim("hurt")
	return amount

# ---------------- Optional animations ----------------
# If the enemy's AnimatedSprite2D "Sprite" has these animations they're used
# (the atheist goats have them; enemies without them just keep their idle):
#   "idle" (looping), "attack" (its turn), "hurt" (hit), "death" (defeated).
func _anim_sprite() -> AnimatedSprite2D:
	var s = get_node_or_null("Sprite")
	return s if s is AnimatedSprite2D else null

func play_anim(anim: String):
	var s = _anim_sprite()
	if s == null or s.sprite_frames == null or not s.sprite_frames.has_animation(anim):
		return
	s.play(anim)
	if not s.sprite_frames.get_animation_loop(anim) and s.sprite_frames.has_animation("idle"):
		if not s.animation_finished.is_connected(_back_to_idle):
			s.animation_finished.connect(_back_to_idle)

func _back_to_idle():
	var s = _anim_sprite()
	if s and s.animation != "death":
		s.play("idle")

# The death animation plays on a copy left in the level (the enemy itself is
# removed at once), which then fades out.
func _death_anim():
	var s = _anim_sprite()
	if s == null or s.sprite_frames == null or not s.sprite_frames.has_animation("death"):
		return
	var ghost = s.duplicate(0)
	get_parent().add_child(ghost)
	ghost.global_transform = s.global_transform
	ghost.play("death")
	var t = ghost.create_tween()
	t.tween_interval(1.4)
	t.tween_property(ghost, "modulate:a", 0.0, 0.6)
	t.tween_callback(ghost.queue_free)

# survives_defeat: out of the battle, but stays in the level
var is_cracked = false
# Straight to 0 HP (ignores defense): cracks a survives_defeat enemy (the
# Idol), defeats any other. Used by the SinDeath counter (2 Cor 1:20).
func knock_out():
	hp = 0
	hp_bar.value = 0
	if survives_defeat:
		_crack()
	else:
		_die()

func _crack():
	if is_cracked:
		return
	is_cracked = true
	bubble.hide_bubble()
	TurnManager.battle_enemies.erase(self)
	make_dormant()
	show_popup(tr("The idol is cracked!"), Color(1, 0.85, 0.3))
	for c in get_children():
		if c is Sprite2D or c is AnimatedSprite2D:
			c.modulate = Color(0.75, 0.7, 0.6)
	cracked.emit()

func _die():
	if not _instant:
		_death_anim()
	bubble.hide_bubble()
	SaveManager.mark_enemy_defeated(self)  # remember it for saving
	queue_free()  # enemy dies
	print(display_name, " defeated")

# One of its kinds (its line_sets, e.g. "silver_wolf")
func is_kind(kind: String) -> bool:
	return kind in line_sets

# Defeated at once by a verse aimed at its kind (character_body_2d.gd
# INSTANT_KILLS): no defense, no damage numbers. A golden copy of it flashes
# and fades where it stood, with "Instant defeat!" above.
var _instant = false   # (the golden flash replaces the death animation)
func instant_defeat():
	if hp <= 0 or is_queued_for_deletion():
		return
	show_popup(tr("Instant defeat!"), Color(1, 0.85, 0.25))
	var level = get_parent()
	for c in get_children():
		if (c is Sprite2D or c is AnimatedSprite2D) and c.visible:
			var ghost = c.duplicate(0)
			ghost.set_script(null)
			level.add_child(ghost)
			ghost.global_transform = c.global_transform
			ghost.z_index = c.z_index + 1
			ghost.modulate = Color(2.2, 1.9, 0.6)
			if ghost is AnimatedSprite2D:
				ghost.pause()
			var t = ghost.create_tween().set_parallel(true)
			t.tween_property(ghost, "scale", ghost.scale * 1.35, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			t.tween_property(ghost, "modulate", Color(3, 2.6, 1, 0), 0.9)
			t.chain().tween_callback(ghost.queue_free)
			break
	hp = 0
	hp_bar.value = 0
	_instant = true
	_die()
