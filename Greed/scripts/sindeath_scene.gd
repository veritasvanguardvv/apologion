extends Node2D
# THE SINDEATH SCENE (end of the Greed level) - Greed/SinDeathScene.tscn
# -------------------------------------------------------------------
#  1. The Sheep (the player) walks into the Trigger: the camera slowly pans
#     to the Golden Calf and the idol speaks.
#  2. Mammon (Greed/MammonGreedBoss.tscn, the old Greedwraith Boss art)
#     appears and talks.
#  3. "Idolatry Cam": a replay of every money / gold pickup of this run
#     (play_of_the_game.gd). Skipped if you picked up none.
#  4. Three answers; each branch ends with "Prepare to die!".
#  5. Mammon becomes SinDeath -> battle against SinDeath + the Golden Calf.
#     Only 'Dmg to SinDeath boss' verses hurt SinDeath, only 'Dmg to Idol'
#     verses hurt the calf (enemy.gd only_vs). The calf never attacks and
#     the battle is won when SinDeath is beaten.
#  6. Victory: the Sheep's answer, then you RAM the calf (X) -> Level Complete.
# Dying in the fight: back at the Greed checkpoint; walking in again skips
# the talk (SaveManager.greed_sindeath_seen).
#
# Advance the talk with Enter / Space / a click / a tap. All lines are below
# (English = the translation key in General/translations/strings.csv).

const PopupText = preload("res://popup_text.gd")
const Battle3D = preload("res://battle_3d.gd")   # the 3D presentation of the fight (Settings > 3D boss battles)

# ---------------- THE DIALOGUE ----------------
# who: "idol", "sheep" or "mammon". ref: shown as the bubble title.
# hurt_pct: this line hurts the player by that % of max HP.
const INTRO = [
	{ "who": "idol", "text": "Bow down and worship me." },
	{ "who": "sheep", "text": "Never!" },
	{ "who": "idol", "text": "Ha! Sure, you have not bent your knees, but you’ve already bent your heart." },
	{ "who": "sheep", "text": "Idols can’t speak! You’re a liar, like your father!" },
]
const MAMMON_TALK = [
	{ "who": "mammon", "text": "You’re right about one thing. I am Mammon, the spirit of greed." },
	{ "who": "mammon", "text": "But I am not lying." },
	{ "who": "mammon", "text": "I’ve seen you every time you chased after easy money…" },
	{ "who": "mammon", "text": "Every time you tried to hoard gold…" },
	{ "who": "mammon", "text": "Don’t lie to yourself." },
]
const CHOICES = [
	"God doesn’t ask for perfection.",
	"God will forgive me.",
	"…",
]
const ANSWERS = [
	[   # 1
		{ "who": "sheep", "text": "God doesn’t ask for perfection." },
		{ "who": "mammon", "text": "It is written, “You must be perfect, as God is perfect,” and “The wages of sin is death.”" },
		{ "who": "mammon", "text": "Prepare to die!" },
	],
	[   # 2
		{ "who": "sheep", "text": "God will forgive me. I believe in Him." },
		{ "who": "mammon", "text": "Even demons believe in God.", "ref": "James 2:19", "hurt_pct": 25 },
		{ "who": "sheep", "text": "No, I meant I believe in the cross." },
		{ "who": "mammon", "text": "But do you truly believe?" },
		{ "who": "mammon", "text": "It is written, “Everyone who is born of God does not sin,” and “The wages of sin is death.”" },
		{ "who": "mammon", "text": "Prepare to die!" },
	],
	[   # 3 (silence)
		{ "who": "mammon", "text": "It is written, “Everyone who is born of God does not sin,” and “The wages of sin is death.”" },
		{ "who": "mammon", "text": "Prepare to die!" },
	],
]
const RETRY = [ { "who": "mammon", "text": "Prepare to die!" } ]
const VICTORY = [
	{ "who": "sheep", "text": "It’s true, my heart strayed from serving God, and I can never be truly good on my own strength." },
	{ "who": "sheep", "text": "But the Lamb of God is my life! He took my death sentence so that I can walk free, and no one can ever separate me from His love!" },
	{ "who": "sheep", "text": "I am clothed in His wool— when the Father sees me, He only sees His righteousness, not mine!" },
	{ "who": "sheep", "text": "Now, time to destroy this idol…" },
]

