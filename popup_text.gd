extends RefCounted
const Battle3D = preload("res://battle_3d.gd")   # 3D boss battle: 2D spots seen through its camera
# Floating text that rises and fades, e.g. "+25" over someone who was healed.
# Usage:  PopupText.spawn(some_node, "+25", Color.GREEN)
# It's added to the level (not to the node), so it stays visible even if the
# node disappears right after.

static func spawn(node: Node2D, text: String, color := Color.WHITE, offset := Vector2(0, -90), time := 1.4) -> Label:
	var label = Label.new()
	label.text = text
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # pass translated text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# (a multi-line popup, e.g. "Guard +50%   Wisdom +20%" over two lines, is
	# sized to its text so it's kept clear of the HUD / bubbles as a whole)
	var lines = text.split("\n")
	var longest = 0
	for l in lines:
		longest = max(longest, l.length())
	label.size = Vector2(max(260.0, longest * 12.0 + 20.0), 30.0 * lines.size())
	label.z_index = 10
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	var center = node.global_position
	var shape = node.get_node_or_null("CollisionShape2D")
	if shape:
		center = shape.global_position
	label.position = center + offset - Vector2(label.size.x / 2.0, 15)
	var level = node.get_tree().current_scene if node.get_tree().current_scene else node.get_parent()
	level.add_child(label)
	var tween = label.create_tween()
	tween.set_parallel(true)
	if Battle3D.is_on():   # the 3D boss battle: rises over where it shows (follows the camera)
		Battle3D.current.track_popup(label, node, center + offset, time)
	else:   # on the screen and clear of the HUD / other popups (hud_layout.gd)
		var vp = label.get_viewport()
		var xf = vp.get_canvas_transform()
		var rise = 40.0 * xf.get_scale().y
		var at = xf.affine_inverse() * Battle3D.keep_on_screen(vp, label, xf * (center + offset), rise)
		label.global_position = at - Vector2(label.size.x / 2.0, 15)
		tween.tween_property(label, "global_position:y", label.global_position.y - 40, time)
	tween.tween_property(label, "modulate:a", 0.0, time * 0.5).set_delay(time * 0.5)
	tween.chain().tween_callback(label.queue_free)
	return label
