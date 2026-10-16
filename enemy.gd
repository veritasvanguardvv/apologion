extends CharacterBody2D

const EnemyVerses = preload("res://enemy_verses.gd")
const SpeechBubble = preload("res://speech_bubble.gd")

var max_hp = 100
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
@export var verse_every = 2              # recite a verse every Nth turn (1 = every turn, 2 = every other turn)
@export var verse_read_time = 2.0        # pause after a verse so you can read it (seconds)
@export var verse_bubble_time = 3.5      # how long a NON-counterable verse bubble stays up
@export var popup_time = 1.5             # how long "Countered! x3" / "No effect" float above it
var turns_taken = 0
# The enemy's type. "" = no type yet: any attack verse hurts it (like before).
# After reciting e.g. a Sloth verse it becomes "sloth": then only Sloth and
# Universal ("all") attack verses can hurt it.
var enemy_type = ""
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
	add_to_group("enemies")  # lets the player and party members find enemies
	hp_bar.value = hp
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
	
	bubble = SpeechBubble.new()
	bubble.target = self
	bubble.head_offset = hp_bar.position + Vector2(hp_bar.size.x / 2.0, -30)
	add_child(bubble)
	# The counter chance is only your very next turn: close it after you act,
	# or if the battle ends (won or ran away).
	TurnManager.player_turn_finished.connect(close_counter_window)
	TurnManager.battle_ended.connect(close_counter_window)

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
	if not verses.is_empty() and (turns_taken - 1) % max(verse_every, 1) == 0:
		return recite_verse()
	var player = get_tree().get_first_node_in_group("player")
	if can_attack and player and player.has_method("take_damage"):
		var damage = attack_damage
		if fear_rounds_left > 0:
			damage *= (1.0 - fear_reduction)   # Fear: weaker attack
		# take_damage returns the damage after the player's guard (Psalm 17:8),
		# so Fear and Guard together = 5 x 0.5 x 0.5 = 1.25
		var dealt = player.take_damage(damage)
		TurnManager.show_message(tr("%s attacks! -%s HP") % [display_name, str(snapped(dealt, 0.1))])
		print(display_name, " attacks for ", dealt)
	else:
		TurnManager.show_message(tr("%s waits...") % display_name)

# Recites one of its verses: hurts the player, changes its type and maybe
# opens a counter chance. Returns how long the battle should wait.
func recite_verse():
	var ref = verses.pick_random()
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
		dealt = player.take_damage(damage)   # the player's Guard reduces it too
	var text = v.es if SaveManager.language == "es" and v.has("es") else v.en
	var title = VerseManager.ref_text(v.title)   # "Genesis 3" / "Génesis 3"
	set_enemy_type(v.type)
	counter_refs = v.get("counters", []).duplicate()
	if counter_refs.is_empty():
		bubble.say(title, text, false, verse_bubble_time)
	else:
		bubble.say(title, text, true, 0.0)   # stays up through your next turn
	TurnManager.show_message(tr("%s recites %s! -%s HP - it's %s type now!") % [display_name, title, str(snapped(dealt, 0.1)), tr(type_name(v.type))])
	print(display_name, " recites ", ref, " for ", dealt, " (counters: ", counter_refs, ")")
	return verse_read_time

func set_enemy_type(new_type: String):
	enemy_type = new_type
	type_label.visible = enemy_type != ""
	type_label.text = type_name(enemy_type)   # e.g. "Sloth": translated automatically

static func type_name(t: String) -> String:
	return "Universal" if t == "all" else t.capitalize()

# Can a player attack verse of this type hurt it?
func can_be_hurt_by(verse_type: String) -> bool:
	return enemy_type == "" or verse_type == "all" or verse_type == enemy_type

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
	# Added to the level (not the enemy) so it stays visible even if this hit defeats it
	label.position = global_position + label.position
	get_parent().add_child(label)
	var tween = label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 40, popup_time)
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
	if hp <= 0:
		bubble.hide_bubble()
		SaveManager.mark_enemy_defeated(self)  # remember it for saving
		queue_free()  # enemy dies
		print("Enemy defeated")
	return amount