# ---------------- THE COUNTER (in the battle) ----------------
# Reciting Ezekiel 36:26-27 (any of its three phrases) at the calf: SinDeath
# slides over to cover it and counters. Answer with 2 Corinthians 1:20 and
# the idol drops to 0 HP at once. James 1:5 / Proverbs 2:6 (or 100% Wisdom)
# put 2 Cor 1:20 in your verse box - press Enter to recite it. Any other verse:
# the counter hits you for counter_damage_mult x SinDeath's attack (it can't be
# dodged - it's a counter, not an attack; Guard still reduces it).
# Only YOUR verses (typed or spoken) trigger it, not phone players'.
const EZEKIEL_REFS = ["Ezekiel 36:26a", "Ezekiel 36:26b", "Ezekiel 36:27"]
const ANSWER_REF = "2 Corinthians 1:20"
const WISDOM_REFS = ["James 1:5", "Proverbs 2:6"]
const COUNTER_TEXT = "God was talking to a different people at a different time. You can't just claim that verse for yourself."
@export var counter_damage_mult = 3.0
@export var slide_time = 0.7        # SinDeath sliding over the calf (seconds)
@export var counter_bubble_offset = Vector2(-300, -230)   # the counter bubble's spot, from SinDeath's feet
var bubble_home_offset = Vector2.ZERO

@export var barrier_path: NodePath = "Interactive/GoldenCalf"
@export var pan_time = 2.4          # the slow pan to the idol (seconds)
@export var zoom_in = 1.25          # camera zoom on the idol (x the normal zoom)

@onready var trigger: Area2D = $Trigger
@onready var mammon = $Mammon
@onready var sindeath = $SinDeath
@onready var idol = $Idol

signal advanced
signal chosen(index: int)

var state = "idle"   # idle, talk, choice, battle, after, ram, done (Baby Mode: baby)
var waiting = false
var wait_since = 0
var player
var barrier
var camera: Camera2D
var bubbles = {}     # who -> SpeechBubble
var hint_layer: CanvasLayer
var hint: Label
var choice_layer: CanvasLayer
var counter_state = ""   # "" (none yet / over), "sliding", "waiting", "done" (idol at 0)
var sindeath_home: Vector2
var battle_3d = null     # battle_3d.gd while the fight is shown in 3D
var counters_shown = 0   # (counted for the tests)
var counter_hits = 0
var autofills = 0


func _ready():
	var level = owner if owner else get_tree().current_scene
	barrier = level.get_node_or_null(barrier_path) if level else null
	if barrier:
		barrier.blocked_message = "Defeat SinDeath first!"
		var calf_sprite = barrier.get_node_or_null("Sprite")
		if calf_sprite:
			calf_sprite.visible = false   # the Idol enemy below draws the calf
		barrier.broken_by_ram.connect(_on_calf_smashed)
	_build_hint()
	if not _boss_alive():
		# SinDeath already beaten (e.g. reloaded): just ram the calf
		state = "ram"
		_crack_look()
		return
	trigger.body_entered.connect(_on_trigger)


func _boss_alive() -> bool:
	return is_instance_valid(sindeath) and not sindeath.is_queued_for_deletion()


func _exit_tree():
	TurnManager.encounters_paused = false
	TurnManager.no_escape = false
	if is_instance_valid(player) and player.get("verse_interceptor") != null:
		player.verse_interceptor = Callable()


# ---------------- Input: advance the talk ----------------

func _input(event):
	if not waiting:
		return
	var go = false
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		go = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		go = true
	elif event is InputEventScreenTouch and event.pressed:
		go = true
	if go and Time.get_ticks_msec() - wait_since > 250:
		get_viewport().set_input_as_handled()
		# the first press finishes a line that's still typing, the next goes on
		if not finish_typing():
			advance()


# Finishes any boss line that's still typing. True if one was.
func finish_typing() -> bool:
	var any = false
	for b in bubbles.values():
		if is_instance_valid(b) and b.is_typing():
			b.finish_typing()
			any = true
	wait_since = Time.get_ticks_msec()
	return any


# Next line (also used by the tests)
func advance():
	if waiting:
		waiting = false
		advanced.emit()


func _wait():
	waiting = true
	wait_since = Time.get_ticks_msec()
	hint.visible = true
	await advanced
	hint.visible = false


# ---------------- The scene ----------------

