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
# Carrying something heavy (the gold in Greed, see greed_level.gd): you can
# jump at most this high (pixels, 0 = no limit) and walk at this fraction of
# your speed. Set by the level whenever the inventory changes.
var carry_max_jump_height = 0.0
var carry_speed_scale = 1.0
# Top sideways speed in the air while carrying something heavy (0 = no limit).
# It holds for every way of moving: walking, the ram dash, Zeal. A speed boost
# (feather) raises it by the same factor - except where the level sets
# speed_boost_air_capped (Greed: around the jump over the water, so the gold
# puzzle there stays the same).
var carry_air_speed = 0.0
# SPEED BOOST (the Greed feathers, greed_pickup.gd): walking speed x speed_boost
# for speed_boost_left seconds. Its own multiplier - not a change to `speed` -
# so Zeal (which saves and restores `speed`) can't wipe it or make it stick.
# Another boost while one is on restarts the countdown (doesn't stack).
# Shows "Speed +50%  7s" in the status row.
var speed_boost = 1.0
var speed_boost_left = 0.0
var speed_boost_air_capped = false
var speed_label: Label
# "en", "es" or "pl". The language lives in SaveManager (set with the main
# menu's English / Español / Polski buttons); this just reads it so verse checks match.
var language: String:
	get:
		return SaveManager.language
# Verse box filter (see _build_verse_panel). Four groups of verse types:
# Pressing a button again cycles through its sub-filters, e.g.
# Attacks (all) > Sloth > Lust > Greed > Wrath > Gluttony > Envy > Pride > Universal > Attacks (all).
const SINS = ["sloth", "lust", "greed", "wrath", "gluttony", "envy", "pride"]
const FILTER_GROUPS = {
	"Attacks": ["sloth", "lust", "greed", "wrath", "gluttony", "envy", "pride", "all"], # 1st button ("all" = Universal: hurts any enemy type)
	"Status": ["zeal", "guard", "faith", "fear", "wisdom"], # 2nd button
	"Special": ["light"],                       # 3rd button
	"Heal": ["heal"],                           # 4th (rightmost) button (includes sheet verses that heal)
}
const ATTACK_TYPES = ["sloth", "lust", "greed", "wrath", "gluttony", "envy", "pride", "all"]   # verse types that do damage
# The verses from the design sheet (every sin) live in a data file made by
# tools/verses_from_sheet.py and are added to all_verses in _ready.
const SHEET_VERSES_PATH = "res://data/verses.json"
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
@export var guard_fx_hover = false   # true: the dome hovers over the sheep; false: on them (the original placement)
@export var guard_fx_hover_gap = 0.22 # the gap under it, in dome heights
const GUARD_DOME_BOTTOM = 14.0       # the closed dome in Guardeffect.png: its bottom / height
const GUARD_DOME_HEIGHT = 29.0       # (frame px, from the frame centre with the offset)
var guard_rounds_left = 0            # 0 = not guarded
var guard_fx: AnimatedSprite2D       # the wings/dome animation (built in _ready)
const GuardShadow = preload("res://guard_shadow.gd")
var guard_shadow   # the shadow the wings cast over the sheep (guard_shadow.gd)
func _update_guard_shadow(delta):
	if guard_shadow:
		guard_shadow.update(delta)
		var body = get_node_or_null("Sprite2D")
		if body and "hold_frame" in body:
			body.hold_frame = GuardShadow.CROUCH_FRAME if guard_shadow.crouching else -1
var guard_label: Label               # "Guard 50% up (3)" (built in _ready)
@export var guard_play_opacity = 0.8    # the wings while they play (a little see-through; their shadow on the sheep stays solid)
@export var guard_linger_opacity = 0.35 # after the animation, the wings stay at this opacity while guarded

# Faith (Psalm 27:1b, Psalm 29:11, Isaiah 40:29): attack up.
# Each Faith verse adds faith_step (+50%) up to faith_max (+100%) and resets
# the duration to faith_rounds. Only the PLAYER's verse damage is boosted.
@export var faith_step = 0.5
@export var faith_max = 1.0
@export var faith_rounds = 3
@export var shofar_sound_path = "res://General/Sounds/shofar.mp3"   # plays when Faith reaches the max
var faith_bonus = 0.0                # 0.5 = +50% attack
var faith_rounds_left = 0
var faith_label: Label

# Wisdom (sheet "Wisdom UP" column, data/verses.json "wisdom"): each Wisdom
# verse adds its % (stacking up to wisdom_max = 100%) and resets the duration
# to wisdom_rounds, like Faith. Wisdom = EVASION: each enemy hit on you is
# dodged with a chance of the wisdom %, but never more than evasion_max (so
# 100% wisdom can't make you untouchable). The SinDeath counter also checks
# for 100% wisdom (Greed/scripts/sindeath_scene.gd).
@export var wisdom_max = 100.0
@export var wisdom_rounds = 3
@export var evasion_max = 75.0        # the dodge chance never goes above this %
var wisdom = 0.0                      # 0..100 (%)
var wisdom_rounds_left = 0
var wisdom_label: Label
var dodges = 0                        # (counted for the tests)
var dodge_override = -1.0             # tests: >= 0 forces the dodge roll (0 = never, 1 = always)
signal wisdom_changed(value)

# A boss scene can take over what a recited verse does (Greed's SinDeath
# counter, sindeath_scene.gd). Called twice from _on_verse_submitted:
#   verse_interceptor.call("pre", verse)  -> true = skip the verse cycle check
#   verse_interceptor.call("post", verse) -> {"effects": bool, "end_turn": bool}
# Typed and spoken (voice) verses both come through here.
var verse_interceptor := Callable()
var shofar_player: AudioStreamPlayer
var shofar_plays = 0                 # how many times the shofar has played (for testing)
signal faith_maxed                   # emitted when Faith newly reaches the max

# Fear (Psalm 75:10): lowers enemy attack - see enemy.gd (fear_reduction)

# Skip Turn (button or K in a battle): ends your turn, but costs this much of
# your max HP (0.1 = 10%). Guard doesn't reduce it - it's a price you choose
# to pay, not an enemy attack.
@export var skip_turn_cost = 0.1

