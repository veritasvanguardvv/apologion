extends Area2D
# Port of Unity's InteractableItem.cs (+ RandomRot.cs) for the Greed level.
#   money  - a coin (+1 to the coin counter)
#   gold   - a gold bar: makes you heavy in some spots (greed_level.gd)
#   heal   - heals value1 HP right away
#   speed  - walk speed x value1 for value2 seconds
#   spell  - a Battle Scroll for your inventory (Ctrl)
#   letter - shows a short letter (letter_key in translations/strings.csv)
# Picked-up items stay gone after saving/loading (like item_pickup.gd).

const PopupText = preload("res://popup_text.gd")

@export_enum("money", "gold", "heal", "speed", "spell", "letter") var kind = "money"
@export var value1 = 0.0
@export var value2 = 0.0
@export var bob_height = 10.0
@export var bob_time = 2.0
@export var letter_key = ""
@export var start_active = true
@export var collect_sound: AudioStream

var time = 0.0
var icon: Node2D
var icon_y = 0.0


func _ready():
	if SaveManager.is_pickup_collected(self):
		queue_free()
		return
	icon = get_node_or_null("Icon")
	if icon:
		icon_y = icon.position.y
		if kind == "money":
			icon.rotation = deg_to_rad(randf_range(-30, 30))   # RandomRot.cs
	time = randf() * bob_time
	body_entered.connect(_on_body_entered)
	if not start_active:
		set_active(false)


func _process(delta):
	time = fmod(time + delta, bob_time)
	if icon:
		icon.position.y = icon_y - round(sin(time / bob_time * TAU) * bob_height * 0.5)


func set_active(on: bool):
	visible = on
	set_deferred("monitoring", on)


func _on_body_entered(body):
	if not body.is_in_group("player") or not visible or is_queued_for_deletion():
		return
	var level = owner if owner else get_tree().current_scene
	match kind:
		"money":
			if level.has_method("add_money"):
				level.add_money(1)
			PopupText.spawn(body, "+1", Color(1, 0.9, 0.35))
		"gold":
			if level.has_method("add_gold"):
				level.add_gold(1)
			PopupText.spawn(body, tr("+ Gold"), Color(1, 0.85, 0.2))
		"heal":
			body.heal(value1 if value1 > 0 else 25.0)
		"speed":
			_speed_buff(body)
		"spell":
			Inventory.add("battle_scroll")
			PopupText.spawn(body, "+ " + tr("Battle Scroll"), Color(1, 0.95, 0.6))
		"letter":
			if level.has_method("show_letter"):
				level.show_letter(letter_key)
	if collect_sound:
		var p = AudioStreamPlayer.new()
		p.stream = collect_sound
		level.add_child(p)
		p.play()
		p.finished.connect(p.queue_free)
	SaveManager.mark_pickup_collected(self)
	queue_free()


func _speed_buff(body):
	var mult = value1 if value1 > 0 else 1.5
	var secs = value2 if value2 > 0 else 10.0
	PopupText.spawn(body, tr("Speed up!"), Color(0.5, 0.9, 1.0))
	body.speed *= mult
	var timer = body.get_tree().create_timer(secs)
	timer.timeout.connect(func():
		if is_instance_valid(body):
			body.speed /= mult)