func _on_trigger(body):
	if state != "idle" or not body.is_in_group("player") or TurnManager.in_battle:
		return
	player = body
	state = "talk"
	_run()


func _run():
	TurnManager.encounters_paused = true
	_lock(true)
	_set_recording(false)
	var retry = SaveManager.greed_sindeath_seen
	await _pan(_idol_view(), zoom_in, pan_time)
	# Dialogue / Idolatry Cam flashback / answer choice — also in Baby Mode.
	# (Baby Mode still skips the turn-based / 3D battle; rams come after.)
	if retry:
		await _mammon_appears()
		await _lines(RETRY)
	else:
		await _lines(INTRO)
		await _mammon_appears()
		await _lines(MAMMON_TALK)
		var recorder = get_tree().get_first_node_in_group("play_recorder")
		if recorder and recorder.has_clips():
			_hide_bubbles()
			await recorder.play(self)
		var pick = await _choose()
		await _lines(ANSWERS[pick])
		SaveManager.greed_sindeath_seen = true
	_hide_bubbles()
	if GameSettings.baby_mode:
		await _transform()
		await _pan(_battle_view(), 1.0, 1.0)
		_end_camera()
		_start_baby_fight()
		return
	if GameSettings.boss_battles_3d:
		await _begin_3d()
	await _transform()
	if battle_3d == null:
		await _pan(_battle_view(), 1.0, 1.0)
	_end_camera()
	_lock(false)
	_start_battle()


func _start_battle():
	state = "battle"
	TurnManager.no_escape = true
	TurnManager.battle_ended.connect(_on_battle_ended, CONNECT_ONE_SHOT)
	idol.awaken()
	sindeath_home = sindeath.position
	bubble_home_offset = sindeath.bubble.head_offset
	counter_state = ""
	if is_instance_valid(player):
		player.verse_interceptor = _intercept_verse
		if not player.wisdom_changed.is_connected(_on_wisdom_changed):
			player.wisdom_changed.connect(_on_wisdom_changed)
	TurnManager.start_battle([sindeath, idol])


# ---------------- The counter ----------------

func _idol_standing() -> bool:
	return is_instance_valid(idol) and not idol.is_cracked and idol.hp > 0

# Called by the player for every verse they recite in this battle
# (character_body_2d.gd verse_interceptor). "pre": true = skip the verse cycle
# check; "post": what to do with the verse (null = the normal effects).
func _intercept_verse(phase: String, verse):
	var active = state == "battle" and _idol_standing() and _boss_alive()
	if phase == "pre":
		# The counter's answers can always be recited (even if used this cycle)
		return active and counter_state in ["sliding", "waiting"] and (verse.ref == ANSWER_REF or verse.ref in WISDOM_REFS)
	if not active:
		return null
	if counter_state == "":
		if verse.ref in EZEKIEL_REFS:
			_start_counter()
			return {"effects": false, "end_turn": false}   # SinDeath covers the calf: no hit; answer now
		return null
	if counter_state in ["sliding", "waiting"]:
		if verse.ref == ANSWER_REF:
			_counter_answered()
			return {"effects": false, "end_turn": true}
		if verse.ref in WISDOM_REFS:
			_autofill_answer()
			return {"effects": true, "end_turn": false}    # its heal / wisdom still happen
		_counter_wins()
		return {"effects": false, "end_turn": true}
	return null