# Ram (like the headbutt in the Unity Greed level): hold the Ram key (X by
# default, remappable in Settings > Controls) while standing on the ground.
# You back up a little while it charges; when the bar is full you dash
# forward and break thorn barriers (greed_barrier.gd) you run into.
# Letting go before it's full (a quick tap of X / the Ram button) does a
# TAP RAM right away: a shorter, slower dash at tap_ram_power (half power: it
# still breaks pots, thorns, blocks - anything a full ram breaks; in Baby Mode
# it counts as a full hit). After a tap ram there's a short tap_ram_cooldown so
# tapping fast can't beat the full ram. Jump still works while charging/dashing.
@export_group("Ram")
@export var ram_charge_time = 0.7     # seconds to hold before the dash
@export var ram_dash_time = 0.7       # how long the dash lasts at most
@export var ram_speed_multiplier = 2.2
@export var ram_backup_speed = 0.2    # backing up while charging (x walking speed)
@export var tap_ram_power = 0.5       # a tap ram: half as long, and 1 + (2.2-1) * 0.5 = 1.6x speed
@export var tap_ram_cooldown = 0.5    # seconds after a tap ram before the next ram can start
@export_group("")
var ram_state = 0                     # 0 = nothing, 1 = charging, 2 = dashing
var ram_timer = 0.0
var ram_power = 1.0                   # the dash going on: 1 = full ram, tap_ram_power = tap ram
var ram_cooldown_left = 0.0
var _ram_tapped = false               # Ram was pressed since the last physics frame
var facing = 1.0                      # 1 = right, -1 = left (last walking direction)
var ram_bar: ProgressBar
var ram_needs_release = false         # after a dash, let go of the key before charging again
signal rammed(collider)               # something was hit by a dash

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
	{"ref": "Matthew 5:28", "type": "lust", "damage": 100, "discovered": true, "en": "everyone who gazes at a woman to lust after her has committed adultery in his heart.", "jesus": true, "pl": "każdy, kto patrzy na kobietę, aby jej pożądać, już popełnił z nią cudzołóstwo w swoim sercu.", "es": "todo el que mira a una mujer para codiciarla ya cometió adulterio en su corazón."},
	{"ref": "Psalm 18:28", "type": "light", "damage": 50, "discovered": false, "en": "the lord, my god, lights up my darkness.", "pl": "Pan, mój Bóg, rozjaśnia moje ciemności.", "es": "Jehová mi Dios alumbrará mis tinieblas."},
	{"ref": "Romans 12:11", "type": "zeal", "damage": 50, "discovered": false, "en": "never lag in diligence. let the spirit excite you as you serve the lord.", "pl": "W gorliwości nie ustawajcie, bądźcie płomiennego ducha, Panu służcie.", "es": "En lo que requiere diligencia, no perezosos; fervientes en espíritu, sirviendo al Señor."},
	{"ref": "1 Corinthians 6:18", "type": "lust", "damage": 50, "discovered": false, "en": "flee sexual immorality!", "pl": "Uciekajcie przed nierządem!", "es": "¡huyan de la inmoralidad sexual!"},
	{"ref": "Proverbs 6:32", "type": "lust", "damage": 50, "discovered": false, "en": "he who commits adultery is a fool who destroys himself.", "pl": "Kto cudzołoży, jest głupcem, który niszczy samego siebie.", "es": "el que comete adulterio es un necio que se destruye a sí mismo."},
	{"ref": "Psalm 18:28a", "type": "light", "damage": 50, "discovered": false, "en": "you light a lamp for me.", "pl": "Ty zapalasz moją lampę.", "es": "Tú encenderás mi lámpara."},
	{"ref": "Psalm 119:105", "type": "light", "damage": 50, "discovered": false, "en": "your word is a lamp to my feet, and a light for my path.", "pl": "Twoje słowo jest lampą dla moich stóp i światłem na mojej ścieżce.", "es": "Lámpara es a mis pies tu palabra, y lumbrera a mi camino."},
	# Guard verse: "damage" isn't used for guard verses. "alt" = other wordings
	# that also count (here the fuller KJV version).
	{"ref": "Psalm 17:8", "type": "guard", "damage": 0, "discovered": false, "en": "hide me under the shadow of your wings.", "pl": "Strzeż mnie jak źrenicy oka, ukryj mnie w cieniu swoich skrzydeł.", "es": "guárdame como a la niña de tus ojos; escóndeme bajo la sombra de tus alas.", "alt": ["keep me as the apple of the eye, hide me under the shadow of thy wings."]},
	# Faith verses (attack up). Spanish = RVR1960. "LORD" counts as "Yahweh" when matching.
	{"ref": "Psalm 27:1b", "type": "faith", "damage": 0, "discovered": false, "en": "Whom shall I fear? Yahweh is the strength of my life.", "pl": "Pan jest twierdzą mego życia, przed kim mam się trwożyć?", "es": "Jehová es la fortaleza de mi vida; ¿de quién he de atemorizarme?", "alt": ["The LORD is the strength of my life; of whom shall I be afraid?", "Yahweh is the strength of my life. Of whom shall I be afraid?"]},
	{"ref": "Psalm 29:11", "type": "faith", "damage": 0, "discovered": false, "en": "Yahweh will give strength to His people.", "pl": "Pan da siłę swojemu ludowi, Pan pobłogosławi swój lud pokojem.", "es": "Jehová dará poder a su pueblo; Jehová bendecirá a su pueblo con paz.", "alt": ["The LORD will give strength unto his people; the LORD will bless his people with peace.", "Yahweh will give strength to his people. Yahweh will bless his people with peace."]},
	{"ref": "Isaiah 40:29", "type": "faith", "damage": 0, "discovered": false, "en": "He gives power to the weak.", "pl": "Daje siłę zmęczonemu i pomnaża moc bezsilnego.", "es": "Él da esfuerzo al cansado, y multiplica las fuerzas al que no tiene ningunas.", "alt": ["He giveth power to the faint; and to them that have no might he increaseth strength.", "He gives power to the weak. He increases the strength of him who has no might."]},
	# Sloth attack verses (Spanish = RVR1960)
	{"ref": "Genesis 2:15", "type": "sloth", "damage": 50, "discovered": false, "en": "God put man in the garden of Eden to work.", "pl": "Pan Bóg wziął człowieka i umieścił go w ogrodzie Eden, aby go uprawiał i strzegł.", "es": "Tomó, pues, Jehová Dios al hombre, y lo puso en el huerto de Edén, para que lo labrara y lo guardase.", "alt": ["The LORD God took the man, and put him into the garden of Eden to dress it and to keep it.", "Yahweh God took the man, and put him into the garden of Eden to cultivate and keep it.", "God put the man in the garden of Eden to work it."]},
	{"ref": "Psalm 126:5", "type": "sloth", "damage": 50, "discovered": false, "en": "Those who plant in tears will harvest with shouts of joy.", "pl": "Ci, którzy sieją we łzach, żąć będą w radości.", "es": "Los que sembraron con lágrimas, con regocijo segarán.", "alt": ["They that sow in tears shall reap in joy.", "Those who sow in tears will reap in joy."]},
	{"ref": "Proverbs 18:9", "type": "sloth", "damage": 100, "discovered": false, "en": "Whoever is slack in his work is a brother to a destroyer.", "pl": "Kto jest opieszały w swojej pracy, jest bratem niszczyciela.", "es": "También el que es negligente en su trabajo es hermano del hombre disipador.", "alt": ["He also that is slothful in his work is brother to him that is a great waster.", "One who is slack in his work is brother to him who is a master of destruction."]},
	# Universal attack verse (type "all" = hurts any enemy type). Also the
	# counter to the enemy verse Genesis 3 (see enemy_verses.gd).
	{"ref": "Galatians 3:13", "type": "all", "damage": 50, "discovered": false, "en": "Christ redeemed us from the curse of the law, having become a curse for us by hanging on a tree.", "pl": "Chrystus wykupił nas od przekleństwa zakonu, stawszy się za nas przekleństwem, bo napisano: Przeklęty każdy, który zawisł na drzewie.", "es": "Cristo nos redimió de la maldición de la ley, hecho por nosotros maldición (porque está escrito: Maldito todo el que es colgado en un madero).", "alt": ["Christ hath redeemed us from the curse of the law, being made a curse for us: for it is written, Cursed is every one that hangeth on a tree.", "Christ redeemed us from the curse of the law, having become a curse for us. For it is written, Cursed is everyone who hangs on a tree.", "Christ redeemed us from the curse of the law, having become a curse for us."]},
	# Fear verse (enemy attack down)
	# Healing verses: "heal" = % of max HP. By default it's split between you
	# and your party member; choose one target (Alt / Target button) for the
	# full amount. See targeting.gd.
	{"ref": "John 3:16", "type": "heal", "heal": 100, "damage": 0, "discovered": false, "en": "For God so loved the world He gave His Son, whoever believes in Him will not perish but have eternal life.", "jesus": true, "pl": "Tak bowiem Bóg umiłował świat, że dał swego jednorodzonego Syna, aby każdy, kto w Niego wierzy, nie zginął, ale miał życie wieczne.", "es": "Porque de tal manera amó Dios al mundo, que ha dado a su Hijo unigénito, para que todo aquel que en él cree, no se pierda, mas tenga vida eterna.", "alt": ["For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.", "For God so loved the world, that he gave his one and only Son, that whoever believes in him should not perish, but have eternal life.", "For God so loved the world that he gave his one and only Son, that whoever believes in him shall not perish but have eternal life."]},
	{"ref": "Romans 6:23b", "type": "heal", "heal": 100, "damage": 0, "discovered": false, "en": "But the free gift of God is eternal life in Christ Jesus our Lord.", "pl": "A darem łaski Bożej jest życie wieczne w Chrystusie Jezusie, Panu naszym.", "es": "mas la dádiva de Dios es vida eterna en Cristo Jesús Señor nuestro.", "alt": ["But the gift of God is eternal life through Jesus Christ our Lord.", "But the free gift of God is eternal life in Christ Jesus our Lord.", "But the gift of God is eternal life in Christ Jesus our Lord."]},
	{"ref": "1 Peter 2:24b", "type": "heal", "heal": 50, "damage": 0, "discovered": false, "en": "You were healed by His wounds.", "pl": "Jego ranami zostaliście uzdrowieni.", "es": "por cuya herida fuisteis sanados.", "alt": ["By whose stripes ye were healed.", "By his wounds you have been healed.", "By his wounds you were healed."]},
	{"ref": "Psalm 34:18", "type": "heal", "heal": 50, "damage": 0, "discovered": false, "en": "Yahweh is near to the broken hearted and saves the crushed spirit.", "pl": "Pan jest blisko tych, którzy mają złamane serce, i wybawia skruszonych na duchu.", "es": "Cercano está Jehová a los quebrantados de corazón; y salva a los contritos de espíritu.", "alt": ["The LORD is nigh unto them that are of a broken heart; and saveth such as be of a contrite spirit.", "Yahweh is near to those who have a broken heart, and saves those who have a crushed spirit.", "The LORD is close to the brokenhearted and saves those who are crushed in spirit."]},
	{"ref": "Matthew 14:30", "type": "heal", "heal": 50, "damage": 0, "discovered": false, "en": "Save me, Lord!", "pl": "Panie, ratuj mnie!", "es": "¡Señor, sálvame!", "alt": ["Lord, save me.", "Lord, save me!"]},
	{"ref": "Psalm 75:10", "type": "fear", "damage": 0, "discovered": false, "en": "God says, \"I will cut off the strength of the wicked.\"", "pl": "Złamię całą moc bezbożnych, a moc sprawiedliwego będzie wywyższona.", "es": "Quebrantaré todo el poderío de los pecadores, y el poder del justo será exaltado.", "alt": ["I will cut off the strength of the wicked.", "All the horns of the wicked also will I cut off; but the horns of the righteous shall be exalted.", "All the horns of the wicked also will I cut off."]}
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
# The iPhone / Android app: tap the box, then type or use the keyboard's dictation key
const TAP_PLACEHOLDER = "Tap here to type or speak Scripture"
const TOUCH_PLACEHOLDER = "Tap Type (or hold Mic and speak) to recite Scripture"

# "... (Tab to see them)" on a computer, "... (tap Verses to see them)" on a phone
static func already_used_text() -> String:
	var gs = Engine.get_main_loop().root.get_node_or_null("/root/GameSettings")
	if gs and gs.touch_prompts():
		return TranslationServer.translate("%s was already used - recite your other %d verse(s) first (tap Verses to see them)")
	return TranslationServer.translate("%s was already used - recite your other %d verse(s) first (Tab to see them)")

func default_placeholder() -> String:
	if TouchControls.tap_to_type():
		return TAP_PLACEHOLDER
	# a touch screen in the browser: the Type / Mic buttons
	return TOUCH_PLACEHOLDER if GameSettings.touch_prompts() else DEFAULT_PLACEHOLDER
var message_id = 0  # used by _show_verse_message so old messages don't overwrite new ones

func _ready():
	add_to_group("player")  # lets SaveManager find the player when saving
	verse_input.text_submitted.connect(_on_verse_submitted)
	verse_input.placeholder_text = default_placeholder()
	
	# Health comes from SaveManager (full HP on a new level, saved HP after loading)
	hp = SaveManager.player_hp
	hp_bar.value = hp
	# If we just loaded a save, move to the saved position
	SaveManager.apply_pending_player_state(self)
	
	_load_sheet_verses()
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
	_layout_hud()
	_build_status_labels()
	_build_bubble_and_speaker()
	_build_ram_bar()
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
	var types = filter_types(group)
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
# Sizes the "Show all" button to its (translated) text and keeps it inside the panel's right edge
func _fit_show_all_button():
	var b = verse_panel.get_node_or_null("ShowAllButton") if verse_panel else null
	if b == null:
		return
	var want = b.get_combined_minimum_size().x
	var x = VERSE_PANEL_SIZE.x - 8 - want
	if not is_equal_approx(b.size.x, want) or not is_equal_approx(b.position.x, x):
		b.set_deferred("size", Vector2(want, 22))
		b.set_deferred("position", Vector2(x, 3))

func _update_filter_buttons():
	_fit_show_all_button.call_deferred()
	for group in FILTER_GROUPS:
		var button = verse_panel.get_node("FilterRow/" + group + "Button")
		if group == filter_group:
			# e.g. "Attacks (all)" for the whole group, "Attacks: Universal" for one type
			button.text = (tr("%s (all)") % tr(group)) if filter_type == "*" else tr(group) + ": " + tr(type_name(filter_type))
			button.modulate = Color(1, 0.9, 0.5)
		else:
			button.text = tr(group)
			button.modulate = Color.WHITE

# ---------------- The level's sin first ----------------
# On a level named after a sin (Greed.tscn -> "greed", Sloth.tscn -> "sloth",
# Lust, Gluttony, and Wrath / Envy / Pride when they get a level) that sin
# comes first under Attacks: first in the button's cycle (Attacks (all) >
# Greed > Sloth > Lust > ...) and its verses at the top of "Attacks (all)".
# Other levels (Endless...) keep the usual order. Worked out from the level
# that's loaded, so it always matches the level you're in.
func level_sin() -> String:
	var scene = get_tree().current_scene if is_inside_tree() else null
	if scene == null:
		return ""
	var level = scene.scene_file_path.get_file().get_basename().to_lower()
	return level if level in SINS else ""

# The group's sub-filters in cycle order (Attacks: the level's sin first)
func filter_types(group: String) -> Array:
	var types: Array = FILTER_GROUPS[group].duplicate()
	var sin = level_sin()
	if group == "Attacks" and sin in types:
		types.erase(sin)
		types.push_front(sin)
	return types

# True if the verse attacks this sin
func _hits_sin(v, sin: String) -> bool:
	if v.get("set", "") == "sheet":
		return v.get("sins", {}).get(sin, 0) > 0
	return v.type == sin

