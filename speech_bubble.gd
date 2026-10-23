extends CanvasLayer
const Battle3D = preload("res://battle_3d.gd")
const HudLayout = preload("res://hud_layout.gd")   # 3D boss battle: 2D spots seen through its camera
# SPEECH BUBBLE (built in code)
# -----------------------------
# A speech bubble that follows a node around and stays inside the screen.
# Two looks (call set_light_style() right after creating it):
#   dark  (default) = dark fill, cream border  -> enemies
#   light           = white fill, black text   -> the player and party members
#   say(title, text, badge, time)
#     badge = true shows a small "!" next to the bubble (= you can counter it!)
#     time  = seconds to stay up; 0 or less = stay until hide_bubble() is called
#   start_typing(voice)  right after say(): the text types itself out (a
#     typewriter), with a voice blip every few letters (boss talk). The first
#     press finishes it (finish_typing(), see sindeath_scene.gd), the next one
#     goes on. The bubble is already full size, so nothing jumps around.

var target: Node2D                    # who is talking
var head_offset = Vector2(0, -150)    # where their head is, from target's origin
var max_width = 340.0
var time_left = 0.0
var stays_up = false

var style: StyleBoxFlat
var panel: PanelContainer
var ref_label: Label
var text_label: Label
var tail: Polygon2D
var badge: Label
# Several bubbles at once (e.g. two enemies): a newer bubble that would
# cover an older one moves up above it.
static var shown_counter = 0
var shown_order = 0

# ---- Typewriter + voice blips ----
# BOSS_VOICE = the user's "Calf_Mammon_voice" recording: 80 short blips, one
# every BOSS_BLIP_STEP seconds. Each blip plays one of them (a random one,
# pitched a bit lower), so the boss "mutters" while the text appears.
const BOSS_VOICE = "res://General/Sounds/Calf_Mammon_voice.mp3"
const BOSS_BLIP_FIRST = 0.045     # where the first blip starts (s)
const BOSS_BLIP_STEP = 0.10955    # one blip every ... (s)
const BOSS_BLIP_COUNT = 80
const BOSS_BLIP_LENGTH = 0.075    # how much of a blip is played (s)
@export var type_speed = 40.0     # letters per second
@export var blip_every = 3        # a blip every 3rd letter (spaces / punctuation don't count)
var typing = false
var type_progress = 0.0
var type_letters = 0
var voice_player: AudioStreamPlayer
var blip_stop_in = 0.0
var blips_played = 0              # (counted for the tests)
static var _boss_voice: AudioStream

func _init():
	layer = 4
	add_to_group("speech_bubbles")
	panel = PanelContainer.new()
	style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.08, 0.16, 0.94)
	style.border_color = Color(0.95, 0.88, 0.6)
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	ref_label = Label.new()
	ref_label.add_theme_color_override("font_color", Color(1, 0.86, 0.35))
	ref_label.add_theme_font_size_override("font_size", 16)
	box.add_child(ref_label)
	text_label = Label.new()
	text_label.add_theme_color_override("font_color", Color(0.97, 0.95, 0.9))
	text_label.add_theme_font_size_override("font_size", 16)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(text_label)
	tail = Polygon2D.new()
	tail.color = Color(0.95, 0.88, 0.6)
	tail.polygon = PackedVector2Array([Vector2(-9, 0), Vector2(9, 0), Vector2(0, 12)])
	add_child(tail)
	# The "!" badge: a round red sticker on the bubble's top-left corner
	badge = Label.new()
	badge.text = "!"
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.custom_minimum_size = Vector2(28, 28)
	badge.add_theme_font_size_override("font_size", 20)
	badge.add_theme_color_override("font_color", Color.WHITE)
	var badge_style = StyleBoxFlat.new()
	badge_style.bg_color = Color(0.85, 0.15, 0.15)
	badge_style.border_color = Color(1, 0.9, 0.5)
	badge_style.set_border_width_all(2)
	badge_style.set_corner_radius_all(14)
	badge.add_theme_stylebox_override("normal", badge_style)
	add_child(badge)
	hide_bubble()

# White bubble, black text and border (for the player and party members)
func set_light_style():
	style.bg_color = Color(1, 1, 1, 0.97)
	style.border_color = Color.BLACK
	tail.color = Color.BLACK
	ref_label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	text_label.add_theme_color_override("font_color", Color.BLACK)