func _start_counter():
	counter_state = "sliding"
	counters_shown += 1
	TurnManager.show_message(tr("SinDeath covers the Idol!"))
	var tw = create_tween()
	tw.tween_property(sindeath, "position:x", idol.position.x, slide_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished
	if counter_state != "sliding":
		return   # already answered while it slid
	counter_state = "waiting"
	# (its usual bubble spot is above its tall HP bar, off the top of the
	# screen under the enemy list: speak from beside its heads instead)
	sindeath.bubble.head_offset = counter_bubble_offset
	sindeath.bubble.say(tr("SinDeath counters!"), tr(COUNTER_TEXT), true, 0.0)   # the enemy counter style ("!")
	sindeath.bubble.start_typing()
	if is_instance_valid(player) and player.wisdom >= 100.0:
		_autofill_answer()   # full Wisdom: you already know the answer
	else:
		TurnManager.show_message(tr("Answer SinDeath with the right verse!"))

func _on_wisdom_changed(value):
	if value >= 100.0 and counter_state == "waiting":
		_autofill_answer()

# Puts 2 Corinthians 1:20 in the verse box: Enter recites it
func _autofill_answer():
	if not is_instance_valid(player):
		return
	var v = player.get_verse(ANSWER_REF)
	if v == null:
		push_warning("SinDeath counter: %s isn't in data/verses.json" % ANSWER_REF)
		return
	autofills += 1
	var text = player.verse_body(v)
	player.verse_input.text = text
	player.verse_input.caret_column = text.length()
	player.verse_input.grab_focus.call_deferred()
	TurnManager.show_message((tr("Wisdom! %s is in your verse box - tap Return to recite it") if GameSettings.touch_prompts() else tr("Wisdom! %s is in your verse box - press Enter")) % VerseManager.ref_text(ANSWER_REF))

func _counter_answered():
	counter_state = "done"
	sindeath.bubble.hide_bubble()
	idol.knock_out()   # "The idol is cracked!" (the ram is still needed after the battle)
	_crack_look()
	TurnManager.show_message(tr("God's promises are “Yes” in Christ!"))
	_shake()
	_slide_back()

func _counter_wins():
	counter_hits += 1
	counter_state = ""   # it can be tried again
	sindeath.bubble.hide_bubble()
	var damage = sindeath.attack_damage * counter_damage_mult
	var dealt = player.take_damage(damage) if is_instance_valid(player) else 0.0   # (not dodgeable)
	if is_instance_valid(player):
		PopupText.spawn(player, "-" + str(snapped(dealt, 0.1)), Color(1, 0.35, 0.3))
	TurnManager.show_message(tr("SinDeath's counter hits! -%s HP") % String.num(snapped(dealt, 0.1)))
	_shake()
	_slide_back()

func _slide_back():
	if not _boss_alive():
		return
	sindeath.bubble.head_offset = bubble_home_offset
	await get_tree().create_timer(0.5).timeout
	if _boss_alive():
		create_tween().tween_property(sindeath, "position:x", sindeath_home.x, slide_time).set_trans(Tween.TRANS_QUAD)


func _lines(lines: Array):
	for line in lines:
		await _say_line(line)


func _say_line(line: Dictionary):
	var who = line.who
	var title = ""
	if line.has("ref"):
		title = VerseManager.ref_text(line.ref)
	elif who == "mammon":
		title = tr("Mammon")
	_hide_bubbles()
	_bubble(who).say(title, tr(line.text), false, 0.0)
	if who != "sheep":
		_bubble(who).start_typing()   # Mammon / the idol: typewriter + boss voice
	if line.has("hurt_pct") and is_instance_valid(player):
		var amount = max(1.0, player.max_hp * line.hurt_pct / 100.0)
		amount = min(amount, player.hp - 1.0)   # a talk can't kill you
		if amount > 0:
			player.take_damage(amount)
			PopupText.spawn(player, "-" + str(int(amount)), Color(1, 0.35, 0.3))
			_shake()
	await _wait()


func _bubble(who: String):
	if who == "sheep" and is_instance_valid(player) and player.get("bubble"):
		return player.bubble
	if bubbles.has(who):
		return bubbles[who]
	var b = preload("res://speech_bubble.gd").new()
	b.max_width = 420.0
	if who == "idol":
		b.target = idol
		b.head_offset = Vector2(20, -60)
	else:
		b.target = mammon
		b.head_offset = Vector2(0, -150)
	add_child(b)
	bubbles[who] = b
	return b


func _hide_bubbles():
	for b in bubbles.values():
		b.hide_bubble()
	if is_instance_valid(player) and player.get("bubble"):
		player.bubble.hide_bubble()


func _mammon_appears():
	var s = mammon.get_node("Sprite")
	mammon.visible = true
	s.offset = Vector2(-32, -8)
	s.play("appear")
	s.modulate.a = 0.0
	s.create_tween().tween_property(s, "modulate:a", 1.0, 0.4)
	await s.animation_finished
	s.offset = Vector2(-32, -40)
	s.play("idle")
	await get_tree().create_timer(0.3).timeout


# Mammon vanishes, SinDeath manifests
func _transform():
	var s = mammon.get_node("Sprite")
	s.offset = Vector2(-32, -24)
	s.play("vanish")
	await s.animation_finished
	mammon.visible = false
	sindeath.awaken()
	var sd = sindeath.get_node("Sprite")
	sindeath.hp_bar.visible = false
	sd.play("manifest")
	_shake()
	await sd.animation_finished
	sd.play("idle")
	sindeath._show_battle_ui(true)   # (no head bar for SinDeath: enemy.gd shows_head_bar)
	await get_tree().create_timer(0.4).timeout


func _choose() -> int:
	state = "choice"
	choice_layer = CanvasLayer.new()
	choice_layer.layer = 30
	add_child(choice_layer)
	var panel = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.03, 0.92)
	sb.border_color = Color(1, 0.8, 0.3)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	panel.anchor_left = 0.2
	panel.anchor_right = 0.8
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_top = -270
	panel.offset_bottom = -40
	choice_layer.add_child(panel)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title = Label.new()
	title.text = "Choose your answer"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.35))
	box.add_child(title)
	var first: Button
	for i in CHOICES.size():
		var b = Button.new()
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.text = "%d- %s" % [i + 1, tr(CHOICES[i])]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 46)   # big enough to tap on a phone
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(choose.bind(i))
		box.add_child(b)
		if first == null:
			first = b
	first.grab_focus.call_deferred()
	var pick = await chosen
	choice_layer.queue_free()
	state = "talk"
	return pick