# True if a verse passes the current filter.
func _passes_filter(v) -> bool:
	var type = v.type
	if filter_group == "all":
		return true
	if v.get("set", "") == "sheet":
		# A sheet verse can attack several sins and heal too
		var sins: Dictionary = v.get("sins", {})
		var attacks = not sins.is_empty() or v.get("all_damage", 0) > 0
		match filter_group:
			"Attacks":
				if filter_type == "*":
					return attacks
				if filter_type == "all":
					return v.get("all_damage", 0) > 0
				return sins.get(filter_type, 0) > 0
			"Heal":
				return v.get("heal", 0) > 0
			"Status":
				if filter_type == "*":
					return v.get("zeal", false) or v.get("guard", false) or v.get("wisdom", 0) > 0 or v.get("faith", 0) > 0
				if filter_type == "wisdom":
					return v.get("wisdom", 0) > 0
				if filter_type == "faith":
					return v.get("faith", 0) > 0
				return filter_type in ["zeal", "guard"] and v.get(filter_type, false)
		return false
	# A built-in verse with the sheet's status columns (John 3:16: heal +
	# Guard + Faith...) also shows under those Status filters
	if filter_group == "Status":
		var st = verse_statuses(v)
		if filter_type == "*" and not st.is_empty():
			return true
		if st.has(filter_type):
			return true
	if filter_type == "*":
		return type in FILTER_GROUPS[filter_group]
	return type == filter_type

# Nice name for a verse type. "all" is shown as "Universal" so it isn't
# confused with "show all".
static func type_name(t: String) -> String:
	return "Universal" if t == "all" else t.capitalize()

# A cut-scene is playing (e.g. Greed's SinDeath scene): no walking, jumping,
# ramming or opening the verse box. The cut-scene uses Enter/Space/clicks.
var cutscene_lock = false

func _input(event):
	if _dismiss_typing_on_outside_press(event):
		return
	if cutscene_lock:
		return
	# (a tap of Ram too quick for any physics frame to see it held: still a tap ram)
	if event.is_action_pressed("ram") and not event.is_echo():
		_ram_tapped = true
	# Baby Mode (baby_mode.gd): no verse box, no typing - Enter and Tab do nothing
	if GameSettings.baby_mode and (event.is_action_pressed("recite") or event.is_action_pressed("toggle_verse_box")):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("recite") and not event.is_echo() and not verse_input.has_focus():
		verse_input.grab_focus()
		get_viewport().set_input_as_handled()
	
	# Up/Down (scroll_verses_up/down) scroll the open verse list; then they
	# do nothing else (no talking / entering doors, no caret moves in the box)
	if verses_scrolling_active() and (event.is_action("scroll_verses_up") or event.is_action("scroll_verses_down")):
		get_viewport().set_input_as_handled()
		if event.is_pressed() and not event.is_echo():
			_scroll_verses(-VERSE_SCROLL_STEP if event.is_action("scroll_verses_up") else VERSE_SCROLL_STEP)
		return
	
	if event.is_action_pressed("interact") and not verse_input.has_focus():
		var prompt = get_parent().get_node_or_null("NPC/PromptLabel")
		if prompt and prompt.get_meta("talk_prompt", false):
			prompt.set_meta("talk_prompt", false)
			prompt.text = "Life's so stressful..."   # translated automatically
	
	# Tab = show/hide the verse box ("toggle_verse_box" in Project Settings > Input Map).
	# Works while typing too. set_input_as_handled() stops Godot from also using
	# Tab to move keyboard focus out of the LineEdit.
	if event.is_action_pressed("toggle_verse_box"):
		get_viewport().set_input_as_handled()
		if verse_panel:
			verse_panel.visible = not verse_panel.visible
			print("Tab pressed - panel visible: ", verse_panel.visible)
			if verse_panel.visible:
				place_verse_panel()
				_update_verse_text()

# ---------------- Clicking / tapping off the verse box ----------------
# While you're typing, a click or tap anywhere outside the verse box closes it
# (like pressing away from a text field): the box loses focus, the phone
# keyboard goes away, nothing is recited and the words you typed stay in the
# box for later. That click does nothing else - it doesn't also press a
# button, pick a target or move a touch button. (Clicks inside the open verse
# list - its filter buttons, scrolling it - still work while you type.)
var _swallow_pointer_frame = -1   # the press that closed the box (its touch + mouse copies)
var _swallow_releases_until = 0   # ...and their releases (msec)

func _dismiss_typing_on_outside_press(event) -> bool:
	var is_press = false
	var pos = Vector2.ZERO
	if event is InputEventMouseButton:
		if not event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			return false   # (the wheel scrolls the verse list)
		is_press = event.pressed
		pos = event.position
	elif event is InputEventScreenTouch:
		is_press = event.pressed
		pos = event.position
	else:
		return false
	var frame = Engine.get_process_frames()
	if is_press:
		if frame == _swallow_pointer_frame:
			get_viewport().set_input_as_handled()   # the mouse copy of the same tap
			return true
		_swallow_releases_until = 0
		if not is_instance_valid(verse_input) or not verse_input.has_focus():
			return false
		if verse_input.get_global_rect().has_point(pos):
			return false   # in the box: move the caret, select...
		if verse_panel and verse_panel.is_visible_in_tree() and verse_panel.get_global_rect().has_point(pos):
			return false
		close_typing()
		_swallow_pointer_frame = frame
		_swallow_releases_until = Time.get_ticks_msec() + 2000
		get_viewport().set_input_as_handled()
		return true
	if Time.get_ticks_msec() < _swallow_releases_until:
		get_viewport().set_input_as_handled()
		return true
	return false

# Leaves the verse box without reciting (keeps what was typed)
func close_typing():
	verse_input.release_focus()
	get_viewport().gui_release_focus()
	DisplayServer.virtual_keyboard_hide()

# ---------------- Scrolling the verse list with the arrow keys ----------------
# Tap = a small step; hold = smooth scrolling (Settings can turn it off).
const VERSE_SCROLL_STEP = 22.0     # pixels per tap
const VERSE_SCROLL_SPEED = 320.0   # pixels per second while held

func verses_scrolling_active() -> bool:
	return verse_panel != null and verse_panel.visible and GameSettings.scroll_verses_with_arrows

func _scroll_verses(amount: float):
	var bar = verse_text.get_v_scroll_bar()
	bar.value = clamp(bar.value + amount, bar.min_value, bar.max_value)

func _process_verse_scroll(delta):
	if verses_scrolling_active():
		var dir = Input.get_action_strength("scroll_verses_down") - Input.get_action_strength("scroll_verses_up")
		if dir != 0.0:
			_scroll_verses(dir * VERSE_SCROLL_SPEED * delta)

func _on_verse_submitted(text):
	if GameSettings.baby_mode:
		_finish_typing()   # Baby Mode: verses aren't typed or spoken (baby_mode.gd)
		return
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
	var skip_cycle = typed_verse != null and verse_interceptor.is_valid() and verse_interceptor.call("pre", typed_verse) == true
	if typed_verse:
		if VerseManager.discover(typed_verse.ref):
			typed_verse.discovered = true
			_show_verse_message(tr("New verse discovered: %s!") % VerseManager.ref_text(typed_verse.ref))
			print("Discovered: ", typed_verse.ref)
		if not skip_cycle and not VerseManager.can_use(typed_verse.ref):
			_show_verse_message(already_used_text() % [VerseManager.ref_text(typed_verse.ref), VerseManager.remaining_count()])
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
	
	if typed_verse and verse_interceptor.is_valid():
		var r = verse_interceptor.call("post", typed_verse)
		if r is Dictionary:
			if r.get("effects", true):
				apply_verse_effects(lower, attack_multiplier(), true, true)
			if r.get("end_turn", true) and TurnManager.is_players_turn():
				TurnManager.player_turn_finished.emit()
			return
	
	# Who it hits / heals: see targeting.gd (all enemies split by default, or
	# the one you chose with Alt). Faith boosts the damage (x1.5 at +50%,
	# x2 at +100%). Only the player can counter (true).
	apply_verse_effects(lower, attack_multiplier(), true, true)
	
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
#   caster       = who recited it (null = you). A negative heal hurts the caster.
func cast_verse(verse, damage_scale := 1.0, can_counter := false, use_choice := true, heal_scale := 1.0, caster = null):
	_attack_only_vs_targets(verse, damage_scale, can_counter, use_choice)
	if verse.get("set", "") == "sheet":
		_cast_sheet_verse(verse, damage_scale, can_counter, use_choice, heal_scale, caster)
		return
	# Guard / Faith / Zeal (and the sheet's extra Guard UP / Faith UP / Wisdom UP
	# / Zeal up columns, e.g. John 3:16): all of them, see apply_verse_statuses
	if not statuses_by_caller:
		if caster == null:
			apply_verse_statuses(verse)
		else:   # Ramuel / Baana: all of it on themselves (their own stats)
			apply_verse_statuses(verse, caster)
	match verse.type:
		"sloth", "lust", "all":
			# Attack: split between the targets (all enemies by default)
			var targets = Targeting.attack_targets(use_choice)
			for enemy in targets:
				if is_instance_valid(enemy) and enemy.has_method("take_damage") and not _hits_only_vs(verse, enemy):
					_attack(verse, enemy, damage_scale / targets.size(), can_counter)
		"heal":
			heal_targets(_heal_targets_for(use_choice), verse.heal * heal_scale)
		"light":
			_light_up()
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

# A verse from the design sheet: it can attack (its sin % against enemies of
# that sin, e.g. Wrath % vs Wrath-type, "All Sin" % against any enemy; the
# higher one counts) AND heal (Heal %, split like the other heal verses).
# A negative heal costs the caster that much of their max HP.
func _cast_sheet_verse(verse, damage_scale, can_counter, use_choice, heal_scale, caster):
	if not verse.get("sins", {}).is_empty() or verse.get("all_damage", 0) > 0:
		var targets = Targeting.attack_targets(use_choice)
		for enemy in targets:
			if is_instance_valid(enemy) and enemy.has_method("take_damage") and not _hits_only_vs(verse, enemy):
				_attack(verse, enemy, damage_scale / targets.size(), can_counter)
	# Every status of the verse (Guard + Wisdom, Guard + Faith...), not just one
	if not statuses_by_caller:
		if caster == null:
			apply_verse_statuses(verse)
		else:   # Ramuel / Baana: all of it on themselves (their own stats)
			apply_verse_statuses(verse, caster)
	var heal_pct = float(verse.get("heal", 0))
	if heal_pct > 0:
		heal_targets(_heal_targets_for(use_choice), heal_pct * heal_scale)
	elif heal_pct < 0:
		var who = caster if caster != null and is_instance_valid(caster) else self
		var cost = who.max_hp * (-heal_pct) / 100.0
		if who == self:
			set_hp(hp - cost)
			PopupText.spawn(self, "-" + str(snapped(cost, 0.1)), Color(1, 0.45, 0.4))
		elif who.has_method("take_damage"):
			who.take_damage(cost)
		if TurnManager.in_battle:
			TurnManager.show_message(tr("%s loses %s HP") % [tr(who.display_name), str(snapped(cost, 0.1))])

