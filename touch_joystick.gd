extends Node2D
# On-screen joystick for phones and tablets (made by touch_controls.gd).
# Put a thumb on it and push left / right to walk: it presses move_left /
# move_right (Input.action_press with a strength, so a light push walks
# slowly), exactly like the arrow keys, so every level works without code of
# its own. Pushing it right up also presses "interact" (talk, doors), like ^.
# Only touches that START on the stick (within grab_radius of its centre)
# move it; it keeps following that finger until it lifts.

@export var radius = 70.0          # the ring
@export var knob_radius = 32.0
@export var grab_radius = 105.0    # how far from the centre a touch can start
@export var dead_zone = 0.2        # push less than this (of the ring) = nothing
@export var full_at = 0.75         # push this far = full speed
@export var up_for_interact = 0.7  # pushed up this far (and not much sideways) = interact

var finger = -1                    # the touch index holding the stick (-1 = none)
var knob = Vector2.ZERO            # knob offset from the centre (canvas pixels)
var axis = 0.0                     # -1 .. 1 (left .. right), after the dead zone
var up = false                     # pushed up (interact)


func _input(event):
	if not is_visible_in_tree():
		release()
		return
	if event is InputEventScreenTouch:
		var p = _local(event.position)
		if event.pressed and finger == -1 and p.length() <= grab_radius:
			finger = event.index
			_move(p)
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == finger:
			release()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == finger:
		_move(_local(event.position))
		get_viewport().set_input_as_handled()


# event positions are in the viewport's canvas pixels; the layer may be moved
func _local(p: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * p


func _move(p: Vector2):
	knob = p.limit_length(radius)
	var x = knob.x / radius
	var a = 0.0
	if abs(x) > dead_zone:
		a = sign(x) * clamp((abs(x) - dead_zone) / max(full_at - dead_zone, 0.01), 0.0, 1.0)
	axis = a
	up = -knob.y / radius >= up_for_interact and abs(x) < 0.5
	queue_redraw()


func release():
	if finger == -1 and axis == 0.0 and not up:
		return
	finger = -1
	knob = Vector2.ZERO
	axis = 0.0
	up = false
	queue_redraw()


func _draw():
	var held = finger != -1
	draw_circle(Vector2.ZERO, radius, Color(1, 1, 1, 0.12 if not held else 0.18))
	draw_arc(Vector2.ZERO, radius, 0, TAU, 48, Color(1, 1, 1, 0.45), 3.0, true)
	# little arrows: < > and ^ (talk)
	var c = Color(1, 1, 1, 0.55)
	for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP]:
		var tip = d * (radius - 10.0)
		var side = Vector2(-d.y, d.x) * 8.0
		draw_colored_polygon(PackedVector2Array([tip, tip - d * 12.0 + side, tip - d * 12.0 - side]), c)
	draw_circle(knob, knob_radius, Color(1, 0.85, 0.4, 0.55) if held else Color(1, 1, 1, 0.35))
	draw_arc(knob, knob_radius, 0, TAU, 32, Color(1, 1, 1, 0.7), 2.0, true)
