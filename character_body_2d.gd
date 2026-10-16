extends CharacterBody2D

const EnemyVerses = preload("res://enemy_verses.gd")   # enemies' own verses (the player can't use them)
const PopupText = preload("res://popup_text.gd")       # floating "+25" / "-10" numbers

var hp = 100
var max_hp: int:            # (the same for every level, set in save_manager.gd)
	get:
		return SaveManager.MAX_HP
var speed = 200
var jump_velocity = -400
var gravity = 980
# "en" or "es". The language lives in SaveManager (set with the main menu's
# English / Español buttons); this just reads it so verse checks match.
var language: String:
	get:
		return SaveManager.language
# Verse box filter (see _build_verse_panel). Four groups of verse types:
const FILTER_GROUPS = {
	"Attacks": ["sloth", "lust", "all"],        # 1st button ("all" = Universal: hurts any enemy type)
	"Status": ["zeal", "guard", "faith", "fear"], # 2nd button
	"Special": ["light"],                       # 3rd button
	"Heal": ["heal"],                           # 4th (rightmost) button
}
const ATTACK_TYPES = ["sloth", "lust", "all"]   # verse types that do damage
var filter_group = "all"   # "all" (Show all), "Attacks", "Status" or "Special"
var filter_type = "*"      # "*" = the whole group, or one type, e.g. "lust"

# Turn-based battles (see turn_manager.gd). Higher battle_speed = acts earlier
# in each round. ("speed" above is walking speed - a different thing.)
@export var battle_speed = 10
var display_name = "You"

# Speech bubble above the player when you recite a verse (white, like party members)
@export_group("Speech bubble")
@export var bubble_max_width = 340.0
@export var bubble_min_time = 2.5        # shortest time it stays up (seconds)
@export var bubble_time_per_char = 0.06  # longer verses stay up longer
@export var bubble_max_time = 6.0
@export var bubble_head_gap = 135.0      # how far above the body's centre the bubble points (above the speaker icon)
var bubble

# Voice (push-to-talk, see speech_recognizer.gd): hold Shift and speak.
# While the mic is on, a pixel-art speaker icon floats above your head.
@export_group("Voice")
@export var speaker_pixel_size = 20.0    # bigger = chunkier pixels on the speaker icon
@export var speaker_size = 110.0         # icon size on screen (pixels)
@export var speaker_height = 85.0        # how far above the body's centre it floats
@export var voice_submit_delay = 0.6     # the recognized text stays in the box this long before it's recited
var speaker_icon: Sprite2D
@export_group("")
# Countering: if an enemy recites a verse that can be countered (it shows a
# "!" bubble), reciting the counter verse on your very next turn multiplies
# the damage. Counters are listed in enemy_verses.gd.
@export var counter_multiplier = 3.0

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