# Pick an answer (buttons, keys 1-3, the tests)
func choose(index: int):
	if state == "choice":
		chosen.emit(index)


func _unhandled_input(event):
	if state == "choice" and event is InputEventKey and event.pressed and not event.echo:
		var n = event.keycode - KEY_1
		if n >= 0 and n < CHOICES.size():
			get_viewport().set_input_as_handled()
			choose(n)


func _on_battle_ended():
	TurnManager.no_escape = false
	if is_instance_valid(player):
		player.verse_interceptor = Callable()
		if player.wisdom_changed.is_connected(_on_wisdom_changed):
			player.wisdom_changed.disconnect(_on_wisdom_changed)
	if counter_state in ["sliding", "waiting"]:
		counter_state = ""
	if _boss_alive():
		# shouldn't happen (no running, and losing reloads the level)
		# - except Baby Mode switched on in the middle of the fight
		state = "idle"
		TurnManager.encounters_paused = false
		idol.make_dormant()
		if battle_3d:
			battle_3d.finish()
			battle_3d = null
		if GameSettings.baby_mode:
			_start_baby_fight()
		return
	state = "after"
	idol.make_dormant()   # walking up to it mustn't start a new battle
	_lock(true)
	await get_tree().create_timer(1.6).timeout   # let "Victory!" show
	if battle_3d:
		await get_tree().create_timer(1.0).timeout   # (the victory camera)
		await battle_3d.finish()   # back to the 2D level for the talk and the ram
		battle_3d = null
	await _lines(VICTORY)
	_hide_bubbles()
	_lock(false)
	TurnManager.encounters_paused = false
	_set_recording(true)
	state = "ram"
	_show_ram_hint()


# ---------------- Baby Mode (baby_mode.gd) ----------------
# Talk / flashback / choice run in _run() like normal. After that: no turn
# battle — SinDeath manifests, then you ram it (ENEMY_HITS) and the idol
# (BabyMode.IDOL_HITS); the last ram on the idol smashes the Golden Calf and
# wins the level. Each ram reads a verse out loud (not pots/herbs).

var _normal_hp = []   # [SinDeath's, the idol's] max HP outside Baby Mode

func _start_baby_fight():
	_lock(false)
	_set_recording(true)
	TurnManager.encounters_paused = false
	state = "baby"
	if _normal_hp.is_empty():
		_normal_hp = [sindeath.max_hp if _boss_alive() else 666, idol.max_hp]
	idol.awaken()
	idol.is_cracked = false
	idol.max_hp = BabyMode.IDOL_HITS
	idol.hp = BabyMode.IDOL_HITS
	if barrier:
		idol.set_meta("baby_ram_body", barrier)   # the idol sits in the solid calf: touching the calf rams it
		barrier.set_meta("baby_shields", idol)    # a dash into the calf rams the idol, not the calf (greed_barrier.gd)
	if _boss_alive():
		sindeath.awaken()
		sindeath.max_hp = BabyMode.ENEMY_HITS   # 2 rams, like every other enemy
		sindeath.hp = BabyMode.ENEMY_HITS
		sindeath.set_meta("baby_rams", 0)
	if not idol.cracked.is_connected(_on_baby_idol_cracked):
		idol.cracked.connect(_on_baby_idol_cracked, CONNECT_ONE_SHOT)
	TurnManager.show_enemy_panel([sindeath, idol] if _boss_alive() else [idol])
	PopupText.spawn(idol, tr("Ram the idol!"), Color(1, 0.85, 0.3), Vector2(0, -110), 3.0)
	hint.text = "Run into SinDeath and the idol!"
	hint.visible = true