func say(title: String, text: String, show_badge := false, time := 3.0):
	ref_label.text = title
	ref_label.visible = title != ""
	typing = false
	text_label.visible_characters = -1
	text_label.text = text
	var font = text_label.get_theme_font("font")
	var size = text_label.get_theme_font_size("font_size")
	var width = max(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x,
		font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	text_label.custom_minimum_size.x = min(width + 2, max_width)
	panel.reset_size()
	panel.visible = true
	tail.visible = true
	badge.visible = show_badge
	stays_up = time <= 0.0
	time_left = time
	shown_counter += 1
	shown_order = shown_counter
	_place()

func start_typing(voice := true):
	if text_label.text == "":
		return
	typing = true
	type_progress = 0.0
	type_letters = 0
	text_label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	text_label.visible_characters = 0
	if voice and voice_player == null:
		if _boss_voice == null and ResourceLoader.exists(BOSS_VOICE):
			_boss_voice = load(BOSS_VOICE)
		voice_player = AudioStreamPlayer.new()
		voice_player.stream = _boss_voice
		voice_player.bus = "SFX"   # the Settings SFX slider
		add_child(voice_player)
	if not voice and voice_player:
		voice_player.stream = null
	if not stays_up:
		time_left += text_label.get_total_character_count() / type_speed   # stays up as long after typing

func is_typing() -> bool:
	return typing and panel.visible

# Shows the rest of the text at once (the first press while it types)
func finish_typing():
	typing = false
	text_label.visible_characters = -1
	_stop_blip()

func _type(delta):
	var total = text_label.get_total_character_count()
	var before = int(type_progress)
	type_progress = min(type_progress + type_speed * delta, total)
	var now = int(type_progress)
	var plain = text_label.text
	for i in range(before, now):
		var c = plain[i] if i < plain.length() else " "
		if _is_letter(c):
			type_letters += 1
			if type_letters % blip_every == 1 or blip_every <= 1:
				_blip()
	text_label.visible_characters = now
	if now >= total:
		typing = false
		text_label.visible_characters = -1

static func _is_letter(c: String) -> bool:
	return c.to_upper() != c.to_lower() or c.is_valid_int()

func _blip():
	if voice_player == null or voice_player.stream == null:
		return
	blips_played += 1
	voice_player.pitch_scale = randf_range(0.85, 0.97)   # a little lower = creepier
	voice_player.play(BOSS_BLIP_FIRST + BOSS_BLIP_STEP * (randi() % BOSS_BLIP_COUNT))
	blip_stop_in = BOSS_BLIP_LENGTH / voice_player.pitch_scale

func _stop_blip():
	if voice_player and voice_player.playing:
		voice_player.stop()
	blip_stop_in = 0.0

func hide_bubble():
	if typing:
		finish_typing()
	panel.visible = false
	tail.visible = false
	badge.visible = false
	stays_up = false

func is_showing() -> bool:
	return panel.visible

func _process(delta):
	if blip_stop_in > 0.0:
		blip_stop_in -= delta
		if blip_stop_in <= 0.0:
			_stop_blip()
	if not panel.visible:
		return
	if typing:
		_type(delta)
	if not is_instance_valid(target):
		hide_bubble()
		return
	if not stays_up:
		time_left -= delta
		if time_left <= 0.0:
			hide_bubble()
			return
	_place()

# Above the target's head, but always inside the screen
func _place():
	if not is_instance_valid(target):
		return
	var screen = get_viewport().get_visible_rect().size
	var head = target.get_global_transform_with_canvas() * head_offset
	if Battle3D.is_on():   # the 3D boss battle: over where they show
		head = Battle3D.screen_point(target, target.get_global_transform() * head_offset)
	panel.reset_size()
	var s = panel.size
	var margin = 8.0
	var pos = Vector2(head.x - s.x / 2.0, head.y - s.y - 12.0)
	pos.x = clamp(pos.x, margin + 14.0, max(margin, screen.x - s.x - margin))
	pos.y = clamp(pos.y, margin + 14.0, max(margin, screen.y - s.y - margin))
	# Don't cover an older bubble: go above it
	for other in get_tree().get_nodes_in_group("speech_bubbles"):
		if other != self and other.is_showing() and other.shown_order < shown_order:
			var other_rect = Rect2(other.panel.position, other.panel.size).grow(6)
			if other_rect.intersects(Rect2(pos, s)):
				pos.y = other_rect.position.y - s.y - 8.0
	pos.y = max(pos.y, margin)
	# ...and clear of the HUD (the turn message, Run / Items, the HP bars, the
	# enemies' panel) and of older bubbles (hud_layout.gd); the badge too
	var older = []
	for other in get_tree().get_nodes_in_group("speech_bubbles"):
		if other != self and other.is_showing() and other.shown_order < shown_order:
			older.append(Rect2(other.panel.position, other.panel.size).grow(6))
	var b = Vector2(14, 14) if badge.visible else Vector2.ZERO
	pos = HudLayout.fit(Rect2(pos - b, s + b), get_viewport(), older) + b
	panel.position = pos
	tail.position = Vector2(clamp(head.x, pos.x + 16.0, pos.x + s.x - 16.0), pos.y + s.y - 2.0)
	badge.position = pos + Vector2(-14, -14)
