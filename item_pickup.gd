extends Area2D
# ITEM PICKUP (item_pickup.tscn)
# ------------------------------
# An item lying in the level. Walk over it to put it in your inventory
# (Ctrl). Set item_id in the Inspector to one of the ids in items.gd.
# Once picked up it stays gone - also after saving and loading (like defeated
# enemies), because SaveManager remembers it.

@export var item_id = "healing_scroll"
@export var bob_height = 4.0        # it floats up and down a little (pixels)
@export var bob_speed = 3.0
@export var icon_scale = 0.75       # size of the 64x64 icon

var time = 0.0
@onready var icon = $Icon


func _ready():
	if SaveManager.is_pickup_collected(self):
		queue_free()
		return
	var item = Inventory.get_item(item_id)
	if item.is_empty():
		push_warning("Unknown item '%s' (add it to items.gd)" % item_id)
	else:
		icon.texture = load(item.icon)
	icon.scale = Vector2.ONE * icon_scale
	time = randf() * TAU   # so several pickups don't bob in sync
	body_entered.connect(_on_body_entered)


func _process(delta):
	time += delta
	icon.position.y = round(sin(time * bob_speed) * bob_height)


func _on_body_entered(body):
	if not body.is_in_group("player") or is_queued_for_deletion():
		return
	Inventory.add(item_id)
	SaveManager.mark_pickup_collected(self)
	_pop_text("+ " + tr(Inventory.get_item(item_id).name))
	print("Picked up ", item_id)
	queue_free()


# Small text that floats up where the item was
func _pop_text(text: String):
	var label = Label.new()
	label.text = text
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # already translated
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(240, 26)
	label.position = global_position + Vector2(-120, -60)
	label.z_index = 10
	label.add_theme_color_override("font_color", Color(1, 0.95, 0.6))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	get_parent().add_child(label)
	var tween = label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 40, 1.2)
	tween.tween_property(label, "modulate:a", 0.0, 0.6).set_delay(0.6)
	tween.chain().tween_callback(label.queue_free)