func _on_baby_idol_cracked():
	if state != "baby":
		return
	state = "baby_end"
	hint.visible = false
	if _boss_alive():
		sindeath.instant_defeat("Rammed!")   # (jumped over it: it goes too)
	await get_tree().create_timer(0.6).timeout   # let "0 / 3" show
	TurnManager.hide_enemy_panel()
	if not baby_victory_done:
		await _baby_victory()   # SinDeath went with the idol: the talk before the smash
	if barrier and not barrier.broken:
		barrier.on_rammed(player)   # smashes the calf: _on_calf_smashed, the level is won


# Baby Mode: the sheep's victory talk ("I am clothed in His wool...") plays too,
# as soon as SinDeath is beaten (or before the calf smashes if it never was).
var baby_victory_done = false

func _baby_victory():
	baby_victory_done = true
	var back_to = state
	state = "baby_talk"
	hint.visible = false
	_lock(true)
	await get_tree().create_timer(0.8).timeout
	hint.text = "Tap to continue" if GameSettings.touch_prompts() else "Click or press Enter to continue"
	await _lines(VICTORY)
	_hide_bubbles()
	_lock(false)
	state = back_to
	if state == "baby":
		hint.text = "Ram the idol!"
		hint.visible = true
		if is_instance_valid(idol):
			PopupText.spawn(idol, tr("Ram the idol!"), Color(1, 0.85, 0.3), Vector2(0, -110), 3.0)


# Baby Mode switched off during the baby fight: the normal battle; switched
# on after SinDeath was beaten: running into the calf smashes it.
func _process(_delta):
	if state == "baby" and GameSettings.baby_mode and not _boss_alive() and not baby_victory_done:
		_baby_victory()
	if state == "baby" and not GameSettings.baby_mode and not TurnManager.in_battle and _boss_alive():
		hint.visible = false
		TurnManager.hide_enemy_panel()
		sindeath.max_hp = _normal_hp[0]
		sindeath.hp = _normal_hp[0]
		idol.max_hp = _normal_hp[1]
		idol.hp = _normal_hp[1]
		_normal_hp = []
		if idol.cracked.is_connected(_on_baby_idol_cracked):
			idol.cracked.disconnect(_on_baby_idol_cracked)
		_start_battle()
	elif state == "baby" and not GameSettings.baby_mode and not _boss_alive():
		# (only the idol left: ram it the normal way)
		hint.visible = false
		TurnManager.hide_enemy_panel()
		if idol.cracked.is_connected(_on_baby_idol_cracked):
			idol.cracked.disconnect(_on_baby_idol_cracked)
		idol.make_dormant()
		state = "ram"
		_show_ram_hint()
	if barrier and state == "ram":
		var want = GameSettings.baby_mode
		if want != barrier.is_in_group("baby_rammables"):
			if want:
				barrier.add_to_group("baby_rammables")
			else:
				barrier.remove_from_group("baby_rammables")


func _show_ram_hint():
	if is_instance_valid(idol):
		PopupText.spawn(idol, tr("Ram the idol!"), Color(1, 0.85, 0.3), Vector2(0, -110), 3.0)
	hint.text = "Ram the idol!"
	hint.visible = true


func _on_calf_smashed():
	state = "done"
	hint.visible = false
	hint.text = "Tap to continue" if GameSettings.touch_prompts() else "Click or press Enter to continue"
	if is_instance_valid(idol):
		_shatter(idol.global_position)
		idol.visible = false


func _crack_look():
	if is_instance_valid(idol):
		idol.get_node("Sprite").modulate = Color(0.8, 0.7, 0.5)


