extends Node2D
# Port of Unity's Parallaxa.cs (Greed background layers).
# The layer moves by (camera start - camera now) * speed, exactly like the
# Unity script. Change speed / speed_y in the Inspector to taste
# (0 = moves with the level; negative values make it lag behind like a
# far-away background).
#
# enabled = false (default): no multi-layer parallax — art stays fixed in
# the level and scrolls 1:1 with the camera.

@export var enabled = false
@export var speed = 0.0
@export var speed_y = 0.0

var start_pos: Vector2
var start_cam: Vector2
var started = false


func _process(_delta):
	if not enabled:
		return
	var cam = get_viewport().get_camera_2d()
	if cam == null:
		return
	var c = cam.get_screen_center_position()
	if not started:
		start_pos = position
		start_cam = c
		started = true
	position = start_pos + Vector2((start_cam.x - c.x) * speed, (start_cam.y - c.y) * speed_y)
