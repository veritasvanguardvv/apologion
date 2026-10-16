extends StaticBody2D
# Port of Unity's Barrier.cs (the thorns, the Golden Calf).
# Like in Unity you RAM it: hold the Ram key (X by default, see Settings >
# Controls) until the bar above your head fills, then you dash forward. A dash
# that runs into the barrier breaks it (character_body_2d.gd calls on_rammed).
# requires_group: it won't break while anything in that group is alive
# (the Golden Calf waits for the Greedwraith). wins_level: breaking it wins.

const PopupText = preload("res://popup_text.gd")

@export var wins_level = false
@export var requires_group = ""
@export var break_sound: AudioStream
# A dash that gets this close also counts (in case the dash stops a hair short)
@export var ram_reach = 40.0

var broken = false


func _physics_process(_delta):
	if broken:
		return
	var player = get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("on_ram_target_reached") or not player.is_ramming():
		return
	# Backup check: the dash is right next to the barrier
	var body = player.get_body_center()
	for c in get_children():
		if c is CollisionShape2D and c.shape:
			var r = c.shape.get_rect()
			var rect = Rect2(c.global_position + r.position * c.global_scale.abs(), r.size * c.global_scale.abs())
			if rect.grow(ram_reach).has_point(body):
				player.on_ram_target_reached(self)
				return


# Called when the player's dash hits this barrier. Returns true if it broke.
func on_rammed(_player = null) -> bool:
	if broken:
		return false
	if requires_group != "":
		for n in get_tree().get_nodes_in_group(requires_group):
			if is_instance_valid(n) and not n.is_queued_for_deletion():
				PopupText.spawn(self, tr("Defeat the Greedwraith first!"), Color(1, 0.6, 0.5))
				return false
	broken = true
	for c in get_children():
		if c is CollisionShape2D or c is CollisionPolygon2D:
			c.set_deferred("disabled", true)
	if break_sound:
		var p = AudioStreamPlayer.new()
		p.stream = break_sound
		add_child(p)
		p.play()
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 2.0)
	tween.tween_callback(func(): visible = false)
	if wins_level:
		var level = owner if owner else get_tree().current_scene
		if level.has_method("win"):
			level.win()
	return true
