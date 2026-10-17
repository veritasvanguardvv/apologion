extends StaticBody2D
# A floating square block in Endless mode (made by endless_level.gd from the
# Unity parts). You can stand on it, and a Ram dash (hold X until the bar is
# full) smashes it - like greed_barrier.gd, but the tiles fly apart.

const BREAK_SOUND = preload("res://Greed/barrier-destroy.mp3")

# A dash that gets this close also counts (in case it stops a hair short)
@export var ram_reach = 30.0

var broken = false


func _physics_process(_delta):
	if broken:
		return
	var player = get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("on_ram_target_reached") or not player.is_ramming():
		return
	var body = player.get_body_center()
	for c in get_children():
		if c is CollisionShape2D and c.shape:
			var r = c.shape.get_rect()
			var rect = Rect2(c.global_position + r.position * c.global_scale.abs(), r.size * c.global_scale.abs())
			if rect.grow(ram_reach).has_point(body):
				player.on_ram_target_reached(self)
				return


# Called by the player's dash (character_body_2d.gd). Returns true if it broke.
func on_rammed(_player = null) -> bool:
	if broken:
		return false
	broken = true
	remove_from_group("endless_blocks")
	for c in get_children():
		if c is CollisionShape2D:
			c.set_deferred("disabled", true)
	var sound = AudioStreamPlayer2D.new()
	sound.stream = BREAK_SOUND
	sound.bus = "SFX" if AudioServer.get_bus_index("SFX") != -1 else "Master"
	add_child(sound)
	sound.play()
	# every tile flies off, spinning, and fades away
	var center = Vector2.ZERO
	var tiles = []
	for c in get_children():
		if c is Sprite2D:
			tiles.append(c)
			center += c.position
	if tiles.size() > 0:
		center /= tiles.size()
	for s in tiles:
		var away = (s.position - center).normalized()
		if away == Vector2.ZERO:
			away = Vector2(randf_range(-1.0, 1.0), -1.0).normalized()
		var tw = create_tween().set_parallel(true)
		tw.tween_property(s, "position", s.position + away * 70.0 + Vector2(randf_range(-30, 30), 140), 0.9).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(s, "rotation", randf_range(-2.5, 2.5), 0.9)
		tw.tween_property(s, "modulate:a", 0.0, 0.9)
	get_tree().create_timer(1.2).timeout.connect(queue_free)
	return true
