extends Sprite2D

var frame_timer = 0.0
var frame_speed = 0.21

func _process(delta):
	frame_timer += delta
	if frame_timer >= frame_speed:
		frame_timer = 0
		frame = (frame + 1) % hframes
