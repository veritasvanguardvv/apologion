extends Area2D
# Port of Unity's TriggerArea.cs (+ Teleport.cs).
# When the player walks in, every call in on_enter runs; on_exit when leaving.
# Each call is [NodePath from the level root, "method", [arguments]], e.g.
#   [NodePath("Triggers/DamageArea (3)"), "hide_area", []]
#   [NodePath("."), "can_enter_room", [1]]       ("." = greed_level.gd)
# These were converted from the Unity events by the converter.

@export var on_enter: Array = []
@export var on_exit: Array = []
@export var hide_on_enter = false
@export var use_teleport = false       # Teleport.cs: move the player to teleport_to
@export var teleport_to = Vector2.ZERO


func _ready():
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _level():
	return owner if owner else get_tree().current_scene


func _on_body_entered(body):
	if not body.is_in_group("player") or not visible:
		return
	if use_teleport:
		_level().call_deferred("teleport_player", teleport_to)
	_run(on_enter)
	if hide_on_enter:
		set_active(false)


func _on_body_exited(body):
	if body.is_in_group("player"):
		_run(on_exit)


func _run(calls: Array):
	for c in calls:
		if c.size() < 2:
			continue
		var target = _level() if str(c[0]) == "." else _level().get_node_or_null(c[0])
		if target and target.has_method(c[1]):
			target.callv(c[1], c[2] if c.size() > 2 else [])
		elif target and c[1] == "set_active":
			target.visible = c[2][0]


# Unity's GameObject.SetActive
func set_active(on: bool):
	visible = on
	set_deferred("monitoring", on)
