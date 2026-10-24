extends Node
# "PLAY OF THE GAME" for the Greed level's SinDeath scene (sindeath_scene.gd).
# Mammon: "I've seen you every time you chased after easy money..." and then a
# highlight reel shows a 2-second clip of EVERY money / gold pickup of this run.
#
# RECORDING (cheap, so it runs fine on iPhone and the web):
#  - Only while the player is near a money/gold pickup (ARM_DISTANCE) we grab
#    the screen FPS times a second, shrink it to CLIP_WIDTH pixels wide and
#    keep it as a small JPEG in a ring buffer of the last PRE_FRAMES frames.
#  - When a pickup happens (greed_pickup.gd calls note_pickup) the clip is
#    those PRE_FRAMES frames (1 s before) + POST_FRAMES frames (1 s after).
#  - Clips live in memory only (SaveManager.greed_clips, so they survive dying
#    / checkpoint reloads), and are cleared when the level is started fresh or
#    a save is loaded. At most MAX_CLIPS clips (a few MB).
#
# PLAYBACK: play(parent) shows them one after the other on a full-screen
# overlay. Skip with the button, K, or a tap on the button. Returns when done.

signal finished

const FPS = 10.0
const PRE_FRAMES = 10
const POST_FRAMES = 10
const MAX_CLIPS = 40
const CLIP_WIDTH = 384
const JPEG_QUALITY = 0.7
const ARM_DISTANCE = 900.0

# One clip = { "kind": "money"/"gold", "frames": [PackedByteArray (JPEG), ...] }
var clips: Array:
	get: return SaveManager.greed_clips

var ring: Array = []         # newest frames while armed
var filling: Array = []      # clips still recording their post-roll: [{ clip, left }]
var timer = 0.0
var recording = true         # the SinDeath scene turns it off


func _ready():
	add_to_group("play_recorder")


func has_clips() -> bool:
	return not clips.is_empty()


func _process(delta):
	if not recording:
		return
	timer += delta
	if timer < 1.0 / FPS:
		return
	timer = 0.0
	if filling.is_empty() and not _near_valuable():
		ring.clear()   # nothing worth remembering here (and saves the work)
		return
	var frame = _grab()
	if frame.is_empty():
		return
	ring.append(frame)
	if ring.size() > PRE_FRAMES:
		ring.pop_front()
	for f in filling.duplicate():
		f.clip.frames.append(frame)
		f.left -= 1
		if f.left <= 0:
			filling.erase(f)


func _near_valuable() -> bool:
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return false
	for p in get_tree().get_nodes_in_group("greed_valuables"):
		if p.visible and p.global_position.distance_squared_to(player.global_position) < ARM_DISTANCE * ARM_DISTANCE:
			return true
	return false


func _grab() -> PackedByteArray:
	var tex = get_viewport().get_texture()
	if tex == null:
		return PackedByteArray()
	var img = tex.get_image()
	if img == null or img.is_empty():
		return PackedByteArray()
	var h = int(round(CLIP_WIDTH * float(img.get_height()) / img.get_width()))
	img.resize(CLIP_WIDTH, max(h, 1), Image.INTERPOLATE_BILINEAR)
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	return img.save_jpg_to_buffer(JPEG_QUALITY)


# greed_pickup.gd: the player just took money or gold
func note_pickup(kind: String):
	if not recording or clips.size() >= MAX_CLIPS:
		return
	if ring.is_empty():
		var frame = _grab()   # e.g. picked up right after a reload
		if not frame.is_empty():
			ring.append(frame)
	var clip = { "kind": kind, "frames": ring.duplicate() }
	clips.append(clip)
	filling.append({ "clip": clip, "left": POST_FRAMES })


# ---------------- Playback ----------------

var skipping = false
var layer: CanvasLayer
var screen: TextureRect
var tag: Label
var counter: Label

const REPLAY_SHADER = """
shader_type canvas_item;
// Old-memory look: warm sepia tint, soft vignette, faint scanlines
uniform float tint = 0.45;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 sepia = vec3(g * 1.08, g * 0.92, g * 0.62);
	c.rgb = mix(c.rgb, sepia, tint);
	float d = distance(UV, vec2(0.5));
	c.rgb *= 1.0 - smoothstep(0.42, 0.75, d) * 0.6;
	c.rgb *= 0.94 + 0.06 * sin(UV.y * 480.0);
	COLOR = c;
}
"""