# ---------------- Status effects (Guard, Faith, Wisdom, Zeal) ----------------
# A verse can have several: e.g. Psalm 36:11a = Guard + Wisdom, Romans 16:18b =
# attack + Guard, John 3:16 = heal + Guard + Faith + Wisdom + Zeal. They all
# apply, each shows in the status row, and one popup lists them.

# Set by a phone player around cast_verse(): they give the statuses
# themselves (to the ally picked on their phone), see party_member.gd.
var statuses_by_caller = false

# The verse's statuses: {"guard": true, "faith": 25.0 (%), "wisdom": 20.0, "zeal": -50.0 (%)}
func verse_statuses(v) -> Dictionary:
	var st = {}
	var t = v.get("type", "")
	if t == "guard" or v.get("guard", false):
		st["guard"] = true
	if t == "faith":
		st["faith"] = faith_step * 100.0
	if float(v.get("faith", 0)) > 0:
		st["faith"] = float(v.faith)
	if float(v.get("wisdom", 0)) > 0:
		st["wisdom"] = float(v.wisdom)
	# Zeal: the sheet's Zeal up % (a negative one is a penalty, e.g. James 3:1
	# -50%); the built-in Zeal verses / list entries without a % give zeal_default
	var z = float(v.get("zeal_pct", 0))
	if z != 0:
		st["zeal"] = z
	elif t == "zeal" or v.get("zeal", false):
		st["zeal"] = zeal_default
	return st

# Gives a verse's statuses to ONE character: `to` = the reciter or the ally
# a support verse was aimed at (null = you). Everyone has their own Guard,
# Faith (their attack), Wisdom (their evasion) and Zeal (their attack +/-),
# see activate_guard / activate_faith / add_wisdom / add_zeal here and in
# party_member.gd.
#   only = just these statuses ([] = all of them)
# Returns the labels shown ("Guard +50%", "Zeal -50%"...).
func apply_verse_statuses(verse, to = null, only := []) -> Array:
	var st = verse_statuses(verse)
	var labels = []
	var who = to if to != null and is_instance_valid(to) and to.has_method("add_zeal") else self
	for k in st.keys():
		if not only.is_empty() and not k in only:
			continue
		match k:
			"guard":
				if who == self:
					activate_guard()
				else:
					who.activate_guard(guard_rounds, guard_reduction)
				labels.append(tr("Guard +%d%%") % roundi(guard_reduction * 100))
			"faith":
				who.activate_faith(st.faith / 100.0)
				labels.append(tr("Faith +%d%%") % roundi(min(st.faith, faith_max * 100)))
			"wisdom":
				who.add_wisdom(st.wisdom)
				labels.append(tr("Wisdom +%d%%") % roundi(st.wisdom))
			"zeal":
				who.add_zeal(st.zeal)
				labels.append(zeal_text(st.zeal))
	if not labels.is_empty():
		# One popup with all of them (two per line), over who got them:
		# on the body, under the verse's speech bubble
		var rows = []
		for i in range(0, labels.size(), 2):
			rows.append("   ".join(labels.slice(i, i + 2)))
		PopupText.spawn(who, "\n".join(rows), Color(0.7, 0.88, 1.0) if st.get("zeal", 0) >= 0 else Color(1.0, 0.7, 0.6), Vector2(0, -40), 1.8)
		last_status_labels = labels
	return labels

# What you have now ("Guard +50%", "Faith +100%", "Zeal -50%"...), e.g. for the phones' party list
func status_labels() -> Array:
	var out = []
	if guard_rounds_left > 0:
		out.append(tr("Guard +%d%%") % roundi(guard_reduction * 100))
	if faith_rounds_left > 0:
		out.append(tr("Faith +%d%%") % roundi(faith_bonus * 100))
	if wisdom_rounds_left > 0 and wisdom > 0:
		out.append(tr("Wisdom +%d%%") % roundi(wisdom))
	if zeal_rounds_left > 0:
		out.append(zeal_text(zeal))
	return out

# "Zeal +50%" / "Zeal -50%"
func zeal_text(pct: float) -> String:
	return tr("Zeal +%d%%") % roundi(min(pct, zeal_max)) if pct >= 0 else tr("Zeal -%d%%") % roundi(min(-pct, -zeal_min))
var last_status_labels = []   # (for the tests)

# Who a verse's healing goes to. A party member can aim it (party_member.gd:
# Ramuel / Baana heal YOU when you're at 50% or less) by setting
# forced_heal_targets around its cast_verse().
var forced_heal_targets: Array = []
func _heal_targets_for(use_choice: bool) -> Array:
	var forced = forced_heal_targets.filter(func(t): return is_instance_valid(t))
	return forced if not forced.is_empty() else Targeting.heal_targets(use_choice)

# How much a verse does to this enemy (before Faith / splitting / defense).
# -1 = no effect.
func verse_damage_against(verse, enemy) -> float:
	# Boss-only enemies (enemy.gd only_vs): only their sheet column counts
	var only = enemy.get("only_vs") if enemy else null
	if only != null and only != "":
		var pct = float(verse.get("vs", {}).get(only, 0))
		return pct if pct > 0 else -1.0
	if verse.get("set", "") == "sheet":
		var dmg = float(verse.get("all_damage", 0))
		var sins: Dictionary = verse.get("sins", {})
		# What kind of enemy is it? A sin type (e.g. "greed"), an "extra" kind
		# from the sheet's Dmg-to columns (e.g. "atheist" - the atheist goats),
		# or nothing yet (untyped).
		# (An extra kind doesn't block the sin %: an atheist goat has no sin
		# type, so any attack verse hurts it, and Dmg to Atheists adds on top.)
		var sin_typed = false
		if enemy.has_method("enemy_sins"):
			for t in enemy.enemy_sins():
				if t in SINS:
					sin_typed = true
		for sin in sins:
			# Its sin % vs enemies of that sin; an untyped enemy is hurt by any
			# attack verse, like the built-in verses
			if not sin_typed or (enemy.has_method("has_sin") and enemy.has_sin(sin)):
				dmg = max(dmg, float(sins[sin]))
		# The Dmg-to column for its kind comes ON TOP (e.g. 2 Corinthians 6:14:
		# 45% vs any sin + 50% vs Atheists = 95% against an atheist goat)
		var extra: Dictionary = verse.get("vs", {})
		var bonus = 0.0
		if enemy.has_method("has_sin"):
			for kind in extra:
				if enemy.has_sin(kind):
					bonus = max(bonus, float(extra[kind]))
		dmg += bonus
		return dmg if dmg > 0 else -1.0
	if enemy.has_method("can_be_hurt_by") and not enemy.can_be_hurt_by(verse.type):
		return -1.0
	return float(verse.damage)

# Loads the design-sheet verses (data/verses.json, every sin) into all_verses.
# A built-in verse above with the same reference wins (it has alt wordings).
# "type" = its strongest sin (for the verse box), "all" if it only has the
# All Sin %, "heal" if it only heals.
func _load_sheet_verses():
	for v in all_verses:
		if v.get("set", "") == "sheet":
			return   # already loaded
	var file = FileAccess.open(SHEET_VERSES_PATH, FileAccess.READ)
	if file == null:
		push_warning("No sheet verses: " + SHEET_VERSES_PATH)
		return
	var data = JSON.parse_string(file.get_as_text())
	if not (data is Dictionary):
		push_warning("Couldn't read " + SHEET_VERSES_PATH)
		return
	var known = {}
	for v in all_verses:
		known[v.ref] = true
	for row in data.get("verses", []):
		if known.has(row.ref):
			# A built-in verse keeps its effect, but gets the sheet's boss
			# columns (Dmg to SinDeath / Idol...) so e.g. John 3:16 hurts SinDeath
			var builtin = get_verse(row.ref)
			if builtin != null and not row.get("vs", {}).is_empty() and not builtin.has("vs"):
				builtin["vs"] = row.vs
			# ...and its status columns on top of its own effect (e.g. John 3:16:
			# heal + Guard + Faith + Wisdom + Zeal), see apply_verse_statuses
			if builtin != null:
				for k in ["guard", "zeal", "faith", "wisdom", "zeal_pct"]:
					if row.get(k, false) and not builtin.has(k) and builtin.get("type", "") != k:
						builtin[k] = row[k]
			continue
		var sins: Dictionary = row.get("sins", {})
		var all_sin = row.get("all_damage", 0)
		var type = "heal"
		var best = 0.0
		for sin in sins:
			if sins[sin] > best:
				best = sins[sin]
				type = sin
		if type == "heal" and all_sin > 0:
			type = "all"
		if type == "heal" and row.get("heal", 0) == 0 and row.get("zeal", false):
			type = "zeal"   # only the Zeal effect
		elif type == "heal" and row.get("heal", 0) == 0 and row.get("guard", false):
			type = "guard"  # only the Guard effect
		elif type == "heal" and row.get("heal", 0) == 0 and row.get("wisdom", 0) > 0:
			type = "wisdom" # only the Wisdom effect
		elif type == "heal" and row.get("heal", 0) == 0 and row.get("faith", 0) > 0:
			type = "faith"  # only the Faith effect
		var v = {
			"ref": row.ref, "set": "sheet", "type": type,
			"damage": max(best, all_sin), "sins": sins, "all_damage": all_sin,
			"vs": row.get("vs", {}),
			"heal": row.get("heal", 0), "jesus": row.get("jesus", false),
			"translation": row.get("translation", ""),
			"zeal": row.get("zeal", false),   # Zeal list / Zeal up: also gives the speed + jump boost
			"zeal_pct": row.get("zeal_pct", 0), # Zeal up %: attack +/- for 3 rounds (< 0 = a penalty, James 3:1)
			"guard": row.get("guard", false), # Guard list / Guard UP: also raises your defense for a few rounds (+ the wings)
			"guard_pct": row.get("guard_pct", 0), # (the sheet's Guard UP %; the game uses guard_reduction)
			"wisdom": row.get("wisdom", 0),   # Wisdom UP %: raises your wisdom (= evasion)
			"faith": row.get("faith", 0),     # Faith UP %: attack up (like the built-in Faith verses)
			"alt": row.get("alt", []),        # other wordings that also match (sheet_fills.json "extra")
			"discovered": false,
			"en": row.get("en", ""), "es": row.get("es", ""), "pl": row.get("pl", ""),
		}
		all_verses.append(v)
		known[v.ref] = true

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

# Zeal (Romans 12:11): run faster and jump higher for zeal_seconds. It's a
# walking boost, counted in SECONDS (not battle turns). Another Zeal verse
# while it's on restarts the countdown (it doesn't stack).
# The countdown shows in the status row ("Zeal +100%  3s") and in the
# level's TimerLabel if it has one. (Before, a level without a TimerLabel -
# Greed - ended the boost at once.)
@export var zeal_seconds = 3
var zeal_left = 0
var zeal_label: Label

