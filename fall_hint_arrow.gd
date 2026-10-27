extends Node2D
# Baby Mode (baby_mode.gd): after a few falls into the same water / pit, a
# big arrow next to the sheep shows the way to go (e.g. in Greed, left to the
# portal back up the hill), swinging back and forth that way. It goes away
# once the sheep is well past it (done_x) or after a while.

var dir = -1.0           # -1 = points left, 1 = right
var done_x = 0.0         # the player's body x past which it's no longer needed (in `dir`)
var lifetime = 25.0
var player: Node2D
var _t = 0.0
const LEN = 190.0
const H = 110.0
const SWING = 30.0


func _ready():
	z_index = 50
	var fill = Polygon2D.new()
	fill.name = "Fill"
	var pts = PackedVector2Array([
		Vector2(-LEN / 2.0, 0), Vector2(-LEN / 2.0 + H * 0.6, -H / 2.0), Vector2(-LEN / 2.0 + H * 0.6, -H * 0.22),
		Vector2(LEN / 2.0, -H * 0.22), Vector2(LEN / 2.0, H * 0.22),
		Vector2(-LEN / 2.0 + H * 0.6, H * 0.22), Vector2(-LEN / 2.0 + H * 0.6, H / 2.0)])
	if dir > 0:
		for i in pts.size():
			pts[i].x = -pts[i].x
	var outline = Line2D.new()
	outline.points = pts
	outline.closed = true
	outline.width = 8.0
	outline.default_color = Color(0.15, 0.1, 0.05)
	fill.polygon = pts
	fill.color = Color(1.0, 0.85, 0.15)
	add_child(fill)
	add_child(outline)


func _process(delta):
	_t += delta
	# back and forth, mostly toward the way to go
	position.x = _home_x() + dir * SWING * (0.5 - 0.5 * cos(_t * 5.0))
	if _t > lifetime or not is_instance_valid(player) or _past():
		queue_free()


var home = Vector2.ZERO
func _home_x() -> float:
	return home.x


func _past() -> bool:
	var x = player.get_body_center().x if player.has_method("get_body_center") else player.global_position.x
	return (x - done_x) * dir > 0.0