# Skip Turn (button or K in a battle): ends your turn, but costs this much of
# your max HP (0.1 = 10%). Guard doesn't reduce it - it's a price you choose
# to pay, not an enemy attack.
@export var skip_turn_cost = 0.1

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
# Attack verses (lust / sloth / all) use the "damage" number here.
var all_verses = [
	{"ref": "Matthew 5:28", "type": "lust", "damage": 100, "discovered": true, "en": "everyone who gazes at a woman to lust after her has committed adultery in his heart.", "es": "todo el que mira a una mujer para codiciarla ya cometió adulterio en su corazón."},
	{"ref": "Psalm 18:28", "type": "light", "damage": 50, "discovered": false, "en": "the lord, my god, lights up my darkness.", "es": "Jehová mi Dios alumbrará mis tinieblas."},
	{"ref": "Romans 12:11", "type": "zeal", "damage": 50, "discovered": false, "en": "never lag in diligence. let the spirit excite you as you serve the lord.", "es": "En lo que requiere diligencia, no perezosos; fervientes en espíritu, sirviendo al Señor."},
	{"ref": "1 Corinthians 6:18", "type": "lust", "damage": 50, "discovered": false, "en": "flee sexual immorality!", "es": "¡huyan de la inmoralidad sexual!"},
	{"ref": "Proverbs 6:32", "type": "lust", "damage": 50, "discovered": false, "en": "he who commits adultery is a fool who destroys himself.", "es": "el que comete adulterio es un necio que se destruye a sí mismo."},
	{"ref": "Psalm 18:28a", "type": "light", "damage": 50, "discovered": false, "en": "you light a lamp for me.", "es": "Tú encenderás mi lámpara."},
	{"ref": "Psalm 119:105", "type": "light", "damage": 50, "discovered": false, "en": "your word is a lamp to my feet, and a light for my path.", "es": "Lámpara es a mis pies tu palabra, y lumbrera a mi camino."},
	# Guard verse: "damage" isn't used for guard verses. "alt" = other wordings
	# that also count (here the fuller KJV version).
	{"ref": "Psalm 17:8", "type": "guard", "damage": 0, "discovered": false, "en": "hide me under the shadow of your wings.", "es": "guárdame como a la niña de tus ojos; escóndeme bajo la sombra de tus alas.", "alt": ["keep me as the apple of the eye, hide me under the shadow of thy wings."]},
	# Faith verses (attack up). Spanish = RVR1960. "LORD" counts as "Yahweh" when matching.
	{"ref": "Psalm 27:1b", "type": "faith", "damage": 0, "discovered": false, "en": "Whom shall I fear? Yahweh is the strength of my life.", "es": "Jehová es la fortaleza de mi vida; ¿de quién he de atemorizarme?", "alt": ["The LORD is the strength of my life; of whom shall I be afraid?", "Yahweh is the strength of my life. Of whom shall I be afraid?"]},
	{"ref": "Psalm 29:11", "type": "faith", "damage": 0, "discovered": false, "en": "Yahweh will give strength to His people.", "es": "Jehová dará poder a su pueblo; Jehová bendecirá a su pueblo con paz.", "alt": ["The LORD will give strength unto his people; the LORD will bless his people with peace.", "Yahweh will give strength to his people. Yahweh will bless his people with peace."]},
	{"ref": "Isaiah 40:29", "type": "faith", "damage": 0, "discovered": false, "en": "He gives power to the weak.", "es": "Él da esfuerzo al cansado, y multiplica las fuerzas al que no tiene ningunas.", "alt": ["He giveth power to the faint; and to them that have no might he increaseth strength.", "He gives power to the weak. He increases the strength of him who has no might."]},
	# Sloth attack verses (Spanish = RVR1960)
	{"ref": "Genesis 2:15", "type": "sloth", "damage": 50, "discovered": false, "en": "God put man in the garden of Eden to work.", "es": "Tomó, pues, Jehová Dios al hombre, y lo puso en el huerto de Edén, para que lo labrara y lo guardase.", "alt": ["The LORD God took the man, and put him into the garden of Eden to dress it and to keep it.", "Yahweh God took the man, and put him into the garden of Eden to cultivate and keep it.", "God put the man in the garden of Eden to work it."]},
	{"ref": "Psalm 126:5", "type": "sloth", "damage": 50, "discovered": false, "en": "Those who plant in tears will harvest with shouts of joy.", "es": "Los que sembraron con lágrimas, con regocijo segarán.", "alt": ["They that sow in tears shall reap in joy.", "Those who sow in tears will reap in joy."]},
	{"ref": "Proverbs 18:9", "type": "sloth", "damage": 100, "discovered": false, "en": "Whoever is slack in his work is a brother to a destroyer.", "es": "También el que es negligente en su trabajo es hermano del hombre disipador.", "alt": ["He also that is slothful in his work is brother to him that is a great waster.", "One who is slack in his work is brother to him who is a master of destruction."]},
	# Universal attack verse (type "all" = hurts any enemy type). Also the
	# counter to the enemy verse Genesis 3 (see enemy_verses.gd).
	{"ref": "Galatians 3:13", "type": "all", "damage": 50, "discovered": false, "en": "Christ redeemed us from the curse of the law, having become a curse for us by hanging on a tree.", "es": "Cristo nos redimió de la maldición de la ley, hecho por nosotros maldición (porque está escrito: Maldito todo el que es colgado en un madero).", "alt": ["Christ hath redeemed us from the curse of the law, being made a curse for us: for it is written, Cursed is every one that hangeth on a tree.", "Christ redeemed us from the curse of the law, having become a curse for us. For it is written, Cursed is everyone who hangs on a tree.", "Christ redeemed us from the curse of the law, having become a curse for us."]},
	# Fear verse (enemy attack down)
	# Healing verses: "heal" = % of max HP. By default it's split between you
	# and your party member; choose one target (Alt / Target button) for the
	# full amount. See targeting.gd.
	{"ref": "John 3:16", "type": "heal", "heal": 100, "damage": 0, "discovered": false, "en": "For God so loved the world He gave His Son, whoever believes in Him will not perish but have eternal life.", "es": "Porque de tal manera amó Dios al mundo, que ha dado a su Hijo unigénito, para que todo aquel que en él cree, no se pierda, mas tenga vida eterna.", "alt": ["For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.", "For God so loved the world, that he gave his one and only Son, that whoever believes in him should not perish, but have eternal life.", "For God so loved the world that he gave his one and only Son, that whoever believes in him shall not perish but have eternal life."]},
	{"ref": "Romans 6:23b", "type": "heal", "heal": 100, "damage": 0, "discovered": false, "en": "But the free gift of God is eternal life in Christ Jesus our Lord.", "es": "mas la dádiva de Dios es vida eterna en Cristo Jesús Señor nuestro.", "alt": ["But the gift of God is eternal life through Jesus Christ our Lord.", "But the free gift of God is eternal life in Christ Jesus our Lord.", "But the gift of God is eternal life in Christ Jesus our Lord."]},
	{"ref": "1 Peter 2:24b", "type": "heal", "heal": 50, "damage": 0, "discovered": false, "en": "You were healed by His wounds.", "es": "por cuya herida fuisteis sanados.", "alt": ["By whose stripes ye were healed.", "By his wounds you have been healed.", "By his wounds you were healed."]},
	{"ref": "Psalm 34:18", "type": "heal", "heal": 50, "damage": 0, "discovered": false, "en": "Yahweh is near to the broken hearted and saves the crushed spirit.", "es": "Cercano está Jehová a los quebrantados de corazón; y salva a los contritos de espíritu.", "alt": ["The LORD is nigh unto them that are of a broken heart; and saveth such as be of a contrite spirit.", "Yahweh is near to those who have a broken heart, and saves those who have a crushed spirit.", "The LORD is close to the brokenhearted and saves those who are crushed in spirit."]},
	{"ref": "Matthew 14:30", "type": "heal", "heal": 50, "damage": 0, "discovered": false, "en": "Save me, Lord!", "es": "¡Señor, sálvame!", "alt": ["Lord, save me.", "Lord, save me!"]},
	{"ref": "Psalm 75:10", "type": "fear", "damage": 0, "discovered": false, "en": "God says, \"I will cut off the strength of the wicked.\"", "es": "Quebrantaré todo el poderío de los pecadores, y el poder del justo será exaltado.", "alt": ["I will cut off the strength of the wicked.", "All the horns of the wicked also will I cut off; but the horns of the righteous shall be exalted.", "All the horns of the wicked also will I cut off."]}
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

# (translated automatically: the LineEdit looks this text up in strings.csv)
const DEFAULT_PLACEHOLDER = "Press Enter (or hold Shift and speak) to recite Scripture"
var message_id = 0  # used by _show_verse_message so old messages don't overwrite new ones

func _ready():
	add_to_group("player")  # lets SaveManager find the player when saving
	verse_input.text_submitted.connect(_on_verse_submitted)
	verse_input.placeholder_text = DEFAULT_PLACEHOLDER
	
	# Health comes from SaveManager (full HP on a new level, saved HP after loading)
	hp = SaveManager.player_hp
	hp_bar.value = hp
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
	_build_bubble_and_speaker()
	# Redraw text that's built in code when the language changes
	SaveManager.language_changed.connect(_on_language_changed)
	# Voice: Shift = mic on (speech_recognizer.gd), the result is recited like typed text
	SpeechRecognizer.listening_changed.connect(_on_listening_changed)
	SpeechRecognizer.transcribed.connect(_on_voice_transcribed)
	SpeechRecognizer.status.connect(_on_voice_status)
	# Bring the chosen party member into this level (party_manager.gd)
	PartyManager.ensure_party.call_deferred()
	# Guard and Faith count down at the end of every battle round
	TurnManager.round_ended.connect(_on_round_ended)

# A group button was pressed (Attacks / Status / Special).
# First press shows the whole group; pressing again cycles through its types.
func _on_group_pressed(group: String):
	var types = FILTER_GROUPS[group]
	if filter_group != group:
		filter_group = group
		filter_type = "*"
	elif filter_type == "*":
		filter_type = types[0]
	else:
		var i = types.find(filter_type)
		filter_type = "*" if i + 1 >= types.size() else types[i + 1]
	_update_filter_buttons()
	_update_verse_text()

func _on_show_all_pressed():
	filter_group = "all"
	filter_type = "*"
	_update_filter_buttons()
	_update_verse_text()

# The active group's button shows what it's filtering and is highlighted.
func _update_filter_buttons():
	for group in FILTER_GROUPS:
		var button = verse_panel.get_node("FilterRow/" + group + "Button")
		if group == filter_group:
			# e.g. "Attacks (all)" for the whole group, "Attacks: Universal" for one type
			button.text = (tr("%s (all)") % tr(group)) if filter_type == "*" else tr(group) + ": " + tr(type_name(filter_type))
			button.modulate = Color(1, 0.9, 0.5)
		else:
			button.text = tr(group)
			button.modulate = Color.WHITE

# True if a verse type passes the current filter.
func _passes_filter(type: String) -> bool:
	if filter_group == "all":
		return true
	if filter_type == "*":
		return type in FILTER_GROUPS[filter_group]
	return type == filter_type

# Nice name for a verse type. "all" is shown as "Universal" so it isn't
# confused with "show all".
static func type_name(t: String) -> String:
	return "Universal" if t == "all" else t.capitalize()

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER and not verse_input.has_focus():
		verse_input.grab_focus()
		get_viewport().set_input_as_handled()
	
	if event.is_action_pressed("ui_up") and not verse_input.has_focus():
		var prompt = get_parent().get_node_or_null("NPC/PromptLabel")
		if prompt and prompt.text == "Press Up to talk":
			prompt.text = "Life's so stressful..."   # both translated automatically
	
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
		_show_verse_message(tr("Wait for your turn!"))
		_finish_typing()
		return
	
	# --- Verse cycle (see verse_manager.gd) ---
	# Figure out which verse was typed. A new verse gets discovered (and can be
	# used right away). A verse already used this cycle is blocked until all
	# the other discovered verses have been used too.
	# Enemy verses (enemy_verses.gd) can't be discovered or used by the player
	if _is_enemy_verse(lower):
		_show_verse_message(tr("That's an enemy's verse - you can't use it"))
		_finish_typing()
		return   # in a battle this does NOT use up your turn
	var typed_verse = _find_verse(lower)
	if typed_verse:
		if VerseManager.discover(typed_verse.ref):
			typed_verse.discovered = true
			_show_verse_message(tr("New verse discovered: %s!") % VerseManager.ref_text(typed_verse.ref))
			print("Discovered: ", typed_verse.ref)
		if not VerseManager.can_use(typed_verse.ref):
			_show_verse_message(tr("%s was already used - recite your other %d verse(s) first (Tab to see them)") % [VerseManager.ref_text(typed_verse.ref), VerseManager.remaining_count()])
			print(typed_verse.ref, " is on cooldown")
			_finish_typing()
			return   # in a battle this does NOT use up your turn
		VerseManager.mark_used(typed_verse.ref)
	elif TurnManager.in_battle:
		# Not a verse we recognise: let the player try again (turn not used)
		_show_verse_message(tr("That's not a verse you know - try again"))
		_finish_typing()
		return
	
	_finish_typing()
	
	# Say it in a speech bubble (reference + the whole verse)
	if typed_verse:
		say_verse(typed_verse)
	
	# Who it hits / heals: see targeting.gd (all enemies split by default, or
	# the one you chose with Alt). Faith boosts the damage (x1.5 at +50%,
	# x2 at +100%). Only the player can counter (true).
	apply_verse_effects(lower, 1.0 + faith_bonus, true, true)
	
	# A real verse was recited: if it was our battle turn, the turn is over
	if TurnManager.is_players_turn():
		TurnManager.player_turn_finished.emit()

# Empties the verse box and gives keyboard control back to the game.
func _finish_typing():
	verse_input.clear()
	verse_input.release_focus()
	get_viewport().gui_release_focus()

# Runs the effects of a recited verse (from its text). Used by the player
# above; party members and scrolls call cast_verse() directly.
#   lower        = the verse text in lowercase
#   damage_scale = multiplies attack damage (Faith)
#   can_counter  = true only for the player
#   use_choice   = use the target chosen with Alt (targeting.gd)
func apply_verse_effects(lower: String, damage_scale := 1.0, can_counter := false, use_choice := false):
	# Only run the effect of the verse that matches best. (Without this,
	# Matthew 5:28 was similar enough to Romans 12:11 to also trigger zeal.)
	var best = _find_verse(lower)
	if best:
		cast_verse(best, damage_scale, can_counter, use_choice)
		return
	# Not a known verse: the old light / zeal checks still work out of battle
	for verse in light_verses:
		if lower.similarity(verse.text) > 0.4 or lower.similarity(verse.ref) > 0.6:
			_light_up()
			break
	for verse in zeal_verses:
		if lower.similarity(verse.text) > 0.4 or lower.similarity(verse.ref) > 0.6:
			_zeal_boost()
			break

# The effect of one verse (an entry of all_verses).
#   damage_scale = attack damage multiplier (Faith for you, 0.25 for party members)
#   heal_scale   = healing multiplier (1 for you and scrolls, 0.25 for party members)
#   use_choice   = false for party members: they always use the default targets
func cast_verse(verse, damage_scale := 1.0, can_counter := false, use_choice := true, heal_scale := 1.0):
	match verse.type:
		"sloth", "lust", "all":
			# Attack: split between the targets (all enemies by default)
			var targets = Targeting.attack_targets(use_choice)
			for enemy in targets:
				if is_instance_valid(enemy) and enemy.has_method("take_damage"):
					_attack(verse, enemy, damage_scale / targets.size(), can_counter)
		"heal":
			heal_targets(Targeting.heal_targets(use_choice), verse.heal * heal_scale)
		"light":
			_light_up()
		"guard":
			activate_guard()
		"faith":
			activate_faith()
		"fear":
			# Fear: every enemy in the battle attacks weaker. Outside a battle it
			# hits the nearest enemy (it starts counting down once a battle starts).
			var targets = Targeting.battle_enemies()
			var nearest = get_nearest_enemy()
			if targets.is_empty() and nearest:
				targets.append(nearest)
			for e in targets:
				if e.has_method("apply_fear"):
					e.apply_fear()
		"zeal":
			_zeal_boost()

# Heals "percent" % of max HP, split between the targets: with two targets
# each gets half of (percent % of THEIR max HP).
func heal_targets(targets: Array, percent: float):
	var parts = []
	for t in targets:
		if is_instance_valid(t) and t.has_method("heal"):
			var healed = t.heal(t.max_hp * percent / 100.0 / targets.size())
			parts.append("%s +%s" % [tr(t.display_name), str(snapped(healed, 0.1))])
	if TurnManager.in_battle and not parts.is_empty():
		TurnManager.show_message(tr("Healed: %s") % ", ".join(parts))
	print("Healed ", parts)

# Light (Psalm 18:28...): lights up the dark for a while
func _light_up():
	light_timer = 0.0
	light_duration = 70.0
	if light: light.energy = 1.0
	if near_light: near_light.energy = 1.0
	if halo: halo.energy = 0.8
	if lamp:
		lamp.energy = 0.8

# Zeal (Romans 12:11): run faster and jump higher for 3 seconds
func _zeal_boost():
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

# Using a scroll from the inventory (inventory.gd). Like reciting its verse,
# but the verse cycle isn't touched and the verse isn't discovered.
func use_scroll(verse, item_name: String):
	say_verse(verse)
	_show_verse_message(tr("You read the %s") % item_name)
	cast_verse(verse, 1.0 + faith_bonus, true, true)
	if TurnManager.is_players_turn():
		TurnManager.player_turn_finished.emit()

# The entry of all_verses with this ref (or null)
func get_verse(ref: String):
	for v in all_verses:
		if v.ref == ref:
			return v
	return null

# True if you or your party member could use some healing
func anyone_hurt() -> bool:
	for t in Targeting.heal_targets(false):
		if t.hp < t.max_hp:
			return true
	return false

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
	_process_speaker_bob(delta)
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
	var display = tr("Ready this cycle: %d of %d") % [VerseManager.remaining_count(), VerseManager.discovered.size()] + "\n\n"
	var shown = 0
	for v in all_verses:
		if not _passes_filter(v.type):
			continue   # hidden by the filter buttons
		shown += 1
		var is_found = VerseManager.is_discovered(v.ref)
		if is_found:
			var body = verse_body(v)
			# Used verses are greyed out until the cycle resets; ready ones are green
			var used = VerseManager.is_used(v.ref)
			var color = "gray" if used else "lightgreen"
			var status = tr("(used)") if used else tr("(ready)")
			var power = verse_power_text(v)
			var kind = tr("Universal (All)") if v.type == "all" else tr(v.type.capitalize())
			display += "[color=%s]%s  %s\n%s  |  %s\n%s[/color]\n\n" % [color, VerseManager.ref_text(v.ref), status, power, kind, body]
		else:
			display += "???\n??%  |  ???\n\n"
	if shown == 0:
		display += tr("(No verses of this kind yet)")
	verse_text.text = display

# The short "what it does" line shown for each verse in the verse box
# (and in the inventory).
func verse_power_text(v) -> String:
	match v.type:
		"heal":
			return tr("Heals %d%% of max HP (split between you and your party)") % v.heal
		"guard":
			return tr("+%d%% defense, %d rounds") % [int(guard_reduction * 100), guard_rounds]
		"faith":
			return tr("+%d%% attack (stacks to +%d%%), %d rounds") % [int(faith_step * 100), int(faith_max * 100), faith_rounds]
		"fear":
			return tr("All enemies in battle: attack -50%, 3 rounds")
		"zeal":
			return tr("Speed + jump boost")
		"light":
			return tr("Lights up the dark")
	var text = "%d%%" % v.damage
	if v.type == "all":
		text += tr(", hurts any enemy type")
	else:
		text += tr(", hurts untyped and %s-type enemies") % tr(v.type.capitalize())
	# Which enemy verses does it counter? (from enemy_verses.gd)
	for ref in EnemyVerses.VERSES:
		var ev = EnemyVerses.VERSES[ref]
		if v.ref in ev.get("counters", []):
			text += tr(", counters %s (x%s)") % [VerseManager.ref_text(ev.title), str(snapped(counter_multiplier, 0.1)).trim_suffix(".0")]
	return text

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
		var score = _verse_score(lower, v)
		if score > best_score:
			best_score = score
			best = v
	return best

# How well typed text (already normalized) matches a verse, 0 = no match.
# The text must be over 40% similar, or the reference over 60% similar.
# The reference can be English or Spanish ("Psalm 17:8" or "Salmos 17:8").
func _verse_score(lower: String, v) -> float:
	var text_score = max(lower.similarity(_normalize(v.en)), lower.similarity(_normalize(v.get("es", ""))))
	for alt in v.get("alt", []):
		text_score = max(text_score, lower.similarity(_normalize(alt)))
	var refs = [v.ref]
	if v.has("title"):
		refs.append(v.title)
	var ref_score = 0.0
	for r in refs:
		ref_score = max(ref_score, lower.similarity(_normalize(r)))
		ref_score = max(ref_score, lower.similarity(_normalize(_spanish_ref(r))))
	if text_score > 0.4 or ref_score > 0.6:
		return max(text_score, ref_score)
	return 0.0

# "Psalm 17:8" -> "Salmos 17:8" (from the Spanish column of strings.csv)
func _spanish_ref(ref: String) -> String:
	var es = TranslationServer.get_translation_object("es")
	var space = ref.rfind(" ")
	if es == null or space == -1:
		return ref
	var book = String(es.get_message(ref.substr(0, space)))
	return (book if book != "" else ref.substr(0, space)) + ref.substr(space)

# True if the text matches an ENEMY verse better than any player verse.
func _is_enemy_verse(lower: String) -> bool:
	lower = _normalize(lower)
	var player_best = 0.0
	for v in all_verses:
		player_best = max(player_best, _verse_score(lower, v))
	for ref in EnemyVerses.VERSES:
		var ev = EnemyVerses.VERSES[ref].duplicate()
		ev["ref"] = ref
		if _verse_score(lower, ev) > player_best:
			return true
	return false

# Makes typed or SPOKEN text easy to compare with the verses:
#   - lowercase, no accents (á -> a) and no punctuation
#   - "LORD", "Jehová", "Señor" and voice mistakes like "Yah way" all count as "Yahweh"
#   - numbers said as words become digits: "psalm seventeen eight" -> "psalm 17 8",
#     "first corinthians" -> "1 corinthians", "salmo ciento diecinueve" -> "salmo 119"
#   - "17:8" -> "17 8" (so it matches the spoken version)
func _normalize(text: String) -> String:
	var t = text.to_lower()
	for pair in [["á", "a"], ["é", "e"], ["í", "i"], ["ó", "o"], ["ú", "u"], ["ü", "u"], ["ñ", "n"]]:
		t = t.replace(pair[0], pair[1])
	var clean = ""
	for c in t:
		clean += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else " "
	var words = []
	for w in clean.split(" ", false):
		words.append(w)
	words = _numbers_to_digits(words)
	t = " " + " ".join(words) + " "
	for name in YAHWEH_SOUNDALIKES:
		t = t.replace(" " + name + " ", " yahweh ")
	return t.strip_edges()

# What the LORD's name may look like after typing or speech recognition
const YAHWEH_SOUNDALIKES = ["the lord", "lord", "yah way", "yah weh", "ya way", "yahway", "yaweh", "yahwe", "yawe",
	"jehovah", "jehova", "el senor", "senor", "yave", "yahve", "jave"]

const NUMBER_WORDS = {
	"zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
	"ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
	"seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
	"sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
	"cero": 0, "uno": 1, "un": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6, "siete": 7, "ocho": 8,
	"nueve": 9, "diez": 10, "once": 11, "doce": 12, "trece": 13, "catorce": 14, "quince": 15, "dieciseis": 16,
	"diecisiete": 17, "dieciocho": 18, "diecinueve": 19, "veinte": 20, "veintiuno": 21, "veintidos": 22,
	"veintitres": 23, "veinticuatro": 24, "veinticinco": 25, "veintiseis": 26, "veintisiete": 27,
	"veintiocho": 28, "veintinueve": 29, "treinta": 30, "cuarenta": 40, "cincuenta": 50, "sesenta": 60,
	"setenta": 70, "ochenta": 80, "noventa": 90,
}
const HUNDRED_WORDS = ["hundred", "cien", "ciento"]
const ORDINAL_WORDS = {"first": "1", "second": "2", "third": "3", "primera": "1", "primero": "1", "segunda": "2", "segundo": "2"}

# Turns runs of number words into digits. "seventeen eight" -> ["17", "8"],
# "one hundred nineteen" -> ["119"], "treinta y uno" -> ["31"]
func _numbers_to_digits(words: Array) -> Array:
	var out = []
	var current = -1   # the number being built, -1 = none
	var i = 0
	while i < words.size():
		var w = words[i]
		if ORDINAL_WORDS.has(w) and current == -1:
			out.append(ORDINAL_WORDS[w])
		elif w in HUNDRED_WORDS:
			if current == -1:
				current = 100
			elif current < 10:
				current *= 100
			else:
				out.append(str(current))
				current = 100
		elif NUMBER_WORDS.has(w):
			var n = NUMBER_WORDS[w]
			var fits = false
			if current != -1:
				if current >= 100 and current % 100 == 0:
					fits = true                                # "one hundred" + "nineteen"
				elif n < 10 and current % 10 == 0 and current >= 20 and current % 100 != 0:
					fits = true                                # "twenty" + "seven"
				elif n < 10 and current % 10 == 0 and current > 100:
					fits = true                                # "one hundred twenty" + "six"
			if fits:
				current += n
			else:
				if current != -1:
					out.append(str(current))
				current = n
		elif (w == "and" or w == "y") and current != -1 and i + 1 < words.size() and NUMBER_WORDS.has(words[i + 1]):
			pass   # "one hundred and five", "treinta y uno"
		else:
			if current != -1:
				out.append(str(current))
				current = -1
			if not (w in ["chapter", "verse", "verses", "capitulo", "versiculo", "versiculos"]):
				out.append(w)
		i += 1
	if current != -1:
		out.append(str(current))
	return out

# Shows a short message in the verse input box (as its grey placeholder text),
# then puts the normal placeholder back after a few seconds.
func _show_verse_message(msg: String):
	message_id += 1
	var my_id = message_id
	verse_input.placeholder_text = msg
	await get_tree().create_timer(3.0).timeout
	if my_id == message_id and is_instance_valid(verse_input):
		verse_input.placeholder_text = DEFAULT_PLACEHOLDER

# Changes the whole game's language ("en" or "es"). Same as the menu buttons.
func set_language(new_language: String):
	SaveManager.set_language(new_language)

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

# Healing (never above max HP). Returns how much was really healed.
func heal(amount) -> float:
	var before = hp
	set_hp(hp + amount)
	var healed = hp - before
	PopupText.spawn(self, "+" + str(snapped(healed, 0.1)), Color(0.45, 1.0, 0.5))
	return healed

# Skip Turn: costs skip_turn_cost of your max HP. Guard does NOT reduce it.
# Returns the HP lost.
func pay_skip_cost() -> float:
	var cost = max_hp * skip_turn_cost
	set_hp(hp - cost)
	PopupText.spawn(self, "-" + str(snapped(cost, 0.1)), Color(1, 0.45, 0.4))
	return cost

# ---------------- Guard (Psalm 17:8) ----------------

# Hits an enemy with an attack verse.
# - Typed enemies (e.g. "Sloth" after Genesis 3) only take damage from verses
#   of their type or Universal ("all") verses. Others do nothing.
# - A counter verse on your next turn after a "!" verse does x counter_multiplier.
func _attack(verse, enemy, damage_scale: float, can_counter: bool):
	if enemy.has_method("can_be_hurt_by") and not enemy.can_be_hurt_by(verse.type):
		var msg = tr("No effect - it's %s type now!") % tr(type_name(enemy.enemy_type))
		enemy.show_popup(msg, Color(0.75, 0.75, 0.75))
		_show_verse_message(msg)
		if TurnManager.in_battle:
			TurnManager.show_message(msg)
		print(verse.ref, ": ", msg)
		return 0.0
	var damage = verse.damage * damage_scale
	if can_counter and enemy.has_method("is_countered_by") and enemy.is_countered_by(verse.ref):
		damage *= counter_multiplier
		var msg = tr("Countered! x%s") % str(snapped(counter_multiplier, 0.1)).trim_suffix(".0")
		enemy.show_popup(msg, Color(1, 0.85, 0.3))
		if TurnManager.in_battle:
			TurnManager.show_message(msg + " -" + str(snapped(damage, 0.1)))
		print(msg)
	var dealt = enemy.take_damage(damage)   # (after the enemy's hidden defense)
	PopupText.spawn(enemy, "-" + str(snapped(dealt, 0.1)), Color.WHITE, Vector2(0, -100))
	print("Hit ", enemy.display_name, " for ", damage, " (", dealt, " after defense)")
	return damage

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
	guard_label.text = tr("Defense +%d%% (%d)") % [int(guard_reduction * 100), guard_rounds_left]

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
	faith_label.text = tr("Faith +%d%% (%d)") % [int(faith_bonus * 100), faith_rounds_left]

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

# ---------------- Language ----------------

# A verse's text in the current language (English if there's no Spanish)
func verse_body(v) -> String:
	return v.get("es", v.en) if language == "es" else v.en

# Text that's built in code doesn't switch by itself: redraw it
func _on_language_changed(_new_language):
	_update_verse_text()
	_update_filter_buttons()
	_update_guard_label()
	_update_faith_label()
	verse_input.placeholder_text = DEFAULT_PLACEHOLDER

# ---------------- Speech bubble and speaker icon ----------------

func _build_bubble_and_speaker():
	bubble = preload("res://speech_bubble.gd").new()
	bubble.set_light_style()   # white = the player and party members
	bubble.target = self
	var body = get_node_or_null("CollisionShape2D")
	bubble.head_offset = (body.position if body else Vector2.ZERO) + Vector2(0, -bubble_head_gap)
	bubble.max_width = bubble_max_width
	add_child(bubble)
	
	# Speaker icon (speaker.png) with a pixelate shader so it looks like pixel art
	speaker_icon = Sprite2D.new()
	speaker_icon.name = "SpeakerIcon"
	speaker_icon.texture = load("res://speaker.png")
	speaker_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var material = ShaderMaterial.new()
	material.shader = load("res://pixelate.gdshader")
	material.set_shader_parameter("pixel_size", speaker_pixel_size)
	speaker_icon.material = material
	var tex_size = speaker_icon.texture.get_size()
	speaker_icon.scale = Vector2.ONE * (speaker_size / max(tex_size.x, tex_size.y))
	speaker_icon.position = (body.position if body else Vector2.ZERO) + Vector2(0, -speaker_height)
	speaker_icon.z_index = 20
	speaker_icon.visible = false
	add_child(speaker_icon)

# Shows "Reference / whole verse" above the player
func say_verse(v):
	var title = VerseManager.ref_text(v.ref)
	var text = verse_body(v)
	text = text.substr(0, 1).to_upper() + text.substr(1)
	var time = clamp(bubble_time_per_char * (title.length() + text.length()), bubble_min_time, bubble_max_time)
	bubble.say(title, text, false, time)

# ---------------- Voice (push-to-talk) ----------------

func _on_listening_changed(on: bool):
	speaker_icon.visible = on
	if on:
		_show_verse_message(tr("Listening... release Shift to recite"))

func _on_voice_status(message: String):
	_show_verse_message(message)

# The recognized words go in the verse box for a moment, then they're
# recited exactly as if you had typed them and pressed Enter.
func _on_voice_transcribed(text: String):
	text = text.strip_edges()
	if text == "":
		_show_verse_message(tr("Didn't catch that - try again"))
		return
	verse_input.text = text
	await get_tree().create_timer(voice_submit_delay).timeout
	if is_instance_valid(verse_input) and verse_input.text == text:
		_on_verse_submitted(text)

# The speaker icon bobs up and down a little (in whole pixels, so it stays crisp)
func _process_speaker_bob(_delta):
	if speaker_icon and speaker_icon.visible:
		var body = get_node_or_null("CollisionShape2D")
		var base_y = (body.position.y if body else 0.0) - speaker_height
		speaker_icon.position.y = base_y + round(sin(Time.get_ticks_msec() / 160.0) * 3.0)