# Zeal in battle (the sheet's Zeal up %): your attack +/- that % for
# zeal_rounds battle rounds, stacking like Faith between zeal_min and
# zeal_max. A NEGATIVE Zeal up (James 3:1 -50%) is a penalty: weaker attacks.
# Verses without a % (Romans 12:11, the Zeal list) give zeal_default.
# Your attack = 1 + Faith + Zeal (attack_multiplier), never below 0.
@export var zeal_default = 50.0
@export var zeal_max = 100.0
@export var zeal_min = -75.0
@export var zeal_rounds = 3
var zeal = 0.0                      # -75..100 (%)
var zeal_rounds_left = 0

# +pct % zeal (or a penalty when < 0). A positive one also gives the speed +
# jump boost (outside battles that's what it's for).
func add_zeal(pct: float):
	if zeal_rounds_left > 0:
		zeal = clamp(zeal + pct, zeal_min, zeal_max)
	else:
		zeal = clamp(pct, zeal_min, zeal_max)
	zeal_rounds_left = zeal_rounds
	if zeal == 0.0:
		zeal_rounds_left = 0
	_update_zeal_label()
	print("Zeal: attack ", ("+" if zeal >= 0 else ""), int(zeal), "% for ", zeal_rounds, " rounds")
	if pct > 0:
		_zeal_boost()

# Your attack verses' damage: 1 + Faith + Zeal (0.5 = +50%)
func attack_multiplier() -> float:
	return max(1.0 + faith_bonus + zeal / 100.0, 0.0)

func _zeal_boost():
	if zeal_left > 0:
		zeal_left = zeal_seconds   # already on: just restart the countdown
		_update_zeal_label()
		return
	# (relative to the current values, so the Greed level's tuning comes back after)
	var old_jump = jump_velocity
	var old_speed = speed
	jump_velocity = old_jump * 1.75
	speed = old_speed * 2
	zeal_left = zeal_seconds
	while zeal_left > 0:
		_update_zeal_label()
		await get_tree().create_timer(1.0).timeout
		if not is_inside_tree():
			return
		zeal_left -= 1
	_update_zeal_label()
	jump_velocity = old_jump
	speed = old_speed

# A speed boost (feather): walking x mult for secs seconds (restarts, doesn't stack)
func add_speed_boost(mult: float, secs: float):
	speed_boost = max(mult, 1.0)
	speed_boost_left = secs
	_update_speed_label()

func _tick_speed_boost(delta):
	if speed_boost_left <= 0.0:
		return
	var shown = ceili(speed_boost_left)
	speed_boost_left -= delta
	if speed_boost_left <= 0.0:
		speed_boost_left = 0.0
		speed_boost = 1.0
		_update_speed_label()
	elif ceili(speed_boost_left) != shown:
		_update_speed_label()

func _update_speed_label():
	if speed_label:
		speed_label.visible = speed_boost_left > 0.0
		speed_label.text = tr("Speed +%d%%  %ds") % [roundi((speed_boost - 1.0) * 100.0), ceili(speed_boost_left)]

func _update_zeal_label():
	var timer_label = get_parent().get_node_or_null("CanvasLayer/TimerLabel") if get_parent() else null
	if timer_label:
		timer_label.text = str(zeal_left) if zeal_left > 0 else ""
	if zeal_label:
		# Battle Zeal ("Zeal -50%  turn 1/3"), else the walking boost's seconds
		zeal_label.visible = zeal_rounds_left > 0 or zeal_left > 0
		if zeal_rounds_left > 0:
			zeal_label.text = zeal_text(zeal) + "  " + tr("turn %d/%d") % [status_turn(zeal_rounds_left, zeal_rounds), zeal_rounds]
		else:
			zeal_label.text = tr("Zeal +100%%  %ds") % zeal_left
		zeal_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.35) if zeal_rounds_left <= 0 or zeal >= 0 else Color(1.0, 0.4, 0.4))

# Using a scroll from the inventory (inventory.gd). Like reciting its verse,
# but the verse cycle isn't touched and the verse isn't discovered.
func use_scroll(verse, item_name: String):
	say_verse(verse)
	_show_verse_message(tr("You read the %s") % item_name)
	cast_verse(verse, attack_multiplier(), true, true)
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
	# During a battle (or a cut-scene) you stay where you are (no walking or jumping)
	var in_battle = TurnManager.in_battle or cutscene_lock
	var typing = verse_input.has_focus()
	if Input.is_action_just_pressed("jump") and is_on_floor() and not typing and not in_battle:
		velocity.y = current_jump_velocity()
		if ram_state == 1:
			_end_ram(false)   # jumping cancels a charge (but not a dash)
	var direction = 0.0 if in_battle or typing else Input.get_axis("move_left", "move_right")
	if direction != 0.0 and ram_state == 0:
		facing = sign(direction)
	elif TurnManager.in_battle and ram_state == 0:
		var toward = _battle_facing()
		if toward != 0:
			facing = toward   # in a battle: look at the enemies (like the party members)
	_apply_facing()
	_process_ram(delta, in_battle or typing)
	if bounce_left > 0.0:
		bounce_left -= delta   # Baby Mode: bounced back off the idol (baby_bounce)
		velocity.x = bounce_speed
	elif ram_state == 1:
		velocity.x = -facing * speed * ram_backup_speed          # backing up to take a run-up
	elif ram_state == 2:
		velocity.x = facing * speed * (1.0 + (ram_speed_multiplier - 1.0) * ram_power)   # the dash (tap ram: slower)
	else:
		velocity.x = direction * speed * carry_speed_scale * speed_boost if direction else move_toward(velocity.x, 0, speed)
	var air_cap = carry_air_speed * (1.0 if speed_boost_air_capped else speed_boost)
	if air_cap > 0.0 and (velocity.y < 0.0 or not is_on_floor()):
		velocity.x = clamp(velocity.x, -air_cap, air_cap)
	move_and_slide()
	if air_cap > 0.0 and not is_on_floor():
		velocity.x = clamp(velocity.x, -air_cap, air_cap)
	_tick_speed_boost(delta)
	if ram_state == 2:
		_check_ram_hits()

# The jump's starting speed: weaker while carrying something heavy, so the
# jump peaks at carry_max_jump_height. With gravity added once per physics
# tick (dt) the feet rise h = v^2/2g + v*dt/2, so solve that for v.
func current_jump_velocity() -> float:
	if carry_max_jump_height > 0.0:
		var half = gravity / float(Engine.physics_ticks_per_second) / 2.0
		var v = -half + sqrt(half * half + 2.0 * gravity * carry_max_jump_height)
		return max(jump_velocity, -v)
	return jump_velocity

# ---------------- Ram ----------------

func _process_ram(delta, blocked: bool):
	if blocked:
		_ram_tapped = false
		if ram_state != 0:
			_end_ram(false)
		return
	if ram_cooldown_left > 0.0:
		ram_cooldown_left -= delta
	var tapped = _ram_tapped
	_ram_tapped = false
	match ram_state:
		0:
			if ram_needs_release and not tapped:
				ram_needs_release = Input.is_action_pressed("ram")
			elif (Input.is_action_pressed("ram") or tapped) and is_on_floor() and ram_cooldown_left <= 0.0:
				ram_needs_release = false
				ram_state = 1
				ram_timer = 0.0
				if not Input.is_action_pressed("ram"):
					_start_dash(tap_ram_power)   # pressed and let go already
		1:
			if not Input.is_action_pressed("ram"):
				_start_dash(tap_ram_power)   # let go early (a tap): a tap ram right away
				return
			ram_timer += delta
			if ram_timer >= ram_charge_time:
				_start_dash(1.0)
		2:
			ram_timer += delta
			if ram_timer >= ram_dash_time * ram_power:
				_end_ram(false)
	_update_ram_bar()

func _start_dash(power: float):
	ram_state = 2
	ram_timer = 0.0
	ram_power = power
	# golden while dashing (a paler gold for a tap ram)
	modulate = Color(1.0, 0.85, 0.45) if power >= 1.0 else Color(1.0, 0.93, 0.7)
	_update_ram_bar()

# A tap ram (not a full one) is going on
func is_tap_ram() -> bool:
	return ram_state == 2 and ram_power < 1.0

# After moving: did the dash run into something that can be rammed?
func _check_ram_hits():
	for i in get_slide_collision_count():
		var collider = get_slide_collision(i).get_collider()
		if collider and collider.has_method("on_rammed"):
			collider.on_rammed(self)
			rammed.emit(collider)
			_end_ram(true)
			return
	if is_on_wall():
		_end_ram(true)   # hit a plain wall

# A barrier noticed the dash right next to it (greed_barrier.gd)
func on_ram_target_reached(target):
	target.on_rammed(self)
	rammed.emit(target)
	_end_ram(true)

func _end_ram(hit: bool):
	if ram_state == 2:
		_ram_ended_at = Time.get_ticks_msec()
	if ram_state == 2:
		ram_needs_release = true
		if hit:
			velocity.x = -facing * 150.0   # small bounce back
		if ram_power < 1.0:
			ram_cooldown_left = tap_ram_cooldown   # (no tap-spamming)
	ram_state = 0
	ram_timer = 0.0
	modulate = Color.WHITE
	_update_ram_bar()

func is_ramming() -> bool:
	return ram_state == 2

# Baby Mode: does touching an enemy now count as a ram? While dashing, and a
# moment after the dash ended (it can stop against the enemy first).
const RAM_GRACE_MSEC = 150
var _ram_ended_at = -100000
func ram_counts() -> bool:
	return ram_state == 2 or Time.get_ticks_msec() - _ram_ended_at <= RAM_GRACE_MSEC

# Baby Mode (baby_mode.gd): a short bounce back after ramming the idol, so
# every hit is a separate ram. dir = -1 (left) or 1 (right).
var bounce_left = 0.0
var bounce_speed = 0.0
func baby_bounce(dir: float, strength := 380.0, time := 0.22, hop := true):
	if ram_state != 0:
		_end_ram(false)
	bounce_speed = dir * strength
	bounce_left = time
	if hop and is_on_floor():
		velocity.y = -220.0   # a little hop

func _build_ram_bar():
	ram_bar = ProgressBar.new()
	ram_bar.name = "RamBar"
	ram_bar.show_percentage = false
	ram_bar.max_value = 1.0
	ram_bar.size = Vector2(70, 8)
	var body = get_node_or_null("CollisionShape2D")
	ram_bar.position = (body.position if body else Vector2.ZERO) + Vector2(-35, -70)
	ram_bar.z_index = 20
	var fill = StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.8, 0.3)
	ram_bar.add_theme_stylebox_override("fill", fill)
	ram_bar.visible = false
	add_child(ram_bar)

func _update_ram_bar():
	if ram_bar == null:
		return
	ram_bar.visible = ram_state == 1
	ram_bar.value = clamp(ram_timer / ram_charge_time, 0.0, 1.0) if ram_state == 1 else 0.0

