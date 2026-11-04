extends Area2D
# Port of Unity's InteractableItem.cs (+ RandomRot.cs) for the Greed level.
#   money  - floating money: goes in your inventory (NOT a coin counter) and
#            flies away when you open the inventory (inventory.gd, Proverbs 23:5)
#   gold   - a gold bar for your inventory: makes you heavy in some spots
#            (greed_level.gd) until you drop it (inventory: click it > Drop)
#   heal   - heals value1 HP right away
#   speed  - walk speed x value1 for value2 seconds
#   spell  - a Battle Scroll for your inventory (Ctrl)
#   letter - shows a short letter (letter_key in General/translations/strings.csv)
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
@export var pickup_delay = 0.0   # seconds before it can be picked up (dropped gold: 1 s)

var time = 0.0
var icon: Node2D
var icon_y = 0.0


func _ready():
	if not has_meta("dropped") and SaveManager.is_pickup_collected(self):
		queue_free()
		return
	icon = get_node_or_null("Icon")
	if icon:
		icon_y = icon.position.y
		if kind == "money":
			icon.rotation = deg_to_rad(randf_range(-18, 18))   # RandomRot.cs (gentler: the bills hang on the trees)
	time = randf() * bob_time
	if kind == "money" or kind == "gold":
		add_to_group("greed_valuables")   # play_of_the_game.gd records near these
	body_entered.connect(_on_body_entered)
	if not start_active:
		set_active(false)
	elif pickup_delay > 0:
		monitoring = false
		get_tree().create_timer(pickup_delay).timeout.connect(func():
			if is_instance_valid(self) and visible: monitoring = true)


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
	if kind == "money" or kind == "gold":
		# Mammon remembers: a 2-second clip for the "Idolatry Cam"
		get_tree().call_group("play_recorder", "note_pickup", kind)
	match kind:
		"money":
			Inventory.add("money")
			PopupText.spawn(body, "+ " + tr("Money"), Color(1, 0.9, 0.35))
		"gold":
			Inventory.add("gold_bar")
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
	if not has_meta("dropped"):
		SaveManager.mark_pickup_collected(self)
	queue_free()


func _speed_buff(body):
	var mult = value1 if value1 > 0 else 1.5
	var secs = value2 if value2 > 0 else 10.0
	PopupText.spawn(body, tr("Speed up!"), Color(0.5, 0.9, 1.0))
	# The player's own boost multiplier (character_body_2d.gd add_speed_boost).
	# (It used to multiply body.speed and divide it back on a timer: Zeal saves
	# and restores speed, so the two could wipe each other out - and with gold
	# the air speed cap hid the boost.)
	if body.has_method("add_speed_boost"):
		body.add_speed_boost(mult, secs)

# Safety net: body_entered only fires when the player *enters* the area, so a
# pickup the sheep was already standing in (after a respawn/teleport, a scene
# reload, or when monitoring was switched back on) was never collected. Check
# the overlaps a few times a second as well.
var _overlap_t = 0.0
func _physics_process(delta):
	_overlap_t += delta
	if _overlap_t < 0.1 or not monitoring or is_queued_for_deletion():
		return
	_overlap_t = 0.0
	for b in get_overlapping_bodies():
		if b.is_in_group("player"):
			_on_body_entered(b)
			return