# Gold shards flying off the calf
func _shatter(at: Vector2):
	for i in 18:
		var p = Polygon2D.new()
		var r = randf_range(6, 16)
		p.polygon = PackedVector2Array([Vector2(-r, -r * 0.6), Vector2(r, -r * 0.3), Vector2(r * 0.2, r)])
		p.color = Color(1, randf_range(0.7, 0.9), randf_range(0.2, 0.4))
		p.global_position = at + Vector2(randf_range(-60, 60), randf_range(-30, 30))
		p.z_index = 5
		get_parent().add_child(p)
		var dir = Vector2(randf_range(-1, 1), randf_range(-1.4, -0.2)).normalized() * randf_range(120, 320)
		var t = p.create_tween().set_parallel(true)
		t.tween_property(p, "global_position", p.global_position + dir + Vector2(0, 160), 1.1).set_ease(Tween.EASE_OUT)
		t.tween_property(p, "rotation", randf_range(-8, 8), 1.1)
		t.tween_property(p, "modulate:a", 0.0, 0.5).set_delay(0.6)
		t.chain().tween_callback(p.queue_free)


# ---------------- Helpers ----------------

func _lock(on: bool):
	if is_instance_valid(player):
		player.cutscene_lock = on
		if on and "velocity" in player:
			player.velocity.x = 0


func _set_recording(on: bool):
	var recorder = get_tree().get_first_node_in_group("play_recorder")
	if recorder:
		recorder.recording = on


func _player_camera() -> Camera2D:
	return player.get_node_or_null("Camera2D") if is_instance_valid(player) else null


func _idol_view() -> Vector2:
	return idol.global_position + Vector2(-140, -90)


func _battle_view() -> Vector2:
	return (player.global_position + idol.global_position) / 2.0 + Vector2(0, -110)


# Slowly moves a cut-scene camera (same limits as the player's) to `to`
func _pan(to: Vector2, zoom_factor: float, time: float):
	var pc = _player_camera()
	if camera == null:
		camera = Camera2D.new()
		camera.name = "CutsceneCamera"
		add_child(camera)
		if pc:
			camera.limit_left = pc.limit_left
			camera.limit_right = pc.limit_right
			camera.limit_top = pc.limit_top
			camera.limit_bottom = pc.limit_bottom
			camera.zoom = pc.zoom
			camera.global_position = pc.get_screen_center_position()
		else:
			camera.global_position = player.global_position
		camera.make_current()
	# don't aim past the limits (the tween would look stuck)
	var base_zoom = pc.zoom if pc else Vector2.ONE
	var z = base_zoom * zoom_factor
	var half = get_viewport_rect().size / z / 2.0
	to.x = clamp(to.x, camera.limit_left + half.x, max(camera.limit_left + half.x, camera.limit_right - half.x))
	to.y = clamp(to.y, camera.limit_top + half.y, max(camera.limit_top + half.y, camera.limit_bottom - half.y))
	var t = camera.create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(camera, "global_position", to, time)
	t.tween_property(camera, "zoom", z, time)
	await t.finished


func _end_camera():
	var pc = _player_camera()
	if pc:
		pc.make_current()
	if camera:
		camera.queue_free()
		camera = null


# The fight in 3D (battle_3d.gd): fades in before SinDeath manifests
func _begin_3d():
	battle_3d = Battle3D.new()
	battle_3d.name = "Battle3D"
	add_child(battle_3d)
	await battle_3d.begin(self, player)

func _shake():
	if battle_3d:
		battle_3d.shake(0.14, 0.3)
	var cam = camera if camera else _player_camera()
	if cam == null:
		return
	var t = cam.create_tween()
	for i in 6:
		t.tween_property(cam, "offset", Vector2(randf_range(-8, 8), randf_range(-6, 6)), 0.04)
	t.tween_property(cam, "offset", Vector2.ZERO, 0.05)


func _build_hint():
	hint_layer = CanvasLayer.new()
	hint_layer.layer = 5
	add_child(hint_layer)
	hint = Label.new()
	hint.text = "Tap to continue" if GameSettings.touch_prompts() else "Click or press Enter to continue"
	hint.anchor_left = 0.0
	hint.anchor_right = 1.0
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_top = -92
	hint.offset_bottom = -62
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 20)
	hint.add_theme_color_override("font_color", Color(1, 0.92, 0.7))
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.add_theme_constant_override("outline_size", 6)
	hint.visible = false
	hint_layer.add_child(hint)