func _process(delta):
	_apply_baby_mode_ui()
	_process_speaker_bob(delta)
	_update_guard_shadow(delta)
	_update_low_hp()
	_process_verse_scroll(delta)
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
	if cycle_label:
		# Counts the verses the filter buttons show (all of them on "Show all")
		var ready = 0
		var found = 0
		for v in all_verses:
			if VerseManager.is_discovered(v.ref) and _passes_filter(v):
				found += 1
				if not VerseManager.is_used(v.ref):
					ready += 1
		cycle_label.text = tr("Ready this cycle: %d of %d") % [ready, found]
	# One row per verse: Index | Verse | Effects (alternating row shading)
	var display = "[table=3]"
	var shown = 0
	# Discovered verses first, then the "???" rows of the ones still to find
	var ordered = []
	var hidden = []
	for v in all_verses:
		if VerseManager.is_discovered(v.ref):
			ordered.append(v)
		else:
			hidden.append(v)
	# "Attacks (all)" on a sin's level: that sin's verses first (each part
	# keeps its usual order)
	var lvl_sin = level_sin()
	if filter_group == "Attacks" and filter_type == "*" and lvl_sin != "":
		var first = ordered.filter(func(v): return _hits_sin(v, lvl_sin))
		var rest = ordered.filter(func(v): return not _hits_sin(v, lvl_sin))
		# discovered first, then the "???" ones, as before
		ordered = first + rest + hidden.filter(func(v): return _hits_sin(v, lvl_sin)) + hidden.filter(func(v): return not _hits_sin(v, lvl_sin))
	else:
		ordered.append_array(hidden)
	for v in ordered:
		if not _passes_filter(v):
			continue   # hidden by the filter buttons
		shown += 1
		var bg = "bg=#2a2236,#211b2c"
		if VerseManager.is_discovered(v.ref):
			var body = verse_body(v)
			# Used verses are greyed out until the cycle resets; ready ones are green
			var used = VerseManager.is_used(v.ref)
			var color = "gray" if used else "lightgreen"
			var status = tr("(used)") if used else tr("(ready)")
			var power = verse_power_text(v)
			var instant = instant_kill_text(v)
			if instant != "":   # in gold in the Effects column
				power = power.replace(instant, "[color=#ffd84a]%s[/color]" % instant)
			var kind = tr("Universal (All)") if v.type == "all" else tr(v.type.capitalize())
			if v.type in ["guard", "zeal"]:
				kind = ""   # "50% def" / "Speed + jump" already say it
			if v.get("set", "") == "sheet":
				var kinds = []
				for sin in v.get("sins", {}):
					kinds.append(tr(sin.capitalize()))
				if v.get("all_damage", 0) > 0:
					kinds.append(tr("Universal (All)"))
				# (Zeal / Guard aren't repeated here: "Speed + jump" / "50% def" say it)
				if kinds.is_empty() and v.get("heal", 0) != 0:
					kinds.append(tr("Heal"))
				kind = _pack_labels(kinds)
			# Words of Jesus: a small red cross after the reference, and the text in red when ready (like red-letter Bibles)
			var jesus_mark = ""
			if v.get("jesus", false):
				jesus_mark = " [color=#ff6b6b]†[/color]"
				if not used:
					body = "[color=#ff9a9a]%s[/color]" % body
			display += "[cell expand=2 %s][color=%s]%s%s\n[font_size=11]%s[/font_size][/color][/cell]" % [bg, color, VerseManager.ref_text(v.ref), jesus_mark, status]
			display += "[cell expand=6 %s][color=%s]%s[/color][/cell]" % [bg, color, body]
			display += "[cell expand=3 %s][color=%s][font_size=11]%s[/font_size][/color][/cell]" % [bg, color, power + ("\n" + kind if kind != "" else "")]
		else:
			display += "[cell expand=2 %s]???[/cell][cell expand=6 %s]???[/cell][cell expand=3 %s]??%%[/cell]" % [bg, bg, bg]
	display += "[/table]"
	if shown == 0:
		display = tr("(No verses of this kind yet)")
	verse_text.text = display

# The short "what it does" line shown for each verse in the verse box
# (and in the inventory).
# Puts short labels on as few lines as fit the Effects column, so a line
# never has to wrap inside a label ("50% def" stays together): "25% vs Sloth," / "10% vs all, 50% def"
func _pack_labels(parts: Array, max_chars := 18) -> String:
	var lines = []
	var line = ""
	for p in parts:
		if line != "" and line.length() + 2 + p.length() <= max_chars:
			line += ", " + p
			continue
		if line != "":
			lines.append(line + ",")
			line = ""
		# a label too long for one line is split between words
		for w in p.split(" "):
			if line == "":
				line = w
			elif line.length() + 1 + w.length() <= max_chars:
				line += " " + w
			else:
				lines.append(line)
				line = w
	if line != "":
		lines.append(line)
	return "\n".join(lines)

# The Effects column of the verse list: short labels ("25% vs Sloth",
# "10% vs all", "50% def", "10% heal").
func verse_power_text(v) -> String:
	if v.get("set", "") == "sheet":
		var parts = []
		if INSTANT_KILLS.has(v.ref):
			parts.append(instant_kill_text(v))
		for sin in v.get("sins", {}):
			parts.append(tr("%d%% vs %s") % [v.sins[sin], tr(sin.capitalize())])
		if v.get("all_damage", 0) > 0:
			parts.append(tr("%d%% vs all") % v.all_damage)
		for kind in v.get("vs", {}):   # e.g. "+50% vs Atheist"
			parts.append("+" + tr("%d%% vs %s") % [v.vs[kind], tr(kind.capitalize())])
		if v.get("heal", 0) > 0:
			parts.append(tr("%d%% heal") % v.heal)
		elif v.get("heal", 0) < 0:
			parts.append(tr("-%d%% HP") % (-v.heal))
		if v.get("zeal", false):
			parts.append(tr("Speed + jump"))
		if float(v.get("zeal_pct", 0)) != 0:
			parts.append(zeal_text(float(v.zeal_pct)))   # "Zeal +50%" / the penalty "Zeal -50%"
		if v.get("guard", false):
			parts.append(tr("%d%% def") % int(guard_reduction * 100))
		if v.get("faith", 0) > 0:
			parts.append(tr("+%d%% atk") % int(min(v.faith, faith_max * 100)))
		if v.get("wisdom", 0) > 0:
			parts.append(tr("+%d%% wis") % int(v.wisdom))
		return _pack_labels(parts)
	var text = _builtin_power_text(v)
	# Boss columns from the sheet (e.g. John 3:16 also hurts SinDeath)
	for kind in v.get("vs", {}):
		text += ", +" + tr("%d%% vs %s") % [v.vs[kind], tr(kind.capitalize())]
	# The sheet's status columns on top of its own effect (John 3:16...)
	var extra = []
	if v.get("guard", false) and v.type != "guard":
		extra.append(tr("%d%% def") % int(guard_reduction * 100))
	if v.get("zeal", false) and v.type != "zeal":
		extra.append(tr("Speed + jump"))
	if float(v.get("zeal_pct", 0)) != 0:
		extra.append(zeal_text(float(v.zeal_pct)))
	if float(v.get("faith", 0)) > 0 and v.type != "faith":
		extra.append(tr("+%d%% atk") % int(min(v.faith, faith_max * 100)))
	if float(v.get("wisdom", 0)) > 0:
		extra.append(tr("+%d%% wis") % int(v.wisdom))
	if not extra.is_empty():
		text = _pack_labels([text] + extra)
	return text

func _builtin_power_text(v) -> String:
	match v.type:
		"heal":
			return tr("%d%% heal") % v.heal
		"guard":
			return tr("%d%% def") % int(guard_reduction * 100)
		"faith":
			return tr("+%d%% atk") % int(faith_step * 100)
		"fear":
			return tr("-50% enemy atk")
		"zeal":
			return tr("Speed + jump")
		"light":
			return tr("Lights up the dark")
	var text = tr("%d%% vs all") % v.damage
	if v.type != "all":
		text = tr("%d%% vs %s") % [v.damage, tr(v.type.capitalize())]
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


# The sheep looks the way it's going: Playerwalkanim.png faces right, so
# walking / ramming left mirrors the sprite (flip_h - the 3D battle view
# copies it, battle_3d.gd). The collision box is symmetric, so only the
# picture flips; the ram already dashes along `facing`.
func _apply_facing():
	var sprite = get_node_or_null("Sprite2D")
	if sprite is Sprite2D:
		sprite.flip_h = facing < 0.0

# Which way the enemies are in a battle: 1 = right, -1 = left, 0 = none
func _battle_facing() -> int:
	var enemies = Targeting.battle_enemies()
	if enemies.is_empty():
		return 0
	var x = 0.0
	for e in enemies:
		x += e.get_center().x if e.has_method("get_center") else e.global_position.x
	return 1 if x / enemies.size() >= get_body_center().x else -1

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
	var text_score = lower.similarity(_normalize(v.en))
	for lang in ["es", "pl"]:
		if v.get(lang, "") != "":
			text_score = max(text_score, lower.similarity(_normalize(v[lang])))
	for alt in v.get("alt", []):
		text_score = max(text_score, lower.similarity(_normalize(alt)))
	var refs = [v.ref]
	if v.has("title"):
		refs.append(v.title)
	var ref_score = 0.0
	for r in refs:
		ref_score = max(ref_score, lower.similarity(_normalize(r)))
		ref_score = max(ref_score, lower.similarity(_normalize(_spanish_ref(r))))
		ref_score = max(ref_score, lower.similarity(_normalize(_localized_ref(r, "pl"))))
	if text_score > 0.4 or ref_score > 0.6:
		return max(text_score, ref_score)
	return 0.0

# "Psalm 17:8" -> "Salmos 17:8" (from the Spanish column of strings.csv)
func _spanish_ref(ref: String) -> String:
	return _localized_ref(ref, "es")

# "Matthew 6:1" -> "Mateusza 6:1" ("pl") / "Mateo 6:1" ("es")
func _localized_ref(ref: String, lang: String) -> String:
	var es = TranslationServer.get_translation_object(lang)
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
	for pair in [["á", "a"], ["é", "e"], ["í", "i"], ["ó", "o"], ["ú", "u"], ["ü", "u"], ["ñ", "n"],
			["ą", "a"], ["ć", "c"], ["ę", "e"], ["ł", "l"], ["ń", "n"], ["ś", "s"], ["ź", "z"], ["ż", "z"]]:
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
	"jehovah", "jehova", "el senor", "senor", "yave", "yahve", "jave", "jahwe", "pan", "pana", "panu", "panie"]

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
		verse_input.placeholder_text = default_placeholder()

# Changes the whole game's language ("en", "es" or "pl"). Same as the menu buttons.
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
# Baby Mode: nothing hurts you (you can't lose; falling still respawns you).
func take_damage(amount):
	if GameSettings.baby_mode:
		return 0.0
	if guard_rounds_left > 0:
		amount *= (1.0 - guard_reduction)
	set_hp(hp - amount)
	return amount

