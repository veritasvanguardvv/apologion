extends StaticBody2D
# Port of Unity's Barrier.cs (the thorns, the Golden Calf).
# In Unity you charge and headbutt it. Apologion has no headbutt, so instead
# reciting any verse (typed or spoken) within break_range breaks it.
# requires_group: it won't break while anything in that group is alive
# (the Golden Calf waits for the Greedwraith). wins_level: breaking it wins.

const PopupText = preload("res://popup_text.gd")

@export var break_range = 450.0
@export var wins_level = false
@export var requires_group = ""
@export var break_sound: AudioStream

var broken = false


func _ready():
	call_deferred("_hook_up")


func _hook_up():
	var level = owner if owner else get_tree().current_scene
	var line = level.get_node_or_null("CanvasLayer/LineEdit")
	if line:
		line.text_submitted.connect(_on_recited)
	SpeechRecognizer.transcribed.connect(_on_recited)


func _on_recited(text: String):
	if broken or text.strip_edges() == "":
		return
	var player = get_tree().get_first_node_in_group("player")
	if player == null or player.get_body_center().distance_to(global_position) > break_range:
		return
	if player.has_method("_find_verse") and player._find_verse(text.to_lower().strip_edges()) == null:
		return
	if requires_group != "":
		for n in get_tree().get_nodes_in_group(requires_group):
			if is_instance_valid(n) and not n.is_queued_for_deletion():
				PopupText.spawn(self, tr("Defeat the Greedwraith first!"), Color(1, 0.6, 0.5))
				return
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
