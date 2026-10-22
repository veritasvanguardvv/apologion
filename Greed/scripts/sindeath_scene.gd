extends Node2D
# THE SINDEATH SCENE (end of the Greed level) - Greed/SinDeathScene.tscn
# -------------------------------------------------------------------
#  1. The Sheep (the player) walks into the Trigger: the camera slowly pans
#     to the Golden Calf and the idol speaks.
#  2. Mammon (Greed/MammonGreedBoss.tscn, the old Greedwraith Boss art)
#     appears and talks.
#  3. "Play of the Game": a replay of every money / gold pickup of this run
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
# (English = the translation key in translations/strings.csv).

const PopupText = preload("res://popup_text.gd")

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

@export var barrier_path: NodePath = "Interactive/GoldenCalf"
@export var pan_time = 2.4          # the slow pan to the idol (seconds)
@export var zoom_in = 1.25          # camera zoom on the idol (x the normal zoom)

@onready var trigger: Area2D = $Trigger
@onready var mammon = $Mammon
@onready var sindeath = $SinDeath
@onready var idol = $Idol

signal advanced
signal chosen(index: int)

var state = "idle"   # idle, talk, choice, battle, after, ram, done
var waiting = false
var wait_since = 0
var player
var barrier
var camera: Camera2D
var bubbles = {}     # who -> SpeechBubble
var hint_layer: CanvasLayer
var hint: Label
var choice_layer: CanvasLayer


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
		advance()


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
	await _transform()
	await _pan(_battle_view(), 1.0, 1.0)
	_end_camera()
	_lock(false)
	state = "battle"
	TurnManager.no_escape = true
	TurnManager.battle_ended.connect(_on_battle_ended, CONNECT_ONE_SHOT)
	idol.awaken()
	TurnManager.start_battle([sindeath, idol])


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
	sindeath.hp_bar.visible = true
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
	if _boss_alive():
		# shouldn't happen (no running, and losing reloads the level)
		state = "idle"
		TurnManager.encounters_paused = false
		idol.make_dormant()
		return
	state = "after"
	idol.make_dormant()   # walking up to it mustn't start a new battle
	_lock(true)
	await get_tree().create_timer(1.6).timeout   # let "Victory!" show
	await _lines(VICTORY)
	_hide_bubbles()
	_lock(false)
	TurnManager.encounters_paused = false
	_set_recording(true)
	state = "ram"
	_show_ram_hint()


func _show_ram_hint():
	if is_instance_valid(idol):
		PopupText.spawn(idol, tr("Ram the idol!"), Color(1, 0.85, 0.3), Vector2(0, -110), 3.0)
	hint.text = "Ram the idol!"
	hint.visible = true


func _on_calf_smashed():
	state = "done"
	hint.visible = false
	hint.text = "Click or press Enter to continue"
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


func _shake():
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
	hint.text = "Click or press Enter to continue"
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