# Baby Mode (baby_mode.gd): an enemy you rammed but didn't finish nips you.
# Never takes your last HP point (you can't lose). Returns the HP lost.
func baby_hurt(amount) -> float:
	var before = hp
	set_hp(max(1.0, hp - amount))
	var lost = before - hp
	if lost > 0:
		PopupText.spawn(self, "-" + str(snapped(lost, 0.1)), Color(1, 0.45, 0.4))
		var sprite = get_node_or_null("Sprite2D")
		if sprite:
			var t = sprite.create_tween()
			t.tween_property(sprite, "self_modulate", Color(1.0, 0.35, 0.35), 0.06)
			t.tween_property(sprite, "self_modulate", Color.WHITE, 0.3)
	_update_low_hp()
	return lost

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
# Verses that defeat one kind of enemy at once (their own sin, named in the
# verse): ignores defense, Guard, Faith and splitting. With the default
# targets every matching enemy in the battle falls; with Alt only the chosen
# target (if it matches). Against anything else the verse works normally.
# The kind is one of the enemy's line_sets (enemy.gd).
const INSTANT_KILLS = {
	"Ecclesiastes 5:10a": "silver_wolf",   # "He who loves silver..." - Greedwolf
	"Isaiah 56:11a": "bronze_wolf",        # "the dogs are greedy..." - Greedog
}
const INSTANT_KILL_NAMES = {"silver_wolf": "Silver wolves", "bronze_wolf": "Bronze wolves"}

func instant_kill_text(verse) -> String:
	if not INSTANT_KILLS.has(verse.get("ref", "")):
		return ""
	return tr("Instant defeat vs %s") % tr(INSTANT_KILL_NAMES[INSTANT_KILLS[verse.ref]])

func instant_kill_against(verse, enemy) -> bool:
	var kind = INSTANT_KILLS.get(verse.get("ref", ""), "")
	return kind != "" and enemy.has_method("is_kind") and enemy.is_kind(kind)

# What "No effect" says on a boss-only enemy (enemy.gd only_vs)
const ONLY_VS_MESSAGES = {
	"sindeath": "No effect - only SinDeath verses can hurt it",
	"idol": "No effect - only idolatry verses can hurt it",
}

# Does this verse hit a boss-only enemy (enemy.gd only_vs) through its column?
func _hits_only_vs(verse, enemy) -> bool:
	var only = enemy.get("only_vs")
	return only != null and only != "" and float(verse.get("vs", {}).get(only, 0)) > 0

# Boss-only enemies are hit by their column of ANY verse, even one that
# otherwise only heals (e.g. Romans 6:23b vs SinDeath).
func _attack_only_vs_targets(verse, damage_scale, can_counter, use_choice):
	if verse.get("vs", {}).is_empty():
		return
	var targets = Targeting.attack_targets(use_choice)
	for enemy in targets:
		if is_instance_valid(enemy) and enemy.has_method("take_damage") and _hits_only_vs(verse, enemy):
			_attack(verse, enemy, damage_scale / targets.size(), can_counter)
		elif is_instance_valid(enemy) and enemy.has_method("take_damage") and enemy.get("only_vs") and not _has_regular_attack(verse):
			# e.g. a SinDeath-only verse at the calf: the normal attack below
			# won't touch it, so say "No damage!" here
			_attack(verse, enemy, damage_scale / targets.size(), can_counter)

# Does the verse attack through its sin / all-sin damage (or a built-in attack type)?
func _has_regular_attack(verse) -> bool:
	if verse.get("set", "") == "sheet":
		return not verse.get("sins", {}).is_empty() or verse.get("all_damage", 0) > 0
	return verse.get("type", "") in ["sloth", "lust", "all"]

# Immune target (a Greed verse vs SinDeath, a non-idolatry verse vs the calf...):
# a "No damage!" popup where the damage number would be, so it doesn't look
# like the verse glitched.
func _no_damage_popup(enemy):
	PopupText.spawn(enemy, tr("No damage!"), Color(0.85, 0.85, 0.85), Vector2(0, -100))

func _attack(verse, enemy, damage_scale: float, can_counter: bool):
	if instant_kill_against(verse, enemy):
		var hp_before = enemy.hp
		var msg = tr("Instant defeat!")
		if TurnManager.in_battle:
			TurnManager.show_message(msg + " " + tr("%s is defeated by %s") % [tr(enemy.display_name), VerseManager.ref_text(verse.ref)])
		_show_verse_message(msg)
		enemy.instant_defeat()
		print(verse.ref, ": instant defeat of ", enemy.display_name)
		return hp_before
	var base_damage = verse_damage_against(verse, enemy)
	if base_damage < 0:
		var msg = tr("No effect - it's %s type now!") % tr(type_name(enemy.enemy_type))
		var only = enemy.get("only_vs")
		if only != null and ONLY_VS_MESSAGES.has(only):
			msg = tr(ONLY_VS_MESSAGES[only])
		elif verse.get("set", "") == "sheet":
			var names = []
			for sin in verse.get("sins", {}):
				names.append(tr(sin.capitalize()))
			msg = tr("No effect - this verse only hurts %s-type enemies") % "/".join(names)
		if not TurnManager.in_battle:   # (in battle the title says it: no second copy)
			enemy.show_popup(msg, Color(0.75, 0.75, 0.75))
		_no_damage_popup(enemy)
		_show_verse_message(msg)
		if TurnManager.in_battle:
			TurnManager.show_message(msg)
		print(verse.ref, ": ", msg)
		return 0.0
	var damage = base_damage * damage_scale
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
	# Play the wings/dome animation once (a little see-through)
	guard_fx.visible = true
	guard_fx.modulate.a = guard_play_opacity
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
	if wisdom_rounds_left > 0:
		wisdom_rounds_left -= 1
		if wisdom_rounds_left == 0:
			wisdom = 0.0
			wisdom_changed.emit(wisdom)
		_update_wisdom_label()
	if zeal_rounds_left > 0:
		zeal_rounds_left -= 1
		if zeal_rounds_left == 0:
			zeal = 0.0
		_update_zeal_label()

func _update_guard_label():
	guard_label.visible = guard_rounds_left > 0
	guard_label.text = tr("Guard +%d%%  turn %d/%d") % [roundi(guard_reduction * 100), status_turn(guard_rounds_left, guard_rounds), guard_rounds]

# Which turn of the status you're on: 1/3 right after the verse, 3/3 in its
# last round (each battle round ends one; at 0 the status is gone)
func status_turn(left: int, total: int) -> int:
	return clampi(total - left + 1, 1, total)

# ---------------- Faith (attack up) ----------------

# +faith_step attack (stacking up to faith_max) and reset the duration.
# Outside a battle it doesn't count down.
func activate_faith(amount := -1.0):
	if amount < 0:
		amount = faith_step   # the built-in Faith verses: +50%
	var was_max = faith_bonus >= faith_max
	if faith_rounds_left > 0:
		faith_bonus = min(faith_bonus + amount, faith_max)
	else:
		faith_bonus = min(amount, faith_max)
	faith_rounds_left = faith_rounds
	_update_faith_label()
	print("Faith: attack +", int(faith_bonus * 100), "% for ", faith_rounds, " rounds")
	if faith_bonus >= faith_max and not was_max:
		_play_shofar()

func _update_faith_label():
	faith_label.visible = faith_rounds_left > 0
	faith_label.text = tr("Faith +%d%%  turn %d/%d") % [roundi(faith_bonus * 100), status_turn(faith_rounds_left, faith_rounds), faith_rounds]

# ---------------- Wisdom (evasion) ----------------

# +amount % wisdom (stacking up to wisdom_max) and reset the duration, like
# Faith. Outside a battle it doesn't count down.
func add_wisdom(amount: float):
	if wisdom_rounds_left > 0:
		wisdom = min(wisdom + amount, wisdom_max)
	else:
		wisdom = min(amount, wisdom_max)
	wisdom_rounds_left = wisdom_rounds
	_update_wisdom_label()
	wisdom_changed.emit(wisdom)
	print("Wisdom: ", int(wisdom), "% (evasion ", int(evasion_chance() * 100), "%) for ", wisdom_rounds, " rounds")

# The chance (0..1) to dodge an enemy hit: the wisdom %, at most evasion_max.
func evasion_chance() -> float:
	return min(wisdom, evasion_max) / 100.0

func _update_wisdom_label():
	if wisdom_label == null:
		return
	wisdom_label.visible = wisdom_rounds_left > 0 and wisdom > 0
	wisdom_label.text = tr("Wisdom %d%%  turn %d/%d") % [roundi(wisdom), status_turn(wisdom_rounds_left, wisdom_rounds), wisdom_rounds]

# An enemy attack / verse / line hitting you (enemy.gd): rolls against your
# evasion first. Returns the damage taken, or -1 if you dodged it.
# (Not for SinDeath's counter or other unavoidable damage: use take_damage.)
func enemy_hit(amount) -> float:
	var roll_ok = randf() < evasion_chance() if dodge_override < 0 else dodge_override >= 1.0
	if amount > 0 and roll_ok:
		dodges += 1
		PopupText.spawn(self, tr("Dodged!"), Color(0.6, 0.95, 1.0))
		print("Dodged! (wisdom ", int(wisdom), "%)")
		return -1.0
	return take_damage(amount)

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
	# One row right of the HP bar (the Items / Run buttons are above it, the
	# verse box below): "Faith +100%  turn 1/3   Guard +50%  turn 2/3 ..."
	# Hidden labels take no space.
	# It sits on its own layer 5 (above the speech bubbles, layer 4, under the
	# menus) so a bubble never hides it, and wraps onto a second line before
	# it reaches the enemy HP panel on the right (the verse box moves down).
	var box = HFlowContainer.new()
	box.name = "StatusRow"
	box.add_theme_constant_override("h_separation", 18)
	box.add_theme_constant_override("v_separation", 0)
	box.position = hp_bar.position + Vector2(hp_bar.size.x + 12, -1)
	var screen_w = get_viewport().get_visible_rect().size.x if is_inside_tree() else 1024.0
	box.custom_minimum_size.x = max(screen_w - box.position.x - STATUS_RIGHT_MARGIN, 200.0)
	status_row = box
	box.resized.connect(place_verse_panel)
	box.add_child(guard_label)
	faith_label = Label.new()
	faith_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.45))
	faith_label.add_theme_color_override("font_outline_color", Color.BLACK)
	faith_label.add_theme_constant_override("outline_size", 4)
	faith_label.visible = false
	box.add_child(faith_label)
	wisdom_label = Label.new()
	wisdom_label.add_theme_color_override("font_color", Color(0.65, 0.95, 0.85))
	wisdom_label.add_theme_color_override("font_outline_color", Color.BLACK)
	wisdom_label.add_theme_constant_override("outline_size", 4)
	wisdom_label.visible = false
	box.add_child(wisdom_label)
	zeal_label = Label.new()
	zeal_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.35))
	zeal_label.add_theme_color_override("font_outline_color", Color.BLACK)
	zeal_label.add_theme_constant_override("outline_size", 4)
	zeal_label.visible = false
	box.add_child(zeal_label)
	speed_label = Label.new()
	speed_label.add_theme_color_override("font_color", Color(0.5, 0.9, 1.0))
	speed_label.add_theme_color_override("font_outline_color", Color.BLACK)
	speed_label.add_theme_constant_override("outline_size", 4)
	speed_label.visible = false
	box.add_child(speed_label)
	var status_layer = CanvasLayer.new()
	status_layer.name = "StatusLayer"
	status_layer.layer = 5
	status_layer.add_child(box)
	add_child.call_deferred(status_layer)
	
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
	# ... or hovering just over the sheep, its shadow on them (as in the
	# reference animation: the dome's bottom about a third of its height
	# above the sheep's back, guard_shadow.gd)
	var body = preload("res://party_member.gd")._visible_body_rect(get_node_or_null("Sprite2D"), self)
	if guard_fx_hover and body.size != Vector2.ZERO:
		guard_fx.position.y = body.position.y - (GUARD_DOME_BOTTOM + guard_fx_hover_gap * GUARD_DOME_HEIGHT) * guard_fx_scale
	guard_fx.z_index = 5
	guard_fx.visible = false
	guard_fx.animation_finished.connect(_on_guard_fx_finished)
	add_child(guard_fx)
	guard_shadow = GuardShadow.new(guard_fx, [get_node_or_null("Sprite2D")])
	
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
# The HUD, laid out like the Unity version: the player's portrait in the
# top-left corner, Run (turn_manager.gd) beside it, the HP bar under it.
const HUD_HP_POS = Vector2(10, 72)
const HUD_HP_SIZE = Vector2(240, 24)
const HUD_PARTY_POS = Vector2(10, 102)   # the party's rows, under the HP bar
const PartyHud = preload("res://party_hud.gd")
var portrait: Control
var party_hud: Control
var status_row: Control

