extends Node2D
# The golden-barred gate (the "cage", Decor/Cover) in Mammon's treasure room.
# Ram it (the Ram dash - or any ram in Baby Mode) and it busts open: the bars
# fly off as gold shards, the gate shakes and falls away. The Golden Calf
# being smashed also busts it, if it's still shut.

@export var cover_path: NodePath = "../../Decor/Cover"
# the stained-glass lattice behind it (the cage bars you see) goes too
@export var bars_path: NodePath = "../../Decor/Square_1"
@export var calf_path: NodePath = "../GoldenCalf"
@export var reach = 24.0
@export var foot_reach = 220.0
@export var break_sound: AudioStream

var cover: Sprite2D
var busted = false


func _ready():
	cover = get_node_or_null(cover_path)
	var calf = get_node_or_null(calf_path)
	if calf and calf.has_signal("broken_by_ram"):
		calf.broken_by_ram.connect(bust)


func gate_rect() -> Rect2:
	if cover == null or cover.texture == null:
		return Rect2()
	var s = cover.global_scale.abs()
	var size = cover.texture.get_size() * s
	return Rect2(cover.global_position + cover.offset * s, size)


func _physics_process(_delta):
	if busted or cover == null:
		return
	var player = get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("get_body_center"):
		return
	var ramming = BabyMode.is_ram(player) if GameSettings.baby_mode else (player.has_method("is_ramming") and player.is_ramming())
	# (the gate stands on the treasure step: a ram at its foot counts too)
	var zone = gate_rect().grow(reach)
	zone.size.y += foot_reach
	if ramming and zone.has_point(player.get_body_center()):
		bust()


func bust():
	if busted or cover == null:
		return
	busted = true
	var r = gate_rect()
	if break_sound:
		var p = AudioStreamPlayer.new()
		p.stream = break_sound
		add_child(p)
		p.play()
	# the bars fly off
	for i in 26:
		var bar = Polygon2D.new()
		var w = randf_range(4, 8)
		var h = randf_range(24, 70)
		bar.polygon = PackedVector2Array([Vector2(-w, -h), Vector2(w, -h), Vector2(w, h), Vector2(-w, h)])
		bar.color = Color(1, randf_range(0.75, 0.9), randf_range(0.1, 0.35))
		bar.global_position = Vector2(randf_range(r.position.x + 20, r.end.x - 20), randf_range(r.position.y + 40, r.end.y - 40))
		bar.z_index = 6
		get_parent().add_child(bar)
		var dir = Vector2(randf_range(-1, 1), randf_range(-1.3, -0.3)).normalized() * randf_range(160, 380)
		var t = bar.create_tween().set_parallel(true)
		t.tween_property(bar, "global_position", bar.global_position + dir + Vector2(0, 260), 1.2).set_ease(Tween.EASE_OUT)
		t.tween_property(bar, "rotation", randf_range(-9, 9), 1.2)
		t.tween_property(bar, "modulate:a", 0.0, 0.5).set_delay(0.7)
		t.chain().tween_callback(bar.queue_free)
	# the gate shakes, then falls away
	var home = cover.position
	var tw = cover.create_tween()
	for k in 4:
		tw.tween_property(cover, "position", home + Vector2(6 if k % 2 == 0 else -6, 0), 0.05)
	tw.tween_property(cover, "position", home, 0.05)
	tw.tween_property(cover, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func(): cover.visible = false)
	var bars = get_node_or_null(bars_path)
	if bars is CanvasItem:
		var tb = bars.create_tween()
		tb.tween_interval(0.25)
		tb.tween_property(bars, "modulate:a", 0.0, 0.6)
		tb.tween_callback(func(): bars.visible = false)
