extends CanvasLayer
# SPEECH BUBBLE (built in code)
# -----------------------------
# A speech bubble that follows a node around and stays inside the screen.
# Two looks (call set_light_style() right after creating it):
#   dark  (default) = dark fill, cream border  -> enemies
#   light           = white fill, black text   -> the player and party members
#   say(title, text, badge, time)
#     badge = true shows a small "!" next to the bubble (= you can counter it!)
#     time  = seconds to stay up; 0 or less = stay until hide_bubble() is called

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

func _init():
	layer = 4
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
	_place()

func hide_bubble():
	panel.visible = false
	tail.visible = false
	badge.visible = false
	stays_up = false

func is_showing() -> bool:
	return panel.visible

func _process(delta):
	if not panel.visible:
		return
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
	panel.reset_size()
	var s = panel.size
	var margin = 8.0
	var pos = Vector2(head.x - s.x / 2.0, head.y - s.y - 12.0)
	pos.x = clamp(pos.x, margin + 14.0, max(margin, screen.x - s.x - margin))
	pos.y = clamp(pos.y, margin + 14.0, max(margin, screen.y - s.y - margin))
	panel.position = pos
	tail.position = Vector2(clamp(head.x, pos.x + 16.0, pos.x + s.x - 16.0), pos.y + s.y - 2.0)
	badge.position = pos + Vector2(-14, -14)