# ---------------- Low health (25% or less) ----------------
# The HP bar turns red, and in a battle the low-health sound (General/Sounds/
# "Low hp sfx.wav") loops on the SFX bus (the Settings SFX slider). The sound
# stops when you're healed above 25%, at 0 HP, out of battle (and when you
# leave the level - it belongs to the player), and while the pause menu /
# its Settings or a full-screen overlay (Idolatry Cam) is up; it starts
# again when they close. The red bar stays the whole time you're low.
const HP_COLOR = Color(0.2, 0.75, 0.25)
const LOW_HP_COLOR = Color(0.85, 0.12, 0.12)
const LOW_HP_RATIO = 0.25
const LOW_HP_SOUND = "res://General/Sounds/Low hp sfx.wav"
var hp_fill: StyleBoxFlat
var low_hp_player: AudioStreamPlayer

func _build_low_hp():
	low_hp_player = AudioStreamPlayer.new()
	low_hp_player.name = "LowHpSound"
	low_hp_player.bus = "SFX"
	if ResourceLoader.exists(LOW_HP_SOUND):
		low_hp_player.stream = load(LOW_HP_SOUND)
	# loops: start over when it ends, as long as it's still wanted
	low_hp_player.finished.connect(func():
		if low_hp_sound_wanted():
			low_hp_player.play())
	add_child.call_deferred(low_hp_player)

func is_low_hp() -> bool:
	return max_hp > 0 and hp <= max_hp * LOW_HP_RATIO

func low_hp_sound_wanted() -> bool:
	if not is_low_hp() or hp <= 0 or not TurnManager.in_battle:
		return false
	var menus = get_tree().get_first_node_in_group("menus") if is_inside_tree() else null
	if menus and (menus.is_main_menu_open() or menus.pause_menu.visible
			or (menus.get("sub_from_pause") and [menus.settings_menu, menus.remap_menu, menus.multiplayer_menu].any(func(m): return m != null and m.visible))):
		return false
	for o in get_tree().get_nodes_in_group("hud_hidden_overlay"):
		if is_instance_valid(o) and o.get("visible") != false:
			return false
	return true

func _update_low_hp():
	if hp_fill:
		var c = LOW_HP_COLOR if is_low_hp() else HP_COLOR
		if hp_fill.bg_color != c:
			hp_fill.bg_color = c
	if low_hp_player == null or not low_hp_player.is_inside_tree() or low_hp_player.stream == null:
		return
	var want = low_hp_sound_wanted()
	if want and not low_hp_player.playing:
		low_hp_player.play()
	elif not want and low_hp_player.playing:
		low_hp_player.stop()

func _layout_hud():
	var hud = hp_bar.get_parent()
	portrait = TurnManager.make_portrait(TurnManager.portrait_of(get_node_or_null("Sprite2D"), 3))
	portrait.name = "PlayerPortrait"
	portrait.position = Vector2(10, 10)
	hud.add_child.call_deferred(portrait)
	hp_bar.position = HUD_HP_POS
	hp_bar.size = HUD_HP_SIZE
	var fill = StyleBoxFlat.new()
	fill.bg_color = HP_COLOR
	fill.set_corner_radius_all(3)
	hp_bar.add_theme_stylebox_override("fill", fill)
	hp_fill = fill
	_build_low_hp()
	# the Zeal countdown goes beside Run, out of the verse box's way
	var timer_label = hud.get_node_or_null("TimerLabel")
	if timer_label:
		timer_label.position = Vector2(206, 18)
	# The party's portraits and HP under yours (party_hud.gd)
	party_hud = PartyHud.new()
	party_hud.position = HUD_PARTY_POS
	party_hud.resized.connect(place_verse_panel)
	hud.add_child.call_deferred(party_hud)

# The verse box (Tab) sits under the HP bar - and under the party's rows and
# a second line of the status row, if there are any.
func place_verse_panel():
	if verse_panel == null:
		return
	var y = VERSE_PANEL_POS.y
	if is_instance_valid(status_row):
		y += max(status_row.size.y - STATUS_LINE_H, 0.0)
	if is_instance_valid(party_hud) and party_hud.used_height() > 0.0:
		y = max(y, HUD_PARTY_POS.y + party_hud.used_height() + 6.0)
	verse_panel.position.y = y

# The verse box (Tab): a compact panel in the top-left, under the HP bar, with
# Index / Verse / Effects columns, so it never covers the characters (they
# stand in the lower middle of the screen).
const VERSE_PANEL_POS = Vector2(10, 102)
const STATUS_RIGHT_MARGIN = 300.0   # keep the status row clear of the enemy HP panel
const STATUS_LINE_H = 26.0          # one line of the status row
const VERSE_PANEL_SIZE = Vector2(620, 184)
var cycle_label: Label

func _build_verse_panel():
	var layer = CanvasLayer.new()
	layer.name = "VerseListLayer"
	add_child(layer)
	verse_panel = Panel.new()
	verse_panel.name = "VersePanel"
	verse_panel.position = VERSE_PANEL_POS
	verse_panel.size = VERSE_PANEL_SIZE
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.16, 0.9)
	style.border_color = Color(0.45, 0.45, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	verse_panel.add_theme_stylebox_override("panel", style)
	layer.add_child(verse_panel)
	var w = VERSE_PANEL_SIZE.x
	
	var title = Label.new()
	title.name = "Title"
	title.text = "Verses" if GameSettings.touch_prompts() else "Verses (Tab to close)"
	title.position = Vector2(8, 3)
	title.add_theme_font_size_override("font_size", 14)
	verse_panel.add_child(title)
	cycle_label = Label.new()
	cycle_label.name = "CycleLabel"
	cycle_label.position = Vector2(w * 0.38, 3)
	cycle_label.add_theme_font_size_override("font_size", 13)
	cycle_label.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	verse_panel.add_child(cycle_label)
	
	var show_all = Button.new()
	show_all.name = "ShowAllButton"
	show_all.text = "Show all"
	show_all.position = Vector2(w - 86, 3)
	show_all.size = Vector2(78, 22)
	show_all.add_theme_font_size_override("font_size", 12)
	show_all.item_rect_changed.connect(_fit_show_all_button)   # stays inside the panel in every language
	show_all.focus_mode = Control.FOCUS_NONE   # so Enter/Space don't press it by accident
	show_all.pressed.connect(_on_show_all_pressed)
	verse_panel.add_child(show_all)
	
	# The filter buttons side by side
	var row = HBoxContainer.new()
	row.name = "FilterRow"
	row.position = Vector2(8, 28)
	row.size = Vector2(w - 16, 24)
	row.add_theme_constant_override("separation", 6)
	verse_panel.add_child(row)
	for group in FILTER_GROUPS:
		var button = Button.new()
		button.name = group + "Button"
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 12)
		# A long label (e.g. Polish) is cut with "…" instead of pushing the row past the panel edge
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.custom_minimum_size.x = 40
		button.pressed.connect(_on_group_pressed.bind(group))
		row.add_child(button)
	
	# Column headings
	var heads = HBoxContainer.new()
	heads.name = "Columns"
	heads.position = Vector2(8, 55)
	heads.size = Vector2(w - 28, 16)
	verse_panel.add_child(heads)
	for c in [["Index", 2], ["Verse", 6], ["Effects", 3]]:
		var h = Label.new()
		h.text = c[0]
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.size_flags_stretch_ratio = c[1]
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_theme_font_size_override("font_size", 12)
		h.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
		heads.add_child(h)
	
	verse_text = RichTextLabel.new()
	verse_text.name = "VerseText"
	verse_text.bbcode_enabled = true   # allows colors in the verse list
	verse_text.position = Vector2(6, 73)
	verse_text.size = Vector2(w - 12, VERSE_PANEL_SIZE.y - 79)
	verse_text.add_theme_font_size_override("normal_font_size", 13)
	verse_text.add_theme_font_size_override("bold_font_size", 13)
	verse_text.add_theme_constant_override("table_h_separation", 6)
	verse_text.add_theme_constant_override("table_v_separation", 3)
	verse_panel.add_child(verse_text)
	_update_filter_buttons()

# ---------------- Language ----------------

# A verse's text in the current language (English if that language has none)
func verse_body(v) -> String:
	if language != "en" and str(v.get(language, "")) != "":
		return v[language]
	return v.en

# Text that's built in code doesn't switch by itself: redraw it
func _on_language_changed(_new_language):
	_update_verse_text()
	_update_filter_buttons()
	_update_guard_label()
	_update_faith_label()
	_update_wisdom_label()
	_update_zeal_label()
	verse_input.placeholder_text = default_placeholder()

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
		_show_verse_message(tr("Listening... release Mic to recite") if GameSettings.touch_prompts() else tr("Listening... release Shift to recite"))

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


# ---------------- Baby Mode (baby_mode.gd) ----------------
# No verse box, verse list or typing while it's on; back as before when it's off.
var _baby_ui = false
func _apply_baby_mode_ui():
	var on = GameSettings.baby_mode
	if on == _baby_ui:
		if on and is_instance_valid(verse_input) and verse_input.visible:
			verse_input.visible = false   # (something showed it again)
		return
	_baby_ui = on
	if is_instance_valid(verse_input):
		if on and verse_input.has_focus():
			close_typing()
		verse_input.visible = not on
	if on and verse_panel:
		verse_panel.visible = false
