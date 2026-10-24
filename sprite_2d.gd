extends Sprite2D

var frame_timer = 0
var frame_speed = 0.1
var idle_timer = 0
var idle_speed = 0.5
var idle_frames = [3, 4]
var idle_index = 0
var hold_frame = -1   # >= 0: stay on this frame (the sheep ducking under the Guard wings)

func _process(delta):
	if hold_frame >= 0:
		frame = hold_frame
		return
	var parent = get_parent()
	if parent.velocity.x != 0:
		frame_timer += delta
		if frame_timer >= frame_speed:
			frame_timer = 0
			frame = (frame + 1) % (hframes - 2)
	else:
		idle_timer += delta
		if idle_timer >= idle_speed:
			idle_timer = 0
			idle_index = (idle_index + 1) % idle_frames.size()
			frame = idle_frames[idle_index]