func play(parent: Node) -> void:
	if clips.is_empty():
		return
	recording = false
	skipping = false
	_build_overlay(parent)
	layer.add_to_group("hud_hidden_overlay")   # turn_manager.gd hides the Items button under it
	var tex: ImageTexture = null
	var img = Image.new()
	for i in clips.size():
		if skipping or not is_instance_valid(layer):
			break
		var clip = clips[i]
		tag.text = tr("+ Gold") if clip.kind == "gold" else "+ " + tr("Money")
		tag.add_theme_color_override("font_color", Color(1, 0.85, 0.2) if clip.kind == "gold" else Color(0.6, 1, 0.55))
		counter.text = "%d / %d" % [i + 1, clips.size()]
		_flash()
		for buf in clip.frames:
			if skipping:
				break
			if img.load_jpg_from_buffer(buf) != OK:
				continue
			if tex == null or tex.get_size() != Vector2(img.get_size()):
				tex = ImageTexture.create_from_image(img)
				screen.texture = tex
			else:
				tex.update(img)
			await get_tree().create_timer(1.0 / FPS).timeout
		if not skipping:
			await get_tree().create_timer(0.15).timeout
	if is_instance_valid(layer):
		var t = layer.get_child(0).create_tween()
		for c in layer.get_children():
			t.parallel().tween_property(c, "modulate:a", 0.0, 0.3)
		await t.finished
		layer.queue_free()
	finished.emit()


func _unhandled_input(event):
	if is_instance_valid(layer) and event is InputEventKey and event.pressed and event.keycode == KEY_K:
		skip()
		get_viewport().set_input_as_handled()


func skip():
	skipping = true


func _flash():
	var flash = layer.get_node_or_null("Flash")
	if flash:
		flash.modulate.a = 0.8
		flash.create_tween().tween_property(flash, "modulate:a", 0.0, 0.25)


func _build_overlay(parent: Node):
	layer = CanvasLayer.new()
	layer.name = "PlayOfTheGameOverlay"
	layer.layer = 40
	parent.add_child(layer)
	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.03, 0.02, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	# the replay picture, 78% of the screen, with a gold frame
	var frame = Panel.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color.BLACK
	sb.border_color = Color(1, 0.8, 0.25)
	sb.set_border_width_all(4)
	frame.add_theme_stylebox_override("panel", sb)
	frame.anchor_left = 0.11
	frame.anchor_right = 0.89
	frame.anchor_top = 0.14
	frame.anchor_bottom = 0.92
	layer.add_child(frame)
	screen = TextureRect.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.offset_left = 4
	screen.offset_top = 4
	screen.offset_right = -4
	screen.offset_bottom = -4
	screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	screen.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var mat = ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = REPLAY_SHADER
	screen.material = mat
	frame.add_child(screen)
	var title = Label.new()
	title.text = "Idolatry Cam"   # (translated: General/translations/strings.csv)
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.offset_top = 14
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 10)
	layer.add_child(title)
	tag = Label.new()
	tag.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	tag.position = Vector2(24, 20)
	tag.add_theme_font_size_override("font_size", 28)
	tag.add_theme_color_override("font_outline_color", Color.BLACK)
	tag.add_theme_constant_override("outline_size", 8)
	frame.add_child(tag)
	counter = Label.new()
	counter.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	counter.anchor_left = 1.0
	counter.anchor_right = 1.0
	counter.offset_left = -140
	counter.offset_right = -20
	counter.offset_top = 20
	counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	counter.add_theme_font_size_override("font_size", 24)
	counter.add_theme_color_override("font_outline_color", Color.BLACK)
	counter.add_theme_constant_override("outline_size", 6)
	frame.add_child(counter)
	var rec = Label.new()
	rec.text = "● REPLAY"
	rec.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	rec.anchor_top = 1.0
	rec.anchor_bottom = 1.0
	rec.offset_left = 24
	rec.offset_top = -48
	rec.add_theme_font_size_override("font_size", 22)
	rec.add_theme_color_override("font_color", Color(1, 0.3, 0.25))
	rec.add_theme_color_override("font_outline_color", Color.BLACK)
	rec.add_theme_constant_override("outline_size", 6)
	frame.add_child(rec)
	var blink = rec.create_tween().set_loops()
	blink.tween_property(rec, "modulate:a", 0.25, 0.5)
	blink.tween_property(rec, "modulate:a", 1.0, 0.5)
	var flash = ColorRect.new()
	flash.name = "Flash"
	flash.color = Color(1, 0.95, 0.8)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.modulate.a = 0.0
	frame.add_child(flash)
	var skip_btn = Button.new()
	skip_btn.text = "Skip (K)" if TurnManager.key_hints() else "Skip"
	skip_btn.anchor_left = 1.0
	skip_btn.anchor_right = 1.0
	skip_btn.anchor_top = 1.0
	skip_btn.anchor_bottom = 1.0
	skip_btn.offset_left = -170
	skip_btn.offset_right = -20
	skip_btn.offset_top = -50
	skip_btn.offset_bottom = -8
	skip_btn.add_theme_font_size_override("font_size", 20)
	skip_btn.pressed.connect(skip)
	layer.add_child(skip_btn)
